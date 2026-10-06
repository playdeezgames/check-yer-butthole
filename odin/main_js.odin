#+build js
package cyb

// The browser side. Everything the game needs from the page comes through the
// handful of imports below (module "env", implemented in web/index.html).
// Strings cross as a pointer and a byte length.

import "base:runtime"
import "core:fmt"

foreign import host "env"

@(default_calling_convention = "contextless")
foreign host {
	dom_clear :: proc() ---
	// kind is an Element_Kind (see KINDS in index.html); ms is only used by Timestamp
	dom_add :: proc(kind: i32, id: i32, ms: f64, text: [^]u8, len: i32) ---
	// Copies the name box's text into buf (UTF-8) and returns its length
	read_name :: proc(buf: [^]u8, cap: i32) -> i32 ---
	// Returns the value's byte length, or -1 if the key is absent or storage is unavailable.
	// The bytes are copied only if they fit in cap.
	storage_get :: proc(key: [^]u8, key_len: i32, buf: [^]u8, cap: i32) -> i32 ---
	storage_set :: proc(key: [^]u8, key_len: i32, val: [^]u8, val_len: i32) ---
	now_ms :: proc() -> f64 ---
	entropy :: proc() -> f64 --- // a whole number below 2^53
	console_log :: proc(text: [^]u8, len: i32) ---
}

LOAD_BUF_SIZE :: 2 * SAVE_BUF_SIZE // JSON_MAX_INPUT, so anything bigger is rejected
NAME_READ_MAX :: 256

app: App
load_v2_buf: [LOAD_BUF_SIZE]u8
load_v1_buf: [LOAD_BUF_SIZE]u8
name_buf: [NAME_READ_MAX]u8

log :: proc(format: string, args: ..any) {
	buf: [160]u8
	text := fmt.bprintf(buf[:], format, ..args)
	console_log(raw_data(text), i32(len(text)))
}

// "" when the key is absent. A value that is too big to read comes back as a
// non-empty junk string, so it counts as present-but-invalid rather than absent.
read_storage :: proc(key: string, buf: []u8) -> string {
	n := storage_get(raw_data(key), i32(len(key)), raw_data(buf), i32(len(buf)))
	if n <= 0 {
		return ""
	}
	if int(n) > len(buf) {
		return "~"
	}
	return string(buf[:n])
}

render :: proc() {
	dom_clear()
	v := &app.view
	for i in 0 ..< v.count {
		e := &v.elements[i]
		dom_add(i32(e.kind), i32(e.id), f64(e.ms), raw_data(e.text[:]), i32(e.len))
	}
}

// Do what the app asked for (save, erase) and redraw the page.
after_update :: proc() {
	if app.want_erase {
		// Abandoned: leave an "empty" marker rather than removing the key, so the
		// original game's save is not migrated back in on the next load.
		app.want_erase = false
		buf: [64]u8
		text := save_write_empty(buf[:])
		key: string = SAVE_KEY
		storage_set(raw_data(key), i32(len(key)), raw_data(text), i32(len(text)))
	}
	if app.want_save {
		app.want_save = false
		buf: [SAVE_BUF_SIZE]u8
		if text, ok := save_write(&app.game, buf[:]); ok {
			key: string = SAVE_KEY
			storage_set(raw_data(key), i32(len(key)), raw_data(text), i32(len(text)))
		} else {
			log("could not write the save")
		}
	}
	render()
}

main :: proc() {
	seed := u64(entropy()) ~ u64(now_ms())
	v2 := read_storage(SAVE_KEY, load_v2_buf[:])
	v1 := read_storage(OLD_SAVE_KEY, load_v1_buf[:])
	source := app_init(&app, seed, v2, v1)
	log("check yer butthole: load %v", source)
	render()
}

// A button was clicked.
@(export)
on_click :: proc "c" (id: i32) {
	context = runtime.default_context()
	n := read_name(raw_data(name_buf[:]), NAME_READ_MAX)
	app_click(&app, int(id), string(name_buf[:clamp(int(n), 0, NAME_READ_MAX)]), i64(now_ms()))
	after_update()
}

// Keeps the Odin runtime alive between clicks; the page is event driven.
@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	return true
}
