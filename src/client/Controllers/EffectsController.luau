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
}

type Particle = {
	frame: Frame,
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
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = if options.secondary and index % 2 == 0 then options.secondary else options.color
		frame.Size = UDim2.fromScale(size / (extent * 2), size / (extent * 2))
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Parent = gui
		table.insert(particles, {
			frame = frame,
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
				particle.frame.BackgroundTransparency = fade
			end
		end
	end
end

function EffectsController.Init() end

function EffectsController.Start()
	RunService.RenderStepped:Connect(onRenderStep)
end

return EffectsController
