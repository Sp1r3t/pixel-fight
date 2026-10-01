# Спрайт-листы бойцов

32 PNG (по два на персонажа: `<id>_a.png` + `<id>_b.png`, см. почему в README генератора —
коротко: Roblox портит текстуры больше ~1024px по стороне), сгенерированы
`tools/pixelart/generate.js` — см. его README за деталями пайплайна и инструкцией, как
загрузить их в Roblox и включить в игре (`src/shared/Config/CharacterSprites.luau`).

Не редактировать эти файлы руками — перегенерировать через `node tools/pixelart/generate.js`
(правки стиля/поз — в `tools/pixelart/rig.js` и `data/poses.js`).
