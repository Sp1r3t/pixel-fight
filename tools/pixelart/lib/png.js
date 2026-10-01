"use strict";
/*
	Минимальный PNG-энкодер (8-bit RGBA, без интерлейса) на встроенном zlib —
	чтобы не тянуть внешние зависимости (npm недоступен/не нужен в этом репо).
*/
const zlib = require("zlib");
const crc32 = require("./crc32");

function chunk(type, data) {
	const typeBuf = Buffer.from(type, "ascii");
	const body = Buffer.concat([typeBuf, data]);
	const len = Buffer.alloc(4);
	len.writeUInt32BE(data.length, 0);
	const crc = Buffer.alloc(4);
	crc.writeUInt32BE(crc32(body), 0);
	return Buffer.concat([len, body, crc]);
}

// pixels: Uint8ClampedArray/Buffer RGBA, length = width*height*4
function encodePNG(width, height, pixels) {
	const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0);
	ihdr.writeUInt32BE(height, 4);
	ihdr[8] = 8; // bit depth
	ihdr[9] = 6; // color type RGBA
	ihdr[10] = 0;
	ihdr[11] = 0;
	ihdr[12] = 0;

	// Добавляем байт фильтра (0 = None) в начало каждой строки.
	const stride = width * 4;
	const raw = Buffer.alloc((stride + 1) * height);
	for (let y = 0; y < height; y++) {
		raw[y * (stride + 1)] = 0;
		pixels.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
	}
	const idat = zlib.deflateSync(raw, { level: 9 });

	return Buffer.concat([sig, chunk("IHDR", ihdr), chunk("IDAT", idat), chunk("IEND", Buffer.alloc(0))]);
}

module.exports = { encodePNG };
