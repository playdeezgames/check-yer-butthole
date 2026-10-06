package cyb

// Saving and loading.
//
// v2 is our own format, stored under the key "cyb:save". v1 is the original
// game's `worldData` JSON; it is read once, converted, and never modified or
// deleted. Everything that is loaded goes through `game_valid` before it
// replaces the game, so a bad file changes nothing.

import "core:fmt"
import "core:unicode/utf8"

SAVE_VERSION :: 3 // v2 saves (before items) are still read
SAVE_KEY :: "cyb:save"
OLD_SAVE_KEY :: "worldData"
SAVE_BUF_SIZE :: 16384
VALUE_LIMIT :: i64(1) << 50

Load_Source :: enum {
	Fresh, // nothing usable to load, or the player abandoned the game (no avatar)
	V2, // loaded a game from a v2 or v3 save
	Migrated_V1, // converted the original game's save
	Rejected_V2, // a v2 save exists but is invalid; fresh game, the save is untouched
	Rejected_V1, // an old save exists but is invalid; fresh game, the save is untouched
}

// Everything the game relies on. A game that passes cannot crash the rules.
game_valid :: proc(g: ^Game) -> bool {
	if !g.has_avatar {
		return true
	}
	p := &g.player
	in_range :: proc(n, lo, hi: i64) -> bool {
		return n >= lo && n <= hi
	}
	if !in_range(i64(p.name_len), 1, NAME_MAX) || !utf8.valid_string(player_name(p)) {
		return false
	}
	if !in_range(p.checks, 0, VALUE_LIMIT) || !in_range(p.xp, 0, VALUE_LIMIT) || !in_range(p.level, 0, VALUE_LIMIT) || !in_range(p.points, 0, VALUE_LIMIT) {
		return false
	}
	if !in_range(p.xp_goal, 1, VALUE_LIMIT) { 	// a goal of 0 would level up forever
		return false
	}
	if !in_range(p.max_irritation, 1, VALUE_LIMIT) || !in_range(p.irritation, 0, p.max_irritation) {
		return false
	}
	for a in Advancement {
		if !in_range(i64(p.advancements[a]), 0, i64(advancement_max_level(a))) {
			return false
		}
	}
	if p.has_last_check && p.last_check_ms < 0 {
		return false
	}
	for n in p.items {
		if !in_range(n, 0, ITEM_COUNT_LIMIT) {
			return false
		}
	}
	if g.message_count < 0 || g.message_count > MAX_MESSAGES {
		return false
	}
	return true
}

// ---- writing ----

// Writes the v2 save into buf. Not ok if there is no avatar or the buffer is too small.
save_write :: proc(g: ^Game, buf: []u8) -> (text: string, ok: bool) {
	if !g.has_avatar {
		return "", false
	}
	p := &g.player
	w := json_writer(buf)
	field :: proc(w: ^Json_Writer, name: string, value: i64) {
		json_raw(w, ",\"")
		json_raw(w, name)
		json_raw(w, "\":")
		json_int_out(w, value)
	}
	json_raw(&w, "{\"version\":")
	json_int_out(&w, i64(SAVE_VERSION))
	json_raw(&w, ",\"name\":")
	json_string_out(&w, player_name(p))
	field(&w, "checks", p.checks)
	field(&w, "xp", p.xp)
	field(&w, "xp_goal", p.xp_goal)
	field(&w, "level", p.level)
	field(&w, "points", p.points)
	field(&w, "irritation", p.irritation)
	field(&w, "max_irritation", p.max_irritation)
	json_raw(&w, ",\"last_check_ms\":")
	if p.has_last_check {
		json_int_out(&w, p.last_check_ms)
	} else {
		json_raw(&w, "null")
	}
	json_raw(&w, ",\"advancements\":{")
	for a in Advancement {
		if a != min(Advancement) {
			json_raw(&w, ",")
		}
		json_raw(&w, "\"")
		json_raw(&w, advancement_info[a].key)
		json_raw(&w, "\":")
		json_int_out(&w, i64(p.advancements[a]))
	}
	json_raw(&w, "},\"items\":{")
	for item in Item {
		if item != min(Item) {
			json_raw(&w, ",")
		}
		json_raw(&w, "\"")
		json_raw(&w, item_info[item].key)
		json_raw(&w, "\":")
		json_int_out(&w, p.items[item])
	}
	json_raw(&w, "},\"messages\":[")
	for i in 0 ..< g.message_count {
		if i > 0 {
			json_raw(&w, ",")
		}
		json_string_out(&w, message_text(&g.messages[i]))
	}
	json_raw(&w, "]}")
	return json_result(&w)
}

// What is stored after the player abandons a game. A v2 save that is present
// (even this empty one) means the new format is in charge, so the original
// game's save is never migrated a second time. The old key itself is not touched.
save_write_empty :: proc(buf: []u8) -> string {
	return fmt.bprintf(buf, `{{"version":%d,"empty":true}}`, SAVE_VERSION)
}

// ---- reading ----

@(private = "file")
load_messages :: proc(g: ^Game, doc: ^Json_Doc, arr: int) {
	if json_kind(doc, arr) != .Array || arr == 0 {
		return
	}
	for c := doc.nodes[arr].first; c != 0 && g.message_count < MAX_MESSAGES; c = doc.nodes[c].next {
		s, ok := json_string(doc, c)
		if !ok {
			continue
		}
		text := utf8_prefix(s, MESSAGE_LEN)
		m := &g.messages[g.message_count]
		g.message_count += 1
		copy(m.buf[:], text)
		m.len = len(text)
	}
}

// Reads a required whole number field of a v2 save.
@(private = "file")
need_int :: proc(doc: ^Json_Doc, obj: int, key: string) -> (i64, bool) {
	return json_int(doc, json_get(doc, obj, key))
}

// Parses a v2 or v3 save into out (an empty Game for the abandon marker). out is only
// touched when the result is true.
save_read :: proc(out: ^Game, text: string) -> bool {
	doc := new(Json_Doc)
	defer free(doc)
	if !json_parse(doc, text) {
		return false
	}
	root := doc.root
	if json_kind(doc, root) != .Object {
		return false
	}
	version, vok := need_int(doc, root, "version")
	if !vok || (version != 2 && version != SAVE_VERSION) {
		return false
	}
	if marker := json_get(doc, root, "empty"); json_kind(doc, marker) == .Bool && doc.nodes[marker].boolean {
		out^ = {} // the marker written on abandon: a valid save with no game in it
		return true
	}
	g: Game
	g.has_avatar = true
	p := &g.player
	name, nok := json_string(doc, json_get(doc, root, "name"))
	if !nok || len(name) < 1 || len(name) > NAME_MAX {
		return false
	}
	copy(p.name_buf[:], name)
	p.name_len = len(name)
	ok: bool
	if p.checks, ok = need_int(doc, root, "checks"); !ok {return false}
	if p.xp, ok = need_int(doc, root, "xp"); !ok {return false}
	if p.xp_goal, ok = need_int(doc, root, "xp_goal"); !ok {return false}
	if p.level, ok = need_int(doc, root, "level"); !ok {return false}
	if p.points, ok = need_int(doc, root, "points"); !ok {return false}
	if p.irritation, ok = need_int(doc, root, "irritation"); !ok {return false}
	if p.max_irritation, ok = need_int(doc, root, "max_irritation"); !ok {return false}
	last := json_get(doc, root, "last_check_ms")
	switch json_kind(doc, last) {
	case .Null:
		if last == 0 {
			return false // the key must be there, as a number or null
		}
	case .Number:
		if p.last_check_ms, ok = json_int(doc, last); !ok {return false}
		p.has_last_check = true
	case .Bool, .String, .Array, .Object:
		return false
	}
	advs := json_get(doc, root, "advancements")
	if json_kind(doc, advs) != .Object {
		return false
	}
	for a in Advancement {
		if a == .Lost_And_Found && version == 2 {
			continue // added in v3; a v2 save has none, which is level 0
		}
		level: i64
		if level, ok = need_int(doc, advs, advancement_info[a].key); !ok || level < 0 || level > i64(advancement_max_level(a)) {
			return false // checked before narrowing to int
		}
		p.advancements[a] = int(level)
	}
	if version == SAVE_VERSION {
		items := json_get(doc, root, "items")
		if json_kind(doc, items) != .Object {
			return false
		}
		for item in Item {
			if p.items[item], ok = need_int(doc, items, item_info[item].key); !ok {return false}
		}
	}
	load_messages(&g, doc, json_get(doc, root, "messages"))
	if !game_valid(&g) {
		return false
	}
	out^ = g
	return true
}

Migrate_Result :: enum {
	Ok,
	No_Avatar, // a valid old save with no character yet: same as a fresh game
	Not_Ours, // looks like another game's `worldData` (itch.io games share one localStorage)
	Invalid,
}

// A number that may be missing or null (JSON.stringify writes NaN as null), in
// which case `default` is used. Any other type is an error.
@(private = "file")
old_stat :: proc(doc: ^Json_Doc, stats: int, key: string, default: i64) -> (i64, bool) {
	n := json_get(doc, stats, key)
	if json_kind(doc, n) == .Null {
		return default, true
	}
	return json_int(doc, n)
}

// Converts the original game's `worldData` JSON. out is only touched on Ok.
migrate_v1 :: proc(out: ^Game, text: string) -> Migrate_Result {
	doc := new(Json_Doc)
	defer free(doc)
	if !json_parse(doc, text) {
		return .Invalid
	}
	root := doc.root
	if json_kind(doc, root) != .Object {
		return .Invalid
	}
	avatar := json_get(doc, root, "avatarCharacterId")
	if json_kind(doc, avatar) == .Null {
		return .No_Avatar
	}
	id, idok := json_int(doc, avatar)
	if !idok || id < 0 || id >= JSON_MAX_NODES {
		return .Invalid
	}
	chars := json_get(doc, root, "characters")
	if json_kind(doc, chars) != .Array {
		return .Invalid
	}
	character := json_at(doc, chars, int(id))
	if json_kind(doc, character) != .Object {
		return .Invalid
	}
	g: Game
	g.has_avatar = true
	p := &g.player
	name, nok := json_string(doc, json_get(doc, character, "name"))
	if !nok {
		return .Invalid
	}
	player_set_name(p, name)
	stats := json_get(doc, character, "statistics")
	if json_kind(doc, stats) != .Object {
		return .Invalid
	}
	// Every game on itch.io shares one localStorage, and the original's key is a
	// generic one. Only this game's character has a ButtholeChecks statistic
	// (possibly null, if it was once NaN); anything without it is someone else's.
	if json_get(doc, stats, "ButtholeChecks") == 0 {
		return .Not_Ours
	}
	ok: bool
	if p.checks, ok = old_stat(doc, stats, "ButtholeChecks", 0); !ok {return .Invalid}
	if p.xp, ok = old_stat(doc, stats, "ExperiencePoints", 0); !ok {return .Invalid}
	if p.xp_goal, ok = old_stat(doc, stats, "ExperienceGoal", START_XP_GOAL); !ok {return .Invalid}
	if p.level, ok = old_stat(doc, stats, "ExperienceLevel", 0); !ok {return .Invalid}
	if p.points, ok = old_stat(doc, stats, "AdvancementPoint", 0); !ok {return .Invalid}
	if p.irritation, ok = old_stat(doc, stats, "Irritation", 0); !ok {return .Invalid}
	if p.max_irritation, ok = old_stat(doc, stats, "MaximumIrritation", START_MAX_IRRITATION); !ok {return .Invalid}
	last, lok := old_stat(doc, stats, "LastCheckTime", -1)
	if !lok {
		return .Invalid
	}
	if last >= 0 {
		p.has_last_check = true
		p.last_check_ms = last
	}
	advs := json_get(doc, character, "advancements")
	if json_kind(doc, advs) == .Object {
		for a in Advancement {
			level: i64
			if level, ok = old_stat(doc, advs, advancement_info[a].key, 0); !ok || level < 0 || level > i64(advancement_max_level(a)) {
				return .Invalid // checked before narrowing to int
			}
			p.advancements[a] = int(level)
		}
	} else if advs != 0 && json_kind(doc, advs) != .Null {
		return .Invalid
	}
	load_messages(&g, doc, json_get(doc, root, "messages"))
	if !game_valid(&g) {
		return .Invalid
	}
	out^ = g
	return .Ok
}

// The one entry point for the platform: pass the text stored under SAVE_KEY and
// under OLD_SAVE_KEY ("" for absent). A v2 save always wins; the old save is only
// read when there is no v2 save at all. g is a fresh game unless the result is V2 or
// Migrated_V1. Nothing is ever deleted here.
load_game :: proc(g: ^Game, v2_text, v1_text: string) -> Load_Source {
	g^ = {}
	if len(v2_text) > 0 {
		if !save_read(g, v2_text) {
			return .Rejected_V2
		}
		return .V2 if g.has_avatar else .Fresh
	}
	if len(v1_text) > 0 {
		switch migrate_v1(g, v1_text) {
		case .Ok:
			return .Migrated_V1
		case .No_Avatar, .Not_Ours:
			return .Fresh
		case .Invalid:
			return .Rejected_V1
		}
	}
	return .Fresh
}
