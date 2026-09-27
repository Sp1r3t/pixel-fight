--!strict
--[[
	ArenaArt — процедурная «слегка пиксельная» графика карт (клиент).

	Всё рисуется прямоугольниками (Frame) по сетке «пикселей арта» (на арене 1 пиксель = 1 студ),
	поэтому получается аккуратный пиксель-арт без картинок. Рисунок детерминирован по id карты.

	  • ArenaArt.build(layers, theme)  — фон арены: небо (градиент, солнце/луна/планеты/туманности,
	    звёзды, сияние), дальние и ближние силуэты, погода и анимированные детали: облака, птицы, молнии,
	    дым и извержение вулкана, дракон с огненным дыханием, неоновые вывески, летающие машины,
	    метеоры, звездолёт. Возвращает update(dt) для анимации;
	  • ArenaArt.preview(parent, theme) — статичная картинка карты для карточек выбора и магазина.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)

type Theme = Arenas.ArenaTheme

-- Холст слоя: куда рисовать и сколько в нём «пикселей арта».
export type Layer = {
	canvas: Instance,
	cols: number,
	rows: number,
}

export type Layers = {
	sky: Layer,
	mid: Layer,
	weather: Layer?,
}

export type Art = {
	update: (dt: number) -> (),
}

type Animation = (t: number, dt: number) -> ()

type Ctx = {
	theme: Theme,
	rng: Rng.Rng, -- рисунок (детерминированный)
	anim: Rng.Rng, -- случайность анимаций
	preview: boolean,
	animations: { Animation },
}

--[[
	Доли высоты холста, где стоят силуэты (линия горизонта). Arena ставит плоскости так, чтобы
	эта линия приходилась на дальний край пола: всё, что ниже, закрыто полом. Небесные детали
	рисуются относительно горизонта: камера видит примерно 35–45 клеток над ним.
]]
local SKY_BASELINE = 0.62
local MID_BASELINE = 0.62
-- Высота силуэтов: дальние — до ~15 клеток, ближние (средний план крупнее на экране) — ниже.
local FAR_SCALE = 0.5
local MID_SCALE = 0.3
local TORII_HEIGHT = 24
-- Размер «пикселя» арта в клетках (клетка = 1 студ): на экране ~5 точек — «слегка пиксельно».
local PIXEL = 0.5

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local ArenaArt = {}

----------------------------------------------------------------------------------------------
-- Примитивы
----------------------------------------------------------------------------------------------

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

-- Прямоугольник в клетках сетки gx × gy родителя (координаты округляются до клетки).
local function box(
	parent: Instance,
	gx: number,
	gy: number,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	local sx, sy = math.floor(x / PIXEL + 0.5) * PIXEL, math.floor(y / PIXEL + 0.5) * PIXEL
	local sw = math.max(PIXEL, math.floor(w / PIXEL + 0.5) * PIXEL)
	local sh = math.max(PIXEL, math.floor(h / PIXEL + 0.5) * PIXEL)
	frame.Position = UDim2.fromScale(sx / gx, sy / gy)
	frame.Size = UDim2.fromScale(sw / gx, sh / gy)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

-- То же без округления (для мелких деталей и движущихся частиц).
local function freeBox(
	parent: Instance,
	gx: number,
	gy: number,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Position = UDim2.fromScale(x / gx, y / gy)
	frame.Size = UDim2.fromScale(w / gx, h / gy)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

-- Прозрачный контейнер для движущегося объекта (внутри — своя сетка).
local function holder(layer: Layer, x: number, y: number, w: number, h: number, z: number): Frame
	local frame = freeBox(layer.canvas, layer.cols, layer.rows, x, y, w, h, BLACK, z, 1)
	frame.Name = "Sprite"
	return frame
end

local function place(frame: GuiObject, layer: Layer, x: number, y: number)
	frame.Position = UDim2.fromScale(x / layer.cols, y / layer.rows)
end

-- Пиксельный круг (эллипс): строки со «ступеньками» по краям.
local function disc(
	parent: Instance,
	gx: number,
	gy: number,
	cx: number,
	cy: number,
	rx: number,
	ry: number,
	color: Color3,
	z: number,
	transparency: number?
)
	local rows = math.max(1, math.floor(ry * 2 / PIXEL + 0.5))
	for row = 0, rows - 1 do
		local t = (row + 0.5) / rows * 2 - 1
		local half = rx * math.sqrt(math.max(0, 1 - t * t))
		local width = math.max(PIXEL, math.floor(half * 2 / PIXEL + 0.5) * PIXEL)
		box(parent, gx, gy, cx - width / 2, cy - ry + row * PIXEL, width, PIXEL, color, z, transparency)
	end
end

-- Ступенчатый треугольник (гора, ёлка, шип): основание на baseY, вершина выше на h.
local function stepped(
	parent: Instance,
	gx: number,
	gy: number,
	x: number,
	baseY: number,
	w: number,
	h: number,
	steps: number,
	color: Color3,
	z: number,
	topWidth: number?
)
	local top = topWidth or 0
	for step = 0, steps - 1 do
		local t = step / steps
		local width = w + (top - w) * t
		box(parent, gx, gy, x + (w - width) / 2, baseY - h * (t + 1 / steps), width, h / steps + PIXEL, color, z)
	end
end

local function layerBox(
	layer: Layer,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number,
	transparency: number?
): Frame
	return box(layer.canvas, layer.cols, layer.rows, x, y, w, h, color, z, transparency)
end

----------------------------------------------------------------------------------------------
-- Силуэты
----------------------------------------------------------------------------------------------

-- Окна зданий: сетка «пикселей», часть горит.
local function windows(
	layer: Layer,
	ctx: Ctx,
	x: number,
	top: number,
	w: number,
	h: number,
	colors: { Color3 },
	chance: number,
	z: number
)
	-- Окна только в той части холста, которую видит камера (экономим объекты на телефоне).
	if (ctx.preview and w < 6) or x + w < layer.cols * 0.25 or x > layer.cols * 0.75 then
		return
	end
	local rng = ctx.rng
	local wy = top + 1.5
	while wy < top + h - 1 do
		local wx = x + 1
		while wx < x + w - 1 do
			if Rng.chance(rng, chance) then
				local color = colors[Rng.integer(rng, 1, #colors)]
				layerBox(layer, wx, wy, PIXEL, PIXEL * 2, color, z, Rng.range(rng, 0, 0.35))
			end
			wx += 1.5
		end
		wy += 2.5
	end
end

local function drawSilhouettes(
	layer: Layer,
	ctx: Ctx,
	style: Arenas.Silhouette,
	color: Color3,
	baseline: number,
	scale: number,
	z: number,
	near: boolean
)
	local rng = ctx.rng
	local theme = ctx.theme
	local cols = layer.cols
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local glow = hex(theme.glow)
	local accent = hex(theme.accent)
	-- Камера видит только середину холста (с учётом сдвига при движении) — рисуем с запасом её.
	local startX, endX = cols * 0.18, cols * 0.82
	local x = startX - Rng.range(rng, 2, 12)
	if style == "Mountains" then
		while x < endX do
			local w = Rng.range(rng, 26, 48) * (if near then 1.2 else 1)
			local h = Rng.range(rng, 12, 30) * scale
			stepped(canvas, gx, gy, x, baseline, w, h, if ctx.preview then 4 else 6, color, z)
			if theme.weather == "Snow" and not near then
				-- Снежная шапка на вершине.
				local capH = h * 0.25
				stepped(canvas, gx, gy, x + w * 0.375, baseline - h + capH, w * 0.25, capH, 3, hex("#EEF6FF"), z)
			end
			x += w * Rng.range(rng, 0.55, 0.8)
		end
	elseif style == "City" or style == "Skyline" then
		local tall = style == "Skyline"
		local windowColors = if tall
			then { glow, accent, hex("#FFE066") }
			else { hex("#FFE9A8"), hex("#FFD166"), accent }
		while x < endX do
			local w = if near then Rng.range(rng, 5, 11) else Rng.range(rng, 8, if tall then 20 else 16)
			local h = Rng.range(rng, if tall then 18 else 10, if tall then 46 else 32) * scale
			if near and tall then
				h *= 0.7
			end
			local top = baseline - h
			layerBox(layer, x, top, w, h + 1, color, z)
			if tall and Rng.chance(rng, 0.6) then
				-- Ступенчатая крыша и антенна с мигающим огоньком.
				local roofW = w * 0.6
				layerBox(layer, x + (w - roofW) / 2, top - 3, roofW, 3, color, z)
				local antennaX = x + w / 2
				local antennaH = Rng.range(rng, 4, 9)
				layerBox(layer, antennaX, top - 3 - antennaH, 1, antennaH, color, z)
				if not ctx.preview then
					local light = layerBox(layer, antennaX, top - 4 - antennaH, 1, 1, hex("#FF4D6D"), z + 1)
					local phase = Rng.range(rng, 0, 6)
					table.insert(ctx.animations, function(t: number)
						light.BackgroundTransparency = if math.sin(t * 3 + phase) > 0.2 then 0 else 0.9
					end)
				end
			end
			local chance = (if near then 0.2 else 0.35) * (if ctx.preview then 0.4 else 1)
			windows(layer, ctx, x, top, w, h, windowColors, chance, z + 1)
			x += w + (if near then Rng.range(rng, 1, 6) else Rng.range(rng, 0, 3))
		end
	elseif style == "Pillars" then
		while x < endX do
			local w = Rng.range(rng, 1, 2)
			local h = Rng.range(rng, 16, 26) * scale
			-- Столбы не заслоняют ворота в центре.
			if not near or math.abs(x - cols / 2) > 12 or table.find(theme.features, "Lanterns") == nil then
				layerBox(layer, x, baseline - h, w, h + 1, color, z)
				layerBox(layer, x - 0.5, baseline - h, w + 1, 0.5, color, z)
			end
			x += Rng.range(rng, 14, 22)
		end
		if near and table.find(theme.features, "Lanterns") == nil then
			-- Причал: перила между столбами.
			layerBox(layer, -2, baseline - 16 * scale * 0.6, cols + 4, 0.5, color, z)
		elseif near then
			-- Ворота-тории в центре: два столба, верхняя изогнутая балка и перекладина.
			local center = cols / 2
			local h = TORII_HEIGHT * scale
			layerBox(layer, center - 6, baseline - h, 1.5, h + 1, color, z)
			layerBox(layer, center + 4.5, baseline - h, 1.5, h + 1, color, z)
			layerBox(layer, center - 8, baseline - h - 1, 16, 1, color, z)
			layerBox(layer, center - 9, baseline - h - 1.5, 2, 1, color, z)
			layerBox(layer, center + 7, baseline - h - 1.5, 2, 1, color, z)
			layerBox(layer, center - 6.5, baseline - h * 0.78, 13, 0.5, color, z)
		end
	elseif style == "Spikes" then
		while x < endX do
			local w = Rng.range(rng, 3, 9)
			local h = Rng.range(rng, 8, 30) * scale
			stepped(canvas, gx, gy, x, baseline, w, h, if ctx.preview then 3 else 4, color, z)
			x += w + Rng.range(rng, 0.5, 5)
		end
	elseif style == "Waves" then
		-- Далёкие острова на горизонте и море полосами (волны покачиваются).
		for _ = 1, 3 do
			local ix = Rng.range(rng, cols * 0.15, cols * 0.85)
			stepped(canvas, gx, gy, ix, baseline - 3, Rng.range(rng, 14, 26), Rng.range(rng, 3, 7), 3, color, z)
		end
		local bands: { Frame } = {}
		for band = 0, 3 do
			local bandColor = color:Lerp(WHITE, band * 0.07)
			table.insert(bands, layerBox(layer, -10, baseline - 3 + band * 2.2, cols + 20, 2, bandColor, z))
			-- Блики на воде.
			if not ctx.preview then
				for _ = 1, 6 do
					layerBox(
						layer,
						Rng.range(rng, 0, cols),
						baseline - 3 + band * 2.2,
						Rng.range(rng, 2, 6),
						1,
						hex(theme.accent),
						z + 1,
						0.5
					)
				end
			end
		end
		if not ctx.preview then
			table.insert(ctx.animations, function(t: number)
				for index, band in bands do
					band.Position = UDim2.fromScale((-10 + math.sin(t * 0.8 + index) * 2) / cols, band.Position.Y.Scale)
				end
			end)
		end
	elseif style == "Trees" then
		while x < endX do
			local w = Rng.range(rng, 8, 16) * (if near then 1.3 else 1)
			local h = Rng.range(rng, 18, 36) * scale
			layerBox(layer, x + w / 2 - 1, baseline - h * 0.25, 2, h * 0.25 + 1, color, z)
			local tiers = Rng.integer(rng, 3, 5)
			for tier = 0, tiers - 1 do
				local tierBase = baseline - h * 0.18 - tier * (h * 0.8 / tiers)
				local tierW = w * (1 - tier / (tiers + 1))
				stepped(
					canvas,
					gx,
					gy,
					x + (w - tierW) / 2,
					tierBase,
					tierW,
					h * 0.35,
					if ctx.preview then 2 else 3,
					color,
					z
				)
			end
			x += w * Rng.range(rng, 0.5, 0.9)
		end
	elseif style == "Volcano" then
		-- Горы по краям, а сам вулкан рисует деталь «Volcano».
		while x < endX do
			local w = Rng.range(rng, 20, 36)
			local h = Rng.range(rng, 8, 20) * scale
			stepped(canvas, gx, gy, x, baseline, w, h, 6, color, z)
			x += w * Rng.range(rng, 0.6, 0.9)
		end
	elseif style == "Rocks" then
		-- Каменистая земля и парящие астероиды.
		while x < endX do
			local w = Rng.range(rng, 6, 14)
			local h = Rng.range(rng, 3, 10) * scale
			stepped(canvas, gx, gy, x, baseline, w, h, 3, color, z)
			x += w + Rng.range(rng, 0, 4)
		end
		local count = if near then 0 else 7
		for _ = 1, count do
			local rx = Rng.range(rng, 2, if near then 4 else 6)
			local ry = rx * Rng.range(rng, 0.5, 0.8)
			local cx = Rng.range(rng, cols * 0.2, cols * 0.8)
			local cy = Rng.range(rng, baseline - (if near then 16 else 40), baseline - rx - 5)
			disc(canvas, gx, gy, cx, cy, rx, ry, color, z)
			-- Светлая кромка сверху.
			box(canvas, gx, gy, cx - rx * 0.5, cy - ry, rx, 1, color:Lerp(glow, 0.25), z)
		end
	end
	-- Сплошная земля под силуэтами.
	layerBox(layer, -2, baseline, cols + 4, layer.rows - baseline + 2, color, z)
end

----------------------------------------------------------------------------------------------
-- Небо и детали
----------------------------------------------------------------------------------------------

local function skyColorAt(theme: Theme, fraction: number): Color3
	return hex(theme.skyTop):Lerp(hex(theme.skyBottom), math.clamp(fraction, 0, 1))
end

local function drawGradient(layer: Layer, theme: Theme)
	local sky = layerBox(layer, 0, 0, layer.cols, layer.rows, WHITE, 1)
	sky.Name = "SkyGradient"
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(hex(theme.skyTop), hex(theme.skyBottom))
	gradient.Rotation = 90
	gradient.Parent = sky
end

local function drawSun(layer: Layer, ctx: Ctx)
	local theme = ctx.theme
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local cx, cy, r = layer.cols * 0.58, layer.rows * SKY_BASELINE - 19, 5.5
	local accent = hex(theme.accent)
	disc(canvas, gx, gy, cx, cy, r + 4, r + 4, accent, 3, 0.88)
	disc(canvas, gx, gy, cx, cy, r + 2, r + 2, accent, 3, 0.74)
	disc(canvas, gx, gy, cx, cy, r, r, accent, 4)
	-- «Ретро»-полосы на нижней половине солнца.
	for index, dy in { 1.5, 3, 4.5 } do
		local y = cy + dy
		local color = skyColorAt(theme, y / layer.rows)
		box(canvas, gx, gy, cx - r - 1, y, r * 2 + 2, if index == 3 then 1 else 0.5, color, 5)
	end
end

local function drawMoon(layer: Layer, ctx: Ctx)
	local theme = ctx.theme
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local cx, cy, r = layer.cols * 0.6, layer.rows * SKY_BASELINE - 24, 4
	local moon = hex("#F4F1DE"):Lerp(hex(theme.accent), 0.15)
	disc(canvas, gx, gy, cx, cy, r + 3, r + 3, moon, 3, 0.9)
	disc(canvas, gx, gy, cx, cy, r + 1.5, r + 1.5, moon, 3, 0.8)
	disc(canvas, gx, gy, cx, cy, r, r, moon, 4)
	local crater = moon:Lerp(hex(theme.skyTop), 0.25)
	box(canvas, gx, gy, cx - 2, cy - 1.5, 1, 1, crater, 5)
	box(canvas, gx, gy, cx + 0.5, cy + 0.5, 1.5, 1, crater, 5)
	box(canvas, gx, gy, cx - 1.5, cy + 2, 1, 0.5, crater, 5)
end

local function drawStars(layer: Layer, ctx: Ctx)
	local rng = ctx.rng
	local count = if ctx.preview then 12 else 55
	local stars: { { frame: Frame, phase: number, speed: number } } = {}
	for _ = 1, count do
		local size = if Rng.chance(rng, 0.2) then 1 else 0.5
		local frame = layerBox(
			layer,
			Rng.range(rng, layer.cols * 0.1, layer.cols * 0.9),
			Rng.range(rng, layer.rows * SKY_BASELINE - 62, layer.rows * SKY_BASELINE - 8),
			size,
			size,
			if Rng.chance(rng, 0.2) then hex(ctx.theme.accent) else WHITE,
			3,
			Rng.range(rng, 0, 0.4)
		)
		table.insert(stars, { frame = frame, phase = Rng.range(rng, 0, 6.3), speed = Rng.range(rng, 1, 3.5) })
	end
	if ctx.preview then
		return
	end
	table.insert(ctx.animations, function(t: number)
		for _, star in stars do
			star.frame.BackgroundTransparency = 0.15 + 0.7 * (0.5 + 0.5 * math.sin(t * star.speed + star.phase))
		end
	end)
end

local function drawNebula(layer: Layer, ctx: Ctx)
	local rng = ctx.rng
	local theme = ctx.theme
	local colors = { hex(theme.glow), hex(theme.far):Lerp(WHITE, 0.2), hex("#B45CFF") }
	for index = 1, 3 do
		local w = Rng.range(rng, 30, 55)
		local h = w * Rng.range(rng, 0.3, 0.45)
		local blob = freeBox(
			layer.canvas,
			layer.cols,
			layer.rows,
			Rng.range(rng, layer.cols * 0.2, layer.cols * 0.7) - w / 2,
			Rng.range(rng, layer.rows * SKY_BASELINE - 60, layer.rows * SKY_BASELINE - 36),
			w,
			h,
			colors[(index - 1) % #colors + 1],
			2,
			0.8
		)
		blob.Name = "Nebula"
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 0.9),
		})
		gradient.Parent = blob
	end
end

local function drawAurora(layer: Layer, ctx: Ctx)
	local theme = ctx.theme
	local strips: { { frame: Frame, x: number, band: number } } = {}
	local colors = { hex(theme.glow), hex(theme.glow):Lerp(hex("#B388FF"), 0.6), hex("#B388FF") }
	local startX, endX = layer.cols * 0.2, layer.cols * 0.8
	local stripW = if ctx.preview then 8 else 4
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	for band = 1, 3 do
		local x = startX
		while x < endX do
			local frame = freeBox(layer.canvas, layer.cols, layer.rows, x, 0, stripW, 1, colors[band], 3, 0.6)
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 90
			gradient.Transparency = fade
			gradient.Parent = frame
			table.insert(strips, { frame = frame, x = x, band = band })
			x += stripW
		end
	end
	local rows = layer.rows
	local function shape(t: number)
		for _, strip in strips do
			local wave = math.sin(strip.x * 0.06 + t * 0.7 + strip.band * 1.7)
			local height = 9 + 5 * wave
			local centerY = rows * SKY_BASELINE - 44 + strip.band * 6 + 3 * math.sin(strip.x * 0.03 + t * 0.4)
			strip.frame.Position = UDim2.fromScale(strip.x / layer.cols, (centerY - height / 2) / rows)
			strip.frame.Size = UDim2.fromScale(stripW / layer.cols, height / rows)
			strip.frame.BackgroundTransparency = 0.45 + 0.3 * (0.5 + 0.5 * math.sin(t * 1.3 + strip.x * 0.1))
		end
	end
	shape(0)
	if not ctx.preview then
		table.insert(ctx.animations, shape)
	end
end

local function drawClouds(layer: Layer, ctx: Ctx)
	local rng = ctx.rng
	local theme = ctx.theme
	local color = WHITE:Lerp(hex(theme.skyBottom), 0.35)
	local clouds: { { frame: Frame, x: number, y: number, speed: number, w: number } } = {}
	local count = if ctx.preview then 3 else 7
	for _ = 1, count do
		local w = Rng.range(rng, 9, 16)
		local h = 3
		local x = Rng.range(rng, 0, layer.cols)
		local y = Rng.range(rng, layer.rows * SKY_BASELINE - 44, layer.rows * SKY_BASELINE - 16)
		local cloud = holder(layer, x, y, w, h, 6)
		local gw, gh = w, h
		box(cloud, gw, gh, 0, 1.5, w, 1.5, color, 6, 0.15)
		box(cloud, gw, gh, w * 0.15, 0.5, w * 0.35, 1, color, 6, 0.15)
		box(cloud, gw, gh, w * 0.45, 0, w * 0.3, 1.5, color, 6, 0.15)
		table.insert(clouds, { frame = cloud, x = x, y = y, speed = Rng.range(rng, 0.6, 1.8), w = w })
	end
	if ctx.preview then
		return
	end
	table.insert(ctx.animations, function(_t: number, dt: number)
		for _, cloud in clouds do
			cloud.x += cloud.speed * dt
			if cloud.x > layer.cols + 5 then
				cloud.x = -cloud.w - 5
			end
			place(cloud.frame, layer, cloud.x, cloud.y)
		end
	end)
end

-- Стая птиц время от времени пролетает по небу.
local function drawBirds(layer: Layer, ctx: Ctx)
	if ctx.preview then
		return
	end
	local color = hex(ctx.theme.near)
	type Bird = { frame: Frame, up: Frame, down: Frame, dx: number, dy: number }
	local birds: { Bird } = {}
	for index = 1, 5 do
		local bird = holder(layer, -20, 0, 2.5, 1.5, 6)
		local up = Instance.new("Frame")
		up.BackgroundTransparency = 1
		up.Size = UDim2.fromScale(1, 1)
		up.Parent = bird
		box(up, 5, 3, 0, 0, 2, 1, color, 6)
		box(up, 5, 3, 3, 0, 2, 1, color, 6)
		box(up, 5, 3, 2, 1, 1, 1, color, 6)
		local down = up:Clone()
		for _, child in down:GetChildren() do
			local frame = child :: Frame
			if frame.Position.X.Scale < 0.3 or frame.Position.X.Scale > 0.5 then
				frame.Position = UDim2.fromScale(frame.Position.X.Scale, 2 / 3)
			end
		end
		down.Visible = false
		down.Parent = bird
		table.insert(birds, {
			frame = bird,
			up = up,
			down = down,
			dx = index * 3.5 + (index % 2),
			dy = (index % 3) * 1.8,
		})
	end
	local anim = ctx.anim
	local nextFlight = Rng.range(anim, 2, 6)
	local flying = false
	local x, y = 0, 0
	table.insert(ctx.animations, function(t: number, dt: number)
		if not flying then
			nextFlight -= dt
			if nextFlight <= 0 then
				flying = true
				x = layer.cols * 0.8
				y = Rng.range(anim, layer.rows * SKY_BASELINE - 34, layer.rows * SKY_BASELINE - 18)
			end
		end
		if flying then
			x -= 9 * dt
			if x < layer.cols * 0.2 - 40 then
				flying = false
				nextFlight = Rng.range(anim, 8, 16)
			end
		end
		local wingsUp = math.sin(t * 12) > 0
		for _, bird in birds do
			place(bird.frame, layer, x + bird.dx, y + bird.dy + math.sin(t * 2 + bird.dx) * 0.8)
			bird.frame.Visible = flying
			bird.up.Visible = wingsUp
			bird.down.Visible = not wingsUp
		end
	end)
end

-- Молнии: вспышка неба и зигзаг разряда.
local function drawLightning(layer: Layer, ctx: Ctx)
	if ctx.preview then
		return
	end
	local flash = layerBox(layer, 0, 0, layer.cols, layer.rows, WHITE, 19, 1)
	flash.Name = "Flash"
	local boltTop = layer.rows * SKY_BASELINE - 64
	local bolt = holder(layer, 0, boltTop, layer.cols, 64, 18)
	bolt.Visible = false
	local anim = ctx.anim
	local nextStrike = Rng.range(anim, 3, 7)
	local strikeTime = -1
	local function buildBolt()
		for _, child in bolt:GetChildren() do
			child:Destroy()
		end
		local gx, gy = layer.cols, 64
		local x = Rng.range(anim, gx * 0.35, gx * 0.65)
		local y = 0
		local color = hex(ctx.theme.accent):Lerp(WHITE, 0.6)
		while y < gy - 2 do
			local segment = Rng.range(anim, 4, 9)
			box(bolt, gx, gy, x, y, 1.2, segment, color, 18)
			y += segment
			local shift = Rng.range(anim, -5, 5)
			box(bolt, gx, gy, math.min(x, x + shift), y, math.abs(shift) + 1, 1.2, color, 18)
			x += shift
		end
	end
	table.insert(ctx.animations, function(_t: number, dt: number)
		nextStrike -= dt
		if nextStrike <= 0 then
			nextStrike = Rng.range(anim, 5, 11)
			strikeTime = 0
			buildBolt()
		end
		if strikeTime >= 0 then
			strikeTime += dt
			-- Двойная вспышка: яркая, пауза, слабее.
			local alpha = if strikeTime < 0.08
				then 0.45
				elseif strikeTime < 0.14 then 0.9
				elseif strikeTime < 0.22 then 0.6
				else math.min(1, 0.6 + (strikeTime - 0.22) * 2)
			flash.BackgroundTransparency = alpha
			bolt.Visible = strikeTime < 0.2
			if strikeTime > 0.5 then
				strikeTime = -1
				flash.BackgroundTransparency = 1
			end
		end
	end)
end

-- Вулкан: конус с лавой, дым и периодическое извержение.
local function drawVolcano(layer: Layer, ctx: Ctx)
	local theme = ctx.theme
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local baseline = layer.rows * SKY_BASELINE
	local big = theme.silhouette == "Volcano"
	local cx = layer.cols * (if big then 0.53 else 0.55)
	local w = if big then 46 else 30
	local h = if big then 17 else 12
	local top = if big then 7 else 5
	local color = hex(theme.far):Lerp(BLACK, 0.2)
	local glow = hex(theme.glow)
	local accent = hex(theme.accent)
	stepped(canvas, gx, gy, cx - w / 2, baseline, w, h, 10, color, 8, top)
	local craterY = baseline - h
	local crater = box(canvas, gx, gy, cx - (top - 2) / 2, craterY - 0.5, top - 2, 1, glow, 9)
	box(canvas, gx, gy, cx - (top - 4) / 2, craterY - 1, top - 4, 0.5, glow, 9, 0.3)
	-- Потоки лавы по склонам.
	local rng = ctx.rng
	for side = -1, 1, 2 do
		local x, y = cx + side * 2, craterY + 1
		while y < baseline - 2 do
			local run = Rng.range(rng, 1, 2.5)
			box(canvas, gx, gy, x, y, 0.5, run, glow, 9, 0.25)
			y += run
			x += side * Rng.range(rng, 0.5, 1.5)
		end
	end
	if ctx.preview then
		return
	end
	-- Дым: клубы поднимаются из кратера, растут и тают.
	type Puff = { frame: Frame, age: number, life: number, drift: number }
	local puffs: { Puff } = {}
	local smokeColor = hex("#6B5B5B")
	for index = 1, 6 do
		local puff = freeBox(canvas, gx, gy, cx, craterY, 2, 1.5, smokeColor, 7, 0.5)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.3, 0)
		corner.Parent = puff
		table.insert(puffs, { frame = puff, age = index * 0.9, life = 5.4, drift = Rng.range(rng, -1.5, 2.5) })
	end
	-- Извержение: брызги лавы по дугам.
	type Blob = { frame: Frame, x: number, y: number, vx: number, vy: number, age: number }
	local blobs: { Blob } = {}
	for _ = 1, 16 do
		local frame = freeBox(canvas, gx, gy, cx, craterY, 0.8, 0.8, glow, 9)
		frame.Visible = false
		table.insert(blobs, { frame = frame, x = cx, y = craterY, vx = 0, vy = 0, age = 99 })
	end
	local anim = ctx.anim
	local nextEruption = Rng.range(anim, 3, 6)
	local pulse = 0
	table.insert(ctx.animations, function(t: number, dt: number)
		for _, puff in puffs do
			puff.age += dt
			if puff.age > puff.life then
				puff.age -= puff.life
			end
			local k = puff.age / puff.life
			local size = 2 + k * 6
			puff.frame.Position =
				UDim2.fromScale((cx - size / 2 + puff.drift * k * 8) / gx, (craterY - 1.5 - k * 14 - size * 0.3) / gy)
			puff.frame.Size = UDim2.fromScale(size / gx, size * 0.7 / gy)
			puff.frame.BackgroundTransparency = 0.45 + 0.55 * k
		end
		nextEruption -= dt
		if nextEruption <= 0 then
			nextEruption = Rng.range(anim, 6, 11)
			pulse = 1
			for _, blob in blobs do
				blob.x, blob.y = cx + Rng.range(anim, -2, 2), craterY
				blob.vx = Rng.range(anim, -6, 6)
				blob.vy = -Rng.range(anim, 10, 17)
				blob.age = 0
				blob.frame.BackgroundColor3 = if Rng.chance(anim, 0.4) then accent else glow
			end
		end
		pulse = math.max(0, pulse - dt * 0.8)
		crater.BackgroundColor3 = glow:Lerp(accent, pulse * (0.5 + 0.5 * math.sin(t * 30)))
		for _, blob in blobs do
			blob.age += dt
			local alive = blob.age < 2.2
			blob.frame.Visible = alive
			if alive then
				blob.vy += 16 * dt
				blob.x += blob.vx * dt
				blob.y += blob.vy * dt
				place(blob.frame, layer, blob.x, blob.y)
			end
		end
	end)
end

-- Дракон (премиальная карта): пролетает над ареной, машет крыльями и дышит огнём.
local DRAGON_SCALE = 0.55 -- клеток неба на пиксель рисунка дракона
local function buildDragon(layer: Layer, ctx: Ctx, facing: number): (Frame, Frame, Frame, Frame)
	local W, H = 40, 20 -- сетка рисунка дракона
	local sprite = holder(layer, -60, 0, W * DRAGON_SCALE, H * DRAGON_SCALE, 10)
	sprite.Name = "Dragon"
	local body = hex(ctx.theme.near):Lerp(hex("#3A0A14"), 0.5)
	local belly = body:Lerp(hex(ctx.theme.glow), 0.25)
	local wing = body:Lerp(hex(ctx.theme.far), 0.4)
	local eye = hex(ctx.theme.accent)
	local function px(parent: Instance, x: number, y: number, w: number, h: number, color: Color3)
		-- Рисуем смотрящим вправо; при facing = -1 отражаем по горизонтали.
		local fx = if facing > 0 then x else W - x - w
		box(parent, W, H, fx, y, w, h, color, 10)
	end
	-- Хвост: сужается к концу.
	px(sprite, 0, 12, 4, 1, body)
	px(sprite, 3, 11, 4, 2, body)
	px(sprite, 6, 10, 5, 2, body)
	px(sprite, 1, 11, 2, 1, eye) -- огонёк на кончике хвоста
	-- Тело.
	px(sprite, 10, 8, 16, 5, body)
	px(sprite, 12, 12, 12, 2, belly)
	-- Лапы.
	px(sprite, 13, 13, 2, 3, body)
	px(sprite, 21, 13, 2, 3, body)
	-- Шея и голова.
	px(sprite, 25, 6, 4, 5, body)
	px(sprite, 28, 4, 4, 4, body)
	px(sprite, 31, 5, 6, 3, body)
	px(sprite, 33, 8, 4, 1, belly) -- челюсть
	px(sprite, 29, 2, 1, 2, body) -- рога
	px(sprite, 31, 1, 1, 3, body)
	px(sprite, 32, 5, 1, 1, eye)
	-- Крылья: поднятые и опущенные (меняются при взмахе).
	local up = Instance.new("Frame")
	up.BackgroundTransparency = 1
	up.Size = UDim2.fromScale(1, 1)
	up.Parent = sprite
	px(up, 13, 6, 12, 2, wing)
	px(up, 14, 4, 10, 2, wing)
	px(up, 15, 2, 7, 2, wing)
	px(up, 17, 0, 4, 2, wing)
	local down = Instance.new("Frame")
	down.BackgroundTransparency = 1
	down.Size = UDim2.fromScale(1, 1)
	down.Visible = false
	down.Parent = sprite
	px(down, 13, 12, 12, 2, wing)
	px(down, 14, 14, 9, 2, wing)
	px(down, 15, 16, 6, 2, wing)
	px(down, 16, 18, 3, 2, wing)
	-- Пламя изо рта.
	local fire = Instance.new("Frame")
	fire.BackgroundTransparency = 1
	fire.Size = UDim2.fromScale(1, 1)
	fire.Visible = false
	fire.Parent = sprite
	return sprite, up, down, fire
end

local function drawDragon(layer: Layer, ctx: Ctx)
	if ctx.preview then
		-- На превью дракон просто парит в небе.
		local sprite = buildDragon(layer, ctx, 1)
		place(sprite, layer, layer.cols * 0.4, layer.rows * SKY_BASELINE - 28)
		return
	end
	local right = { buildDragon(layer, ctx, 1) }
	local left = { buildDragon(layer, ctx, -1) }
	local anim = ctx.anim
	local glow, accent = hex(ctx.theme.glow), hex(ctx.theme.accent)
	type Flame = { frame: Frame, x: number, y: number, vx: number, vy: number, age: number }
	local flames: { Flame } = {}
	for _ = 1, 18 do
		local frame = freeBox(layer.canvas, layer.cols, layer.rows, 0, 0, 2, 2, glow, 11)
		frame.Visible = false
		table.insert(flames, { frame = frame, x = 0, y = 0, vx = 0, vy = 0, age = 99 })
	end
	local nextFlight = Rng.range(anim, 2, 5)
	local flying = false
	local direction = 1
	local x, baseY = 0, 0
	local breathAt, breathing = 0, 0
	local emitCarry = 0
	table.insert(ctx.animations, function(t: number, dt: number)
		if not flying then
			nextFlight -= dt
			if nextFlight <= 0 then
				flying = true
				direction = if Rng.chance(anim, 0.5) then 1 else -1
				x = if direction > 0 then layer.cols * 0.15 - 25 else layer.cols * 0.85
				baseY = Rng.range(anim, layer.rows * SKY_BASELINE - 30, layer.rows * SKY_BASELINE - 20)
				breathAt = Rng.range(anim, layer.cols * 0.4, layer.cols * 0.6)
				breathing = 0
			end
		end
		local active = if direction > 0 then right else left
		local inactive = if direction > 0 then left else right
		inactive[1].Visible = false
		active[1].Visible = flying
		if flying then
			x += direction * 11 * dt
			local y = baseY + math.sin(t * 1.4) * 2.5
			place(active[1], layer, x, y)
			local wingsUp = math.sin(t * 7) > 0
			active[2].Visible = wingsUp
			active[3].Visible = not wingsUp
			-- Огненное дыхание посреди пролёта.
			local headX = x + (if direction > 0 then 38 else 2) * DRAGON_SCALE
			if breathing == 0 and math.abs(x + 20 * DRAGON_SCALE - breathAt) < 1.5 then
				breathing = 1.4
			end
			if breathing > 0 then
				breathing = math.max(0, breathing - dt)
				emitCarry += dt * 26
				while emitCarry >= 1 do
					emitCarry -= 1
					for _, flame in flames do
						if flame.age > 0.6 then
							flame.age = 0
							flame.x, flame.y = headX, y + 6.5 * DRAGON_SCALE
							flame.vx = direction * Rng.range(anim, 12, 20)
							flame.vy = Rng.range(anim, 1, 5)
							flame.frame.BackgroundColor3 = if Rng.chance(anim, 0.35)
								then accent
								elseif Rng.chance(anim, 0.2) then WHITE
								else glow
							break
						end
					end
				end
			end
			if (direction > 0 and x > layer.cols * 0.85) or (direction < 0 and x < layer.cols * 0.15 - 25) then
				flying = false
				nextFlight = Rng.range(anim, 10, 18)
			end
		end
		for _, flame in flames do
			flame.age += dt
			local alive = flame.age < 0.6
			flame.frame.Visible = alive
			if alive then
				flame.x += flame.vx * dt
				flame.y += flame.vy * dt
				local size = 0.8 + flame.age * 3
				flame.frame.Size = UDim2.fromScale(size / layer.cols, size / layer.rows)
				flame.frame.BackgroundTransparency = flame.age / 0.6
				place(flame.frame, layer, flame.x - size / 2, flame.y - size / 2)
			end
		end
	end)
end

-- Неоновые вывески на ближних небоскрёбах (премиальная карта «Неон-Сити»): мигают.
local NEON_WORDS = { "PIXEL", "FIGHT", "24/7", "ARCADE", "K.O.", "BOOM", "COMBO", "HERO" }
local NEON_VERTICAL = { "BAR", "ZAP", "POW", "HOT", "NEON", "WOW" }

local function drawNeonSigns(layer: Layer, ctx: Ctx)
	local rng = ctx.rng
	local theme = ctx.theme
	local colors = { hex(theme.glow), hex(theme.accent), hex("#FFE066"), hex("#7CFF6B") }
	local baseline = layer.rows * MID_BASELINE
	type Sign = { stroke: UIStroke, label: TextLabel, phase: number, off: number }
	local signs: { Sign } = {}
	local count = if ctx.preview then 4 else 8
	for index = 1, count do
		local vertical = index % 3 == 0
		local w = if vertical then 1.5 else Rng.range(rng, 5, 8)
		local h = if vertical then 6 else 2
		local x = layer.cols * (0.22 + 0.56 * (index - 0.5) / count) + Rng.range(rng, -4, 4)
		local y = baseline - Rng.range(rng, 1.5, 4) - h
		local color = colors[Rng.integer(rng, 1, #colors)]
		local frame = layerBox(layer, x, y, w, h, hex("#0B0718"), 12)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 1
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Arcade
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.TextColor3 = color
		label.ZIndex = 13
		local word = if vertical
			then NEON_VERTICAL[Rng.integer(rng, 1, #NEON_VERTICAL)]
			else NEON_WORDS[Rng.integer(rng, 1, #NEON_WORDS)]
		if vertical then
			local letters: { string } = {}
			for letter in string.gmatch(word, ".") do
				table.insert(letters, letter)
			end
			word = table.concat(letters, "\n")
		end
		label.Text = word
		label.Parent = frame
		table.insert(signs, { stroke = stroke, label = label, phase = Rng.range(rng, 0, 10), off = 0 })
	end
	if ctx.preview then
		return
	end
	local anim = ctx.anim
	table.insert(ctx.animations, function(t: number, dt: number)
		for _, sign in signs do
			if sign.off > 0 then
				sign.off -= dt
			elseif Rng.chance(anim, dt * 0.25) then
				sign.off = Rng.range(anim, 0.05, 0.4)
			end
			-- Мерцание: иногда гаснет, иногда быстро мигает.
			local flicker = sign.off > 0 and math.sin(t * 60 + sign.phase) > -0.3
			local transparency = if flicker then 0.85 else 0.05 * (0.5 + 0.5 * math.sin(t * 4 + sign.phase))
			sign.label.TextTransparency = transparency
			sign.stroke.Transparency = transparency
		end
	end)
end

-- Летающие машины (премиальная карта «Неон-Сити»).
local function drawFlyingCars(layer: Layer, ctx: Ctx)
	if ctx.preview then
		return
	end
	local anim = ctx.anim
	type Car = { frame: Frame, x: number, y: number, speed: number, direction: number }
	local cars: { Car } = {}
	local base = layer.rows * SKY_BASELINE
	local lanes = { base - 22, base - 17, base - 12 }
	for index = 1, 6 do
		local lane = (index - 1) % #lanes + 1
		local direction = if lane % 2 == 1 then 1 else -1
		local W, H = 9, 2 -- сетка рисунка машины
		local car = holder(layer, 0, 0, W * 0.5, H * 0.5, 8)
		local function px(x: number, y: number, w: number, h: number, color: Color3, transparency: number?)
			local fx = if direction > 0 then x else W - x - w
			box(car, W, H, fx, y, w, h, color, 8, transparency)
		end
		px(3, 0, 5, 1, hex("#2A2A40"))
		px(3, 1, 6, 1, hex("#3D3D5C"))
		px(5, 0, 2, 1, hex(ctx.theme.accent))
		px(8, 1, 1, 1, WHITE) -- фара
		px(2, 1, 1, 1, hex("#FF3355")) -- стоп-сигнал
		px(0, 1, 2, 1, hex(ctx.theme.glow), 0.5) -- световой след
		table.insert(cars, {
			frame = car,
			x = Rng.range(anim, layer.cols * 0.2, layer.cols * 0.8),
			y = lanes[lane],
			speed = Rng.range(anim, 8, 16),
			direction = direction,
		})
	end
	table.insert(ctx.animations, function(_t: number, dt: number)
		for _, car in cars do
			-- Машины ездят по видимой части неба (остальная не видна камере).
			car.x += car.direction * car.speed * dt
			if car.x > layer.cols * 0.82 then
				car.x = layer.cols * 0.18 - 10
			elseif car.x < layer.cols * 0.18 - 10 then
				car.x = layer.cols * 0.82
			end
			place(car.frame, layer, car.x, car.y)
		end
	end)
end

-- Планета с кольцами и спутником (премиальная «Космо-арена»).
local function drawPlanets(layer: Layer, ctx: Ctx)
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local cx, cy, r = layer.cols * 0.44, layer.rows * SKY_BASELINE - 24, 7
	local bands = { hex("#F2B880"), hex("#E08E6D"), hex("#C06C84"), hex("#F5D0A9") }
	-- Планета: строки диска разного цвета — полосы газового гиганта.
	local rows = math.floor(r * 2 / PIXEL + 0.5)
	for row = 0, rows - 1 do
		local t = (row + 0.5) / rows * 2 - 1
		local width = math.max(PIXEL, math.floor(r * math.sqrt(math.max(0, 1 - t * t)) * 2 / PIXEL + 0.5) * PIXEL)
		local color = bands[(math.floor(row / 3) % #bands) + 1]
		-- Тень справа снизу: край темнее.
		box(canvas, gx, gy, cx - width / 2, cy - r + row * PIXEL, width, PIXEL, color, 5)
		local shade = math.max(PIXEL, width * 0.2)
		box(canvas, gx, gy, cx + width / 2 - shade, cy - r + row * PIXEL, shade, PIXEL, BLACK, 6, 0.6)
	end
	-- Кольцо: точки эллипса, передняя половина поверх планеты.
	local ringColor = hex("#E8D5B5")
	local points = if ctx.preview then 36 else 64
	for index = 0, points - 1 do
		local angle = index / points * math.pi * 2
		local px = cx + math.cos(angle) * (r + 6)
		local py = cy + math.sin(angle) * 2.2
		local front = math.sin(angle) > 0
		box(canvas, gx, gy, px - 0.5, py, 1, PIXEL, ringColor, if front then 7 else 4, 0.15)
	end
	-- Дальняя маленькая планета.
	local small = hex(ctx.theme.glow)
	local smallX, smallY = layer.cols * 0.6, layer.rows * SKY_BASELINE - 32
	disc(canvas, gx, gy, smallX, smallY, 2.5, 2.5, small, 4)
	box(canvas, gx, gy, smallX - 1.5, smallY - 1.5, 1, 1, WHITE, 5, 0.3)
	-- Спутник на орбите вокруг большой планеты.
	local moon = holder(layer, cx, cy, 2.5, 2.5, 7)
	disc(moon, 5, 5, 2.5, 2.5, 2.5, 2.5, hex("#B8C0FF"), 7)
	local function orbit(t: number)
		local angle = t * 0.35
		local mx = cx + math.cos(angle) * (r + 11) - 1.25
		local my = cy + math.sin(angle) * 4 - 1.25
		place(moon, layer, mx, my)
		moon.ZIndex = if math.sin(angle) > 0 then 8 else 3
		for _, child in moon:GetChildren() do
			(child :: Frame).ZIndex = moon.ZIndex
		end
	end
	orbit(1)
	if not ctx.preview then
		table.insert(ctx.animations, orbit)
	end
end

-- Метеоры: яркая голова и тающий хвост.
local function drawMeteors(layer: Layer, ctx: Ctx)
	if ctx.preview then
		return
	end
	local anim = ctx.anim
	local glow, accent = hex(ctx.theme.glow), hex(ctx.theme.accent)
	type Meteor = { parts: { Frame }, x: number, y: number, vx: number, vy: number, age: number }
	local meteors: { Meteor } = {}
	for _ = 1, 4 do
		local parts: { Frame } = {}
		for index = 0, 6 do
			local size = if index == 0 then 1 else math.max(0.3, 0.9 - index * 0.1)
			local frame = freeBox(
				layer.canvas,
				layer.cols,
				layer.rows,
				0,
				0,
				size,
				size,
				if index == 0 then WHITE elseif index < 3 then accent else glow,
				6,
				index * 0.12
			)
			frame.Visible = false
			table.insert(parts, frame)
		end
		table.insert(meteors, { parts = parts, x = 0, y = 0, vx = 0, vy = 0, age = 99 })
	end
	local nextMeteor = Rng.range(anim, 1, 3)
	table.insert(ctx.animations, function(_t: number, dt: number)
		nextMeteor -= dt
		if nextMeteor <= 0 then
			nextMeteor = Rng.range(anim, 1.2, 3.5)
			for _, meteor in meteors do
				if meteor.age > 1.4 then
					meteor.age = 0
					meteor.x = Rng.range(anim, layer.cols * 0.45, layer.cols * 0.8)
					meteor.y = Rng.range(anim, layer.rows * SKY_BASELINE - 66, layer.rows * SKY_BASELINE - 46)
					meteor.vx = -Rng.range(anim, 28, 40)
					meteor.vy = Rng.range(anim, 12, 18)
					break
				end
			end
		end
		for _, meteor in meteors do
			meteor.age += dt
			local alive = meteor.age < 1.4
			if alive then
				meteor.x += meteor.vx * dt
				meteor.y += meteor.vy * dt
			end
			for index, part in meteor.parts do
				part.Visible = alive
				if alive then
					local back = (index - 1) * 0.9
					local length = math.sqrt(meteor.vx * meteor.vx + meteor.vy * meteor.vy)
					place(part, layer, meteor.x - meteor.vx / length * back, meteor.y - meteor.vy / length * back)
				end
			end
		end
	end)
end

-- Звездолёт иногда пролетает по небу.
local function drawShip(layer: Layer, ctx: Ctx)
	local W, H = 12, 5 -- сетка рисунка корабля
	local ship = holder(layer, -20, 0, W * 0.5, H * 0.5, 9)
	ship.Name = "Ship"
	local hull, dark = hex("#C9D1E8"), hex("#6B7394")
	box(ship, W, H, 3, 2, 8, 2, hull, 9)
	box(ship, W, H, 5, 1, 4, 1, hull, 9)
	box(ship, W, H, 6, 1, 2, 1, hex(ctx.theme.glow), 10) -- кабина
	box(ship, W, H, 4, 4, 5, 1, dark, 9) -- крыло
	box(ship, W, H, 4, 0, 3, 1, dark, 9)
	local flame = box(ship, W, H, 1, 2, 2, 2, hex(ctx.theme.accent), 9)
	if ctx.preview then
		place(ship, layer, layer.cols * 0.58, layer.rows * SKY_BASELINE - 30)
		return
	end
	local anim = ctx.anim
	local nextFlight = Rng.range(anim, 4, 8)
	local flying = false
	local x, y = 0, 0
	-- Корабль нарисован носом вправо: летит слева направо.
	table.insert(ctx.animations, function(t: number, dt: number)
		if not flying then
			nextFlight -= dt
			if nextFlight <= 0 then
				flying = true
				x = layer.cols * 0.15 - W
				y = Rng.range(anim, layer.rows * SKY_BASELINE - 38, layer.rows * SKY_BASELINE - 26)
			end
		else
			x += 12 * dt
			if x > layer.cols * 0.85 then
				flying = false
				nextFlight = Rng.range(anim, 14, 24)
			end
		end
		ship.Visible = flying
		place(ship, layer, x, y + math.sin(t * 2) * 0.6)
		flame.BackgroundTransparency = if math.sin(t * 40) > 0 then 0 else 0.4
	end)
end

-- Маяк на острове (гавань): луч света «ходит» из стороны в сторону.
local function drawLighthouse(layer: Layer, ctx: Ctx)
	local canvas, gx, gy = layer.canvas, layer.cols, layer.rows
	local baseline = layer.rows * SKY_BASELINE
	local x = layer.cols * 0.4
	local far = hex(ctx.theme.far)
	-- Остров.
	stepped(canvas, gx, gy, x - 7, baseline - 1, 14, 3, 3, far, 7)
	-- Башня: белые и красные полосы, сужается кверху.
	local towerH = 11
	for index = 0, 10 do
		local y = baseline - 3 - (index + 1) * towerH / 11
		local width = 2.6 - index * 0.1
		box(
			canvas,
			gx,
			gy,
			x - width / 2,
			y,
			width,
			towerH / 11 + 0.2,
			if index % 2 == 0 then hex("#F4F1DE") else hex("#C8553D"),
			8
		)
	end
	local lampY = baseline - 3 - towerH - 1.5
	box(canvas, gx, gy, x - 1.5, lampY - 0.5, 3, 0.5, hex(ctx.theme.near), 8) -- крыша
	local lamp = box(canvas, gx, gy, x - 1, lampY, 2, 1.5, hex(ctx.theme.accent), 9)
	box(canvas, gx, gy, x - 1.5, lampY + 1.5, 3, 0.5, hex(ctx.theme.near), 8)
	if ctx.preview then
		return
	end
	local beam = Instance.new("Frame")
	beam.Name = "Beam"
	beam.BorderSizePixel = 0
	beam.BackgroundColor3 = hex(ctx.theme.accent)
	beam.BackgroundTransparency = 0.35
	beam.ZIndex = 9
	beam.Parent = canvas
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(0, 1)
	gradient.Parent = beam
	local length = 34
	table.insert(ctx.animations, function(t: number)
		local phase = math.cos(t * 0.9)
		local reach = length * math.abs(phase)
		local side = if phase >= 0 then 1 else -1
		beam.Size = UDim2.fromScale(reach / gx, 1.2 / gy)
		beam.Position = UDim2.fromScale((x + (if side > 0 then 0 else -reach)) / gx, (lampY + 0.2) / gy)
		gradient.Rotation = if side > 0 then 0 else 180
		-- Луч смотрит на нас — вспыхивает сам фонарь.
		lamp.BackgroundColor3 = hex(ctx.theme.accent):Lerp(WHITE, 1 - math.abs(phase))
	end)
end

-- Фонарики на тории (додзё): покачиваются.
local function drawLanterns(layer: Layer, ctx: Ctx)
	local baseline = layer.rows * MID_BASELINE
	local center = layer.cols / 2
	local beamY = baseline - TORII_HEIGHT * MID_SCALE * 0.78 + 0.5 -- под перекладиной ворот (см. Pillars)
	local lanterns: { { frame: Frame, phase: number } } = {}
	for index = -2, 2 do
		local x = center + index * 2.4
		local lantern = holder(layer, x - 0.6, beamY, 1.2, 2, 9)
		box(lantern, 3, 5, 1, 0, 1, 1, hex(ctx.theme.near), 9) -- шнурок
		box(lantern, 3, 5, 0, 1, 3, 3, hex("#E63946"), 9)
		box(lantern, 3, 5, 1, 2, 1, 1, hex(ctx.theme.accent), 10) -- огонёк
		box(lantern, 3, 5, 1, 4, 1, 1, hex(ctx.theme.near), 9)
		table.insert(lanterns, { frame = lantern, phase = index })
	end
	if ctx.preview then
		return
	end
	table.insert(ctx.animations, function(t: number)
		for _, lantern in lanterns do
			lantern.frame.Rotation = math.sin(t * 1.5 + lantern.phase) * 8
		end
	end)
end

----------------------------------------------------------------------------------------------
-- Погода (частицы на отдельном слое перед средним планом, позади бойцов)
----------------------------------------------------------------------------------------------

type Particle = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	phase: number,
	size: number,
}

local function drawWeather(layer: Layer, ctx: Ctx)
	local weather = ctx.theme.weather
	if weather == "None" or ctx.preview then
		return
	end
	local anim = ctx.anim
	local theme = ctx.theme
	local count = ({
		Rain = 50,
		Snow = 40,
		Petals = 26,
		Embers = 30,
		Fireflies = 22,
		Ash = 30,
		Dust = 30,
	} :: { [string]: number })[weather] or 20
	local particles: { Particle } = {}
	for _ = 1, count do
		local size = Rng.range(anim, 0.25, 0.5)
		local w, h = size, size
		local color = WHITE
		local transparency = 0.1
		local vx, vy = 0, 0
		if weather == "Rain" then
			w, h = 0.12, 1.4
			color = hex("#9FB8FF")
			transparency = 0.45
			vx, vy = -6, Rng.range(anim, 60, 80)
		elseif weather == "Snow" then
			vy = Rng.range(anim, 4, 9)
		elseif weather == "Petals" then
			w, h = size * 1.2, size * 0.7
			color = hex(theme.glow)
			vx, vy = Rng.range(anim, -4, -1), Rng.range(anim, 3, 7)
		elseif weather == "Embers" then
			w, h = size * 0.6, size * 0.6
			color = if Rng.chance(anim, 0.5) then hex(theme.glow) else hex(theme.accent)
			vy = -Rng.range(anim, 4, 10)
		elseif weather == "Fireflies" then
			w, h = 0.3, 0.3
			color = hex(theme.glow)
		elseif weather == "Ash" then
			w, h = size * 0.8, size * 0.8
			color = if Rng.chance(anim, 0.2) then hex(theme.glow) else hex("#7A6E6A")
			transparency = 0.2
			vx, vy = Rng.range(anim, -2, 1), Rng.range(anim, 2, 6)
		elseif weather == "Dust" then
			w, h = size * 0.45, size * 0.45
			color = if Rng.chance(anim, 0.3) then hex(theme.glow) else WHITE
			transparency = 0.55
			vx = Rng.range(anim, 1, 3)
		end
		local x, y = Rng.range(anim, 0, layer.cols), Rng.range(anim, 0, layer.rows)
		local frame = freeBox(layer.canvas, layer.cols, layer.rows, x, y, w, h, color, 2, transparency)
		table.insert(particles, {
			frame = frame,
			x = x,
			y = y,
			vx = vx,
			vy = vy,
			phase = Rng.range(anim, 0, 6.3),
			size = size,
		})
	end
	local cols, rows = layer.cols, layer.rows
	table.insert(ctx.animations, function(t: number, dt: number)
		for _, p in particles do
			local sway = 0
			if weather == "Snow" or weather == "Petals" or weather == "Ash" then
				sway = math.sin(t * 1.3 + p.phase) * 2
			elseif weather == "Embers" then
				sway = math.sin(t * 2.1 + p.phase) * 1.5
				p.frame.BackgroundTransparency = 0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * 7 + p.phase))
			elseif weather == "Fireflies" then
				p.vx = math.cos(t * 0.7 + p.phase) * 3
				p.vy = math.sin(t * 0.9 + p.phase * 1.3) * 2
				p.frame.BackgroundTransparency = 0.05 + 0.85 * (0.5 + 0.5 * math.sin(t * 2.5 + p.phase))
			elseif weather == "Dust" then
				p.frame.BackgroundTransparency = 0.4 + 0.5 * (0.5 + 0.5 * math.sin(t * 2 + p.phase))
			end
			p.x += (p.vx + sway) * dt
			p.y += p.vy * dt
			if p.y > rows + 3 then
				p.y = -3
				p.x = Rng.range(anim, 0, cols)
			elseif p.y < -3 then
				p.y = rows + 3
				p.x = Rng.range(anim, 0, cols)
			end
			if p.x < -3 then
				p.x += cols + 6
			elseif p.x > cols + 3 then
				p.x -= cols + 6
			end
			if weather == "Petals" then
				p.frame.Rotation = math.sin(t * 2 + p.phase) * 60
			end
			p.frame.Position = UDim2.fromScale(p.x / cols, p.y / rows)
		end
	end)
end

----------------------------------------------------------------------------------------------
-- Сборка
----------------------------------------------------------------------------------------------

local FEATURE_ORDER: { Arenas.Feature } = {
	"Nebula",
	"Stars",
	"Aurora",
	"Sun",
	"Moon",
	"Planets",
	"Clouds",
	"Volcano",
	"Birds",
	"FlyingCars",
	"Meteors",
	"Ship",
	"Dragon",
	"Lightning",
	"Lighthouse",
}

local SKY_FEATURES: { [string]: (Layer, Ctx) -> () } = {
	Nebula = drawNebula,
	Stars = drawStars,
	Aurora = drawAurora,
	Sun = drawSun,
	Moon = drawMoon,
	Planets = drawPlanets,
	Clouds = drawClouds,
	Volcano = drawVolcano,
	Birds = drawBirds,
	FlyingCars = drawFlyingCars,
	Meteors = drawMeteors,
	Ship = drawShip,
	Dragon = drawDragon,
	Lightning = drawLightning,
	Lighthouse = drawLighthouse,
}

local function hasFeature(theme: Theme, feature: string): boolean
	return table.find(theme.features, feature :: any) ~= nil
end

local function newCtx(theme: Theme, preview: boolean): Ctx
	local seed = Rng.seedFromString(theme.id)
	return {
		theme = theme,
		rng = Rng.new(seed),
		anim = Rng.new(seed + 7),
		preview = preview,
		animations = {},
	}
end

local function drawAll(layers: Layers, ctx: Ctx)
	local theme = ctx.theme
	local sky, mid = layers.sky, layers.mid
	drawGradient(sky, theme)
	for _, feature in FEATURE_ORDER do
		local draw = SKY_FEATURES[feature]
		if draw and hasFeature(theme, feature) then
			draw(sky, ctx)
		end
	end
	drawSilhouettes(sky, ctx, theme.silhouette, hex(theme.far), sky.rows * SKY_BASELINE, FAR_SCALE, 7, false)
	drawSilhouettes(mid, ctx, theme.nearSilhouette, hex(theme.near), mid.rows * MID_BASELINE, MID_SCALE, 7, true)
	if hasFeature(theme, "Lanterns") then
		drawLanterns(mid, ctx)
	end
	if hasFeature(theme, "NeonSigns") then
		drawNeonSigns(mid, ctx)
	end
	local weather = layers.weather
	if weather then
		drawWeather(weather, ctx)
	end
end

-- Нарисовать фон арены на слоях; update(dt) двигает анимации.
function ArenaArt.build(layers: Layers, theme: Theme): Art
	local ctx = newCtx(theme, false)
	drawAll(layers, ctx)
	local t = 0
	return {
		update = function(dt: number)
			t += dt
			for _, animation in ctx.animations do
				animation(t, dt)
			end
		end,
	}
end

--[[
	Статичная картинка карты (для карточек выбора и магазина): видимая в бою часть неба,
	силуэты, пол. parent — рамка карточки (картинка заполняет её целиком и обрезается по краям).
]]
function ArenaArt.preview(parent: Instance, theme: Theme): Frame
	local root = Instance.new("Frame")
	root.Name = "ArenaPreview"
	root.BackgroundColor3 = hex(theme.skyTop)
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent
	-- Небо: показываем центральную часть (в бою камера видит примерно её).
	local skyFrame = Instance.new("Frame")
	skyFrame.Name = "Sky"
	skyFrame.BackgroundTransparency = 1
	skyFrame.Position = UDim2.fromScale(-0.5, -0.32)
	skyFrame.Size = UDim2.fromScale(2, 1.85)
	skyFrame.Parent = root
	local midFrame = Instance.new("Frame")
	midFrame.Name = "Mid"
	midFrame.BackgroundTransparency = 1
	midFrame.Position = UDim2.fromScale(-0.4, 0.2)
	midFrame.Size = UDim2.fromScale(1.8, 0.95)
	midFrame.Parent = root
	local ctx = newCtx(theme, true)
	drawAll({
		sky = { canvas = skyFrame, cols = 260, rows = 120 },
		mid = { canvas = midFrame, cols = 200, rows = 40 },
	}, ctx)
	-- Пол арены с полосами.
	local floor = Instance.new("Frame")
	floor.Name = "Floor"
	floor.BackgroundColor3 = hex(theme.floor)
	floor.BorderSizePixel = 0
	floor.Position = UDim2.fromScale(0, 0.86)
	floor.Size = UDim2.fromScale(1, 0.14)
	floor.ZIndex = 20
	floor.Parent = root
	for index = 0, 9 do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = hex(theme.floorLine)
		line.BorderSizePixel = 0
		line.Position = UDim2.fromScale(index / 10 + 0.03, 0)
		line.Size = UDim2.new(0, 2, 1, 0)
		line.ZIndex = 21
		line.Parent = floor
	end
	return root
end

return ArenaArt
