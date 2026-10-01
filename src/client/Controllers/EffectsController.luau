--!strict
--[[
	EffectsController — визуальные эффекты боя.

	Пиксельные частицы: квадратики в BillboardGui, разлетающиеся с гравитацией и затуханием.
	Своя простая система вместо ParticleEmitter: полный контроль над «пиксельным» стилем
	и никаких внешних текстур.

	В мире (BillboardGui в точке арены): искры, кольца удара, «звёзды» из лучей, росчерки,
	цифры урона, ударные волны по земле, сбор энергии в руках перед магией.
	На экране (ScreenGui поверх боя): вспышки, затемнение краёв, линии скорости и вставка
	супера с портретом бойца и названием приёма.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local Types = require(ReplicatedStorage.Shared.Types)
local Rig = require(script.Parent.Parent.Sprites.Rig)
local PixelIcons = require(script.Parent.Parent.UI.PixelIcons)

export type BurstOptions = {
	count: number,
	color: Color3,
	speed: number, -- студ/с
	size: number, -- студов
	life: number, -- секунды
	gravity: number?, -- студ/с² вниз
	spread: number?, -- угол разлёта в градусах вокруг направления
	direction: number?, -- угол направления в градусах (0 — вправо, 90 — вверх)
	secondary: Color3?,
	glyph: string?, -- частицы-символы (★, ♥, ϟ) вместо квадратиков
	palette: { Color3 }?, -- разноцветные частицы (конфетти)
}

type Particle = {
	frame: GuiObject,
	text: boolean,
	x: number,
	y: number,
	vx: number,
	vy: number,
	size: number,
}

type Burst = {
	anchor: Part,
	gui: BillboardGui,
	particles: { Particle },
	age: number,
	life: number,
	gravity: number,
	extent: number,
}

local EffectsController = {
	Name = "EffectsController",
}

local folder: Folder? = nil
local bursts: { Burst } = {}
local rng = Rng.new(7)

-- Анимированный эффект: update(t 0..1, dt) каждый кадр, затем destroy.
type Effect = {
	age: number,
	life: number,
	update: (t: number, dt: number) -> (),
	destroy: () -> (),
}
local effects: { Effect } = {}
local WHITE = Color3.new(1, 1, 1)

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = "Effects"
	created.Parent = Workspace
	folder = created
	return created
end

-- Разлёт пиксельных частиц из точки (мировые координаты арены).
function EffectsController.burst(position: Vector3, options: BurstOptions)
	local extent = options.speed * options.life + options.size * 2 + 2
	local anchor = Instance.new("Part")
	anchor.Name = "Burst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 0, 1))
	anchor.Parent = getFolder()

	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(extent * 2, extent * 2)
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Parent = anchor

	local particles: { Particle } = {}
	local spread = options.spread or 360
	local direction = options.direction or 90
	for index = 1, options.count do
		local angle = math.rad(direction + Rng.range(rng, -spread / 2, spread / 2))
		local speed = options.speed * Rng.range(rng, 0.4, 1)
		local size = options.size * Rng.range(rng, 0.6, 1.2)
		local palette = options.palette
		local color = if palette
			then palette[(index - 1) % #palette + 1]
			elseif options.secondary and index % 2 == 0 then options.secondary
			else options.color
		local frame: GuiObject
		local glyph = options.glyph
		if glyph then
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Text = glyph
			label.TextColor3 = color
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			frame = label
		else
			local square = Instance.new("Frame")
			square.BorderSizePixel = 0
			square.BackgroundColor3 = color
			frame = square
		end
		local scale = if glyph then 1.6 else 1
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromScale(size * scale / (extent * 2), size * scale / (extent * 2))
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Parent = gui
		table.insert(particles, {
			frame = frame,
			text = glyph ~= nil,
			x = 0,
			y = 0,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed,
			size = size,
		})
	end

	table.insert(bursts, {
		anchor = anchor,
		gui = gui,
		particles = particles,
		age = 0,
		life = options.life,
		gravity = options.gravity or 0,
		extent = extent,
	})
end

-- Пыль из-под ног (прыжок, приземление, рывок).
function EffectsController.dust(x: number, y: number, direction: number?)
	EffectsController.burst(Vector3.new(x, y + 0.2, 0), {
		count = 8,
		color = Color3.fromRGB(210, 200, 180),
		secondary = Color3.fromRGB(160, 150, 135),
		speed = 5,
		size = 0.35,
		life = 0.35,
		gravity = 6,
		spread = if direction then 60 else 150,
		direction = if direction then (if direction > 0 then 20 else 160) else 90,
	})
end

-- Искры удара: размер и количество растут с уроном.
function EffectsController.hitSpark(
	x: number,
	y: number,
	strength: number,
	primary: Color3,
	secondary: Color3,
	direction: number
)
	local power = math.clamp(strength, 0.2, 2)
	EffectsController.burst(Vector3.new(x, y, 0), {
		count = math.floor(8 + 10 * power),
		color = primary,
		secondary = secondary,
		speed = 10 + 10 * power,
		size = 0.35 + 0.25 * power,
		life = 0.22 + 0.12 * power,
		gravity = 8,
		spread = 140,
		direction = if direction >= 0 then 0 else 180,
	})
	-- Короткая «звезда» удара в центре.
	EffectsController.burst(Vector3.new(x, y, 0), {
		count = 4,
		color = Color3.new(1, 1, 1),
		speed = 2,
		size = 0.9 + 0.5 * power,
		life = 0.08 + 0.04 * power,
		spread = 360,
	})
end

----------------------------------------------------------------------------------------------
-- Эффекты в мире
----------------------------------------------------------------------------------------------

-- BillboardGui размером size × size студов в точке арены (чуть ближе к камере, чем бойцы).
local function billboard(position: Vector3, size: number): (Part, BillboardGui)
	local anchor = Instance.new("Part")
	anchor.Name = "Effect"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 0, 1.2))
	anchor.Parent = getFolder()
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(size, size)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = anchor
	return anchor, gui
end

local function addEffect(life: number, update: (t: number, dt: number) -> (), destroy: () -> ())
	table.insert(effects, { age = 0, life = math.max(life, 0.01), update = update, destroy = destroy })
	update(0, 0)
end

local function centered(parent: Instance, color: Color3, z: number, round: boolean): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.ZIndex = z
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

-- Расходящееся кольцо (удар, блок, приземление): radius — в студах.
function EffectsController.ring(position: Vector3, color: Color3, radius: number, life: number, thickness: number?)
	local size = radius * 2 + 1
	local anchor, gui = billboard(position, size)
	local ring = centered(gui, color, 2, true)
	ring.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 4
	stroke.Parent = ring
	addEffect(life, function(t: number)
		local eased = 1 - (1 - t) ^ 3
		local fraction = (0.15 + 0.85 * eased) * radius * 2 / size
		ring.Size = UDim2.fromScale(fraction, fraction)
		stroke.Transparency = t
	end, function()
		anchor:Destroy()
	end)
end

-- «Звезда» удара из лучей (стиль комикса).
function EffectsController.starBurst(position: Vector3, color: Color3, size: number, life: number, rays: number?)
	local anchor, gui = billboard(position, size * 2)
	local count = rays or 8
	local lines: { Frame } = {}
	local offset = Rng.range(rng, 0, 45)
	for index = 1, count do
		local line = centered(gui, if index % 2 == 0 then WHITE else color, 3, false)
		line.AnchorPoint = Vector2.new(0.5, 1)
		line.Rotation = offset + (index - 1) * 360 / count
		table.insert(lines, line)
	end
	local core = centered(gui, WHITE, 4, true)
	addEffect(life, function(t: number)
		for index, line in lines do
			local length = (0.25 + 0.25 * (index % 2)) * (1 - t * 0.3)
			line.Size = UDim2.fromScale(0.05 * (1 - t), length)
			line.BackgroundTransparency = t
		end
		local coreSize = 0.3 * (1 - t)
		core.Size = UDim2.fromScale(coreSize, coreSize)
		core.BackgroundTransparency = t * 0.8
	end, function()
		anchor:Destroy()
	end)
end

-- Росчерк (режущий удар): тонкая вспышка под углом.
function EffectsController.slash(position: Vector3, color: Color3, length: number, angle: number, life: number)
	local anchor, gui = billboard(position, length * 1.4)
	local blade = centered(gui, WHITE, 3, true)
	blade.Rotation = angle
	local glow = centered(gui, color, 2, true)
	glow.Rotation = angle
	addEffect(life, function(t: number)
		local grow = math.min(1, t * 4)
		blade.Size = UDim2.fromScale(0.7 * grow, 0.04 * (1 - t))
		glow.Size = UDim2.fromScale(0.72 * grow, 0.1 * (1 - t))
		glow.BackgroundTransparency = 0.3 + t * 0.7
	end, function()
		anchor:Destroy()
	end)
end

-- Ударная волна по земле (сбили с ног, приземление после броска).
function EffectsController.shockwave(x: number, y: number, color: Color3, width: number)
	local anchor, gui = billboard(Vector3.new(x, y + 0.2, 0), width)
	local wave = centered(gui, color, 2, true)
	wave.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.Parent = wave
	addEffect(0.45, function(t: number)
		local eased = 1 - (1 - t) ^ 2
		wave.Size = UDim2.fromScale(0.2 + 0.8 * eased, (0.2 + 0.8 * eased) * 0.18)
		stroke.Transparency = t
	end, function()
		anchor:Destroy()
	end)
end

-- Цифра урона: всплывает над противником (крупнее и ярче на контрударе и супере).
function EffectsController.damageNumber(position: Vector3, value: number, color: Color3, big: boolean?)
	local scale = if big then 1.6 else 1
	local anchor, gui = billboard(position, 3 * scale)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 0.45)
	label.Text = tostring(math.floor(value + 0.5))
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.ZIndex = 5
	label.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Parent = label
	local drift = Rng.range(rng, -0.12, 0.12)
	addEffect(0.8, function(t: number)
		pop.Scale = if t < 0.15 then 0.6 + t / 0.15 * 0.7 else 1.3 - math.min(0.3, (t - 0.15) * 2)
		label.Position = UDim2.fromScale(0.5 + drift * t, 0.5 - 0.35 * t)
		label.TextTransparency = math.max(0, (t - 0.6) / 0.4)
		label.TextStrokeTransparency = label.TextTransparency
	end, function()
		anchor:Destroy()
	end)
end

-- Сбор энергии: искры слетаются к точке (начало магии и суперов).
function EffectsController.converge(position: Vector3, color: Color3, radius: number, count: number, life: number)
	local size = radius * 2 + 1
	local anchor, gui = billboard(position, size)
	type Spark = { frame: Frame, angle: number, delay: number }
	local sparks: { Spark } = {}
	for index = 1, count do
		local spark = centered(gui, if index % 3 == 0 then WHITE else color, 3, false)
		table.insert(sparks, {
			frame = spark,
			angle = Rng.range(rng, 0, math.pi * 2),
			delay = Rng.range(rng, 0, 0.35),
		})
	end
	local core = centered(gui, color, 4, true)
	addEffect(life, function(t: number)
		for _, spark in sparks do
			local local_t = math.clamp((t - spark.delay) / (1 - spark.delay), 0, 1)
			local distance = (1 - local_t) * radius / size
			spark.frame.Position =
				UDim2.fromScale(0.5 + math.cos(spark.angle) * distance, 0.5 + math.sin(spark.angle) * distance)
			local sparkSize = 0.18 / size * (0.6 + local_t)
			spark.frame.Size = UDim2.fromScale(sparkSize, sparkSize)
			spark.frame.BackgroundTransparency = if local_t <= 0 then 1 else 0.1 + 0.6 * local_t
		end
		local coreSize = (0.2 + 0.5 * t) / size
		core.Size = UDim2.fromScale(coreSize, coreSize)
		core.BackgroundTransparency = 0.3 + 0.5 * math.abs(math.sin(t * 20))
	end, function()
		anchor:Destroy()
	end)
end

-- Вспышка на весь экран (удар супера, нокаут).
local flashFrame: Frame? = nil
local flashTime = 0
local flashDuration = 0
local flashStrength = 0

local function getFlashFrame(): Frame?
	if flashFrame and flashFrame.Parent then
		return flashFrame
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelFightFX"
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local frame = Instance.new("Frame")
	frame.Name = "Flash"
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	gui.Parent = playerGui
	flashFrame = frame
	return frame
end

-- Эмоция: пузырь с пиксельной иконкой над бойцом — подпрыгивает, висит и тает (2 с).
function EffectsController.emote(position: Vector3, iconId: string)
	local anchor, gui = billboard(position, 3)
	local bubble = centered(gui, Color3.new(1, 1, 1), 1, true)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 16, 34)
	stroke.Thickness = 3
	stroke.Parent = bubble
	local art = Instance.new("Frame")
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(0.8, 0.8)
	art.ZIndex = 2
	art.Parent = bubble
	local def = PixelIcons.icons[iconId]
	if def then
		local grid = PixelIcons.Size
		local cell = 1 / grid
		for row = 1, grid do
			local rowText = def.rows[row]
			for col = 1, grid do
				local color = def.palette[rowText:sub(col, col)]
				if color then
					local pixel = Instance.new("Frame")
					pixel.BorderSizePixel = 0
					pixel.BackgroundColor3 = color
					pixel.Position = UDim2.fromScale((col - 1) * cell, (row - 1) * cell)
					pixel.Size = UDim2.fromScale(cell, cell)
					pixel.ZIndex = 2
					pixel.Parent = art
				end
			end
		end
	end
	addEffect(2, function(t: number)
		-- Выскакивает с перелётом, в конце тает и чуть поднимается.
		local pop = if t < 0.12 then t / 0.12 * 1.15 elseif t < 0.2 then 1.15 - (t - 0.12) / 0.08 * 0.15 else 1
		bubble.Size = UDim2.fromScale(0.62 * pop, 0.62 * pop)
		local fade = math.clamp((t - 0.8) / 0.2, 0, 1)
		bubble.BackgroundTransparency = fade
		stroke.Transparency = fade
		art.BackgroundTransparency = 1
		for _, child in art:GetChildren() do
			if child:IsA("Frame") then
				child.BackgroundTransparency = fade
			end
		end
		bubble.Position = UDim2.fromScale(0.5, 0.5 - t * 0.12)
	end, function()
		anchor:Destroy()
	end)
end

--[[
	Финишер (Config/Cosmetics, KoEffect) в точке нокаута: звездопад, конфетти-взрыв,
	фейерверк (три залпа) или удар молнии.
]]
function EffectsController.finisher(
	itemId: string,
	x: number,
	y: number,
	primary: Color3,
	secondary: Color3,
	glyph: string?
)
	if itemId == "ko_starfall" then
		for index = 1, 3 do
			task.delay((index - 1) * 0.18, function()
				EffectsController.burst(Vector3.new(x + (index - 2) * 3, y + 12, 0), {
					count = 10,
					color = primary,
					secondary = secondary,
					speed = 6,
					size = 0.7,
					life = 1.2,
					gravity = 10,
					spread = 120,
					direction = -90,
					glyph = glyph or "★",
				})
			end)
		end
	elseif itemId == "ko_confetti" then
		EffectsController.burst(Vector3.new(x, y + 3, 0), {
			count = 40,
			color = primary,
			speed = 22,
			size = 0.45,
			life = 1.1,
			gravity = 18,
			spread = 160,
			direction = 90,
			palette = {
				Color3.fromRGB(255, 79, 139),
				Color3.fromRGB(58, 168, 240),
				Color3.fromRGB(255, 210, 63),
				Color3.fromRGB(47, 196, 111),
				Color3.fromRGB(180, 92, 240),
			},
		})
	elseif itemId == "ko_fireworks" then
		for index = 1, 3 do
			task.delay((index - 1) * 0.3, function()
				local position = Vector3.new(x + (index - 2) * 5, y + 9 + index, 0)
				EffectsController.ring(position, if index % 2 == 0 then secondary else primary, 3, 0.4, 4)
				EffectsController.burst(position, {
					count = 26,
					color = primary,
					secondary = secondary,
					speed = 14,
					size = 0.4,
					life = 0.8,
					gravity = 6,
					spread = 360,
				})
			end)
		end
	elseif itemId == "ko_thunder" then
		EffectsController.screenFlash(Color3.fromRGB(200, 230, 255), 0.35, 0.8)
		EffectsController.slash(Vector3.new(x, y + 6, 0), primary, 12, 90, 0.35)
		EffectsController.burst(Vector3.new(x, y + 1, 0), {
			count = 16,
			color = primary,
			secondary = secondary,
			speed = 16,
			size = 0.8,
			life = 0.5,
			gravity = 4,
			spread = 180,
			direction = 90,
			glyph = glyph or "ϟ",
		})
	end
end

function EffectsController.screenFlash(color: Color3, duration: number, strength: number?)
	local frame = getFlashFrame()
	if frame == nil then
		return
	end
	frame.BackgroundColor3 = color
	flashTime = 0
	flashDuration = math.max(duration, 0.01)
	flashStrength = math.clamp(strength or 0.6, 0, 1)
	frame.BackgroundTransparency = 1 - flashStrength
end

----------------------------------------------------------------------------------------------
-- Эффекты на экране: вставка супера
----------------------------------------------------------------------------------------------

local function fxGui(): ScreenGui?
	local frame = getFlashFrame()
	if frame == nil then
		return nil
	end
	return frame.Parent :: ScreenGui
end

--[[
	Вставка супера (как в аниме-файтингах): экран темнеет по краям, летят линии скорости,
	по диагонали проносится полоса с портретом бойца (поза супера) и названием приёма.
	side — с какой стороны экрана боец (-1 — слева, 1 — справа).
]]
function EffectsController.superCutIn(def: Types.CharacterDef, palette: Types.Palette?, title: string, side: number)
	local gui = fxGui()
	if gui == nil then
		return
	end
	local color = Color3.fromHex(def.cosmetics.superFlash)
	local holder = Instance.new("Frame")
	holder.Name = "SuperCutIn"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 10
	holder.Parent = gui

	-- Затемнение.
	local shade = Instance.new("Frame")
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 10
	shade.Parent = holder

	-- Линии скорости.
	type Line = { frame: Frame, y: number, speed: number, length: number }
	local lines: { Line } = {}
	for index = 1, 22 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = if index % 3 == 0 then color else WHITE
		line.ZIndex = 11
		line.Parent = holder
		table.insert(lines, {
			frame = line,
			y = Rng.range(rng, 0.05, 0.95),
			speed = Rng.range(rng, 2.5, 5),
			length = Rng.range(rng, 0.15, 0.45),
		})
	end

	-- Полоса с портретом.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.BackgroundColor3 = color
	band.BorderSizePixel = 0
	band.Rotation = -6 * side
	band.Size = UDim2.fromScale(1.4, 0.3)
	band.ZIndex = 12
	band.Parent = holder
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(color:Lerp(Color3.new(0, 0, 0), 0.55), color)
	gradient.Rotation = if side > 0 then 180 else 0
	gradient.Parent = band
	local edge = Instance.new("UIStroke")
	edge.Color = WHITE
	edge.Thickness = 3
	edge.Parent = band

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0.5, 0.5)
	portrait.BackgroundTransparency = 1
	portrait.Position = UDim2.fromScale(if side > 0 then 0.68 else 0.32, 0.42)
	portrait.ZIndex = 13
	portrait.Parent = band
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = portrait
	portrait.Size = UDim2.fromScale(0.3, 2.2)
	local viewDef = def
	if palette then
		local copy = table.clone(def) :: any
		copy.palette = palette
		viewDef = copy
	end
	local rig = Rig.new(portrait, viewDef)
	rig.setFacing(-side)
	rig.show("Super", 0, 0.3)

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Position = UDim2.fromScale(if side > 0 then 0.36 else 0.64, 0.45)
	label.Size = UDim2.fromScale(0.42, 0.5)
	label.Text = string.upper(title)
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.TextStrokeTransparency = 0
	label.ZIndex = 14
	label.Parent = band
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Fighter"
	nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.Position = UDim2.fromScale(if side > 0 then 0.36 else 0.64, 0.82)
	nameLabel.Size = UDim2.fromScale(0.3, 0.2)
	nameLabel.Text = string.upper(def.displayName)
	nameLabel.TextColor3 = color:Lerp(WHITE, 0.6)
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0.2
	nameLabel.ZIndex = 14
	nameLabel.Parent = band

	local life = 1.05
	addEffect(life, function(t: number, dt: number)
		-- Въезд (0–15 %), пауза, выезд (85–100 %).
		local x: number
		if t < 0.15 then
			x = -side * (1 - t / 0.15) ^ 2
		elseif t > 0.85 then
			x = side * ((t - 0.85) / 0.15) ^ 2
		else
			x = 0
		end
		band.Position = UDim2.fromScale(0.5 + x * 1.2, 0.46)
		shade.BackgroundTransparency = 1 - 0.55 * (if t < 0.1 then t / 0.1 elseif t > 0.8 then (1 - t) / 0.2 else 1)
		for _, line in lines do
			local progress = (t * line.speed + line.y * 3) % 1
			local lx = if side > 0 then progress else 1 - progress
			line.frame.Position = UDim2.fromScale(lx - line.length / 2, line.y)
			line.frame.Size = UDim2.new(line.length, 0, 0, 3)
			line.frame.BackgroundTransparency = 0.2 + 0.6 * math.abs(math.sin(t * 20 + line.y * 10))
		end
		rig.update(dt, 0, 0)
		rig.show("Super", 0, 0.3)
	end, function()
		holder:Destroy()
	end)
end

function EffectsController.clear()
	for _, burst in bursts do
		burst.anchor:Destroy()
	end
	table.clear(bursts)
	for _, effect in effects do
		effect.destroy()
	end
	table.clear(effects)
end

local function updateFlash(dt: number)
	local frame = flashFrame
	if frame == nil or flashDuration <= 0 then
		return
	end
	flashTime += dt
	local t = math.clamp(flashTime / flashDuration, 0, 1)
	frame.BackgroundTransparency = 1 - flashStrength * (1 - t)
	if t >= 1 then
		flashDuration = 0
	end
end

local function onRenderStep(dt: number)
	updateFlash(dt)
	for index = #effects, 1, -1 do
		local effect = effects[index]
		effect.age += dt
		if effect.age >= effect.life then
			effect.destroy()
			table.remove(effects, index)
		else
			effect.update(effect.age / effect.life, dt)
		end
	end
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		burst.age += dt
		if burst.age >= burst.life then
			burst.anchor:Destroy()
			table.remove(bursts, index)
		else
			local fade = burst.age / burst.life
			local scale = burst.extent * 2
			for _, particle in burst.particles do
				particle.vy -= burst.gravity * dt
				particle.x += particle.vx * dt
				particle.y += particle.vy * dt
				particle.frame.Position = UDim2.fromScale(0.5 + particle.x / scale, 0.5 - particle.y / scale)
				if particle.text then
					(particle.frame :: TextLabel).TextTransparency = fade
				else
					particle.frame.BackgroundTransparency = fade
				end
			end
		end
	end
end

function EffectsController.Init() end

function EffectsController.Start()
	RunService.RenderStepped:Connect(onRenderStep)
end

return EffectsController
