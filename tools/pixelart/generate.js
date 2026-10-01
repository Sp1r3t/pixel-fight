"use strict";
/*
	Генерирует пиксельные спрайт-листы всех бойцов в art/sprites/<id>_a.png и <id>_b.png.

	Два листа на персонажа, не один: Roblox портит (пересжимает/съезжают координаты кадров)
	текстуры со стороной больше ~1024px, а один лист на 12 рядов при детальном кадре быстро
	упирается в этот предел. Поэтому раскладка режется пополам по рядам:
	  _a.png — Idle, Walk, Dash, Jump, Crouch, Block   (локомоция/защита, ряды 0..5)
	  _b.png — Light, Heavy, Special, Super, Hit, Knockdown (атаки/реакции, ряды 0..5 внутри _b)
	Игровой SheetSprite сам выбирает нужный файл по ряду анимации (Types.SpriteSheet.splitRow) —
	с точки зрения кода анимации это по-прежнему один лист 0..11.
	Win, Lose, CrouchLight/Heavy, AirLight/Heavy рисовать не нужно — подхватываются автозаменой
	(Config/Animations.fallbacks) в игровом аниматоре.

	Запуск:
	  node tools/pixelart/generate.js            — все 16 персонажей
	  node tools/pixelart/generate.js rook        — только один (быстрый прототип)
	  node tools/pixelart/generate.js rook --frame=120 --ss=6  — другое разрешение/качество
*/

const fs = require("fs");
const path = require("path");
const { Canvas } = require("./lib/canvas");
const { encodePNG } = require("./lib/png");
const { drawCharacter, OUTLINE } = require("./rig");
const { ROWS, ROW_META, poseForFrame } = require("./data/poses");
const { LOOKS } = require("./data/looks");
const { CHARACTERS } = require("./data/characters");

const args = process.argv.slice(2);
const only = args.find((a) => !a.startsWith("--"));
const flag = (name, def) => {
	const found = args.find((a) => a.startsWith(`--${name}=`));
	return found ? Number(found.split("=")[1]) : def;
};

// 120px × 6 рядов × (8 колонок макс.) = 960×720 на каждый из двух листов — оба измерения
// с запасом под пределом текстур Roblox (безопасно держать ≤1024px по каждой стороне;
// на 96px при одном 12-рядном листе (1152px высоты) Roblox пересжимает лист при импорте,
// и координаты кадров (ImageRectOffset) съезжают — отсюда «рваные» персонажи).
const FRAME = flag("frame", 120); // итоговый размер кадра, px — должен совпадать с Config/CharacterSprites.luau
const SS = flag("ss", 6); // множитель супер-сэмпла (качество даунсемпла)
const SPLIT_ROW = 6; // ряды 0..5 -> _a.png, 6..11 -> _b.png (см. Config/CharacterSprites.luau)

const GROUP_A = ROWS.slice(0, SPLIT_ROW);
const GROUP_B = ROWS.slice(SPLIT_ROW);
const colsOf = (group) => Math.max(...group.map((a) => ROW_META[a].frames));

function renderFrame(look, palette, animation, frameIndex, frameCount, specialKind, superDelivery) {
	const ssSize = FRAME * SS;
	const canvas = new Canvas(ssSize, ssSize);
	const pose = poseForFrame(animation, frameIndex, frameCount, specialKind, superDelivery);
	drawCharacter(canvas, ssSize, 1, look, palette, pose);
	const palList = Array.from(canvas.paletteSet.values());
	palList.push({ r: 255, g: 255, b: 255 }, { r: 0, g: 0, b: 0 });
	return canvas.toSprite(FRAME, FRAME, palList, OUTLINE);
}

function blit(dst, dstW, src, srcW, srcH, dx, dy) {
	for (let y = 0; y < srcH; y++) {
		const srcOff = y * srcW * 4;
		const dstOff = ((dy + y) * dstW + dx) * 4;
		src.copy(dst, dstOff, srcOff, srcOff + srcW * 4);
	}
}

function renderGroup(look, charDef, group) {
	const cols = colsOf(group);
	const w = FRAME * cols;
	const h = FRAME * group.length;
	const pixels = Buffer.alloc(w * h * 4);
	group.forEach((animation, row) => {
		const meta = ROW_META[animation];
		for (let f = 0; f < meta.frames; f++) {
			const frameBuf = renderFrame(look, charDef.palette, animation, f, meta.frames, charDef.specialKind, charDef.superDelivery);
			blit(pixels, w, frameBuf, FRAME, FRAME, f * FRAME, row * FRAME);
		}
	});
	return { pixels, w, h };
}

function main() {
	const outDir = path.join(__dirname, "..", "..", "art", "sprites");
	fs.mkdirSync(outDir, { recursive: true });
	const list = only ? CHARACTERS.filter((c) => c.id === only) : CHARACTERS;
	if (list.length === 0) {
		console.error(`неизвестный персонаж: ${only}`);
		process.exit(1);
	}
	for (const c of list) {
		const start = Date.now();
		const look = LOOKS[c.id];
		if (!look) throw new Error(`нет облика для ${c.id}`);
		const a = renderGroup(look, c, GROUP_A);
		const b = renderGroup(look, c, GROUP_B);
		const fileA = path.join(outDir, `${c.id}_a.png`);
		const fileB = path.join(outDir, `${c.id}_b.png`);
		fs.writeFileSync(fileA, encodePNG(a.w, a.h, a.pixels));
		fs.writeFileSync(fileB, encodePNG(b.w, b.h, b.pixels));
		console.log(
			`${c.id}: a=${a.w}x${a.h} b=${b.w}x${b.h}, кадр ${FRAME}px — ${fileA}, ${fileB} (${Date.now() - start}мс)`
		);
	}
	console.log(`_a.png ряды 0..${SPLIT_ROW - 1}: ${GROUP_A.map((r, i) => `${i}=${r}(${ROW_META[r].frames})`).join(", ")}`);
	console.log(
		`_b.png ряды ${SPLIT_ROW}..${ROWS.length - 1}: ${GROUP_B.map((r, i) => `${i}=${r}(${ROW_META[r].frames})`).join(", ")}`
	);
}

main();
