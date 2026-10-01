--!strict
--[[
	Cinematics — постановка ролика супера на клиенте.

	Сервер во время ролика держит бойцов на месте и наносит урон сериями (CinematicHit);
	клиент в это время «режиссирует» картинку, не влияя на бой:
	  • фон ролика за бойцами (у Deluxe-персонажей — особый, со «звёздами»), наезд камеры;
	  • отдельная непрерывная траектория каждого бойца из SuperChoreography;
	  • прогресс собственных кадров ульты синхронизирован с серверным роликом;
	  • камера учитывает расстояние и высоту обоих бойцов.
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
local InteractionTether = require(script.Parent.InteractionTether)

export type Context = {
	folder: Instance,
	attacker: FighterView.FighterView,
	defender: FighterView.FighterView,
	attackerX: number,
	defenderX: number,
	duration: number, -- секунды
	hits: number,
	focusCamera: boolean, -- в 2v2 приближение видят только участники супера
}

type Active = {
	context: Context,
	def: Types.CharacterDef,
	delivery: string,
	style: string,
	dir: number, -- направление от атакующего к противнику
	elapsed: number,
	hitsDone: number,
	backdrop: Part,
	sparkles: { Frame },
	tether: InteractionTether.Tether?,
}

local CombatProfiles = require(ReplicatedStorage.Shared.Config.CombatProfiles)
local Choreography = require(script.Parent.SuperChoreography)
local InteractionReactions = require(script.Parent.InteractionReactions)
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
	local cinematicStyle = def.super.cinematic.style
	local profile = CombatProfiles.get(def.visualStyle or def.id)
	local backdropStyle =
		CosmeticStyles.backdrop(def.cosmetics.cinematicBackdrop, def.cosmetics.superFlash, cinematicStyle)
	local backdrop, sparkles = buildBackdrop(context.folder, centerX, backdropStyle)
	local state: Active = {
		context = context,
		def = def,
		delivery = def.super.delivery,
		style = if profile then profile.id else def.id,
		dir = dir,
		elapsed = 0,
		hitsDone = 0,
		backdrop = backdrop,
		sparkles = sparkles,
		tether = InteractionTether.new(context.folder, if profile then profile.id else def.id),
	}
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
	local accent = Color3.fromHex(def.cosmetics.superFlash)
	if state.style == "abbot" then
		EffectsController.dust(position.X, 0, nil)
		EffectsController.ring(position, accent, 4.8, 0.45, 8)
	elseif state.style == "ned" then
		EffectsController.dust(position.X, 0, nil)
		EffectsController.burst(position, {
			count = 14,
			color = Color3.fromRGB(104, 160, 86),
			secondary = accent,
			speed = 17,
			size = 0.42,
			life = 0.48,
			gravity = 12,
			spread = 110,
			direction = -90,
		})
	elseif state.style == "tidebreaker" then
		EffectsController.ring(position, accent, 5.2, 0.5, 9)
		EffectsController.burst(position, {
			count = 12,
			color = Color3.fromRGB(30, 150, 165),
			secondary = accent,
			speed = 20,
			size = 0.38,
			life = 0.42,
			gravity = 3,
			spread = 160,
			direction = -90,
		})
	elseif state.style == "grist" or state.style == "cinder" or state.style == "oru" then
		EffectsController.dust(position.X, math.max(0, position.Y - 2.8), nil)
		CameraController.shake(0.6, 0.25)
	elseif state.style == "rime" then
		EffectsController.ring(position, Color3.fromRGB(210, 248, 255), 4.4, 0.4, 8)
	elseif state.style == "kessa" or state.style == "hex" then
		EffectsController.starBurst(position, accent, 4.2, 0.24, 10)
	elseif state.style == "wraith" or state.style == "nocturne" or state.style == "null" then
		EffectsController.converge(position, accent, 5.5, 20, 0.36)
	elseif state.style == "tally" then
		EffectsController.burst(position, {
			count = 15,
			color = Color3.fromRGB(110, 180, 78),
			secondary = accent,
			speed = 21,
			size = 0.45,
			life = 0.46,
			gravity = 10,
			spread = 130,
			direction = -90,
		})
	elseif state.style == "farrow" or state.style == "vane" or state.style == "sovereign" then
		EffectsController.starBurst(position, accent, 3.4, 0.2, 9)
	elseif state.delivery == "Barrage" then
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
	-- Signature effects are keyed by the character's actual cinematic, not only
	-- by the six delivery families. This gives each fighter a readable motif.
	if state.style == "juno" then
		EffectsController.ring(position, accent, 2.8, 0.25, 4)
	elseif state.style == "pike" then
		EffectsController.starBurst(position + Vector3.new(state.dir * 0.8, 0, 0), accent, 2.8, 0.22, 5)
	elseif state.style == "zip" then
		EffectsController.burst(position, {
			count = 7,
			color = accent,
			secondary = Color3.new(1, 1, 1),
			speed = 18,
			size = 0.32,
			life = 0.24,
			gravity = 0,
			spread = 35,
			direction = if state.dir > 0 then 180 else 0,
		})
	elseif state.style == "sable" or state.style == "tempest" then
		EffectsController.screenFlash(accent, 0.045, 0.28)
		EffectsController.starBurst(position, accent, 3.2, 0.18, 4)
	elseif state.style == "ashka" then
		EffectsController.burst(position, {
			count = 12,
			color = accent,
			secondary = Color3.fromRGB(255, 90, 25),
			speed = 24,
			size = 0.42,
			life = 0.38,
			gravity = -5,
			spread = 70,
			direction = -90,
		})
	elseif state.style == "glacia" then
		EffectsController.ring(position, Color3.fromRGB(215, 250, 255), 3.5, 0.35, 7)
	elseif state.style == "byte" then
		EffectsController.starBurst(position, accent, 2.2, 0.18, 8)
	elseif state.style == "morrow" then
		EffectsController.ring(position, accent, 4, 0.4, 3)
	elseif state.style == "astra" then
		EffectsController.converge(position, accent, 4.5, 14, 0.28)
	elseif state.style == "brakk" then
		EffectsController.dust(position.X, math.max(0, position.Y - 2.8), nil)
	else
		EffectsController.starBurst(position, accent, 2.2, 0.2, 6)
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
	local ax, dx = context.attackerX, context.defenderX
	local victimProfile = CombatProfiles.get(context.defender.def.visualStyle or context.defender.def.id)
	local advance, height, push, lift = Choreography.offsets(
		state.style,
		if victimProfile then victimProfile.role else nil,
		ax,
		dx,
		t,
		context.attacker.stageWall
	)
	local attackerOffset = Vector2.new(advance, height)
	local defenderOffset = Vector2.new(push, lift)
	context.attacker.setCinematicProgress(t)
	local reaction, reactionProgress = InteractionReactions.sample(state.style, t)
	local victimSprites = context.defender.def.sprites
	if victimSprites and reaction and victimSprites.animations[reaction] then
		context.defender.setReactionProgress(reaction, reactionProgress)
	end

	context.attacker.setOffset(attackerOffset.X, attackerOffset.Y)
	context.defender.setOffset(defenderOffset.X, defenderOffset.Y)
	if state.tether then
		local source = context.attacker.anchor.CFrame.Position + Vector3.new(state.dir * 0.85, 0, 0.3)
		local target = context.defender.anchor.CFrame.Position + Vector3.new(0, 0.15, 0.3)
		state.tether.update(source, target, t)
	end

	for index, dot in state.sparkles do
		dot.BackgroundTransparency = 0.2 + 0.6 * math.abs(math.sin(state.elapsed * 3 + index))
	end

	-- Камера держит обоих бойцов целиком. В 2v2 остальные игроки видят эффект
	-- в общей камере и не теряют контроль из-за чужого приближения.
	local focusX = (ax + attackerOffset.X + dx + defenderOffset.X) / 2
	local focusY = 5.5 + math.max(attackerOffset.Y, defenderOffset.Y) * 0.55
	if context.focusCamera then
		local span = math.abs((ax + attackerOffset.X) - (dx + defenderOffset.X))
		local sceneHeight = math.max(attackerOffset.Y, defenderOffset.Y)
		CameraController.setOverride(focusX, focusY, math.max(28, span * 1.2 + 16, sceneHeight * 1.4 + 22))
	end
end

function Cinematics.stop()
	local state = active
	if state == nil then
		return
	end
	active = nil
	state.context.attacker.setCinematicProgress(nil)
	state.context.defender.setReactionProgress(nil, nil)
	state.context.attacker.setOffset(0, 0)
	state.context.defender.setOffset(0, 0)
	state.backdrop:Destroy()
	if state.tether then
		state.tether.destroy()
	end
	CameraController.setOverride(nil, nil, nil)
end

return Cinematics
