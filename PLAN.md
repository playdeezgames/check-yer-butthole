# Plan: port Check Yer B*tthole to Odin / wasm

Source of truth for the original: `index.zip` (vanilla JS, DOM, `localStorage`), published at https://thegrumpygamedev.itch.io/check-yer-btthole. Toolchain notes live in the vault: `/home/yermom/git/bok-of-splorr/splorr/Tech/Odin wasm recipe.md`, `Gotchas.md`, `Shipping to itch.io.md`. Closest precedent: `/home/yermom/git/TGGD_AGBIC24` (the bus game).

## Decisions

| # | Decision | Choice |
| - | -------- | ------ |
| 1 | Look | Keep the plain HTML look (real DOM buttons and paragraphs). Odin owns state and logic; JS only builds DOM. |
| 2 | Bugs | Fix `roll`. Crit chance is a purchased stat: level 0 means 0%, never a crit. Everything else stays faithful. |
| 3 | Saves | One-way migration. New format has `version: 2` under a new key; old `worldData` is read once and left in place as a backup. |
| 4 | Layout | `odin/` subfolder like the bus game. |
| 5 | Name | Unchanged. Keep both original strings: tab title "Check Yer B*tth*le! THE GAME", menu "Check Yer B*tthole, THE GAME". No "of SPLORR!!". |
| 6 | Scope | Port, ship, then extend. New features are separate later steps. |

## Original rules (to be pinned in `docs/original-rules.md`)

- Check: if irritation >= max (100) refuse ("Yer butthole is too irritated!"). Otherwise +1 irritation, XP and `ButtholeChecks` gain = Thoroughness effect (x2 on a crit).
- Crit: effect table `[0..6]` percent for levels 0..6, costs 1,2,4,8,16,32. Original rolled 0..99 and tested `<= crit`, so level 0 crit about 1%. Port: roll 1..100, crit if roll <= crit%.
- Thoroughness: effects 1,2,3,4; costs 5,10,15.
- Irritation Recovery: effects 60,55,50,45,40,35,30 seconds per point; costs 1,2,4,8,16,32.
- Recovery runs at the start of a check, from `LastCheckTime`: `floor(elapsed_s / interval)` points, capped at current irritation, `LastCheckTime` advances by whole intervals. First ever check just stamps the time.
- Level-up while XP >= goal: XP -= goal, level += 1, advancement points += new level, goal doubles ("+N Advancement Point(s)", "Yer now level N"). The original's first message prints the level, not the points granted; they are equal, so this is not a behaviour change.
- Advancement purchase: cost indexed by current level, needs enough points, max level = number of costs (shows "Current Level: MAX").
- Screens: main menu (Start / Continue), start (name box, default "n00b", Cancel / EMBARK!), neutral/navigation, advancements list, advancement detail (Buy!, Go Back), game menu (Continue / Abandon), confirm abandon. Next-recovery time is shown from `LastCheckTime` once it exists.
- Known quirks not to carry over: the roll bug, `irritation == NaN` (always false), and "any exception while drawing wipes the save".

## Architecture

```
odin/
  build.sh            build js_wasm32 into odin/out, copy odin.js and web/*
  rules.odin          pure: stats, check, recovery, level-up, advancement table (enum-indexed), costs/effects
  rng.odin            own seeded generator, roll(min, max) inclusive
  save.odin           v2 save write/read, v1 (worldData) migration, validation
  ui.odin             screen enum, draw/handle pair per screen; emits abstract DOM commands
  main_js.odin        #+build js: foreign DOM imports, localStorage, Date.now, exported on_click / on_tick
  game_test.odin      #+build !js: odin test
  web/index.html      host page: DOM glue implementing the imports
```

- Time is passed in as `now_ms: i64`, so recovery is testable without a clock.
- The page is event driven, no frame loop. Odin re-renders after each click; there is no timer, because the original shows an absolute recovery time, not a countdown (the browser formats it).
- JS imports (module `env`): `clear`, `add_text(tag, ptr, len)`, `add_button(id, ptr, len)`, `add_input(id, ptr, len)`, `read_input(id, buf, cap)`, storage get/set/remove, `now_ms`, `entropy`. Strings cross as pointer plus length. Exported `proc "c"`: `on_click(id)`, `on_tick()`.
- Name text is only ever set through `textContent`, never `innerHTML`.
- Seed the RNG from entropy, and cap any retry loop (see Gotchas).

## Save format (v2)

JSON text under the key `cyb:save`:

```
{ "version": 2, "name": ..., "checks": ..., "xp": ..., "xp_goal": ..., "level": ..., "points": ...,
  "irritation": ..., "max_irritation": ..., "last_check_ms": ..., "advancements": {"Crit": n, ...}, "messages": [...] }
```

- Migration reads old `worldData`: `avatarCharacterId` selects the character; statistics map `ButtholeChecks`, `ExperiencePoints`, `ExperienceGoal`, `ExperienceLevel`, `AdvancementPoint`, `Irritation`, `MaximumIrritation`, `LastCheckTime`; advancements map `Crit`, `Thoroughness`, `IrritationRecovery`; `messages` carries over.
- On abandon the save key is not removed but replaced by `{"version":2,"empty":true}`, so the old `worldData` is never migrated a second time (found in the phase 7 playtest).
- Validate every field (type, range, level <= max level, irritation <= max). A bad save is rejected whole and never deleted; the game falls back to the title screen with no avatar.
- Hand-written JSON reader (about 10 fields), no `core:encoding/json` (see Gotchas for its traps).

## Phases

1. **Pin the original.** Extract `index.zip` to `reference/original/` (and keep the zip's hash in `docs/original-rules.md`). Write `docs/original-rules.md` from the section above. Check the live itch page text and embed size; keep copy for `ITCH_DESCRIPTION.md`.
2. **Scaffold.** `odin/` skeleton, `build.sh`, `.gitignore`, `CLAUDE.md`, `README.md`, `shippit.sh`, `TODO.md`, `devlog/`. `shippit.sh` runs tests, builds, and pushes only with `--push`.
3. **Core.** `rng`, `rules`, advancement table; native tests for check, crit boundaries (0% never crits, 100% always), recovery over long gaps and partial intervals, multi-level-up, purchase limits, max level.
4. **Save.** v2 write/read, v1 migration with real-looking old JSON (fresh, mid-game, unspent points, `LastCheckTime` null), rejection of corrupt data, round-trip tests.
5. **UI.** Screen state machine with all seven screens and the original wording; a test that plays through every screen with fake DOM output.
6. **Web shim.** `main_js.odin`, `web/index.html`; DOM glue, storage, tick. Serve on a port that is not 8765 and check who owns it first.
7. **Playtest.** Real key presses and clicks in the browser pane at desktop and phone widths; migrate a hand-made old save; verify recovery across a closed tab.
8. **Ship (only when asked).** Update `ITCH_DESCRIPTION.md` and the AI disclosure, commit, then `butler push` to the existing page. Confirm the slug on the live page first. Check the live page afterwards in the browser pane.
9. **Extend (later).** Features chosen with the user, each as its own step. First on the list is the **items upgrade** (car keys, wedding ring, banana, cheese); see `docs/items-design.md`.

## Settled after the first pass

- Save key: `cyb:save`. The old `worldData` key is never touched.
- Migration is silent, and so is a rejected save (fresh game, nothing deleted, no message).
- AI disclosure: an adapted Robokitteh-style credits line in `ITCH_DESCRIPTION.md` (original written by the user in 2025; the Odin/WebAssembly port written in conversation with Claude Code, Claude Sonnet 5.5; design and jokes are the user's), plus a casual sentence in the port's devlog post ("I wrote this with Claude Code, which did most of the typing.").

## Open items

- The page has no butler channel yet (the original was uploaded by hand as a zip). The first push creates one; the old upload has to be removed by hand.
