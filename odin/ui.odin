package cyb

// The screens. Each screen draws into a View: a flat list of elements that the
// platform replays into the page (real DOM headings, paragraphs and buttons).
// No browser imports here, so the whole interface can be played in tests.

import "core:fmt"

ELEMENT_TEXT_MAX :: 256
MAX_ELEMENTS :: 64

Element_Kind :: enum {
	Heading1,
	Heading2,
	Heading3,
	Paragraph,
	Timestamp, // a paragraph: the text, then `ms` as a local date and time (the browser formats it)
	Button, // `id` is the Action to send back
	Line_Break,
	Text_Field, // a paragraph with the text as a label and a text box; `id` names the box
}

Element :: struct {
	kind: Element_Kind,
	id:   int,
	ms:   i64,
	text: [ELEMENT_TEXT_MAX]u8,
	len:  int,
}

View :: struct {
	elements: [MAX_ELEMENTS]Element,
	count:    int,
	overflow: bool, // set if a screen ever tried to draw more than fits (tests check it)
}

element_text :: proc(e: ^Element) -> string {
	return string(e.text[:e.len])
}

// What a button does. Advancement buttons are ACTION_SELECT + the Advancement.
Action :: enum int {
	None,
	Start,
	Continue,
	Cancel,
	Embark,
	Check,
	Advancements,
	Game_Menu,
	Buy,
	Go_Back,
	Continue_Game,
	Abandon_Game,
	Yes,
	No,
}

ACTION_SELECT :: 100
NAME_FIELD_ID :: 1

Screen :: enum {
	Main_Menu,
	Start_Game,
	Neutral, // the main play screen
	Advancements,
	Advancement_Details,
	Game_Menu,
	Confirm_Abandon,
}

App :: struct {
	game:       Game,
	screen:     Screen,
	detail:     Advancement, // the advancement shown on Advancement_Details
	rng:        Rng,
	view:       View,
	want_save:  bool, // the platform should write the save (then clear this)
	want_erase: bool, // the game was abandoned: the platform should store save_write_empty (then clear this)
}

// ---- building a view ----

view_add :: proc(v: ^View, kind: Element_Kind, format: string, args: ..any) -> ^Element {
	if v.count >= MAX_ELEMENTS {
		v.overflow = true
		return &v.elements[MAX_ELEMENTS - 1] // scribble on the last one rather than crash
	}
	e := &v.elements[v.count]
	v.count += 1
	e^ = {
		kind = kind,
	}
	e.len = len(fmt.bprintf(e.text[:], format, ..args))
	return e
}

add_button :: proc(v: ^View, id: int, format: string, args: ..any) {
	view_add(v, .Button, format, ..args).id = id
}

add_break :: proc(v: ^View) {
	view_add(v, .Line_Break, "")
}

// ---- text of the advancements ----

effect_text :: proc(a: Advancement, level: int, buf: []u8) -> string {
	n := advancement_effect_at(a, level)
	switch a {
	case .Crit:
		return fmt.bprintf(buf, "Crit chance %d%%", n)
	case .Thoroughness:
		return fmt.bprintf(buf, "Checks per click: %d", n)
	case .Irritation_Recovery:
		return fmt.bprintf(buf, "Irritation Recovery Rate %ds", n)
	}
	return ""
}

// ---- the screens ----

draw_main_menu :: proc(app: ^App) {
	v := &app.view
	view_add(v, .Heading1, "Check Yer B*tthole, THE GAME")
	view_add(v, .Heading2, "A production of TheGrumpyGameDev")
	if app.game.has_avatar {
		add_button(v, int(Action.Continue), "Continue")
	} else {
		add_button(v, int(Action.Start), "Start")
	}
}

draw_start_game :: proc(app: ^App) {
	v := &app.view
	view_add(v, .Heading1, "Start Game")
	view_add(v, .Text_Field, "Character Name:").id = NAME_FIELD_ID
	add_button(v, int(Action.Cancel), "Cancel")
	add_button(v, int(Action.Embark), "EMBARK!")
}

draw_neutral :: proc(app: ^App) {
	v := &app.view
	g := &app.game
	p := &g.player
	for i in 0 ..< g.message_count {
		view_add(v, .Paragraph, "%s", message_text(&g.messages[i]))
	}
	view_add(v, .Paragraph, "Character Name: %s", player_name(p))
	view_add(v, .Paragraph, "XP: %d/%d (Level %d)", p.xp, p.xp_goal, p.level)
	view_add(v, .Paragraph, "Irritation: %d/%d", p.irritation, p.max_irritation)
	if p.has_last_check {
		interval_ms := i64(effect(p, .Irritation_Recovery)) * 1000
		view_add(v, .Timestamp, "Next irritation recovery: ").ms = p.last_check_ms + interval_ms
	}
	view_add(v, .Paragraph, "Advancement Points: %d", p.points)
	view_add(v, .Paragraph, "Butthole Checks: %d", p.checks)
	add_button(v, int(Action.Check), "Check Butthole")
	add_button(v, int(Action.Advancements), "Advancements")
	add_button(v, int(Action.Game_Menu), "Game Menu")
}

draw_advancements :: proc(app: ^App) {
	v := &app.view
	p := &app.game.player
	view_add(v, .Heading2, "Advancements(Work in Progress):")
	for a in Advancement {
		if cost, ok := next_cost(p, a); ok {
			add_button(v, ACTION_SELECT + int(a), "%s (Current: %d, Cost: %d)", advancement_info[a].name, p.advancements[a], cost)
		} else {
			// the original printed "Cost: undefined" here
			add_button(v, ACTION_SELECT + int(a), "%s (Current: %d, Cost: MAX)", advancement_info[a].name, p.advancements[a])
		}
		add_break(v)
	}
	add_button(v, int(Action.Go_Back), "Go Back")
}

draw_advancement_details :: proc(app: ^App) {
	v := &app.view
	p := &app.game.player
	a := app.detail
	info := advancement_info[a]
	level := p.advancements[a]
	view_add(v, .Heading3, "%s", info.name)
	view_add(v, .Paragraph, "%s", info.description)
	buf: [64]u8
	if cost, ok := next_cost(p, a); ok {
		view_add(v, .Paragraph, "Current Level: %d (Effect: %s)", level, effect_text(a, level, buf[:]))
		view_add(v, .Paragraph, "Next Level: %d (Effect: %s)", level + 1, effect_text(a, level + 1, buf[:]))
		view_add(v, .Paragraph, "Advancement Cost: %d (You have %d)", cost, p.points)
		if can_buy(p, a) {
			add_button(v, int(Action.Buy), "Buy!")
			add_break(v)
		}
	} else {
		view_add(v, .Paragraph, "Current Level: MAX (Effect: %s)", effect_text(a, level, buf[:]))
	}
	add_button(v, int(Action.Go_Back), "Go Back")
}

draw_game_menu :: proc(app: ^App) {
	v := &app.view
	view_add(v, .Heading1, "Game Menu")
	add_button(v, int(Action.Continue_Game), "Continue Game")
	add_button(v, int(Action.Abandon_Game), "Abandon Game")
}

draw_confirm_abandon :: proc(app: ^App) {
	v := &app.view
	view_add(v, .Heading1, "Are you sure you want to abandon the game?")
	add_button(v, int(Action.Yes), "Yes")
	add_button(v, int(Action.No), "No")
}

app_draw :: proc(app: ^App) {
	app.view = {}
	if !app.game.has_avatar && app.screen != .Start_Game {
		app.screen = .Main_Menu // every other screen needs a character
	}
	switch app.screen {
	case .Main_Menu:
		draw_main_menu(app)
	case .Start_Game:
		draw_start_game(app)
	case .Neutral:
		draw_neutral(app)
	case .Advancements:
		draw_advancements(app)
	case .Advancement_Details:
		draw_advancement_details(app)
	case .Game_Menu:
		draw_game_menu(app)
	case .Confirm_Abandon:
		draw_confirm_abandon(app)
	}
}

// ---- starting up and clicking ----

// Loads whatever the platform found in storage and shows the main menu.
app_init :: proc(app: ^App, seed: u64, v2_text, v1_text: string) -> Load_Source {
	app^ = {}
	rng_seed(&app.rng, seed)
	source := load_game(&app.game, v2_text, v1_text)
	app.screen = .Main_Menu
	app_draw(app)
	return source
}

// Entering the main play screen saves, as the original did.
enter_neutral :: proc(app: ^App) {
	app.screen = .Neutral
	app.want_save = true
}

// A button was clicked. `input` is the current text of the name box (ignored on
// other screens). Clicks that make no sense on the current screen are ignored, so a
// stale or forged id cannot do anything.
app_click :: proc(app: ^App, id: int, input: string, now_ms: i64) {
	g := &app.game
	p := &g.player
	action := Action(id) if id >= 0 && id < ACTION_SELECT else Action.None
	switch app.screen {
	case .Main_Menu:
		#partial switch action {
		case .Start:
			if !g.has_avatar {
				app.screen = .Start_Game
			}
		case .Continue:
			if g.has_avatar {
				enter_neutral(app)
			}
		}
	case .Start_Game:
		#partial switch action {
		case .Cancel:
			app.screen = .Main_Menu
		case .Embark:
			game_start(g, input)
			enter_neutral(app)
		}
	case .Neutral:
		#partial switch action {
		case .Check:
			check_butthole(g, &app.rng, now_ms)
			enter_neutral(app)
		case .Advancements:
			app.screen = .Advancements
		case .Game_Menu:
			app.screen = .Game_Menu
		}
	case .Advancements:
		if id >= ACTION_SELECT && id < ACTION_SELECT + len(Advancement) {
			app.detail = Advancement(id - ACTION_SELECT)
			app.screen = .Advancement_Details
		} else if action == .Go_Back {
			enter_neutral(app)
		}
	case .Advancement_Details:
		#partial switch action {
		case .Buy:
			if buy(p, app.detail) {
				app.want_save = true // the original forgot to save here
			}
		case .Go_Back:
			app.screen = .Advancements
		}
	case .Game_Menu:
		#partial switch action {
		case .Continue_Game:
			enter_neutral(app)
		case .Abandon_Game:
			app.screen = .Confirm_Abandon
		}
	case .Confirm_Abandon:
		#partial switch action {
		case .Yes:
			game_abandon(g)
			app.want_erase = true
			app.want_save = false
			app.screen = .Main_Menu
		case .No:
			app.screen = .Game_Menu
		}
	}
	app_draw(app)
}
