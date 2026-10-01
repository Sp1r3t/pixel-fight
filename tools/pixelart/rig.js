"use strict";
/*
	Пиксельный рендер бойца — порт геометрии src/client/Sprites/Rig.luau (тот же скелет,
	те же формулы суставов), но вместо Roblox Frame рисует капсулы/круги/полигоны
	в супер-разрешении (см. lib/canvas.js), откуда потом получается пиксель-арт кадр.
*/

const { hex, shade } = require("./lib/canvas");

const BUILDS = {
	Normal: { torsoLen: 0.2, torsoW: 0.15, head: 0.115, neck: 0.016, upperArm: 0.115, foreArm: 0.105, armW: 0.05, foreW: 0.046, hand: 0.05, thigh: 0.145, shin: 0.14, legW: 0.064, shinW: 0.054, footL: 0.082, footH: 0.032 },
	Slim: { torsoLen: 0.2, torsoW: 0.13, head: 0.112, neck: 0.018, upperArm: 0.115, foreArm: 0.105, armW: 0.043, foreW: 0.04, hand: 0.046, thigh: 0.148, shin: 0.142, legW: 0.056, shinW: 0.048, footL: 0.078, footH: 0.03 },
	Heavy: { torsoLen: 0.21, torsoW: 0.2, head: 0.12, neck: 0.014, upperArm: 0.12, foreArm: 0.11, armW: 0.068, foreW: 0.062, hand: 0.062, thigh: 0.14, shin: 0.135, legW: 0.08, shinW: 0.068, footL: 0.092, footH: 0.036 },
	Small: { torsoLen: 0.17, torsoW: 0.13, head: 0.12, neck: 0.012, upperArm: 0.098, foreArm: 0.09, armW: 0.044, foreW: 0.04, hand: 0.046, thigh: 0.122, shin: 0.118, legW: 0.056, shinW: 0.048, footL: 0.08, footH: 0.032 },
};

const GROUND = 0.96;
const OUTLINE = hex("#0B0814");
const WHITE = { r: 255, g: 255, b: 255 };
const BLACK = { r: 0, g: 0, b: 0 };

function dir(angleDeg) {
	const rad = (angleDeg * Math.PI) / 180;
	return [Math.sin(rad), Math.cos(rad)];
}

function rotateAround(x, y, cx, cy, degrees) {
	if (!degrees) return [x, y];
	const rad = (degrees * Math.PI) / 180;
	const c = Math.cos(rad),
		s = Math.sin(rad);
	const dx = x - cx,
		dy = y - cy;
	return [cx + dx * c - dy * s, cy + dx * s + dy * c];
}

function computeJoints(pose, d) {
	pose = Object.assign({ sF: 0, eF: 0, sB: 0, eB: 0, hF: 0, kF: 0, hB: 0, kB: 0, lean: 0 }, pose);
	function reach(h, k) {
		const [, c1] = dir(h);
		const [, c2] = dir(h - k);
		return d.thigh * c1 + d.shin * c2 + d.footH;
	}
	let hipY = pose.hip !== undefined ? pose.hip : GROUND - Math.max(reach(pose.hF, pose.kF), reach(pose.hB, pose.kB));
	hipY += pose.drop || 0;
	let hipX = 0.5 + (pose.x || 0);

	let [upX, upY] = dir(pose.lean);
	upY = -upY;
	let shoulderX = hipX + upX * d.torsoLen,
		shoulderY = hipY + upY * d.torsoLen + (pose.breath || 0);
	let neckX = shoulderX + upX * d.neck,
		neckY = shoulderY + upY * d.neck;
	const headAngle = pose.lean + (pose.head || 0);
	let [hx, hy] = dir(headAngle);
	let headX = neckX + hx * d.head * 0.5,
		headY = neckY - hy * d.head * 0.5;

	function limbEnd(x, y, angle, length) {
		const [sx, cy] = dir(angle);
		return [x + sx * length, y + cy * length];
	}
	let shoulderFX = shoulderX + (d.shoulderSpread || 0.012),
		shoulderFY = shoulderY + 0.012;
	let shoulderBX = shoulderX - (d.shoulderSpread || 0.014),
		shoulderBY = shoulderY + 0.006;
	let [elbowFX, elbowFY] = limbEnd(shoulderFX, shoulderFY, pose.sF, d.upperArm);
	let [handFX, handFY] = limbEnd(elbowFX, elbowFY, pose.sF + pose.eF, d.foreArm);
	let [elbowBX, elbowBY] = limbEnd(shoulderBX, shoulderBY, pose.sB, d.upperArm);
	let [handBX, handBY] = limbEnd(elbowBX, elbowBY, pose.sB + pose.eB, d.foreArm);
	let hipFX = hipX + 0.014,
		hipFY = hipY;
	let hipBX = hipX - 0.014,
		hipBY = hipY;
	let [kneeFX, kneeFY] = limbEnd(hipFX, hipFY, pose.hF, d.thigh);
	let [ankleFX, ankleFY] = limbEnd(kneeFX, kneeFY, pose.hF - pose.kF, d.shin);
	let [kneeBX, kneeBY] = limbEnd(hipBX, hipBY, pose.hB, d.thigh);
	let [ankleBX, ankleBY] = limbEnd(kneeBX, kneeBY, pose.hB - pose.kB, d.shin);

	const rot = pose.rot || 0;
	const pivotX = (hipX + shoulderX) / 2,
		pivotY = (hipY + shoulderY) / 2;
	const r = (x, y) => rotateAround(x, y, pivotX, pivotY, rot);
	[hipX, hipY] = r(hipX, hipY);
	[shoulderX, shoulderY] = r(shoulderX, shoulderY);
	[neckX, neckY] = r(neckX, neckY);
	[headX, headY] = r(headX, headY);
	[shoulderFX, shoulderFY] = r(shoulderFX, shoulderFY);
	[shoulderBX, shoulderBY] = r(shoulderBX, shoulderBY);
	[elbowFX, elbowFY] = r(elbowFX, elbowFY);
	[handFX, handFY] = r(handFX, handFY);
	[elbowBX, elbowBY] = r(elbowBX, elbowBY);
	[handBX, handBY] = r(handBX, handBY);
	[hipFX, hipFY] = r(hipFX, hipFY);
	[hipBX, hipBY] = r(hipBX, hipBY);
	[kneeFX, kneeFY] = r(kneeFX, kneeFY);
	[ankleFX, ankleFY] = r(ankleFX, ankleFY);
	[kneeBX, kneeBY] = r(kneeBX, kneeBY);
	[ankleBX, ankleBY] = r(ankleBX, ankleBY);
	const bodyAngle = pose.lean + rot;

	return {
		hipX, hipY, shoulderX, shoulderY, neckX, neckY, headX, headY, headAngle,
		shoulderFX, shoulderFY, shoulderBX, shoulderBY,
		elbowFX, elbowFY, handFX, handFY, elbowBX, elbowBY, handBX, handBY,
		hipFX, hipFY, hipBX, hipBY, kneeFX, kneeFY, ankleFX, ankleFY, kneeBX, kneeBY, ankleBX, ankleBY,
		bodyAngle, rot, pose,
	};
}

function resolveColor(value, fallback, palette) {
	if (value === undefined || value === null) return fallback;
	if (value === "primary") return hex(palette.primary);
	if (value === "secondary") return hex(palette.secondary);
	if (value === "accent") return hex(palette.accent);
	return hex(value);
}

// Рисует одного бойца в заданной позе на холст супер-разрешения (canvas — Canvas из lib/canvas.js).
function drawCharacter(canvas, ss, facing, look, palette, pose) {
	const d = BUILDS[look.build] || BUILDS.Normal;
	const j = computeJoints(pose, d);

	const P = (x, y) => [(facing >= 0 ? x : 1 - x) * ss, y * ss];
	const capsule = (ax, ay, bx, by, width, color, alpha) => {
		const [px1, py1] = P(ax, ay);
		const [px2, py2] = P(bx, by);
		canvas.fillCapsule(px1, py1, px2, py2, width * ss, color, alpha);
	};
	const circle = (cx, cy, radius, color, alpha) => {
		const [px, py] = P(cx, cy);
		canvas.fillCircle(px, py, radius * ss, color, alpha);
	};
	// Тень на полу — под нижней стопой, для ощущения опоры.
	{
		const groundY = Math.max(j.ankleFY, j.ankleBY) + d.footH * 0.6;
		const [sx, sy] = P(j.hipX, groundY);
		canvas.fillCircle(sx, sy, d.torsoW * 0.9 * ss, BLACK, 0.16);
	}

	const skin = hex(look.skin || "#E0AC69");
	const topColor = resolveColor(look.top.color, skin, palette);
	const topTrim = resolveColor(look.top.trim, topColor, palette);
	const pantsColor = resolveColor(look.pants.color, topColor, palette);
	const bootColor = resolveColor(look.boots, BLACK, palette);
	const gloveColor = resolveColor(look.gloves, skin, palette);
	const hairColor = resolveColor(look.hair.color, BLACK, palette);
	const element = resolveColor(look.element, WHITE, palette);
	const bare = look.top.style === "Bare";
	const torsoColor = bare ? skin : topColor;
	const sleeveColor = look.sleeves === "None" || bare ? skin : topColor;
	const foreColor = look.sleeves === "Full" && !bare ? topColor : skin;
	const shinColor = look.pants.style === "Shorts" ? skin : pantsColor;

	// --- Аура (суперы) ---
	if (pose.aura && pose.aura > 0.02) {
		circle(j.hipX, j.hipY - 0.12, (d.torsoW + 0.2) * (1 + pose.aura * 0.15), element, 0.28 * pose.aura);
	}

	// --- Плащ/крылья за спиной (перед задней рукой) ---
	const extras = look.extras || {};
	if (extras.cape) {
		const capeColor = shade(resolveColor(extras.cape, topColor, palette), 0.12);
		const [bx, by] = dir(j.bodyAngle - 8);
		const tailX = j.shoulderX - bx * 0.02 - Math.max(0, pose.lean) * 0.0015;
		const tailY = j.hipY + 0.16 + Math.abs(Math.min(0, pose.lean)) * 0.001;
		capsule(j.shoulderX - 0.02, j.shoulderY, tailX - 0.05, tailY, d.torsoW * 0.55, capeColor, 1);
	}

	// --- Задняя рука / нога (тени) ---
	capsule(j.shoulderBX, j.shoulderBY, j.elbowBX, j.elbowBY, d.armW, shade(sleeveColor, 0.2), 1);
	capsule(j.elbowBX, j.elbowBY, j.handBX, j.handBY, d.foreW, shade(foreColor, 0.2), 1);
	circle(j.handBX, j.handBY, d.hand * 0.5, shade(gloveColor, 0.15), 1);
	capsule(j.hipBX, j.hipBY, j.kneeBX, j.kneeBY, d.legW, shade(pantsColor, 0.2), 1);
	capsule(j.kneeBX, j.kneeBY, j.ankleBX, j.ankleBY, d.shinW, shade(shinColor, 0.2), 1);
	drawFoot(canvas, ss, facing, j.ankleBX, j.ankleBY, j.pose.hB - j.pose.kB, j.rot, d, shade(bootColor, 0.15));

	// --- Таз + торс ---
	capsule(j.hipX - d.torsoW * 0.1, j.hipY, j.hipX + d.torsoW * 0.1, j.hipY, d.legW * 1.05, pantsColor, 1);
	capsule(j.hipX, j.hipY, j.shoulderX, j.shoulderY, d.torsoW, torsoColor, 1);
	{
		// Блик на груди — третий тон для объёма.
		const [nx, ny] = dir(j.bodyAngle + 90);
		capsule(j.hipX + nx * d.torsoW * 0.18, j.hipY + ny * d.torsoW * 0.18, j.shoulderX + nx * d.torsoW * 0.18, j.shoulderY + ny * d.torsoW * 0.18, d.torsoW * 0.32, shade(torsoColor, -0.14), 0.65);
	}
	drawTorsoDetail(canvas, P, capsule, circle, j, d, look, topColor, topTrim, skin, palette);
	capsule(j.shoulderX, j.shoulderY, j.neckX, j.neckY, d.foreW * 0.9, shade(skin, 0.1), 1);

	// --- Передняя нога ---
	capsule(j.hipFX, j.hipFY, j.kneeFX, j.kneeFY, d.legW, pantsColor, 1);
	capsule(j.kneeFX, j.kneeFY, j.ankleFX, j.ankleFY, d.shinW, shinColor, 1);
	capsule(j.hipFX, j.hipFY, j.kneeFX - d.legW * 0.15, j.kneeFY, d.legW * 0.3, shade(pantsColor, -0.12), 0.5);
	drawFoot(canvas, ss, facing, j.ankleFX, j.ankleFY, j.pose.hF - j.pose.kF, j.rot, d, bootColor);

	// --- Голова ---
	const headColor = look.face.eyes === "Skull" ? hex("#E8E4D8") : skin;
	circle(j.headX, j.headY, d.head * 0.52, headColor, 1);
	drawHair(canvas, P, capsule, circle, j, d, look, hairColor, topTrim, "back");
	drawHeadwear(canvas, P, capsule, circle, j, d, look, palette, "back");
	drawFace(canvas, P, capsule, circle, j, d, look, skin, hairColor, element, palette);
	drawHair(canvas, P, capsule, circle, j, d, look, hairColor, topTrim, "front");
	drawHeadwear(canvas, P, capsule, circle, j, d, look, palette, "front");

	// --- Передняя рука ---
	capsule(j.shoulderFX, j.shoulderFY, j.elbowFX, j.elbowFY, d.armW, sleeveColor, 1);
	{
		// Блик на бицепсе — тот же приём, что на груди/бедре, для объёма руки.
		const [nx, ny] = dir(j.bodyAngle + 90);
		capsule(j.shoulderFX + nx * d.armW * 0.22, j.shoulderFY + ny * d.armW * 0.22, j.elbowFX + nx * d.armW * 0.22, j.elbowFY + ny * d.armW * 0.22, d.armW * 0.34, shade(sleeveColor, -0.16), 0.55);
	}
	capsule(j.elbowFX, j.elbowFY, j.handFX, j.handFY, d.foreW * (look.top.style === "Robe" ? 1.2 : 1), foreColor, 1);
	const handSize = d.hand * (look.bigGloves ? 1.5 : 1) * (pose.open ? 1.15 : 1);
	circle(j.handFX, j.handFY, handSize * 0.5, gloveColor, 1);
	// Намёк на большой палец — иначе кисть читается как шар.
	{
		const hdx = j.handFX - j.elbowFX,
			hdy = j.handFY - j.elbowFY;
		const hlen = Math.hypot(hdx, hdy) || 0.0001;
		const [tnx, tny] = [-hdy / hlen, hdx / hlen];
		circle(j.handFX + tnx * handSize * 0.32 - hdx / hlen * handSize * 0.12, j.handFY + tny * handSize * 0.32 - hdy / hlen * handSize * 0.12, handSize * 0.22, shade(gloveColor, 0.08), 1);
	}

	// --- Оружие ---
	drawWeapon(canvas, P, capsule, circle, j, look, palette);

	// --- Наплечники / шарф / рюкзак поверх ---
	if (extras.shoulderPads) {
		// Тонкий меховой кант на предплечье задней руки — не лезет на лицо.
		const padColor = resolveColor(extras.shoulderPads, WHITE, palette);
		capsule(j.elbowBX, j.elbowBY, j.elbowBX + (j.handBX - j.elbowBX) * 0.35, j.elbowBY + (j.handBY - j.elbowBY) * 0.35, d.foreW * 1.5, shade(padColor, 0.1), 1);
	}
	if (extras.scarf) {
		capsule(j.neckX - 0.01, j.neckY - 0.01, j.neckX - 0.06, j.neckY + 0.08, d.foreW * 0.9, resolveColor(extras.scarf, WHITE, palette), 1);
	}
	if (extras.backpack) {
		const [bx, by] = dir(j.bodyAngle);
		capsule(j.shoulderX - bx * 0.02, j.shoulderY, j.hipX - bx * 0.02, j.hipY, d.torsoW * 0.5, resolveColor(extras.backpack, BLACK, palette), 1);
	}
	if (extras.jets) {
		circle(j.ankleFX, j.ankleFY + 0.02, d.footH * 0.6, resolveColor(extras.jets, element, palette), 1);
	}

	// --- Магическое свечение в руках (заряд особого/супера) ---
	if (pose.glow && pose.glow > 0.02) {
		const size = 0.028 + pose.glow * 0.045;
		circle(j.handFX, j.handFY, size, element, Math.min(1, 0.55 + pose.glow * 0.4));
		circle(j.handBX, j.handBY, size * 0.75, element, Math.min(1, 0.4 + pose.glow * 0.3));
	}
}

function drawFoot(canvas, ss, facing, ax, ay, shinAngle, rot, d, color) {
	const footAngle = shinAngle * 0.35 + rot;
	const [fx, fy] = dir(footAngle + 90);
	const P = (x, y) => [(facing >= 0 ? x : 1 - x) * ss, y * ss];
	const toeX = ax + fx * d.footL,
		toeY = ay + fy * d.footL + d.footH * 0.3;
	const [px1, py1] = P(ax, ay);
	const [px2, py2] = P(toeX, toeY);
	canvas.fillCapsule(px1, py1, px2, py2, d.footH * 1.3 * ss, color, 1);
	// Подошва: тонкая тёмная полоса снизу.
	const [nx, ny] = dir(footAngle + 180);
	const [sx1, sy1] = P(ax + nx * d.footH * 0.4, ay + ny * d.footH * 0.4);
	const [sx2, sy2] = P(toeX + nx * d.footH * 0.4, toeY + ny * d.footH * 0.4);
	canvas.fillCapsule(sx1, sy1, sx2, sy2, d.footH * 0.5 * ss, shade(color, 0.35), 1);
	// Манжета голенища: светлый кант у щиколотки.
	const [cx, cy] = P(ax, ay);
	canvas.fillCircle(cx, cy, d.footH * 0.55 * ss, shade(color, -0.15), 0.9);
}

function drawTorsoDetail(canvas, P, capsule, circle, j, d, look, topColor, topTrim, skin, palette) {
	const style = look.top.style;
	const mid = (t) => [j.hipX + (j.shoulderX - j.hipX) * t, j.hipY + (j.shoulderY - j.hipY) * t];
	if (style === "Jacket" || style === "Armor") {
		const [mx, my] = mid(0.08);
		capsule(mx, my, j.shoulderX, j.shoulderY, d.torsoW * 0.1, shade(topTrim, 0.1), 1); // молния
		const [nx, ny] = dir(j.bodyAngle + 90);
		capsule(j.shoulderX - nx * d.torsoW * 0.45, j.shoulderY - ny * d.torsoW * 0.45, j.shoulderX + nx * d.torsoW * 0.45, j.shoulderY + ny * d.torsoW * 0.45, d.torsoW * 0.14, topTrim, 1); // воротник
	} else if (style === "Gi" || style === "Robe" || style === "Cloak") {
		const [mx, my] = mid(0.1);
		capsule(mx, my, j.shoulderX + 0.01, j.shoulderY, d.torsoW * 0.22, topTrim, 1);
	} else if (style === "Tank" || style === "Top") {
		// Вырез горловины у плеча — маленький, а не «окно» посреди груди.
		const [nx, ny] = dir(j.bodyAngle + 90);
		const [mx, my] = mid(0.85);
		capsule(mx - nx * d.torsoW * 0.16, my - ny * d.torsoW * 0.16, mx + nx * d.torsoW * 0.16, my + ny * d.torsoW * 0.16, d.torsoW * 0.12, skin, 1);
	}
	if (style === "Bare") {
		// Грудь и пресс на голом торсе — иначе читается одноцветным пятном. Только тонкие
		// тени по центральной линии (пресс) и под ключицей (грудь), не сплошные пятна.
		const [cx1, cy1] = mid(0.12);
		const [cx2, cy2] = mid(0.24);
		capsule(cx1, cy1, cx2, cy2, d.torsoW * 0.72, shade(skin, 0.1), 0.4); // низ груди/диафрагма
		for (let i = 0; i < 2; i++) {
			const [ax, ay] = mid(0.42 + i * 0.16);
			capsule(ax - d.torsoW * 0.02, ay, ax + d.torsoW * 0.02, ay, d.torsoW * 0.5, shade(skin, 0.12), 0.35); // пресс
		}
	}
	if (look.belt) {
		const [mx, my] = mid(0.03);
		capsule(mx - d.torsoW * 0.5, my, mx + d.torsoW * 0.5, my, d.legW * 0.4, resolveColor(look.belt, topTrim, palette), 1);
	}
	if (look.extras && look.extras.sash) {
		const [mx, my] = mid(0.2);
		capsule(mx - d.torsoW * 0.4, j.hipY, mx + d.torsoW * 0.3, j.shoulderY, d.torsoW * 0.16, resolveColor(look.extras.sash, topTrim, palette), 1);
	}
}

const HAIR_DEPTH = { Short: 0.3, Long: 0.3, Ponytail: 0.3, Bob: 0.32, Spiky: 0.3, Mohawk: 0.28, Topknot: 0.26, Bald: 0, None: 0 };

function drawHair(canvas, P, capsule, circle, j, d, look, hairColor, topTrim, layer) {
	const style = look.hair.style;
	if (style === "None" || style === "Bald") return;
	const [bx, by] = dir(j.headAngle - 90);
	const [downX, downY] = dir(j.headAngle);
	// Макушка: центр смещён вверх-назад от центра головы (в системе координат головы).
	const capX = j.headX - bx * d.head * 0.12 - downX * d.head * 0.34;
	const capY = j.headY - by * d.head * 0.12 - downY * d.head * 0.34;
	if (layer === "back") {
		if (style === "Ponytail") {
			capsule(capX - bx * 0.02, capY + d.head * 0.15, capX - bx * 0.16, capY + d.head * 0.55, d.head * 0.2, hairColor, 1);
		} else if (style === "Long") {
			capsule(j.headX - bx * d.head * 0.2, j.headY - d.head * 0.1, j.headX - bx * d.head * 0.25, j.headY + d.head * 1.0, d.head * 0.36, hairColor, 1);
		} else if (style === "Topknot") {
			circle(capX, capY - d.head * 0.22, d.head * 0.15, hairColor, 1);
		}
		return;
	}
	// layer === front: «шапка» волос — накрывает макушку/виски, не заходит ниже бровей.
	circle(capX, capY, d.head * (HAIR_DEPTH[style] || 0.24) * 0.7 + d.head * 0.1, hairColor, 1);
	if (style === "Spiky" || style === "Mohawk") {
		for (let i = 0; i < 4; i++) {
			const t = i / 3 - 0.5;
			capsule(capX + t * d.head * 0.6 * bx + t * d.head * 0.1, capY - d.head * 0.05, capX + t * d.head * 0.75 * bx, capY - d.head * 0.45, d.head * 0.09, hairColor, 1);
		}
	}
	if (style === "Bob") {
		circle(j.headX - bx * d.head * 0.58, j.headY + d.head * 0.05, d.head * 0.2, hairColor, 1);
	}
	if (style === "Short") {
		for (let i = 0; i < 3; i++) {
			const t = i / 2 - 0.5;
			capsule(capX + t * d.head * 0.5, capY - d.head * 0.08, capX + t * d.head * 0.6, capY - d.head * 0.3, d.head * 0.065, shade(hairColor, -0.08), 1);
		}
	}
	if (style === "Topknot") {
		capsule(capX, capY - d.head * 0.1, capX, capY - d.head * 0.36, d.head * 0.14, topTrim, 1);
	}
}

function drawHeadwear(canvas, P, capsule, circle, j, d, look, palette, layer) {
	const head = look.head || {};
	const [bx, by] = dir(j.headAngle - 90);
	if (head.band && layer === "front") {
		// Смещаем полосу ко лбу (выше линии глаз), не через центр головы.
		const [downX, downY] = dir(j.headAngle);
		const bcx = j.headX - downX * d.head * 0.22,
			bcy = j.headY - downY * d.head * 0.22;
		capsule(bcx - bx * d.head * 0.56, bcy - by * d.head * 0.56, bcx + bx * d.head * 0.56, bcy + by * d.head * 0.56, d.head * 0.12, resolveColor(head.band, WHITE, palette), 1);
	}
	if (head.hood && layer === "back") {
		circle(j.headX - bx * d.head * 0.05, j.headY - d.head * 0.15, d.head * 0.62, resolveColor(head.hood, BLACK, palette), 1);
	}
	if (head.helmet && layer === "front") {
		circle(j.headX, j.headY - d.head * 0.15, d.head * 0.58, resolveColor(head.helmet, hex("#8A9199"), palette), 1);
		if (head.plume) {
			capsule(j.headX, j.headY - d.head * 0.55, j.headX - bx * 0.05, j.headY - d.head * 1.1, d.head * 0.1, resolveColor(head.plume, WHITE, palette), 1);
		}
	}
	if (head.goggles && layer === "front") {
		circle(j.headX + Math.abs(bx) * d.head * 0.15 + d.head * 0.15, j.headY - d.head * 0.02, d.head * 0.18, resolveColor(head.goggles, WHITE, palette), 1);
	}
	if (head.crown && layer === "front") {
		for (let i = 0; i < 3; i++) {
			const t = i / 2 - 0.5;
			circle(j.headX + t * d.head * 0.6, j.headY - d.head * 0.55, d.head * 0.1, resolveColor(head.crown, hex("#FFE66D"), palette), 1);
		}
	}
	if (head.headphones && layer === "front") {
		circle(j.headX - bx * d.head * 0.55, j.headY, d.head * 0.16, resolveColor(head.headphones, WHITE, palette), 1);
	}
}

function drawFace(canvas, P, capsule, circle, j, d, look, skin, hairColor, element, palette) {
	const eyes = look.face.eyes;
	const [fx] = dir(90); // направление "вперёд" по лицу
	const eyeX = j.headX + fx * d.head * 0.24;
	const eyeY = j.headY - d.head * 0.03;
	if (eyes === "Skull") {
		circle(eyeX, eyeY, d.head * 0.12, OUTLINE, 1);
		circle(eyeX, eyeY, d.head * 0.05, resolveColor(look.face.glow, element, palette), 1);
	} else if (eyes === "Visor") {
		circle(eyeX, eyeY, d.head * 0.19, resolveColor(look.face.glow, element, palette), 1);
		circle(eyeX, eyeY - d.head * 0.05, d.head * 0.06, WHITE, 0.5);
	} else if (eyes === "Glow") {
		circle(eyeX, eyeY, d.head * 0.13, resolveColor(look.face.glow, element, palette), 1);
		circle(eyeX, eyeY, d.head * 0.06, WHITE, 0.7);
	} else {
		// Белок + зрачок + бровь — не просто точка.
		const narrow = eyes === "Narrow";
		circle(eyeX, eyeY, d.head * (narrow ? 0.09 : 0.11), WHITE, 1);
		circle(eyeX + fx * d.head * 0.03, eyeY, d.head * (narrow ? 0.045 : 0.055), OUTLINE, 1);
		capsule(eyeX - d.head * 0.1, eyeY - d.head * 0.09, eyeX + d.head * 0.14, eyeY - d.head * (narrow ? 0.13 : 0.11), d.head * 0.045, shade(hairColor, 0.1), 1);
	}
	if (look.face.mask) {
		circle(eyeX - d.head * 0.05, j.headY + d.head * 0.18, d.head * 0.3, resolveColor(look.face.mask, BLACK, palette), 1);
	}
	if (look.face.beard) {
		// Компактная борода-эспаньолка на подбородке — не закрывает пол-лица.
		circle(eyeX - d.head * 0.02, j.headY + d.head * 0.46, d.head * 0.14, resolveColor(look.face.beard, BLACK, palette), 1);
	}
	if (!look.face.mask && eyes !== "Skull") {
		capsule(eyeX - d.head * 0.04, j.headY + d.head * 0.36, eyeX + d.head * 0.1, j.headY + d.head * 0.36, d.head * 0.035, shade(skin, 0.45), 1); // рот
	}
}

function drawWeapon(canvas, P, capsule, circle, j, look, palette) {
	if (!look.weapon) return;
	const w = look.weapon;
	const main = resolveColor(w.color, WHITE, palette);
	const trim = resolveColor(w.accent, WHITE, palette);
	const dx = j.handFX - j.elbowFX;
	const dy = j.handFY - j.elbowFY;
	const len = Math.hypot(dx, dy) || 0.0001;
	const wx = dx / len,
		wy = dy / len;
	const tip = (dist) => [j.handFX + wx * dist, j.handFY + wy * dist];
	if (w.kind === "Spear" || w.kind === "Staff" || w.kind === "Scythe") {
		const [bx, by] = tip(0.42);
		const [ax, ay] = tip(-0.14);
		capsule(ax, ay, bx, by, 0.016, main, 1);
		circle(bx, by, w.kind === "Staff" ? 0.045 : 0.03, trim, 1);
		if (w.kind === "Scythe") {
			const [cx, cy] = tip(0.28);
			circle(cx, cy, 0.06, trim, 1);
		}
	} else if (w.kind === "Katana") {
		const [bx, by] = tip(0.34);
		capsule(j.handFX, j.handFY, bx, by, 0.018, main, 1);
		circle(j.handFX, j.handFY, 0.025, trim, 1);
	} else if (w.kind === "Fans") {
		for (let i = 0; i < 3; i++) {
			const angle = Math.atan2(wy, wx) + ((i - 1) * Math.PI) / 6;
			const [bx, by] = [j.handFX + Math.cos(angle) * 0.09, j.handFY + Math.sin(angle) * 0.09];
			capsule(j.handFX, j.handFY, bx, by, 0.018, i % 2 === 0 ? trim : main, 1);
		}
	} else if (w.kind === "Disc") {
		circle(j.handFX + wx * 0.02, j.handFY + wy * 0.02, 0.038, main, 1);
		circle(j.handFX + wx * 0.02, j.handFY + wy * 0.02, 0.018, trim, 1);
	}
}

module.exports = { drawCharacter, BUILDS, computeJoints, dir, OUTLINE };
