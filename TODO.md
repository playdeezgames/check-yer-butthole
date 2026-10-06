# TODO

## Port (see PLAN.md)

- [x] Phase 1: pin the original (`reference/original/`, `docs/original-rules.md`)
- [x] Phase 2: scaffold
- [x] Phase 3: core rules and tests (33 tests passing)
- [x] Phase 4: save v2 and v1 migration (51 tests passing, wasm builds)
- [x] Phase 5: UI screens (67 tests passing; `ui.odin`, `View` replayed by the platform)
- [x] Phase 6: web shim (`main_js.odin`, `web/index.html`; smoke-tested in the browser pane: title, start, embark, check, save, reload, Continue)
- [x] Phase 7: playtest (real browser; see `docs/playtest-2026-10-06.md`)
- [ ] Phase 8: ship (copy and devlog written, zip builds; the push and the page edits are the user's call)

## Carry forward

- Native tests use a 64-bit `int`; `js_wasm32` has a 32-bit `int`. The tests cannot see overflow there, so anything big (timestamps, stats) is `i64`. Phase 7 must run the real migration in the browser (hand-made old `worldData`, real `localStorage`) to confirm.
- The platform (phase 6) must: read `cyb:save` and `worldData` and call `load_game`; write `cyb:save` after each change (on entering the neutral screen, like the original); never delete either key; on abandon store the empty marker in `cyb:save`. A rejected v2 save is left alone until the next save overwrites it, which happens only once the player starts a new game.

- Platform contract from phase 5: `app_init(app, seed, v2_text, v1_text)`, then after every `app_click(app, id, name_box_text, now_ms)` replay `app.view` into the DOM (a `Timestamp` element is its text plus `new Date(ms).toLocaleString()`; a `Text_Field` is a paragraph with a label and a text box; set text only through `textContent`/`.value`). Then act on and clear `want_save` (write `cyb:save`) and `want_erase` (remove `cyb:save` only). There is no timer: the original shows an absolute recovery time, not a countdown.
- Deviations in phase 5: buying an advancement saves immediately (the original only saved on returning to the main screen); an advancement at max level shows "Cost: MAX" (the original showed "Cost: undefined").

## Decided

- Save key `cyb:save`; migration is silent (also when a save is rejected)
- AI disclosure: credits line in `ITCH_DESCRIPTION.md` and a casual sentence in the port's devlog

## Open

- The page has no butler channel (the original was uploaded by hand as a zip); the first push creates one, and the old upload must be removed by hand

## Future expansion (not for the first parity update)

- **Items upgrade** (car keys, wedding ring, banana, cheese). **Designed with the user and built (see `docs/items-design.md`), not yet committed or shipped.** The lore is settled (the song "H.Y.C.Y.BH", *Who Moved My Cheese?*, and a banana song). What the items are *for* is deliberately undefined, so do not invent it; ask. A player comment asked for "find an item every now and then".
- A winning screen (a player asked "Is there a winning screen?"). Ask the user first; the lack of one may be the joke.

## Phase 8 checklist (the user does these, or says "push")

- [ ] Review `ITCH_DESCRIPTION.md` and `devlog/20261006/devlog.md`; edit freely
- [ ] `./shippit.sh --push` (only when the user says so; creates the `html` channel)
- [ ] On the itch page: remove the old zip upload, tick "This file will be played in the browser" on the new one, set the embed size
- [ ] Paste the description, post the devlog
- [ ] Check the live page in the browser pane afterwards (text, embed, first key press, saves, a migration with a real old save)
