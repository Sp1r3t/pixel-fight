--!strict
--[[
	EffectsController — визуальные эффекты боя.

	Пиксельные частицы: квадратики в BillboardGui, разлетающиеся с гравитацией и затуханием.
	Своя простая система вместо ParticleEmitter: полный контроль над «пиксельным» стилем
	и никаких внешних текстур.
	Этап 3 добавляет искры ударов, хитстоп, тряску; этап 8 — вспышки и ролики суперов.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Rng = require(ReplicatedStorage.Shared.Util.Rng)

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

function EffectsController.clear()
	for _, burst in bursts do
		burst.anchor:Destroy()
	end
	table.clear(bursts)
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
