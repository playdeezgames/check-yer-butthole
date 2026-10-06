# Original behaviour (reference)

The original game is in `reference/original/`, extracted from `index.zip` (sha256 `1e15cab7aa0725d0744eeb466907bcf510ced21cd482e50b9d17d10603cdf906`, files dated June 2025, last script change 2025-06-19). Live at https://thegrumpygamedev.itch.io/check-yer-btthole. This file is the spec for the Odin port. "Port:" lines say where the port deliberately differs.

## State

One character (`N00b`). Statistics at start: ButtholeChecks 0, ExperiencePoints 0, ExperienceGoal 100, ExperienceLevel 0, AdvancementPoint 0, Irritation 0, MaximumIrritation 100. `LastCheckTime` is absent until the first check. Advancement levels start at 0. A message list is saved with the world.

## The check ("Check Butthole")

1. Clear messages.
2. **Recover irritation** (below).
3. **Perform check:**
   - If irritation >= maximum: message "Yer butthole is too irritated!" and stop (no XP).
   - Else messages "You check yer butthole!" and "+1 irritation"; irritation += 1.
   - thoroughness = Thoroughness effect; crit = Crit effect (percent).
   - Crit roll succeeds: message "Critical check! Doubly effective!" and thoroughness x2.
   - ButtholeChecks += thoroughness; message "+{thoroughness} XP"; ExperiencePoints += thoroughness.
4. **Level up** while XP >= goal: XP -= goal; level += 1; message "+{level} Advancement Point(s)"; AdvancementPoint += level; message "Yer now level {level}"; goal += goal (doubles).
5. Save and redraw.

Port: the crit roll is fixed (see Bugs).

## Irritation recovery

- If `LastCheckTime` is absent: set it to now and recover nothing (this is the first check).
- Otherwise `interval` = Irritation Recovery effect in seconds; `n = floor(elapsed_s / interval)`; `LastCheckTime += n * interval * 1000` (so partial progress is kept, and it advances even when irritation is 0, so nothing is banked); `n` is capped at current irritation; if `n > 0`: message "-{n} Irritation", irritation -= n.
- Runs at the start of each check, even one that is refused. It does not run on load or on a timer; the displayed irritation is stale until the next check.
- The neutral screen shows "Next irritation recovery: {local date time of LastCheckTime + interval}" once `LastCheckTime` exists.

## Advancements

| Name | Description | Costs (level 0..) | Effects (level 0..) | Effect text |
| --- | --- | --- | --- | --- |
| Critical Check % (`Crit`) | Chance of getting a "crit" when checking yer butthole. | 1, 2, 4, 8, 16, 32 | 0, 1, 2, 3, 4, 5, 6 | "Crit chance N%" |
| Thoroughness (`Thoroughness`) | You can't be too careful about this! | 5, 10, 15 | 1, 2, 3, 4 | "Checks per click: N" |
| Irritation Recovery (`IrritationRecovery`) | Time in seconds before recovering irritation due to friction from checking. | 1, 2, 4, 8, 16, 32 | 60, 55, 50, 45, 40, 35, 30 | "Irritation Recovery Rate Ns" |

Max level = number of costs. Buying costs `costs[level]` points and raises the level by 1; the Buy! button only appears when affordable.

## Screens and wording

- **Main menu:** h1 "Check Yer B*tthole, THE GAME", h2 "A production of TheGrumpyGameDev", then "Continue" if there is an avatar, else "Start". Tab title is "Check Yer B*tth*le! THE GAME" (different spelling, keep both).
- **Start:** h1 "Start Game", "Character Name:" and a text box, buttons "Cancel", "EMBARK!". An empty or whitespace name becomes "n00b"; otherwise the text is used as typed.
- **Neutral (main play):** message lines, then "Character Name: {name}", "XP: {xp}/{goal} (Level {level})", "Irritation: {i}/{max}", the next-recovery line, "Advancement Points: {n}", "Butthole Checks: {n}", buttons "Check Butthole", "Advancements", "Game Menu". Every entry to this screen saves the game.
- **Advancements:** h2 "Advancements(Work in Progress):", one button per advancement "{name} (Current: {level}, Cost: {cost})", then "Go Back".
- **Advancement detail:** h3 name, description, then if not max: "Current Level: {l} (Effect: ...)", "Next Level: {l+1} (Effect: ...)", "Advancement Cost: {cost} (You have {points})", "Buy!" if affordable; if max: "Current Level: MAX (Effect: ...)". Then "Go Back".
- **Game menu:** h1 "Game Menu", "Continue Game", "Abandon Game". **Confirm:** h1 "Are you sure you want to abandon the game?", "Yes" (wipes the save and returns to the main menu), "No".

## Persistence

`localStorage` key `worldData`, value `{"avatarCharacterId": 0, "characters": [{"name", "statistics": {...}, "advancements": {...}}], "messages": [...]}`. Statistic keys: `ButtholeChecks`, `ExperiencePoints`, `ExperienceGoal`, `ExperienceLevel`, `AdvancementPoint`, `Irritation`, `MaximumIrritation`, `LastCheckTime` (ms since epoch). Advancement keys: `Crit`, `Thoroughness`, `IrritationRecovery`. A missing key on load means a fresh game.

## Bugs in the original

1. **`Utility.roll(min, max)` ignores `min`:** it returns `floor(random * (max - min + 1))`, 0 to 99 for `roll(1, 100)`. With the test `roll <= crit`, level 0 (0%) still crits about 1% of the time, and every level gives about 1% too much. **Port: roll 1..100 inclusive, so 0% never crits.** Crit is something the player buys.
2. The advancements list shows "Cost: undefined" for an advancement at max level (`costs[level]` is out of range). Port: show a sensible max marker, for example "MAX".
3. `irritation == NaN` in `Neutral.run` is always false, so its null check only works through `== null`. No port needed.
4. Any exception while drawing the neutral screen wipes the save and returns to the main menu. Port: validate on load and never delete a save on failure.
5. If the clock goes backwards, the original computed a negative number of intervals and moved `LastCheckTime` backwards. Port: do nothing until the clock catches up (tested).
6. A corrupt `worldData` JSON throws at startup with no recovery. Port: validate, keep the key, start fresh.

## Itch page (checked 2026-10-06)

Short text "I blame clayman." Genre Simulation, free. Devlogs: "Local Storage and XP" (Jun 12 2025), "Advancements that Pack a Punch!" (Jun 13), "Irritation and Irritation Recovery" (Jun 14). Several comments, including a request for a winning screen and for finding items. The page has no butler channel: the build was uploaded by hand as a zip, so the first `butler push` creates one and the old upload has to be removed by hand.
