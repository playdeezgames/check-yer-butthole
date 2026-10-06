# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Check Yer B*tthole, THE GAME" is an idle clicker published at https://thegrumpygamedev.itch.io/check-yer-btthole. The original (June 2025) is vanilla JavaScript driving the DOM, kept untouched in `reference/original/` (from `index.zip`, sha256 in `docs/original-rules.md`). It is being ported to Odin compiled to `js_wasm32`. `PLAN.md` holds the decisions and the phases; `docs/original-rules.md` is the behaviour reference.

## Decisions to respect

- The look stays plain HTML (real DOM buttons and paragraphs). Odin owns state and logic; JS only builds DOM.
- Crit chance is a purchased stat: level 0 is 0%, so it never crits. The original's `roll` bug is fixed, everything else is faithful.
- Saves migrate one way from the old `worldData` key to a `version: 2` save under the key `cyb:save`, silently (also when a save is rejected: start fresh, no message). Never delete the old key or a save that fails validation. Abandoning stores an empty marker (`save_write_empty`) in `cyb:save` instead of removing it, otherwise the old save is migrated back in on the next load.
- The name is unchanged: tab title "Check Yer B*tth*le! THE GAME", menu "Check Yer B*tthole, THE GAME". No "of SPLORR!!".
- Port first, ship, then extend. Ask the user before adding features. The first planned extension is the items upgrade (car keys, wedding ring, banana, cheese); the lore is not written, so ask the user before designing it.

## Commands

- Build: `odin/build.sh` writes `odin/out/`. Serve it with a static server on a port other than 8765 (check who owns the port first).
- Test (native): `cd odin && odin test . -define:ODIN_TEST_THREADS=1`.
- Ship: `./shippit.sh` runs tests and builds but does not upload; `./shippit.sh --push` publishes to itch.io. Only run `--push` when the user says so.

## Gotchas for this repo

- `int` is 32 bits on `js_wasm32` but 64 on the native test build. Use `i64` for anything large (stats, millisecond timestamps, parsed JSON numbers), and range-check an `i64` before narrowing it to `int`. Always run `odin/build.sh` as well as the tests.
- Constant strings and arrays cannot be indexed by a runtime value; put them in a variable first.

## Architecture

See `PLAN.md`. Files: `rng.odin`, `rules.odin` (the game), `json.odin` (allocator-free JSON reader and writer), `save.odin` (v2 save, v1 migration, `game_valid`, `load_game`). Platform code lives in `main_js.odin` (`#+build js`, with the matching JS in `odin/web/index.html`; `ui.odin`'s `Element_Kind` order must match `KINDS` there, and a test checks it), tests in `game_test.odin` (`#+build !js`); the rest has no browser imports and never imports `core:os`.

## Vault

Notes on the toolchain and past lessons: `/home/yermom/git/bok-of-splorr/splorr/Tech/Odin wasm recipe.md` and `Gotchas.md`.
