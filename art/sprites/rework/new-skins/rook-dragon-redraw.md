# Rook: replacement dragon effect — pending generation

Scope: a new transparent raster effect atlas for the existing Rook–Brakk rehearsal.
The current procedural dragon is not an approved final asset.

## Generation status

Built-in image generation attempted on 2026-10-01. It returned HTTP 429,
`usage_limit_reached`, reset epoch `1790878509`:
2026-10-01 18:15:09 UTC / 21:15:09 Moscow.
No replacement image was produced. No CLI/API fallback was invoked.

## Reference and prompt

Style reference: `rook-source.png`. Preserve the approved character's pixel
cluster sizes, deliberate outlines and pixel shading. The fighter itself must
not appear in this effect atlas.

Create a detailed, fierce eastern FIRE DRAGON, facing right in side view:
angular reptilian skull, swept antler horns, brow ridges, narrow eye, articulated
open jaw with individual fangs, long whiskers, clawed forelegs and an articulated
serpentine body. Draw overlapping scale plates, contrasting belly scales, a
dorsal ridge and a tapered tail. Crimson scale shadows, orange and gold fire,
ivory highlights. Flames surround recognizable dragon anatomy.

Four equal cells in a 2 × 2 transparent atlas. Four coherent frames of one
attacking dragon: traveling body wave, moving jaw, flame whiskers and embers.
Consistent body proportions and size. Each complete dragon, including horns,
claws, tail and flames, fits fully inside its cell with generous transparent
margins. No characters, victims, scenery, text, guides, boxes, soft blur or glow.

## Integration constraints

- Render the effect in arena coordinates independently of fighter cells.
- Preserve current impact timing, body flash, recoil and flame aftermath.
- Inspect each frame before replacing the current effect.
- Keep the new atlas as a separate versioned file; do not overwrite actor skins.
