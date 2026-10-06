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

Advancement :: enum {
	Crit,
	Thoroughness,
	Irritation_Recovery,
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
