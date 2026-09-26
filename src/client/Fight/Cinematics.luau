--!strict
--[[
	Cinematics — постановка ролика супера на клиенте.

	Сервер во время ролика держит бойцов на месте и наносит урон сериями (CinematicHit);
	клиент в это время «режиссирует» картинку, не влияя на бой:
	  • фон ролика за бойцами (у Deluxe-персонажей — особый, со «звёздами»), наезд камеры;
	  • движение бойцов по сценарию способа доставки супера:
	      Rush     — атакующий мечется сквозь противника, в конце подбрасывает его;
	      Launcher — оба взмывают вверх, серия в воздухе;
	      Beam     — луч через весь экран, противника отжимает назад;
	      Barrage  — сверху сыплется обстрел;
	      Grab     — противника поднимают над головой и впечатывают в пол;
	      Counter  — неподвижная стойка и серия молниеносных ударов с вспышками.
	Цвета — из косметики атакующего (цвет вспышки супера, искры, фон).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)
local FighterView = require(script.Parent.FighterView)
local CosmeticStyles = require(script.Parent.CosmeticStyles)
local SparkStyles = require(script.Parent.SparkStyles)
local EffectsController = require(script.Parent.Parent.Controllers.EffectsController)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)

export type Context = {
	folder: Instance,
	attacker: FighterView.FighterView,
	defender: FighterView.FighterView,
	attackerX: number,
	defenderX: number,
	duration: number, -- секунды
	hits: number,
}

type Active = {
	context: Context,
	def: Types.CharacterDef,
	delivery: string,
	dir: number, -- направление от атакующего к противнику
	elapsed: number,
	hitsDone: number,
	backdrop: Part,
	sparkles: { Frame },
	beam: Part?,
	slammed: boolean,
}

local Cinematics = {}

local BACKDROP_Z = -1.5
local rng = Rng.new(99)
local active: Active? = nil

local function makePart(folder: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Parent = folder
	return part
end

-- Фон за бойцами: градиент и (у Deluxe) мерцающие частицы.
local function buildBackdrop(folder: Instance, centerX: number, style: CosmeticStyles.BackdropStyle): (Part, { Frame })
	local width, height = 90, 44
	local plane = makePart(
		folder,
		"SuperBackdrop",
		Vector3.new(width, height, 0.2),
		Vector3.new(centerX, height / 2 - 4, BACKDROP_Z),
		style.bottom
	)
	plane.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Canvas"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(width * 4, height * 4)
	gui.LightInfluence = 0
	gui.Adornee = plane
	gui.Parent = plane
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(style.top, style.bottom)
	gradient.Rotation = 90
	gradient.Parent = fill
	local sparkles: { Frame } = {}
	local sparkle = style.sparkle
	if sparkle then
		for index = 1, 40 do
			local dot = Instance.new("Frame")
			dot.Name = `Sparkle{index}`
			dot.BorderSizePixel = 0
			dot.BackgroundColor3 = sparkle
			local size = Rng.range(rng, 0.004, 0.012)
			dot.Size = UDim2.fromScale(size, size * width / height)
			dot.Position = UDim2.fromScale(Rng.next(rng), Rng.next(rng) * 0.8)
			dot.ZIndex = 2
			dot.Parent = fill
			table.insert(sparkles, dot)
		end
	end
	return plane, sparkles
end

function Cinematics.isActive(): boolean
	return active ~= nil
end

function Cinematics.start(context: Context)
	Cinematics.stop()
	local def = context.attacker.def
	local dir = if context.defenderX >= context.attackerX then 1 else -1
	local centerX = (context.attackerX + context.defenderX) / 2
	local backdropStyle = CosmeticStyles.backdrop(def.cosmetics.cinematicBackdrop, def.cosmetics.superFlash)
	local backdrop, sparkles = buildBackdrop(context.folder, centerX, backdropStyle)
	local state: Active = {
		context = context,
		def = def,
		delivery = def.super.delivery,
		dir = dir,
		elapsed = 0,
		hitsDone = 0,
		backdrop = backdrop,
		sparkles = sparkles,
		beam = nil,
		slammed = false,
	}
	if state.delivery == "Beam" then
		local length = 34
		state.beam = makePart(
			context.folder,
			"SuperBeam",
			Vector3.new(length, 2.2, 0.3),
			Vector3.new(context.attackerX + dir * (length / 2 + 1), 3.5, 0.6),
			Color3.fromHex(def.cosmetics.superFlash)
		);
		(state.beam :: Part).Material = Enum.Material.Neon
	end
	active = state
	CameraController.shake(0.4, 0.3)
end

-- Позиция противника на экране с учётом постановки (для искр ударов).
function Cinematics.defenderOffset(): (number, number)
	local state = active
	if state == nil then
		return 0, 0
	end
	return state.context.defender.anchor.CFrame.Position.X - state.context.defenderX, 0
end

-- Очередной удар серии.
function Cinematics.hit()
	local state = active
	if state == nil then
		return
	end
	state.hitsDone += 1
	local context = state.context
	local def = state.def
	local style = SparkStyles.get(def.cosmetics.hitSpark)
	local position = context.defender.anchor.CFrame.Position
	context.defender.flash(1)
	if state.delivery == "Barrage" then
		EffectsController.burst(position + Vector3.new(0, 7, 0), {
			count = 10,
			color = style.primary,
			secondary = style.secondary,
			speed = 26,
			size = 0.5,
			life = 0.3,
			gravity = 20,
			spread = 40,
			direction = -90,
		})
	elseif state.delivery == "Counter" then
		EffectsController.screenFlash(Color3.new(1, 1, 1), 0.08, 0.35)
		context.attacker.flash(0.6)
	end
	CameraController.shake(0.25, 0.12)
end

function Cinematics.update(dt: number)
	local state = active
	if state == nil then
		return
	end
	local context = state.context
	state.elapsed += dt
	local t = math.clamp(state.elapsed / math.max(context.duration, 0.1), 0, 1)
	local dir = state.dir
	local ax, dx = context.attackerX, context.defenderX
	local attackerOffset = Vector2.zero
	local defenderOffset = Vector2.zero
	local delivery = state.delivery
	local hits = math.max(1, context.hits)

	if delivery == "Rush" then
		-- Атакующий мечется с одной стороны противника на другую, в конце — подброс.
		local phase = t * hits
		local side = if math.floor(phase) % 2 == 0 then -dir else dir
		local frac = phase % 1
		local targetX = dx + side * 2.2
		attackerOffset = Vector2.new(targetX - ax, math.sin(frac * math.pi) * 1.5)
		defenderOffset = Vector2.new(dir * 0.3 * math.sin(frac * math.pi), 0)
		if t > 0.85 then
			defenderOffset = Vector2.new(0, 8 * (t - 0.85) / 0.15)
		end
	elseif delivery == "Launcher" then
		local rise = 9 * math.sin(math.min(t / 0.7, 1) * math.pi / 2)
		defenderOffset = Vector2.new(0, rise)
		attackerOffset = Vector2.new((dx - dir * 1.6) - ax, math.max(0, rise - 1))
	elseif delivery == "Beam" then
		defenderOffset = Vector2.new(dir * 3 * t + math.sin(state.elapsed * 60) * 0.1, 0)
		local beam = state.beam
		if beam then
			beam.Transparency = 0.15 + 0.25 * math.abs(math.sin(state.elapsed * 25))
		end
	elseif delivery == "Grab" then
		if t < 0.55 then
			local lift = t / 0.55
			defenderOffset = Vector2.new((ax - dx) * lift, 6 * lift)
			attackerOffset = Vector2.new(0, 0)
		elseif t < 0.8 then
			local jump = (t - 0.55) / 0.25
			local height = 6 + 6 * math.sin(jump * math.pi)
			defenderOffset = Vector2.new(ax - dx, height)
			attackerOffset = Vector2.new(0, height - 5)
		else
			defenderOffset = Vector2.new(ax - dx + dir * 1.5, 0)
			if not state.slammed then
				state.slammed = true
				CameraController.shake(1, 0.5)
				EffectsController.dust(dx + defenderOffset.X, 0, nil)
				EffectsController.dust(dx + defenderOffset.X, 0, nil)
			end
		end
	elseif delivery == "Counter" or delivery == "Barrage" then
		local frac = (t * hits) % 1
		defenderOffset = Vector2.new(dir * 0.4 * math.sin(frac * math.pi), 0)
	end

	context.attacker.setOffset(attackerOffset.X, attackerOffset.Y)
	context.defender.setOffset(defenderOffset.X, defenderOffset.Y)

	for index, dot in state.sparkles do
		dot.BackgroundTransparency = 0.2 + 0.6 * math.abs(math.sin(state.elapsed * 3 + index))
	end

	-- Камера наезжает на пару и следует за полётом.
	local focusX = (ax + attackerOffset.X + dx + defenderOffset.X) / 2
	local focusY = 4 + math.max(attackerOffset.Y, defenderOffset.Y) * 0.6
	CameraController.setOverride(focusX, focusY, 16)
end

function Cinematics.stop()
	local state = active
	if state == nil then
		return
	end
	active = nil
	state.context.attacker.setOffset(0, 0)
	state.context.defender.setOffset(0, 0)
	state.backdrop:Destroy()
	local beam = state.beam
	if beam then
		beam:Destroy()
	end
	CameraController.setOverride(nil, nil, nil)
end

return Cinematics
