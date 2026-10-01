"use strict";
/*
	Холст супер-разрешения для «настоящего» пиксель-арта:
	  1) рисуем чёткие (без сглаживания) полигоны/круги в высоком разрешении (SS);
	  2) даунсемплим боксом до целевого размера кадра — края сами становятся мягкими;
	  3) квантуем цвет каждого пикселя к ближайшему из палитры персонажа (плоские зоны цвета);
	  4) обводим силуэт на 1 пиксель тёмным контуром — классический вид спрайтов.
*/

function hex(str) {
	const s = str.replace("#", "");
	return { r: parseInt(s.slice(0, 2), 16), g: parseInt(s.slice(2, 4), 16), b: parseInt(s.slice(4, 6), 16) };
}

function lerpColor(a, b, t) {
	return { r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t };
}

function shade(c, amount) {
	// amount > 0 — темнее (к чёрному), amount < 0 — светлее (к белому).
	if (amount >= 0) return lerpColor(c, { r: 0, g: 0, b: 0 }, amount);
	return lerpColor(c, { r: 255, g: 255, b: 255 }, -amount);
}

class Canvas {
	constructor(w, h) {
		this.w = w;
		this.h = h;
		this.paletteSet = new Map(); // все цвета, которыми реально рисовали — база для квантизации
		this.data = new Float64Array(w * h * 4); // r,g,b,a — a acts as coverage 0..1
	}

	// Плоская (без AA) заливка выпуклого полигона сканлайнами.
	fillPolygon(points, color, alpha) {
		alpha = alpha === undefined ? 1 : alpha;
		let minY = Math.max(0, Math.floor(Math.min(...points.map((p) => p[1]))));
		let maxY = Math.min(this.h - 1, Math.ceil(Math.max(...points.map((p) => p[1]))));
		const n = points.length;
		for (let y = minY; y <= maxY; y++) {
			const yc = y + 0.5;
			const xs = [];
			for (let i = 0; i < n; i++) {
				const [x1, y1] = points[i];
				const [x2, y2] = points[(i + 1) % n];
				if ((y1 <= yc && y2 > yc) || (y2 <= yc && y1 > yc)) {
					const t = (yc - y1) / (y2 - y1);
					xs.push(x1 + t * (x2 - x1));
				}
			}
			xs.sort((a, b) => a - b);
			for (let i = 0; i + 1 < xs.length; i += 2) {
				const xStart = Math.max(0, Math.round(xs[i]));
				const xEnd = Math.min(this.w - 1, Math.round(xs[i + 1]) - 1);
				for (let x = xStart; x <= xEnd; x++) {
					this._blend(x, y, color, alpha);
				}
			}
		}
	}

	fillCircle(cx, cy, r, color, alpha) {
		alpha = alpha === undefined ? 1 : alpha;
		const minX = Math.max(0, Math.floor(cx - r));
		const maxX = Math.min(this.w - 1, Math.ceil(cx + r));
		const minY = Math.max(0, Math.floor(cy - r));
		const maxY = Math.min(this.h - 1, Math.ceil(cy + r));
		for (let y = minY; y <= maxY; y++) {
			for (let x = minX; x <= maxX; x++) {
				const dx = x + 0.5 - cx;
				const dy = y + 0.5 - cy;
				if (dx * dx + dy * dy <= r * r) this._blend(x, y, color, alpha);
			}
		}
	}

	// Толстая линия (капсула) между двумя точками — удобно для конечностей/оружия.
	fillCapsule(x1, y1, x2, y2, width, color, alpha) {
		const dx = x2 - x1;
		const dy = y2 - y1;
		const len = Math.hypot(dx, dy) || 0.0001;
		const nx = (-dy / len) * (width / 2);
		const ny = (dx / len) * (width / 2);
		this.fillPolygon(
			[
				[x1 + nx, y1 + ny],
				[x2 + nx, y2 + ny],
				[x2 - nx, y2 - ny],
				[x1 - nx, y1 - ny],
			],
			color,
			alpha
		);
		this.fillCircle(x1, y1, width / 2, color, alpha);
		this.fillCircle(x2, y2, width / 2, color, alpha);
	}

	_blend(x, y, color, alpha) {
		const key = Math.round(color.r) + "," + Math.round(color.g) + "," + Math.round(color.b);
		if (!this.paletteSet.has(key)) this.paletteSet.set(key, { r: color.r, g: color.g, b: color.b });
		if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
		const i = (y * this.w + x) * 4;
		const a = this.data[i + 3];
		const outA = alpha + a * (1 - alpha);
		if (outA <= 0) return;
		this.data[i] = (color.r * alpha + this.data[i] * a * (1 - alpha)) / outA;
		this.data[i + 1] = (color.g * alpha + this.data[i + 1] * a * (1 - alpha)) / outA;
		this.data[i + 2] = (color.b * alpha + this.data[i + 2] * a * (1 - alpha)) / outA;
		this.data[i + 3] = outA;
	}

	// Даунсемпл боксом SS->1 + квантизация к палитре + обводка силуэта. Возвращает Buffer RGBA (out*out*4).
	toSprite(outW, outH, palette, outlineColor) {
		const ssX = this.w / outW;
		const ssY = this.h / outH;
		const rgba = new Uint8ClampedArray(outW * outH * 4);
		const mask = new Uint8Array(outW * outH);
		for (let y = 0; y < outH; y++) {
			for (let x = 0; x < outW; x++) {
				let r = 0,
					g = 0,
					b = 0,
					a = 0,
					count = 0;
				const x0 = Math.floor(x * ssX);
				const x1 = Math.floor((x + 1) * ssX);
				const y0 = Math.floor(y * ssY);
				const y1 = Math.floor((y + 1) * ssY);
				for (let sy = y0; sy < y1; sy++) {
					for (let sx = x0; sx < x1; sx++) {
						const i = (sy * this.w + sx) * 4;
						const alpha = this.data[i + 3];
						r += this.data[i] * alpha;
						g += this.data[i + 1] * alpha;
						b += this.data[i + 2] * alpha;
						a += alpha;
						count++;
					}
				}
				const avgA = a / count;
				const o = (y * outW + x) * 4;
				if (avgA < 0.35 || count === 0) {
					rgba[o] = 0;
					rgba[o + 1] = 0;
					rgba[o + 2] = 0;
					rgba[o + 3] = 0;
					mask[y * outW + x] = 0;
					continue;
				}
				const avgR = r / a;
				const avgG = g / a;
				const avgB = b / a;
				const nearest = nearestColor(palette, avgR, avgG, avgB);
				rgba[o] = nearest.r;
				rgba[o + 1] = nearest.g;
				rgba[o + 2] = nearest.b;
				rgba[o + 3] = 255;
				mask[y * outW + x] = 1;
			}
		}
		// Обводка: 1px тёмный контур по внешнему краю силуэта.
		const outC = outlineColor;
		for (let y = 0; y < outH; y++) {
			for (let x = 0; x < outW; x++) {
				const idx = y * outW + x;
				if (mask[idx]) continue;
				let touches = false;
				for (const [dx, dy] of [
					[1, 0],
					[-1, 0],
					[0, 1],
					[0, -1],
				]) {
					const nx = x + dx,
						ny = y + dy;
					if (nx >= 0 && ny >= 0 && nx < outW && ny < outH && mask[ny * outW + nx]) {
						touches = true;
						break;
					}
				}
				if (touches) {
					const o = idx * 4;
					rgba[o] = outC.r;
					rgba[o + 1] = outC.g;
					rgba[o + 2] = outC.b;
					rgba[o + 3] = 255;
				}
			}
		}
		return Buffer.from(rgba.buffer, rgba.byteOffset, rgba.byteLength);
	}
}

function nearestColor(palette, r, g, b) {
	let best = palette[0];
	let bestDist = Infinity;
	for (const c of palette) {
		const dr = c.r - r,
			dg = c.g - g,
			db = c.b - b;
		const dist = dr * dr + dg * dg + db * db;
		if (dist < bestDist) {
			bestDist = dist;
			best = c;
		}
	}
	return best;
}

module.exports = { Canvas, hex, lerpColor, shade };
