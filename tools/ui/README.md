# Campaign UI art and review

`campaign-art.cjs` is the authoring source for five campaign illustrations. It creates the native `CampaignArtwork.luau` span data, `atlas.svg`, and `geometry.json`. The game uses native GUI geometry and requires no image upload. Only the nearby chapters are mounted; scrolling within a chapter preserves its illustration instances.

To regenerate the art, run `node tools/ui/campaign-art.cjs`.

To review the real component hierarchy in a browser:

1. Run `lune run tools/ui/export-review.luau`.
2. Run `node tools/ui/review-assets.cjs` to resolve uploaded sprite IDs to local preview sheets.
3. Run `node tools/ui/preview-server.cjs` and open `http://127.0.0.1:8641/art/ui/campaign/review.html`.

The review exports the game's actual instance properties. Its CSS renderer approximates Roblox font sizing, automatic layouts and image tinting; it does not replace a device check in Studio. The review JSON is generated and ignored by Git. Captured PNGs document the checked composition.
