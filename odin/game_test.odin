#+build !js
package cyb

import "core:testing"

T0 :: i64(1_700_000_000_000)

new_game :: proc(name := "tester") -> Game {
	g: Game
	game_start(&g, name)
	return g
}

seeded :: proc(seed: u64 = 1) -> Rng {
	r: Rng
	rng_seed(&r, seed)
	return r
}

has_message :: proc(g: ^Game, text: string) -> bool {
	for i in 0 ..< g.message_count {
		if message_text(&g.messages[i]) == text {
			return true
		}
	}
	return false
}

// ---- rng ----

@(test)
roll_covers_the_whole_inclusive_range :: proc(t: ^testing.T) {
	r := seeded()
	seen: [101]int
	for _ in 0 ..< 100_000 {
		v := rng_roll(&r, 1, 100)
		testing.expect(t, v >= 1 && v <= 100)
		seen[v] += 1
	}
	testing.expect_value(t, seen[0], 0)
	for v in 1 ..= 100 {
		testing.expectf(t, seen[v] > 0, "value %d never rolled", v)
	}
}

@(test)
roll_honours_the_minimum :: proc(t: ^testing.T) {
	r := seeded(7)
	for _ in 0 ..< 10_000 {
		v := rng_roll(&r, 5, 7)
		testing.expect(t, v >= 5 && v <= 7)
	}
	testing.expect_value(t, rng_roll(&r, 3, 3), 3)
}

@(test)
same_seed_same_sequence :: proc(t: ^testing.T) {
	a := seeded(42)
	b := seeded(42)
	c := seeded(43)
	differs := false
	for _ in 0 ..< 20 {
		x := rng_next(&a)
		testing.expect_value(t, x, rng_next(&b))
		if x != rng_next(&c) {
			differs = true
		}
	}
	testing.expect(t, differs)
}

// ---- new game and names ----

@(test)
new_game_has_original_starting_stats :: proc(t: ^testing.T) {
	g := new_game("Bob")
	p := &g.player
	testing.expect(t, g.has_avatar)
	testing.expect_value(t, player_name(p), "Bob")
	testing.expect_value(t, p.xp, 0)
	testing.expect_value(t, p.xp_goal, 100)
	testing.expect_value(t, p.level, 0)
	testing.expect_value(t, p.points, 0)
	testing.expect_value(t, p.irritation, 0)
	testing.expect_value(t, p.max_irritation, 100)
	testing.expect_value(t, p.checks, 0)
	testing.expect(t, !p.has_last_check)
	for a in Advancement {
		testing.expect_value(t, p.advancements[a], 0)
	}
}

@(test)
blank_names_become_n00b :: proc(t: ^testing.T) {
	for name in ([]string{"", "   ", "\t\n"}) {
		g := new_game(name)
		testing.expect_value(t, player_name(&g.player), "n00b")
	}
	g := new_game("  spaced  ")
	testing.expect_value(t, player_name(&g.player), "  spaced  ")
}

@(test)
long_names_are_cut_on_a_character_boundary :: proc(t: ^testing.T) {
	long := "ééééééééééééééééééééééééééééééééééééééééé" // 41 x 2 bytes
	g := new_game(long)
	name := player_name(&g.player)
	testing.expect(t, len(name) <= NAME_MAX)
	testing.expect_value(t, len(name) % 2, 0)
	testing.expect_value(t, name, long[:len(name)])
}

@(test)
abandon_clears_everything :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	check_butthole(&g, &r, T0)
	game_abandon(&g)
	testing.expect(t, !g.has_avatar)
	testing.expect_value(t, g.player.xp, 0)
	testing.expect_value(t, g.message_count, 0)
}

// ---- crits ----

@(test)
crit_boundaries :: proc(t: ^testing.T) {
	testing.expect(t, !is_crit(1, 0), "0% must never crit, even on a roll of 1")
	testing.expect(t, is_crit(1, 1))
	testing.expect(t, !is_crit(2, 1))
	testing.expect(t, is_crit(6, 6))
	testing.expect(t, !is_crit(7, 6))
	testing.expect(t, is_crit(100, 100))
}

@(test)
zero_crit_never_crits :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded(99)
	for i in 0 ..< 20_000 {
		g.player.irritation = 0
		g.player.xp = 0
		check_butthole(&g, &r, T0)
		testing.expectf(t, !has_message(&g, "Critical check! Doubly effective!"), "crit at 0%% on check %d", i)
		testing.expect_value(t, g.player.xp, 1)
	}
}

@(test)
crit_rate_matches_the_percentage :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Crit] = 6 // 6%
	r := seeded(5)
	crits := 0
	N :: 100_000
	for _ in 0 ..< N {
		g.player.irritation = 0
		g.player.xp = 0
		check_butthole(&g, &r, T0)
		if has_message(&g, "Critical check! Doubly effective!") {
			crits += 1
			testing.expect_value(t, g.player.xp, 2)
		}
	}
	// 6% of 100000 is 6000; allow a wide margin (about 6 standard deviations)
	testing.expectf(t, crits > 5_000 && crits < 7_000, "crits: %d", crits)
}

@(test)
thoroughness_scales_xp_and_crits_double_it :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Thoroughness] = 3 // 4 per check
	r := seeded()
	check_butthole(&g, &r, T0)
	crit := has_message(&g, "Critical check! Doubly effective!")
	testing.expect_value(t, g.player.xp, 8 if crit else 4)
	testing.expect_value(t, g.player.checks, g.player.xp)
}

// ---- the check and irritation ----

@(test)
check_messages_and_stats :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	check_butthole(&g, &r, T0)
	testing.expect(t, has_message(&g, "You check yer butthole!"))
	testing.expect(t, has_message(&g, "+1 irritation"))
	testing.expect(t, has_message(&g, "+1 XP"))
	testing.expect_value(t, g.player.irritation, 1)
	testing.expect_value(t, g.player.xp, 1)
	testing.expect_value(t, g.player.checks, 1)
}

@(test)
messages_are_cleared_each_check :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	check_butthole(&g, &r, T0)
	first := g.message_count
	check_butthole(&g, &r, T0)
	testing.expect_value(t, g.message_count, first)
}

@(test)
too_irritated_refuses_and_gives_nothing :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	g.player.irritation = 100
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	check_butthole(&g, &r, T0)
	testing.expect_value(t, g.message_count, 1)
	testing.expect(t, has_message(&g, "Yer butthole is too irritated!"))
	testing.expect_value(t, g.player.xp, 0)
	testing.expect_value(t, g.player.irritation, 100)
	testing.expect_value(t, g.player.checks, 0)
}

@(test)
hundred_checks_fill_irritation_then_refuse :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	for _ in 0 ..< 100 {
		check_butthole(&g, &r, T0) // no time passes
	}
	testing.expect_value(t, g.player.irritation, 100)
	check_butthole(&g, &r, T0)
	testing.expect(t, has_message(&g, "Yer butthole is too irritated!"))
}

@(test)
first_check_stamps_the_time_and_recovers_nothing :: proc(t: ^testing.T) {
	g := new_game()
	g.player.irritation = 5
	recover_irritation(&g, T0)
	testing.expect(t, g.player.has_last_check)
	testing.expect_value(t, g.player.last_check_ms, T0)
	testing.expect_value(t, g.player.irritation, 5)
	testing.expect_value(t, g.message_count, 0)
}

@(test)
recovery_needs_a_whole_interval :: proc(t: ^testing.T) {
	g := new_game()
	g.player.irritation = 10
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	recover_irritation(&g, T0 + 59_999)
	testing.expect_value(t, g.player.irritation, 10)
	testing.expect_value(t, g.player.last_check_ms, T0)
	recover_irritation(&g, T0 + 60_000)
	testing.expect_value(t, g.player.irritation, 9)
	testing.expect_value(t, g.player.last_check_ms, T0 + 60_000)
	testing.expect(t, has_message(&g, "-1 Irritation"))
}

@(test)
recovery_keeps_partial_progress :: proc(t: ^testing.T) {
	g := new_game()
	g.player.irritation = 10
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	recover_irritation(&g, T0 + 150_000) // 2.5 intervals
	testing.expect_value(t, g.player.irritation, 8)
	testing.expect_value(t, g.player.last_check_ms, T0 + 120_000)
	recover_irritation(&g, T0 + 180_000) // the half interval is still counted
	testing.expect_value(t, g.player.irritation, 7)
}

@(test)
recovery_is_capped_at_current_irritation_and_stamp_still_advances :: proc(t: ^testing.T) {
	g := new_game()
	g.player.irritation = 2
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	recover_irritation(&g, T0 + 10 * 60_000)
	testing.expect_value(t, g.player.irritation, 0)
	testing.expect_value(t, g.player.last_check_ms, T0 + 10 * 60_000)
	testing.expect(t, has_message(&g, "-2 Irritation"))
}

@(test)
recovery_uses_the_advancement_interval :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Irritation_Recovery] = 6 // 30 s
	g.player.irritation = 10
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	recover_irritation(&g, T0 + 90_000)
	testing.expect_value(t, g.player.irritation, 7)
}

@(test)
clock_going_backwards_changes_nothing :: proc(t: ^testing.T) {
	g := new_game()
	g.player.irritation = 10
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	recover_irritation(&g, T0 - 500_000)
	testing.expect_value(t, g.player.irritation, 10)
	testing.expect_value(t, g.player.last_check_ms, T0)
}

@(test)
recovery_runs_even_when_the_check_is_refused :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	g.player.irritation = 100
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	check_butthole(&g, &r, T0 + 60_000)
	testing.expect(t, has_message(&g, "-1 Irritation"))
	testing.expect_value(t, g.player.irritation, 100) // 99, then the check adds 1
	testing.expect(t, has_message(&g, "You check yer butthole!"))
}

// ---- levelling ----

@(test)
levelling_up_follows_the_original :: proc(t: ^testing.T) {
	g := new_game()
	p := &g.player
	p.xp = 100
	handle_levelling(&g)
	testing.expect_value(t, p.level, 1)
	testing.expect_value(t, p.xp, 0)
	testing.expect_value(t, p.points, 1)
	testing.expect_value(t, p.xp_goal, 200)
	testing.expect(t, has_message(&g, "+1 Advancement Point(s)"))
	testing.expect(t, has_message(&g, "Yer now level 1"))
}

@(test)
xp_carries_over_a_level_up :: proc(t: ^testing.T) {
	g := new_game()
	g.player.xp = 130
	handle_levelling(&g)
	testing.expect_value(t, g.player.level, 1)
	testing.expect_value(t, g.player.xp, 30)
}

@(test)
several_levels_at_once :: proc(t: ^testing.T) {
	g := new_game()
	p := &g.player
	p.xp = 700 // 100 + 200 + 400 = 700 exactly
	handle_levelling(&g)
	testing.expect_value(t, p.level, 3)
	testing.expect_value(t, p.points, 1 + 2 + 3)
	testing.expect_value(t, p.xp, 0)
	testing.expect_value(t, p.xp_goal, 800)
}

@(test)
one_below_the_goal_does_not_level :: proc(t: ^testing.T) {
	g := new_game()
	g.player.xp = 99
	handle_levelling(&g)
	testing.expect_value(t, g.player.level, 0)
	testing.expect_value(t, g.message_count, 0)
}

@(test)
checking_to_level_one :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded()
	p := &g.player
	p.xp = 99
	check_butthole(&g, &r, T0)
	testing.expect_value(t, p.level, 1)
	testing.expect(t, p.xp <= 1) // 99+1 = 100, or 101 with a crit
}

@(test)
message_list_is_bounded :: proc(t: ^testing.T) {
	g := new_game()
	for _ in 0 ..< 50 {
		add_message(&g, "message")
	}
	testing.expect_value(t, g.message_count, MAX_MESSAGES)
	add_message(&g, "%s", "no panic past the end")
}

// ---- advancements ----

@(test)
advancement_tables_match_the_original :: proc(t: ^testing.T) {
	for a in Advancement {
		info := advancement_info[a]
		testing.expect_value(t, len(info.effects), len(info.costs) + 1)
		testing.expect_value(t, advancement_max_level(a), len(info.costs))
	}
	testing.expect_value(t, advancement_effect_at(.Crit, 0), 0)
	testing.expect_value(t, advancement_effect_at(.Crit, 6), 6)
	testing.expect_value(t, advancement_effect_at(.Thoroughness, 3), 4)
	testing.expect_value(t, advancement_effect_at(.Irritation_Recovery, 0), 60)
	testing.expect_value(t, advancement_effect_at(.Irritation_Recovery, 6), 30)
	testing.expect_value(t, advancement_max_level(.Crit), 6)
	testing.expect_value(t, advancement_max_level(.Thoroughness), 3)
	testing.expect_value(t, advancement_max_level(.Irritation_Recovery), 6)
}

@(test)
buying_spends_points_and_levels_up :: proc(t: ^testing.T) {
	g := new_game()
	p := &g.player
	p.points = 3
	testing.expect(t, can_buy(p, .Crit))
	testing.expect(t, buy(p, .Crit)) // costs 1
	testing.expect_value(t, p.points, 2)
	testing.expect_value(t, p.advancements[.Crit], 1)
	testing.expect_value(t, effect(p, .Crit), 1)
	cost, ok := next_cost(p, .Crit)
	testing.expect_value(t, cost, 2)
	testing.expect(t, ok)
	testing.expect(t, buy(p, .Crit)) // costs 2
	testing.expect_value(t, p.points, 0)
	testing.expect(t, !can_buy(p, .Crit)) // next costs 4
	testing.expect(t, !buy(p, .Crit))
	testing.expect_value(t, p.advancements[.Crit], 2)
}

@(test)
cannot_buy_without_enough_points :: proc(t: ^testing.T) {
	g := new_game()
	p := &g.player
	p.points = 4
	testing.expect(t, !can_buy(p, .Thoroughness)) // costs 5
	testing.expect(t, !buy(p, .Thoroughness))
	testing.expect_value(t, p.points, 4)
}

@(test)
every_advancement_can_be_bought_to_max :: proc(t: ^testing.T) {
	for a in Advancement {
		g := new_game()
		p := &g.player
		p.points = 1_000
		for i in 0 ..< advancement_max_level(a) {
			testing.expectf(t, buy(p, a), "%v level %d", a, i)
		}
		testing.expect(t, at_max_level(p, a))
		_, ok := next_cost(p, a)
		testing.expect(t, !ok)
		testing.expect(t, !buy(p, a))
		testing.expect_value(t, effect(p, a), advancement_info[a].effects[advancement_max_level(a)])
	}
}

@(test)
total_cost_to_max_matches_the_original_costs :: proc(t: ^testing.T) {
	g := new_game()
	p := &g.player
	p.points = 1_000
	for a in Advancement {
		for buy(p, a) {}
	}
	spent := 1_000 - p.points
	testing.expect_value(t, spent, (1 + 2 + 4 + 8 + 16 + 32) * 2 + (5 + 10 + 15) + (2 + 4 + 8 + 16 + 32 + 64))
}

// ---- Lost and Found and items ----

@(test)
find_boundaries :: proc(t: ^testing.T) {
	testing.expect(t, !is_find(1, 0), "0% must never find, even on a roll of 1")
	testing.expect(t, is_find(1, 1))
	testing.expect(t, !is_find(2, 1))
	testing.expect(t, is_find(6, 6))
	testing.expect(t, !is_find(7, 6))
}

@(test)
item_weights_are_the_agreed_ones :: proc(t: ^testing.T) {
	testing.expect_value(t, item_weight_total(), 1000)
	// walk every possible roll: banana 60%, cheese 30%, car keys 9.9%, wedding ring 0.1%
	counts: [Item]int
	for roll in 1 ..= 1000 {
		counts[item_for_roll(roll)] += 1
	}
	testing.expect_value(t, counts[.Banana], 600)
	testing.expect_value(t, counts[.Cheese], 300)
	testing.expect_value(t, counts[.Car_Keys], 99)
	testing.expect_value(t, counts[.Wedding_Ring], 1)
	// and the edges between them
	testing.expect_value(t, item_for_roll(1), Item.Banana)
	testing.expect_value(t, item_for_roll(600), Item.Banana)
	testing.expect_value(t, item_for_roll(601), Item.Cheese)
	testing.expect_value(t, item_for_roll(900), Item.Cheese)
	testing.expect_value(t, item_for_roll(901), Item.Car_Keys)
	testing.expect_value(t, item_for_roll(999), Item.Car_Keys)
	testing.expect_value(t, item_for_roll(1000), Item.Wedding_Ring)
}

@(test)
level_zero_never_finds_anything :: proc(t: ^testing.T) {
	g := new_game()
	r := seeded(11)
	for i in 0 ..< 20_000 {
		g.player.irritation = 0
		check_butthole(&g, &r, T0)
	}
	testing.expect_value(t, items_total(&g.player), 0)
}

@(test)
find_rate_matches_the_percentage :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Lost_And_Found] = 6 // 6%
	r := seeded(21)
	N :: 100_000
	for _ in 0 ..< N {
		g.player.irritation = 0
		g.player.xp = 0
		check_butthole(&g, &r, T0)
	}
	found := items_total(&g.player)
	// 6% of 100000 is 6000; allow about 6 standard deviations
	testing.expectf(t, found > 5_000 && found < 7_000, "found: %d", found)
	// and in the agreed proportions: bananas well ahead of cheese, cheese well ahead of keys
	testing.expect(t, g.player.items[.Banana] > g.player.items[.Cheese])
	testing.expect(t, g.player.items[.Cheese] > 3 * g.player.items[.Car_Keys])
	testing.expect(t, g.player.items[.Car_Keys] > g.player.items[.Wedding_Ring])
}

@(test)
a_find_adds_to_the_count_and_says_so :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Lost_And_Found] = 6
	r := seeded(3)
	said := map[string]bool{}
	defer delete(said)
	for _ in 0 ..< 3_000 {
		g.player.irritation = 0
		before := items_total(&g.player)
		check_butthole(&g, &r, T0)
		after := items_total(&g.player)
		testing.expect(t, after - before <= 1, "at most one item per check")
		for item in Item {
			if has_message(&g, item_info[item].found_message) {
				testing.expect_value(t, after - before, 1)
				said[item_info[item].found_message] = true
			}
		}
		if after == before {
			for item in Item {
				testing.expect(t, !has_message(&g, item_info[item].found_message), "a message without a find")
			}
		}
	}
	testing.expect(t, said[item_info[Item.Banana].found_message])
	testing.expect(t, said[item_info[Item.Cheese].found_message])
	testing.expect(t, items_total(&g.player) > 100)
}

@(test)
the_find_message_comes_after_the_xp_message :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Lost_And_Found] = 6
	r := seeded(8)
	for _ in 0 ..< 500 {
		g.player.irritation = 0
		g.player.xp = 0
		check_butthole(&g, &r, T0)
		for item in Item {
			if has_message(&g, item_info[item].found_message) {
				xp_at, found_at := -1, -1
				for i in 0 ..< g.message_count {
					text := message_text(&g.messages[i])
					if text == "+1 XP" || text == "+2 XP" {
						xp_at = i
					}
					if text == item_info[item].found_message {
						found_at = i
					}
				}
				testing.expect(t, xp_at >= 0 && found_at > xp_at)
				return
			}
		}
	}
	testing.fail_now(t, "no find in 500 checks at 6%")
}

@(test)
a_refused_check_never_finds_anything :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Lost_And_Found] = 6
	r := seeded(4)
	g.player.has_last_check = true
	g.player.last_check_ms = T0
	for _ in 0 ..< 5_000 {
		g.player.irritation = 100
		check_butthole(&g, &r, T0)
	}
	testing.expect_value(t, items_total(&g.player), 0)
}

@(test)
item_counts_stop_at_the_limit :: proc(t: ^testing.T) {
	g := new_game()
	g.player.advancements[.Lost_And_Found] = 6
	for item in Item {
		g.player.items[item] = ITEM_COUNT_LIMIT
	}
	r := seeded(5)
	for _ in 0 ..< 1_000 {
		g.player.irritation = 0
		check_butthole(&g, &r, T0)
	}
	for item in Item {
		testing.expect_value(t, g.player.items[item], ITEM_COUNT_LIMIT)
	}
}
