# Items upgrade: design (decided 2026-10-06, not built yet)

Decided with the user, one question at a time. This is the second release; the first (the Odin port) is shipped.

## Lore (where the items come from)

The whole game is a nod to **"H.Y.C.Y.BH" ("Have You Checked Your Butthole")** by Tom Cardy (2021). The items are things people lose, plus one thing nobody wants:

| Item | Source | Role |
| --- | --- | --- |
| Car keys | Verse 1 of Tom Cardy's song (a roommate has lost his car keys) | a lost thing |
| Wedding ring | Verse 2 of the same song (the rings are missing at a wedding) | a lost thing |
| Cheese | *Who Moved My Cheese?*, Spencer Johnson's 1998 self-help parable | a thing that went missing |
| Banana | "Don't Put Bananas In My Butt" by Biff the Dinosaur & Outerscope (May 2026) | **a hazard**: it is never lost, it is unwelcome |

Do not reproduce lyrics anywhere in the game, the page or the docs; paraphrase only.

## Mechanics

- **Finding:** a new purchased advancement, **Lost and Found** (key `LostAndFound`). Level 0 finds nothing. After a *successful* check (not a refused one), roll once: the level's chance in percent finds an item.
  - Levels 0 to 6: chance 0, 1, 2, 3, 4, 5, 6 percent; costs 2, 4, 8, 16, 32, 64 points.
  - Name "Lost and Found". Description "Everything you've lost has to be somewhere." Effect line "Item find chance N%".
- **Which item:** weighted pick per find, from a small table: banana 600, cheese 300, car keys 99, wedding ring 1 (out of 1000). Banana most common, ring one in a thousand. Weights live in one table so they can be retuned.
- **Inventory:** items stack, with counts. A new **Inventory** button on the main screen, shown only once the player has found something, opens a screen listing "Banana: 5", "Cheese: 2", "Car keys: 1", "Wedding ring: 1" (singular name, then the count) and a Go Back button.
- **The banana stays:** it goes into the inventory like the rest and cannot be removed. A bad find in name only, for now.
- **Messages on a find** (in the message list, after the check's own messages):
  - Banana: "You found a banana. Nobody asked for this."
  - Cheese: "You found cheese. So that's where it went."
  - Car keys: "You found car keys. Somebody has been looking everywhere."
  - Wedding ring: "You found a wedding ring. The wedding may now proceed."

## Not decided (do not invent these; ask the user)

- **What the items are for.** The user said the good items "become part of the inventory and then lead to another aspect of the game later on", and that each thing is to be defined later. Until then they only count.
- **What the banana does** as a hazard beyond sitting in the inventory.
- **A winning screen** (a player asked for one; the lack may be the joke).
- **Credit for the references** (Tom Cardy, Spencer Johnson, Biff the Dinosaur & Outerscope) on the itch page. A user decision.

## Technical notes (for whoever builds it)

- **Saves:** existing `version: 2` saves have no `LostAndFound` advancement and no items, and the current v2 reader requires every advancement key. Adding fields to v2 would make every shipped save fail validation. So: bump to `version: 3` (an `items` object and the new advancement key), keep a v2 reader that fills the missing values with 0, and keep writing only v3. Same rules as before: validate everything, never delete a save, abandon writes the empty marker. Tests: a real shipped v2 save text must load and gain the new fields.
- **Rules code:** add `Item` and a weight table to `rules.odin`; `Advancement` gets a fourth entry (the UI loops over the enum, so the list and detail screens pick it up). The find roll is part of `perform_check` after a successful check. Keep the `View` element limit (64) in mind: the main screen already has up to 16 messages.
- **UI:** `Screen.Inventory`, an `Action.Inventory`, a draw proc, and the button on `draw_neutral` only when the count of items is above zero. Update the DOM-structure check in the playtest.
- **Tests to write first:** 0% never finds, the weights over a large sample (including the ring being rare but possible by forcing the roll), the find only after a successful check, stacking counts, the Inventory button appearing only after a find, v2 to v3 loading, and the soak test with items.
