# Character visual rework concepts

These are pixel-art concept assets made from the existing roster and the requested visual direction. The current batch is:

- `characters-01-rook-mira-brakk-juno.png` through `characters-04-tempest-byte-morrow-astra.png` — all 16 current playable characters, four per sheet.
- `bosses-01-pip-ned-tally-farrow.png` through `bosses-05-abbot-wraith-sovereign-null.png` — all 20 tower bosses, four per sheet.
- `boss-tung-sahur.png` — a separate wooden drum-monster take for the tower's Tung Sahur visual style.
- `character-and-boss-sketches.md` — signature attack direction and a four-beat, unique super storyboard for every playable character and boss.

These are standalone concept images, not animation atlases. They are not wired into the live sprite loader: the game expects transparent 8-column animation pages at fixed frame dimensions. Convert each design into complete per-character animation pages before changing `CharacterSpriteUploads` or `CharacterSprites`.

`rook-fighting-stance.png` and `kraken-boss-concept.png` are earlier one-off drafts from the previous pass. They are kept as history; the kraken draft is intentionally excluded from the current direction because it was too detailed and not pixel-like enough.
