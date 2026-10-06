#+build !js
package cyb

import "core:fmt"
import "core:strings"
import "core:testing"

new_app :: proc(v2 := "", v1 := "") -> App {
	app: App
	app_init(&app, 1, v2, v1)
	return app
}

// The visible text of the whole screen, one line per element (buttons in [brackets]).
screen_lines :: proc(app: ^App) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< app.view.count {
		e := &app.view.elements[i]
		text := element_text(e)
		switch e.kind {
		case .Button:
			append(&lines, fmt.tprintf("[%s]", text))
		case .Line_Break:
		case .Timestamp:
			append(&lines, fmt.tprintf("%s<%d>", text, e.ms))
		case .Heading1, .Heading2, .Heading3, .Paragraph, .Text_Field:
			append(&lines, text)
		}
	}
	return lines[:]
}

// The whole screen must be exactly these lines.
expect_screen :: proc(t: ^testing.T, app: ^App, expected: []string, loc := #caller_location) {
	actual := screen_lines(app)
	same := len(actual) == len(expected)
	for i in 0 ..< min(len(actual), len(expected)) {
		if actual[i] != expected[i] {
			same = false
		}
	}
	testing.expectf(t, same, "screen mismatch\n expected: %v\n   actual: %v", expected, actual, loc = loc)
}

has_line :: proc(app: ^App, line: string) -> bool {
	for l in screen_lines(app) {
		if l == line {
			return true
		}
	}
	return false
}

button_id :: proc(app: ^App, label: string) -> (id: int, ok: bool) {
	for i in 0 ..< app.view.count {
		e := &app.view.elements[i]
		if e.kind == .Button && element_text(e) == label {
			return e.id, true
		}
	}
	return 0, false
}

// Click the button with this label. Fails the test if there is no such button.
click :: proc(t: ^testing.T, app: ^App, label: string, input := "", now_ms := T0) {
	id, ok := button_id(app, label)
	testing.expectf(t, ok, "no button [%s] on screen %v; screen: %v", label, app.screen, screen_lines(app))
	if ok {
		app_click(app, id, input, now_ms)
	}
}

begin_game :: proc(t: ^testing.T, app: ^App, name := "Bob") {
	click(t, app, "Start")
	click(t, app, "EMBARK!", name)
}

take_save :: proc(app: ^App) -> bool {
	s := app.want_save
	app.want_save = false
	return s
}

// ---- the original wording ----

@(test)
title_screen :: proc(t: ^testing.T) {
	app := new_app()
	testing.expect_value(t, len(screen_lines(&app)), 3)
	testing.expect(t, has_line(&app, "Check Yer B*tthole, THE GAME"))
	testing.expect(t, has_line(&app, "A production of TheGrumpyGameDev"))
	testing.expect(t, has_line(&app, "[Start]"))
	testing.expect_value(t, app.view.elements[0].kind, Element_Kind.Heading1)
	testing.expect_value(t, app.view.elements[1].kind, Element_Kind.Heading2)
}

@(test)
start_screen_and_cancel :: proc(t: ^testing.T) {
	app := new_app()
	click(t, &app, "Start")
	expect_screen(t, &app, []string{"Start Game", "Character Name:", "[Cancel]", "[EMBARK!]"})
	testing.expect_value(t, app.view.elements[1].kind, Element_Kind.Text_Field)
	testing.expect_value(t, app.view.elements[1].id, NAME_FIELD_ID)
	click(t, &app, "Cancel")
	testing.expect(t, has_line(&app, "[Start]"))
	testing.expect(t, !app.game.has_avatar)
}

@(test)
embarking_shows_the_neutral_screen :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app, "Bob")
	lines := screen_lines(&app)
	expected := []string {
		"Character Name: Bob",
		"XP: 0/100 (Level 0)",
		"Irritation: 0/100",
		"Advancement Points: 0",
		"Butthole Checks: 0",
		"[Check Butthole]",
		"[Advancements]",
		"[Game Menu]",
	}
	testing.expect_value(t, len(lines), len(expected))
	for line, i in expected {
		testing.expect_value(t, lines[i] if i < len(lines) else "", line)
	}
	testing.expect(t, take_save(&app), "entering the main screen saves")
}

@(test)
blank_name_becomes_n00b_and_html_is_just_text :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app, "   ")
	testing.expect(t, has_line(&app, "Character Name: n00b"))
	click(t, &app, "Game Menu")
	click(t, &app, "Abandon Game")
	click(t, &app, "Yes")
	begin_game(t, &app, "<b>&amp;</b>")
	testing.expect(t, has_line(&app, "Character Name: <b>&amp;</b>")) // shown as typed; the page uses textContent
}

@(test)
checking_shows_messages_and_the_recovery_time :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	for line in screen_lines(&app) {
		testing.expect(t, !strings.has_prefix(line, "Next irritation recovery"), "no time before the first check")
	}
	click(t, &app, "Check Butthole", now_ms = T0)
	lines := screen_lines(&app)
	testing.expect_value(t, lines[0], "You check yer butthole!")
	testing.expect_value(t, lines[1], "+1 irritation")
	// no crit at level 0, so the third line is the XP
	testing.expect_value(t, lines[2], "+1 XP")
	testing.expect(t, has_line(&app, "Irritation: 1/100"))
	// the first check only stamps the time; the next recovery is one interval (60 s) later
	testing.expect(t, has_line(&app, fmt.tprintf("Next irritation recovery: <%d>", T0 + 60_000)))
	testing.expect(t, has_line(&app, "Butthole Checks: 1"))
	click(t, &app, "Check Butthole", now_ms = T0 + 60_000)
	testing.expect(t, has_line(&app, "-1 Irritation"))
	testing.expect(t, has_line(&app, fmt.tprintf("Next irritation recovery: <%d>", T0 + 120_000)))
}

@(test)
every_check_saves :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	take_save(&app)
	click(t, &app, "Check Butthole")
	testing.expect(t, take_save(&app))
	click(t, &app, "Advancements")
	testing.expect(t, !take_save(&app), "just looking does not save")
	click(t, &app, "Go Back")
	testing.expect(t, take_save(&app), "back on the main screen saves")
	click(t, &app, "Game Menu")
	click(t, &app, "Continue Game")
	testing.expect(t, take_save(&app))
}

// ---- advancements ----

@(test)
advancements_list :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	click(t, &app, "Advancements")
	expect_screen(t, &app, []string {
			"Advancements(Work in Progress):",
			"[Critical Check % (Current: 0, Cost: 1)]",
			"[Thoroughness (Current: 0, Cost: 5)]",
			"[Irritation Recovery (Current: 0, Cost: 1)]",
			"[Lost and Found (Current: 0, Cost: 2)]",
			"[Go Back]",
		})
	testing.expect_value(t, app.view.elements[0].kind, Element_Kind.Heading2)
}

@(test)
detail_screen_when_you_cannot_afford_it :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	click(t, &app, "Advancements")
	click(t, &app, "Thoroughness (Current: 0, Cost: 5)")
	expect_screen(t, &app, []string {
			"Thoroughness",
			"You can't be too careful about this!",
			"Current Level: 0 (Effect: Checks per click: 1)",
			"Next Level: 1 (Effect: Checks per click: 2)",
			"Advancement Cost: 5 (You have 0)",
			"[Go Back]",
		})
	testing.expect_value(t, app.view.elements[0].kind, Element_Kind.Heading3)
}

@(test)
buying_through_the_screens :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	app.game.player.points = 3
	take_save(&app)
	click(t, &app, "Advancements")
	click(t, &app, "Critical Check % (Current: 0, Cost: 1)")
	testing.expect(t, has_line(&app, "Current Level: 0 (Effect: Crit chance 0%)"))
	testing.expect(t, has_line(&app, "Next Level: 1 (Effect: Crit chance 1%)"))
	testing.expect(t, has_line(&app, "Advancement Cost: 1 (You have 3)"))
	click(t, &app, "Buy!")
	testing.expect(t, take_save(&app), "buying saves (the original forgot to)")
	testing.expect(t, has_line(&app, "Current Level: 1 (Effect: Crit chance 1%)"))
	testing.expect(t, has_line(&app, "Advancement Cost: 2 (You have 2)"))
	click(t, &app, "Buy!")
	testing.expect(t, has_line(&app, "Advancement Cost: 4 (You have 0)"))
	_, can := button_id(&app, "Buy!")
	testing.expect(t, !can, "no Buy! button when it is unaffordable")
	click(t, &app, "Go Back")
	testing.expect(t, has_line(&app, "[Critical Check % (Current: 2, Cost: 4)]"))
	testing.expect_value(t, app.game.player.points, 0)
}

@(test)
max_level_screens :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	app.game.player.points = 1_000
	for a in Advancement {
		for buy(&app.game.player, a) {}
	}
	click(t, &app, "Advancements")
	testing.expect(t, has_line(&app, "[Critical Check % (Current: 6, Cost: MAX)]"))
	testing.expect(t, has_line(&app, "[Thoroughness (Current: 3, Cost: MAX)]"))
	testing.expect(t, has_line(&app, "[Irritation Recovery (Current: 6, Cost: MAX)]"))
	testing.expect(t, has_line(&app, "[Lost and Found (Current: 6, Cost: MAX)]"))
	click(t, &app, "Irritation Recovery (Current: 6, Cost: MAX)")
	expect_screen(t, &app, []string {
			"Irritation Recovery",
			"Time in seconds before recovering irritation due to friction from checking.",
			"Current Level: MAX (Effect: Irritation Recovery Rate 30s)",
			"[Go Back]",
		})
	click(t, &app, "Go Back")
	testing.expect_value(t, app.screen, Screen.Advancements)
}

@(test)
playing_to_level_one_and_buying :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	// 100 XP needs 100 clean checks, with irritation recovering in between
	for i in 0 ..< 100 {
		click(t, &app, "Check Butthole", now_ms = T0 + i64(i) * 60_000)
	}
	testing.expect_value(t, app.game.player.level, 1)
	testing.expect(t, has_line(&app, "Yer now level 1"))
	testing.expect(t, has_line(&app, "+1 Advancement Point(s)"))
	testing.expect(t, has_line(&app, "XP: 0/200 (Level 1)"))
	testing.expect(t, has_line(&app, "Advancement Points: 1"))
	click(t, &app, "Advancements")
	click(t, &app, "Critical Check % (Current: 0, Cost: 1)")
	click(t, &app, "Buy!")
	testing.expect_value(t, app.game.player.advancements[.Crit], 1)
}

// ---- menus ----

@(test)
game_menu_and_abandon :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	click(t, &app, "Game Menu")
	expect_screen(t, &app, []string{"Game Menu", "[Continue Game]", "[Abandon Game]"})
	click(t, &app, "Abandon Game")
	expect_screen(t, &app, []string{"Are you sure you want to abandon the game?", "[Yes]", "[No]"})
	click(t, &app, "No")
	testing.expect_value(t, app.screen, Screen.Game_Menu)
	testing.expect(t, app.game.has_avatar)
	testing.expect(t, !app.want_erase)
	click(t, &app, "Abandon Game")
	take_save(&app)
	click(t, &app, "Yes")
	testing.expect(t, app.want_erase)
	testing.expect(t, !app.want_save)
	testing.expect(t, !app.game.has_avatar)
	testing.expect(t, has_line(&app, "[Start]"))
}

@(test)
continue_resumes_a_loaded_game :: proc(t: ^testing.T) {
	app := new_app("", OLD_MIDGAME)
	testing.expect(t, has_line(&app, "[Continue]"))
	_, has_start := button_id(&app, "Start")
	testing.expect(t, !has_start)
	click(t, &app, "Continue")
	testing.expect(t, has_line(&app, "Character Name: Bob"))
	testing.expect(t, has_line(&app, "XP: 17/200 (Level 1)"))
	testing.expect(t, has_line(&app, "Irritation: 12/100"))
	testing.expect(t, has_line(&app, "Advancement Points: 1"))
	testing.expect(t, has_line(&app, "Butthole Checks: 42"))
	testing.expect(t, has_line(&app, "You check yer butthole!")) // saved messages come back
	// Irritation Recovery is level 2: 50 s
	testing.expect(t, has_line(&app, "Next irritation recovery: <1750000050000>"))
}

@(test)
a_broken_save_gives_the_start_screen :: proc(t: ^testing.T) {
	app: App
	source := app_init(&app, 1, "{broken", OLD_MIDGAME)
	testing.expect_value(t, source, Load_Source.Rejected_V2)
	testing.expect(t, has_line(&app, "[Start]"))
	testing.expect(t, !app.want_save)
	testing.expect(t, !app.want_erase)
}

@(test)
clicks_that_do_not_belong_are_ignored :: proc(t: ^testing.T) {
	app := new_app()
	for id in ([]int{-1, 0, 5, 8, 9, 12, 13, 99, 100, 102, 103, 1000, 1 << 40}) {
		app_click(&app, id, "x", T0)
		testing.expect_value(t, app.screen, Screen.Main_Menu)
		testing.expect(t, !app.game.has_avatar)
	}
	begin_game(t, &app)
	app.game.player.points = 100
	// Buy and the advancement ids mean nothing on the main screen
	for id in ([]int{int(Action.Buy), ACTION_SELECT, int(Action.Yes), int(Action.Embark), int(Action.Abandon_Game)}) {
		app_click(&app, id, "x", T0)
		testing.expect_value(t, app.screen, Screen.Neutral)
	}
	testing.expect_value(t, app.game.player.points, 100)
	testing.expect(t, app.game.has_avatar)
}

// ---- soak ----

// Click random buttons, with random names, times and storage round trips, and
// check that nothing ever goes wrong.
@(test)
random_play_never_breaks :: proc(t: ^testing.T) {
	r := seeded(31337)
	app := new_app()
	now := T0
	saved := ""
	buf: [SAVE_BUF_SIZE]u8
	names := []string{"", "Bob", "  ", "<script>", "é😀", "x"}
	screens_seen: [Screen]bool
	for step in 0 ..< 20_000 {
		screens_seen[app.screen] = true
		testing.expect(t, !app.view.overflow, "a screen overflowed the view")
		testing.expect(t, game_valid(&app.game))
		// every screen has a button, so the player is never stuck
		buttons: [MAX_ELEMENTS]int
		n := 0
		for i in 0 ..< app.view.count {
			if app.view.elements[i].kind == .Button {
				buttons[n] = app.view.elements[i].id
				n += 1
			}
		}
		testing.expectf(t, n > 0, "no buttons on screen %v at step %d", app.screen, step)
		if n == 0 {
			return
		}
		if step % 400 == 0 && app.game.has_avatar {
			app.game.player.points += 60 // let random play reach the expensive advancements and items
		}
		now += i64(rng_roll(&r, 0, 200_000))
		app_click(&app, buttons[rng_roll(&r, 0, n - 1)], names[rng_roll(&r, 0, len(names) - 1)], now)
		if app.want_erase {
			app.want_erase = false
			saved = ""
		}
		if app.want_save {
			app.want_save = false
			text, ok := save_write(&app.game, buf[:])
			testing.expect(t, ok)
			saved = strings.clone(text, context.temp_allocator)
			// what was just saved must load back to the same game
			check: Game
			testing.expect(t, save_read(&check, saved))
			testing.expect(t, check.player == app.game.player)
		}
		if step % 997 == 0 { 	// pretend the tab was closed and reopened
			app_init(&app, u64(step), saved, "")
		}
	}
	for s in Screen {
		testing.expectf(t, screens_seen[s], "the soak never reached %v", s)
	}
}

// web/index.html decodes the element kind by position.
@(test)
element_kinds_match_the_web_page :: proc(t: ^testing.T) {
	testing.expect_value(t, int(Element_Kind.Heading1), 0)
	testing.expect_value(t, int(Element_Kind.Heading2), 1)
	testing.expect_value(t, int(Element_Kind.Heading3), 2)
	testing.expect_value(t, int(Element_Kind.Paragraph), 3)
	testing.expect_value(t, int(Element_Kind.Timestamp), 4)
	testing.expect_value(t, int(Element_Kind.Button), 5)
	testing.expect_value(t, int(Element_Kind.Line_Break), 6)
	testing.expect_value(t, int(Element_Kind.Text_Field), 7)
}

// ---- items ----

// Give the player a few of everything, as if they had been found.
stock_inventory :: proc(app: ^App) {
	app.game.player.items = {
		.Banana       = 5,
		.Cheese       = 2,
		.Car_Keys     = 1,
		.Wedding_Ring = 1,
	}
}

@(test)
lost_and_found_screens :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	app.game.player.points = 100
	click(t, &app, "Advancements")
	click(t, &app, "Lost and Found (Current: 0, Cost: 2)")
	expect_screen(
		t,
		&app,
		[]string {
			"Lost and Found",
			"Everything you've lost has to be somewhere.",
			"Current Level: 0 (Effect: Item find chance 0%)",
			"Next Level: 1 (Effect: Item find chance 1%)",
			"Advancement Cost: 2 (You have 100)",
			"[Buy!]",
			"[Go Back]",
		},
	)
	click(t, &app, "Buy!")
	testing.expect_value(t, app.game.player.advancements[.Lost_And_Found], 1)
	testing.expect_value(t, app.game.player.points, 98)
	testing.expect(t, has_line(&app, "Current Level: 1 (Effect: Item find chance 1%)"))
	testing.expect(t, has_line(&app, "Advancement Cost: 4 (You have 98)"))
}

@(test)
no_inventory_button_until_something_is_found :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	_, has := button_id(&app, "Inventory")
	testing.expect(t, !has)
	// a forged click on the Inventory button does nothing either
	app_click(&app, int(Action.Inventory), "", T0)
	testing.expect_value(t, app.screen, Screen.Neutral)
	stock_inventory(&app)
	app_draw(&app)
	_, has = button_id(&app, "Inventory")
	testing.expect(t, has)
}

@(test)
inventory_screen :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	stock_inventory(&app)
	app_draw(&app)
	// the button sits between Advancements and Game Menu
	lines := screen_lines(&app)
	n := len(lines)
	testing.expect_value(t, lines[n - 3], "[Advancements]")
	testing.expect_value(t, lines[n - 2], "[Inventory]")
	testing.expect_value(t, lines[n - 1], "[Game Menu]")
	take_save(&app)
	click(t, &app, "Inventory")
	expect_screen(t, &app, []string{"Inventory:", "Banana: 5", "Cheese: 2", "Car keys: 1", "Wedding ring: 1", "[Go Back]"})
	testing.expect_value(t, app.view.elements[0].kind, Element_Kind.Heading2)
	testing.expect(t, !take_save(&app), "looking does not save")
	click(t, &app, "Go Back")
	testing.expect_value(t, app.screen, Screen.Neutral)
}

@(test)
inventory_lists_only_what_you_have :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	app.game.player.items[.Banana] = 7
	app_draw(&app)
	click(t, &app, "Inventory")
	expect_screen(t, &app, []string{"Inventory:", "Banana: 7", "[Go Back]"})
}

@(test)
the_game_finds_items_when_played :: proc(t: ^testing.T) {
	app := new_app()
	begin_game(t, &app)
	app.game.player.points = 1_000
	click(t, &app, "Advancements")
	for _ in 0 ..< 6 {
		label := fmt.tprintf("Lost and Found (Current: %d, Cost: %d)", app.game.player.advancements[.Lost_And_Found], find_costs[app.game.player.advancements[.Lost_And_Found]])
		click(t, &app, label)
		click(t, &app, "Buy!")
		click(t, &app, "Go Back")
	}
	click(t, &app, "Go Back")
	testing.expect_value(t, app.game.player.advancements[.Lost_And_Found], 6)
	found := false
	for i in 0 ..< 400 {
		app.game.player.irritation = 0
		click(t, &app, "Check Butthole", now_ms = T0 + i64(i))
		if _, ok := button_id(&app, "Inventory"); ok {
			found = true
			break
		}
	}
	testing.expect(t, found, "no item in 400 checks at 6%")
	click(t, &app, "Inventory")
	testing.expect(t, strings.has_suffix(screen_lines(&app)[1], ": 1"), "the first find shows a count of 1")
}
