#+build !js
package cyb

import "core:strings"
import "core:testing"

// What the original game stores for a character who has played a while.
OLD_MIDGAME :: `{"characters":[{"statistics":{"ButtholeChecks":42,"ExperiencePoints":17,"ExperienceGoal":200,"ExperienceLevel":1,"AdvancementPoint":1,"Irritation":12,"MaximumIrritation":100,"LastCheckTime":1750000000000},"advancements":{"Crit":1,"Thoroughness":0,"IrritationRecovery":2},"name":"Bob"}],"messages":["You check yer butthole!","+1 irritation","+1 XP"],"avatarCharacterId":0}`

// Just after EMBARK!, before any check (no LastCheckTime yet).
OLD_FRESH :: `{"characters":[{"statistics":{"ButtholeChecks":0,"ExperiencePoints":0,"ExperienceGoal":100,"ExperienceLevel":0,"AdvancementPoint":0,"Irritation":0,"MaximumIrritation":100},"advancements":{"Crit":0,"Thoroughness":0,"IrritationRecovery":0},"name":"n00b"}],"messages":[],"avatarCharacterId":0}`

// After "Abandon Game" nothing is stored, but a world with no avatar is possible.
OLD_NO_AVATAR :: `{"characters":[],"messages":[]}`

played_game :: proc() -> Game {
	g := new_game("Ünï \"quoted\" \\ name")
	p := &g.player
	p.checks = 1234
	p.xp = 56
	p.xp_goal = 800
	p.level = 3
	p.points = 9
	p.irritation = 77
	p.has_last_check = true
	p.last_check_ms = T0
	p.advancements = {
		.Crit                = 4,
		.Thoroughness        = 2,
		.Irritation_Recovery = 6,
	}
	add_message(&g, "line \"one\"")
	add_message(&g, "tab\there\nnewline é 😀")
	return g
}

same_game :: proc(t: ^testing.T, a, b: ^Game) {
	testing.expect(t, a.has_avatar == b.has_avatar)
	testing.expect(t, a.player == b.player)
	testing.expect_value(t, a.message_count, b.message_count)
	for i in 0 ..< min(a.message_count, b.message_count) {
		testing.expect_value(t, message_text(&a.messages[i]), message_text(&b.messages[i]))
	}
}

write :: proc(g: ^Game, buf: []u8) -> string {
	text, ok := save_write(g, buf)
	assert(ok)
	return text
}

// ---- v2 ----

@(test)
v2_round_trip :: proc(t: ^testing.T) {
	g := played_game()
	buf: [SAVE_BUF_SIZE]u8
	text := write(&g, buf[:])
	out: Game
	testing.expect(t, save_read(&out, text))
	same_game(t, &g, &out)
}

@(test)
v2_round_trip_without_a_last_check :: proc(t: ^testing.T) {
	g := new_game()
	buf: [SAVE_BUF_SIZE]u8
	text := write(&g, buf[:])
	testing.expect(t, strings.contains(text, `"last_check_ms":null`))
	out: Game
	testing.expect(t, save_read(&out, text))
	testing.expect(t, !out.player.has_last_check)
	same_game(t, &g, &out)
}

@(test)
v2_text_has_the_expected_shape :: proc(t: ^testing.T) {
	g := new_game("Bob")
	g.player.advancements[.Crit] = 2
	buf: [SAVE_BUF_SIZE]u8
	text := write(&g, buf[:])
	testing.expect_value(
		t,
		text,
		`{"version":2,"name":"Bob","checks":0,"xp":0,"xp_goal":100,"level":0,"points":0,"irritation":0,"max_irritation":100,"last_check_ms":null,"advancements":{"Crit":2,"Thoroughness":0,"IrritationRecovery":0},"messages":[]}`,
	)
}

@(test)
v2_write_needs_an_avatar_and_enough_room :: proc(t: ^testing.T) {
	buf: [SAVE_BUF_SIZE]u8
	empty: Game
	_, ok := save_write(&empty, buf[:])
	testing.expect(t, !ok)
	g := played_game()
	small: [40]u8
	_, ok = save_write(&g, small[:])
	testing.expect(t, !ok)
	// the worst case still fits: 16 messages of 128 bytes
	for _ in 0 ..< MAX_MESSAGES {
		add_message(&g, "%s", strings.repeat("x", MESSAGE_LEN - 1, context.temp_allocator))
	}
	_, ok = save_write(&g, buf[:])
	testing.expect(t, ok)
}

@(test)
v2_rejects_bad_saves :: proc(t: ^testing.T) {
	g := played_game()
	buf: [SAVE_BUF_SIZE]u8
	good := strings.clone(write(&g, buf[:]), context.temp_allocator)
	out: Game
	testing.expect(t, save_read(&out, good))

	swap :: proc(s, from, to: string) -> string {
		r, _ := strings.replace(s, from, to, 1, context.temp_allocator)
		return r
	}
	bad := []string {
		"",
		"{}",
		"[]",
		"null",
		good[:len(good) - 1], // truncated
		strings.concatenate({good, "x"}, context.temp_allocator), // trailing garbage
		swap(good, `"version":2`, `"version":3`),
		swap(good, `"version":2`, `"version":"2"`),
		swap(good, `"checks":1234,`, ``), // missing field
		swap(good, `"xp":56`, `"xp":"56"`), // wrong type
		swap(good, `"xp":56`, `"xp":5.5`), // not a whole number
		swap(good, `"xp":56`, `"xp":-1`),
		swap(good, `"xp_goal":800`, `"xp_goal":0`), // would level up forever
		swap(good, `"irritation":77`, `"irritation":101`), // over the maximum
		swap(good, `"max_irritation":100`, `"max_irritation":0`),
		swap(good, `"Crit":4`, `"Crit":7`), // above max level
		swap(good, `"Crit":4`, `"Crit":-1`),
		swap(good, `"Crit":4,`, ``), // missing advancement
		swap(good, `"last_check_ms":1700000000000`, `"last_check_ms":"soon"`),
		swap(good, `"last_check_ms":1700000000000,`, ``), // the key must exist
		swap(good, `"xp":56`, `"xp":1e300`),
		swap(good, `"xp":56`, `"xp":9007199254740993`), // beyond exact doubles
		swap(good, `"name":"`, `"name":"1234567890123456789012345678901234567890123456789012345678901234567890`),
		swap(good, `"advancements":{`, `"advancements":[`),
	}
	for text, i in bad {
		before := out
		testing.expectf(t, !save_read(&out, text), "bad save %d was accepted: %s", i, text)
		testing.expect(t, out.player == before.player, "a rejected save changed the game")
	}
}

@(test)
v2_ignores_unknown_fields_and_bad_messages :: proc(t: ^testing.T) {
	text := `{"future":{"a":[1,2,3]},"version":2,"name":"Bob","checks":0,"xp":0,"xp_goal":100,"level":0,"points":0,"irritation":0,"max_irritation":100,"last_check_ms":null,"advancements":{"Crit":0,"Thoroughness":0,"IrritationRecovery":0,"Other":9},"messages":["ok",5,null,"fine"]}`
	out: Game
	testing.expect(t, save_read(&out, text))
	testing.expect_value(t, out.message_count, 2)
	testing.expect_value(t, message_text(&out.messages[1]), "fine")
}

// ---- the parser ----

@(test)
parser_decodes_escapes :: proc(t: ^testing.T) {
	doc := new(Json_Doc)
	defer free(doc)
	testing.expect(t, json_parse(doc, `["a\"b\\c\/d\b\f\n\r\t","é","😀"]`))
	s, ok := json_string(doc, json_at(doc, doc.root, 0))
	testing.expect(t, ok)
	testing.expect_value(t, s, "a\"b\\c/d\b\f\n\r\t")
	s, _ = json_string(doc, json_at(doc, doc.root, 1))
	testing.expect_value(t, s, "é")
	s, _ = json_string(doc, json_at(doc, doc.root, 2))
	testing.expect_value(t, s, "😀")
}

@(test)
parser_rejects_malformed_json :: proc(t: ^testing.T) {
	doc := new(Json_Doc)
	defer free(doc)
	bad := []string {
		`{`, `}`, `[1,]`, `{"a"}`, `{"a":}`, `{"a":1,}`, `{a:1}`, `[1 2]`, `"abc`, `tru`, `nul`, `01x`, `-`,
		`"\ud83d"`, // lone high surrogate
		`"\ude00"`, // lone low surrogate
		`"\u12"`, `"\x"`,
		"\"tab\there\"", // raw control character
		"\"\xff\"", // invalid UTF-8
		`[[[[[[[[[1]]]]]]]]]`, // deeper than the limit
	}
	for text, i in bad {
		testing.expectf(t, !json_parse(doc, text), "case %d was accepted: %s", i, text)
	}
	testing.expect(t, json_parse(doc, ` { "a" : [ 1 , 2.5 , -3e2 , true , false , null ] } `))
}

@(test)
parser_limits_are_enforced :: proc(t: ^testing.T) {
	doc := new(Json_Doc)
	defer free(doc)
	many := strings.repeat("1,", JSON_MAX_NODES, context.temp_allocator)
	testing.expect(t, !json_parse(doc, strings.concatenate({"[", many, "1]"}, context.temp_allocator)))
	huge := strings.repeat(" ", JSON_MAX_INPUT + 1, context.temp_allocator)
	testing.expect(t, !json_parse(doc, huge))
}

// ---- migration from the original game ----

@(test)
migrates_a_midgame_save :: proc(t: ^testing.T) {
	out: Game
	testing.expect_value(t, migrate_v1(&out, OLD_MIDGAME), Migrate_Result.Ok)
	p := &out.player
	testing.expect(t, out.has_avatar)
	testing.expect_value(t, player_name(p), "Bob")
	testing.expect_value(t, p.checks, 42)
	testing.expect_value(t, p.xp, 17)
	testing.expect_value(t, p.xp_goal, 200)
	testing.expect_value(t, p.level, 1)
	testing.expect_value(t, p.points, 1)
	testing.expect_value(t, p.irritation, 12)
	testing.expect_value(t, p.max_irritation, 100)
	testing.expect(t, p.has_last_check)
	testing.expect_value(t, p.last_check_ms, 1750000000000)
	testing.expect_value(t, p.advancements[.Crit], 1)
	testing.expect_value(t, p.advancements[.Thoroughness], 0)
	testing.expect_value(t, p.advancements[.Irritation_Recovery], 2)
	testing.expect_value(t, out.message_count, 3)
	testing.expect_value(t, message_text(&out.messages[2]), "+1 XP")
}

@(test)
migrates_a_fresh_save :: proc(t: ^testing.T) {
	out: Game
	testing.expect_value(t, migrate_v1(&out, OLD_FRESH), Migrate_Result.Ok)
	testing.expect(t, !out.player.has_last_check)
	testing.expect_value(t, player_name(&out.player), "n00b")
	testing.expect_value(t, out.message_count, 0)
}

@(test)
migrated_games_keep_playing_and_round_trip :: proc(t: ^testing.T) {
	g: Game
	testing.expect_value(t, migrate_v1(&g, OLD_MIDGAME), Migrate_Result.Ok)
	// 12 irritation, last check at 1750000000000; two hours later it has all recovered
	r := seeded()
	check_butthole(&g, &r, 1750000000000 + 2 * 3600 * 1000)
	testing.expect(t, has_message(&g, "-12 Irritation"))
	testing.expect_value(t, g.player.irritation, 1)
	buf: [SAVE_BUF_SIZE]u8
	out: Game
	testing.expect(t, save_read(&out, write(&g, buf[:])))
	same_game(t, &g, &out)
}

@(test)
migration_with_unspent_points_and_nulls :: proc(t: ^testing.T) {
	// JSON.stringify turns a NaN statistic into null; those take their starting value
	text := `{"characters":[{"statistics":{"ButtholeChecks":null,"ExperiencePoints":3,"ExperienceGoal":100,"ExperienceLevel":0,"AdvancementPoint":9,"Irritation":null,"LastCheckTime":null},"advancements":{},"name":"x"}],"messages":[],"avatarCharacterId":0}`
	out: Game
	testing.expect_value(t, migrate_v1(&out, text), Migrate_Result.Ok)
	testing.expect_value(t, out.player.points, 9)
	testing.expect_value(t, out.player.checks, 0)
	testing.expect_value(t, out.player.irritation, 0)
	testing.expect_value(t, out.player.max_irritation, 100)
	testing.expect(t, !out.player.has_last_check)
}

@(test)
migration_cleans_up_names_and_messages :: proc(t: ^testing.T) {
	long := strings.repeat("é", 100, context.temp_allocator)
	msgs := strings.repeat(`"m",`, 30, context.temp_allocator)
	text := strings.concatenate(
		{
			`{"characters":[{"statistics":{"ButtholeChecks":0},"advancements":{},"name":"   "}],"messages":[`,
			msgs,
			`"`,
			long,
			`"],"avatarCharacterId":0}`,
		},
		context.temp_allocator,
	)
	out: Game
	testing.expect_value(t, migrate_v1(&out, text), Migrate_Result.Ok)
	testing.expect_value(t, player_name(&out.player), "n00b")
	testing.expect_value(t, out.message_count, MAX_MESSAGES)

	text2 := strings.concatenate({`{"characters":[{"statistics":{"ButtholeChecks":0},"name":"`, long, `"}],"avatarCharacterId":0}`}, context.temp_allocator)
	testing.expect_value(t, migrate_v1(&out, text2), Migrate_Result.Ok)
	testing.expect(t, out.player.name_len <= NAME_MAX)
	testing.expect_value(t, out.player.name_len % 2, 0)
}

@(test)
migration_of_a_world_without_an_avatar :: proc(t: ^testing.T) {
	out: Game
	testing.expect_value(t, migrate_v1(&out, OLD_NO_AVATAR), Migrate_Result.No_Avatar)
	testing.expect(t, !out.has_avatar)
}

@(test)
migration_rejects_bad_old_saves :: proc(t: ^testing.T) {
	swap :: proc(s, from, to: string) -> string {
		r, _ := strings.replace(s, from, to, 1, context.temp_allocator)
		return r
	}
	bad := []string {
		"",
		"not json",
		"[]",
		`{"avatarCharacterId":1,"characters":[]}`, // no such character
		`{"avatarCharacterId":"0","characters":[]}`,
		`{"avatarCharacterId":0,"characters":{}}`,
		`{"avatarCharacterId":0,"characters":[5]}`,
		`{"avatarCharacterId":-1,"characters":[{"name":"a","statistics":{}}]}`,
		swap(OLD_MIDGAME, `"name":"Bob"`, `"name":7`),
		swap(OLD_MIDGAME, `"ExperienceGoal":200`, `"ExperienceGoal":0`),
		swap(OLD_MIDGAME, `"ExperiencePoints":17`, `"ExperiencePoints":"17"`),
		swap(OLD_MIDGAME, `"Irritation":12`, `"Irritation":500`),
		swap(OLD_MIDGAME, `"Crit":1`, `"Crit":50`),
		swap(OLD_MIDGAME, `"Crit":1`, `"Crit":"1"`),
		swap(OLD_MIDGAME, `"statistics":{`, `"statistics":[`),
		swap(OLD_MIDGAME, `"AdvancementPoint":1`, `"AdvancementPoint":-4`),
	}
	for text, i in bad {
		out: Game
		testing.expectf(t, migrate_v1(&out, text) == .Invalid, "old save %d was accepted: %s", i, text)
		testing.expect(t, !out.has_avatar)
	}
}

// ---- the platform entry point ----

@(test)
load_game_picks_the_right_source :: proc(t: ^testing.T) {
	g := played_game()
	buf: [SAVE_BUF_SIZE]u8
	v2 := strings.clone(write(&g, buf[:]), context.temp_allocator)

	out: Game
	testing.expect_value(t, load_game(&out, "", ""), Load_Source.Fresh)
	testing.expect(t, !out.has_avatar)

	testing.expect_value(t, load_game(&out, "", OLD_MIDGAME), Load_Source.Migrated_V1)
	testing.expect_value(t, player_name(&out.player), "Bob")

	testing.expect_value(t, load_game(&out, "", OLD_NO_AVATAR), Load_Source.Fresh)
	testing.expect_value(t, load_game(&out, "", "garbage"), Load_Source.Rejected_V1)
	testing.expect(t, !out.has_avatar)

	// a v2 save always wins over the old one
	testing.expect_value(t, load_game(&out, v2, OLD_MIDGAME), Load_Source.V2)
	same_game(t, &g, &out)

	// a broken v2 save is rejected; the old save is not used as a fallback
	testing.expect_value(t, load_game(&out, "{broken", OLD_MIDGAME), Load_Source.Rejected_V2)
	testing.expect(t, !out.has_avatar)
}

// ---- hostile input ----

@(test)
mutated_saves_never_crash_and_always_validate :: proc(t: ^testing.T) {
	g := played_game()
	buf: [SAVE_BUF_SIZE]u8
	sources := [?]string{strings.clone(write(&g, buf[:]), context.temp_allocator), OLD_MIDGAME}
	alphabet := "{}[]\",:-0159.eE\\ntfu"
	r := seeded(2026)
	accepted := 0
	for iteration in 0 ..< 6000 {
		src := sources[iteration % len(sources)]
		mutated := make([]u8, len(src), context.temp_allocator)
		copy(mutated, src)
		for _ in 0 ..< 1 + rng_roll(&r, 0, 3) {
			i := rng_roll(&r, 0, len(mutated) - 1)
			switch rng_roll(&r, 0, 2) {
			case 0:
				mutated[i] = u8(rng_roll(&r, 0, 255))
			case 1:
				mutated[i] = alphabet[rng_roll(&r, 0, len(alphabet) - 1)]
			case 2:
				mutated = mutated[:i] // truncate
			}
			if len(mutated) == 0 {
				break
			}
		}
		out: Game
		source := load_game(&out, string(mutated) if iteration % 2 == 0 else "", string(mutated) if iteration % 2 == 1 else "")
		if source == .V2 || source == .Migrated_V1 {
			accepted += 1
			testing.expect(t, game_valid(&out))
			// and the result must be safe to play
			rr := seeded()
			check_butthole(&out, &rr, T0)
		}
	}
	testing.expect(t, accepted > 0, "the fuzzer never produced a loadable save, so it tested nothing")
}

// ---- abandoning must not bring the old save back ----

@(test)
the_empty_marker_stops_the_old_save_coming_back :: proc(t: ^testing.T) {
	buf: [SAVE_BUF_SIZE]u8
	marker := save_write_empty(buf[:])
	testing.expect_value(t, marker, `{"version":2,"empty":true}`)
	out: Game
	// found in the browser: after Abandon, a reload used to migrate the old save again
	testing.expect_value(t, load_game(&out, marker, OLD_MIDGAME), Load_Source.Fresh)
	testing.expect(t, !out.has_avatar)
	testing.expect_value(t, load_game(&out, marker, ""), Load_Source.Fresh)
	// only a literal true counts; anything else is an ordinary (invalid) v2 save
	for bad in ([]string{`{"version":2,"empty":false}`, `{"version":2,"empty":"true"}`, `{"version":2,"empty":1}`, `{"version":3,"empty":true}`, `{"empty":true}`}) {
		testing.expect_value(t, load_game(&out, bad, OLD_MIDGAME), Load_Source.Rejected_V2)
	}
}

@(test)
a_new_game_replaces_the_marker :: proc(t: ^testing.T) {
	g := new_game("Bob")
	buf: [SAVE_BUF_SIZE]u8
	text := write(&g, buf[:])
	out: Game
	testing.expect_value(t, load_game(&out, text, OLD_MIDGAME), Load_Source.V2)
	same_game(t, &g, &out)
}

// itch.io games all share one localStorage, and `worldData` is a generic key.
@(test)
another_games_world_data_is_not_migrated :: proc(t: ^testing.T) {
	others := []string {
		`{"characters":[{"name":"Hero","statistics":{"Gold":5,"Health":10}}],"messages":[],"avatarCharacterId":0}`,
		`{"characters":[{"name":"Hero","statistics":{}}],"messages":[],"avatarCharacterId":0}`,
		`{"characters":[{"name":"Hero"}],"avatarCharacterId":0}`,
	}
	for text, i in others {
		out: Game
		testing.expectf(t, migrate_v1(&out, text) == .Not_Ours || migrate_v1(&out, text) == .Invalid, "case %d was migrated", i)
		testing.expect(t, !out.has_avatar)
		testing.expect_value(t, load_game(&out, "", text) == .Migrated_V1, false)
		testing.expect(t, !out.has_avatar)
	}
	out: Game
	testing.expect_value(t, migrate_v1(&out, others[0]), Migrate_Result.Not_Ours)
	testing.expect_value(t, load_game(&out, "", others[0]), Load_Source.Fresh)
	testing.expect_value(t, load_game(&out, "", others[1]), Load_Source.Fresh)
}
