package cyb

import "core:fmt"

// The rules of the game. Nothing here touches the browser or the clock: time comes
// in as `now_ms` (milliseconds since the epoch) so everything can be tested.

NAME_MAX :: 64
MESSAGE_LEN :: 128
MAX_MESSAGES :: 16
DEFAULT_NAME :: "n00b"
START_XP_GOAL :: 100
START_MAX_IRRITATION :: 100
CRIT_ROLL_SIDES :: 100
ITEM_COUNT_LIMIT :: i64(1) << 50

Advancement :: enum {
	Crit,
	Thoroughness,
	Irritation_Recovery,
	Lost_And_Found, // the chance to find an item when checking
}

Advancement_Info :: struct {
	key:         string, // name in the old and new save files
	name:        string,
	description: string,
	costs:       []int, // cost to go from level i to i+1; max level is len(costs)
	effects:     []int, // effect at level i; one longer than costs
}

crit_costs := [?]int{1, 2, 4, 8, 16, 32}
crit_effects := [?]int{0, 1, 2, 3, 4, 5, 6}
thoroughness_costs := [?]int{5, 10, 15}
thoroughness_effects := [?]int{1, 2, 3, 4}
recovery_costs := [?]int{1, 2, 4, 8, 16, 32}
recovery_effects := [?]int{60, 55, 50, 45, 40, 35, 30}
find_costs := [?]int{2, 4, 8, 16, 32, 64}
find_effects := [?]int{0, 1, 2, 3, 4, 5, 6}

advancement_info := [Advancement]Advancement_Info {
	.Crit = {
		key = "Crit",
		name = "Critical Check %",
		description = "Chance of getting a \"crit\" when checking yer butthole.",
		costs = crit_costs[:],
		effects = crit_effects[:],
	},
	.Thoroughness = {
		key = "Thoroughness",
		name = "Thoroughness",
		description = "You can't be too careful about this!",
		costs = thoroughness_costs[:],
		effects = thoroughness_effects[:],
	},
	.Irritation_Recovery = {
		key = "IrritationRecovery",
		name = "Irritation Recovery",
		description = "Time in seconds before recovering irritation due to friction from checking.",
		costs = recovery_costs[:],
		effects = recovery_effects[:],
	},
	.Lost_And_Found = {
		key = "LostAndFound",
		name = "Lost and Found",
		description = "Everything you've lost has to be somewhere.",
		costs = find_costs[:],
		effects = find_effects[:],
	},
}

// What a find can turn up. See docs/items-design.md for where each comes from.
Item :: enum {
	Banana,
	Cheese,
	Car_Keys,
	Wedding_Ring,
}

Item_Info :: struct {
	key:           string, // name in the save file
	name:          string, // as shown in the inventory
	found_message: string,
	weight:        int, // chance of being the item found, relative to the others
}

item_info := [Item]Item_Info {
	.Banana = {key = "Banana", name = "Banana", found_message = "You found a banana. Nobody asked for this.", weight = 600},
	.Cheese = {key = "Cheese", name = "Cheese", found_message = "You found cheese. So that's where it went.", weight = 300},
	.Car_Keys = {key = "CarKeys", name = "Car keys", found_message = "You found car keys. Somebody has been looking everywhere.", weight = 99},
	.Wedding_Ring = {key = "WeddingRing", name = "Wedding ring", found_message = "You found a wedding ring. The wedding may now proceed.", weight = 1},
}

Message :: struct {
	buf: [MESSAGE_LEN]u8,
	len: int,
}

Player :: struct {
	name_buf:       [NAME_MAX]u8,
	name_len:       int,
	checks:         i64, // ButtholeChecks
	xp:             i64,
	xp_goal:        i64,
	level:          i64,
	points:         i64, // advancement points
	irritation:     i64,
	max_irritation: i64,
	has_last_check: bool,
	last_check_ms:  i64,
	advancements:   [Advancement]int,
	items:          [Item]i64, // how many of each have been found
}

Game :: struct {
	has_avatar:    bool,
	player:        Player,
	messages:      [MAX_MESSAGES]Message,
	message_count: int,
}

// ---- names and messages ----

player_name :: proc(p: ^Player) -> string {
	return string(p.name_buf[:p.name_len])
}

// The longest prefix of text that is at most n bytes and does not cut a UTF-8
// sequence in half.
utf8_prefix :: proc(text: string, n: int) -> string {
	n := min(n, len(text))
	for n > 0 && n < len(text) && (text[n] & 0xC0) == 0x80 {
		n -= 1
	}
	return text[:n]
}

// An empty or whitespace-only name becomes "n00b"; otherwise it is used as typed,
// cut to NAME_MAX bytes (on a character boundary).
player_set_name :: proc(p: ^Player, name: string) {
	blank := true
	for c in transmute([]u8)name {
		if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
			blank = false
			break
		}
	}
	text := utf8_prefix(DEFAULT_NAME if blank else name, NAME_MAX)
	copy(p.name_buf[:], text)
	p.name_len = len(text)
}

message_text :: proc(m: ^Message) -> string {
	return string(m.buf[:m.len])
}

clear_messages :: proc(g: ^Game) {
	g.message_count = 0
}

add_message :: proc(g: ^Game, format: string, args: ..any) {
	if g.message_count >= MAX_MESSAGES {
		return
	}
	m := &g.messages[g.message_count]
	g.message_count += 1
	text := fmt.bprintf(m.buf[:], format, ..args)
	m.len = len(text)
}

// ---- starting a game ----

player_init :: proc(p: ^Player, name: string) {
	p^ = {}
	player_set_name(p, name)
	p.xp_goal = START_XP_GOAL
	p.max_irritation = START_MAX_IRRITATION
}

game_start :: proc(g: ^Game, name: string) {
	g^ = {}
	player_init(&g.player, name)
	g.has_avatar = true
}

game_abandon :: proc(g: ^Game) {
	g^ = {}
}

// ---- advancements ----

advancement_max_level :: proc(a: Advancement) -> int {
	return len(advancement_info[a].costs)
}

advancement_effect_at :: proc(a: Advancement, level: int) -> int {
	return advancement_info[a].effects[level]
}

// The effect of the player's current level (small numbers, so int).
effect :: proc(p: ^Player, a: Advancement) -> int {
	return advancement_effect_at(a, p.advancements[a])
}

at_max_level :: proc(p: ^Player, a: Advancement) -> bool {
	return p.advancements[a] >= advancement_max_level(a)
}

// Cost of the next level; ok is false at max level.
next_cost :: proc(p: ^Player, a: Advancement) -> (cost: int, ok: bool) {
	if at_max_level(p, a) {
		return 0, false
	}
	return advancement_info[a].costs[p.advancements[a]], true
}

can_buy :: proc(p: ^Player, a: Advancement) -> bool {
	cost, ok := next_cost(p, a)
	return ok && i64(cost) <= p.points
}

buy :: proc(p: ^Player, a: Advancement) -> bool {
	if !can_buy(p, a) {
		return false
	}
	cost, _ := next_cost(p, a)
	p.points -= i64(cost)
	p.advancements[a] += 1
	return true
}

// ---- the check ----

// A roll of 1..100 is a crit when it is at or below the crit percentage, so
// 0% never crits.
is_crit :: proc(roll, crit_percent: int) -> bool {
	return roll <= crit_percent
}

// A find happens when the roll (1..100) is at or below the Lost and Found
// percentage, so level 0 never finds anything.
is_find :: proc(roll, find_percent: int) -> bool {
	return roll <= find_percent
}

item_weight_total :: proc() -> int {
	total := 0
	for info in item_info {
		total += info.weight
	}
	return total
}

// Which item a roll of 1..item_weight_total() is: the weights are laid end to end.
item_for_roll :: proc(roll: int) -> Item {
	upto := 0
	for item in Item {
		upto += item_info[item].weight
		if roll <= upto {
			return item
		}
	}
	return max(Item)
}

items_total :: proc(p: ^Player) -> i64 {
	total: i64
	for n in p.items {
		total += n
	}
	return total
}

// Recover irritation for the time since the last check. The first check ever
// only stamps the time. Partial progress is kept: the stamp moves forward by
// whole intervals only (even when there is nothing to recover).
recover_irritation :: proc(g: ^Game, now_ms: i64) {
	p := &g.player
	if !p.has_last_check {
		p.has_last_check = true
		p.last_check_ms = now_ms
		return
	}
	interval_ms := i64(effect(p, .Irritation_Recovery)) * 1000
	elapsed_ms := now_ms - p.last_check_ms
	if elapsed_ms < 0 {
		return // the clock went backwards; wait for it to catch up
	}
	intervals := elapsed_ms / interval_ms
	p.last_check_ms += intervals * interval_ms
	recovered := min(p.irritation, intervals)
	if recovered > 0 {
		add_message(g, "-%d Irritation", recovered)
		p.irritation -= recovered
	}
}

perform_check :: proc(g: ^Game, rng: ^Rng) {
	p := &g.player
	if p.irritation >= p.max_irritation {
		add_message(g, "Yer butthole is too irritated!")
		return
	}
	add_message(g, "You check yer butthole!")
	add_message(g, "+1 irritation")
	p.irritation += 1

	thoroughness := i64(effect(p, .Thoroughness))
	crit := effect(p, .Crit)
	if is_crit(rng_roll(rng, 1, CRIT_ROLL_SIDES), crit) {
		add_message(g, "Critical check! Doubly effective!")
		thoroughness *= 2
	}
	p.checks += thoroughness
	add_message(g, "+%d XP", thoroughness)
	p.xp += thoroughness

	// Lost and Found: only after a check that happened (a refused one returned above)
	if is_find(rng_roll(rng, 1, CRIT_ROLL_SIDES), effect(p, .Lost_And_Found)) {
		item := item_for_roll(rng_roll(rng, 1, item_weight_total()))
		if p.items[item] < ITEM_COUNT_LIMIT {
			p.items[item] += 1
		}
		add_message(g, "%s", item_info[item].found_message)
	}
}

handle_levelling :: proc(g: ^Game) {
	p := &g.player
	for p.xp >= p.xp_goal {
		p.xp -= p.xp_goal
		p.level += 1
		add_message(g, "+%d Advancement Point(s)", p.level)
		p.points += p.level
		add_message(g, "Yer now level %d", p.level)
		p.xp_goal += p.xp_goal
	}
}

// One click of "Check Butthole".
check_butthole :: proc(g: ^Game, rng: ^Rng, now_ms: i64) {
	clear_messages(g)
	recover_irritation(g, now_ms)
	perform_check(g, rng)
	handle_levelling(g)
}
