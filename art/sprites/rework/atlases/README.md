# Combat animation atlases

**Superseded:** these sheets use the old procedural appearances and were rejected for the approved concept redesign. Use `../new-skins/` for the new reference-based artwork. Do not upload this directory as the new skins.

Generated pixel animation sheets for all 16 playable fighters. Each character has six 1024×1024 pages of 128×128 frames, with transparent backgrounds and a shared Rock-style palette/rendering pass.

## Animation rows

The page and row for every animation are listed in `manifest.json` and `ArcadeSpriteLayout.luau`.

- Idle, Walk, Dash, Jump, BackJump
- Crouch, Block, Light, Heavy, Special
- Super, Hit, Knockdown
- CrouchLight, CrouchHeavy, AirLight, AirHeavy
- Light2, Light3

Each standard action has 16 frames. Super has 64 frames with its own pose sequence and character motif. `roster.png` and each `<character>-portrait.png` are quick previews. The `asset-ids.example.json` file is a blank map for the Roblox image IDs after the pages are uploaded.

The 20 boss forms are animated procedurally in `src/client/Sprites/RigPoses.luau`: each visual style now has its own guard, alternating hand strings, heavy kick, retreat jump and a silhouette-led super pose. Their impact motifs are selected in `src/client/Fight/Cinematics.luau`.

The generated fighter pages are local source assets. The running Roblox client still points to the previously uploaded image IDs in `src/shared/Config/CharacterSpriteUploads.luau`; those IDs can only be replaced after the new pages are uploaded and imported.
