--!strict
--[[
	Процедурная пиксельная «кукла» — плейсхолдер вместо спрайт-листа.
	Собрана из прямоугольников в цветах палитры персонажа, позы — PuppetPoses.
	Интерфейс совпадает с SheetSprite, поэтому замена на настоящий арт не требует изменений в бою.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local PuppetPoses = require(script.Parent.PuppetPoses)

type Pose = PuppetPoses.Pose

-- Размеры частей в долях клетки спрайта.
local TORSO = 0.24
local TORSO_W = 0.17
local HEAD = 0.14
local ARM = 0.21
local LEG = 0.3
local LIMB_W = 0.07
local FIST = 0.075
local GROUND = 0.96

local OUTLINE = Color3.fromHex("#05030B")
local IDLE: Types.AnimationName = "Idle"

export type PuppetSprite = {
	root: Frame,
	show: (animation: Types.AnimationName, time: number, progress: number?) -> (),
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	destroy: () -> (),
}

type Part = {
	frame: Frame,
	baseColor: Color3,
}

local function makePart(parent: Instance, name: string, color: Color3, zIndex: number, outline: boolean): Part
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	if outline then
		local stroke = Instance.new("UIStroke")
		stroke.Color = OUTLINE
		stroke.Thickness = 1.5
		stroke.Parent = frame
	end
	frame.Parent = parent
	return { frame = frame, baseColor = color }
end

local function lerpPose(a: Pose, b: Pose, t: number): Pose
	local function mix(x: number?, y: number?, default: number): number
		local from = x or default
		local to = y or default
		return from + (to - from) * t
	end
	local hip: number?
	if a.hip and b.hip then
		hip = a.hip + (b.hip - a.hip) * t
	else
		hip = if t < 0.5 then a.hip else b.hip
	end
	return {
		lean = mix(a.lean, b.lean, 0),
		armF = mix(a.armF, b.armF, 0),
		armB = mix(a.armB, b.armB, 0),
		legF = mix(a.legF, b.legF, 0),
		legB = mix(a.legB, b.legB, 0),
		hip = hip,
		drop = mix(a.drop, b.drop, 0),
		x = mix(a.x, b.x, 0),
		glow = mix(a.glow, b.glow, 0),
	}
end

-- Поза в момент времени (для анимаций по времени) или по прогрессу 0..1 (для ударов).
local function samplePose(animation: Types.AnimationName, time: number, progress: number?): Pose
	local keys = PuppetPoses[animation] or PuppetPoses[IDLE]
	local count = #keys
	if count == 1 then
		return keys[1]
	end
	local def = Animations.defaults[animation]
	local position: number
	if progress ~= nil then
		position = math.clamp(progress, 0, 1) * (count - 1)
	else
		position = time * (if def then def.fps else 6)
		if def == nil or def.loop then
			position %= count
		else
			position = math.min(position, count - 1)
		end
	end
	local index = math.floor(position)
	local nextIndex = if index + 1 > count - 1 then (if def and def.loop then 0 else index) else index + 1
	return lerpPose(keys[index + 1], keys[nextIndex + 1], position - index)
end

local PuppetSprite = {}

function PuppetSprite.new(parent: Instance, def: Types.CharacterDef): PuppetSprite
	local primary = Color3.fromHex(def.palette.primary)
	local secondary = Color3.fromHex(def.palette.secondary)
	local accent = Color3.fromHex(def.palette.accent)
	local shade = function(color: Color3): Color3
		return color:Lerp(Color3.new(0, 0, 0), 0.3)
	end

	local root = Instance.new("Frame")
	root.Name = "Puppet"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	local glow = makePart(root, "Glow", accent, 1, false)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = glow.frame

	local legB = makePart(root, "LegBack", shade(secondary), 2, true)
	local footB = makePart(root, "FootBack", shade(primary), 3, true)
	local armB = makePart(root, "ArmBack", shade(primary), 4, true)
	local fistB = makePart(root, "FistBack", shade(secondary), 5, true)
	local torso = makePart(root, "Torso", primary, 6, true)
	local belt = makePart(root, "Belt", accent, 7, false)
	local head = makePart(root, "Head", secondary, 8, true)
	local band = makePart(root, "Band", accent, 9, false)
	local legF = makePart(root, "LegFront", secondary, 10, true)
	local footF = makePart(root, "FootFront", primary, 11, true)
	local armF = makePart(root, "ArmFront", primary, 12, true)
	local fistF = makePart(root, "FistFront", secondary, 13, true)

	local allParts = { legB, footB, armB, fistB, torso, belt, head, band, legF, footF, armF, fistF }

	local facing = 1

	local function place(part: Part, cx: number, cy: number, w: number, h: number, rotation: number)
		local x = if facing >= 0 then cx else 1 - cx
		part.frame.Position = UDim2.fromScale(x, cy)
		part.frame.Size = UDim2.fromScale(w, h)
		part.frame.Rotation = if facing >= 0 then rotation else -rotation
	end

	-- Конечность из сустава (jx, jy) под углом angle: возвращает конец.
	local function limb(part: Part, jx: number, jy: number, angle: number, length: number): (number, number)
		local radians = math.rad(angle)
		local ex = jx + math.sin(radians) * length
		local ey = jy + math.cos(radians) * length
		place(part, (jx + ex) / 2, (jy + ey) / 2, LIMB_W, length, -angle)
		return ex, ey
	end

	local function show(animation: Types.AnimationName, time: number, progress: number?)
		local pose = samplePose(animation, time, progress)
		local lowestFoot = math.max(math.cos(math.rad(pose.legF)), math.cos(math.rad(pose.legB)))
		local hipY = (pose.hip or (GROUND - LEG * lowestFoot)) + (pose.drop or 0)
		local hipX = 0.5 + (pose.x or 0)
		local lean = math.rad(pose.lean)
		local upX, upY = math.sin(lean), -math.cos(lean)

		-- Ноги.
		local fbx, fby = limb(legB, hipX - 0.02, hipY, pose.legB, LEG)
		place(footB, fbx + 0.025, fby, 0.08, 0.045, 0)
		local ffx, ffy = limb(legF, hipX + 0.02, hipY, pose.legF, LEG)
		place(footF, ffx + 0.025, ffy, 0.08, 0.045, 0)

		-- Торс и голова.
		local topX, topY = hipX + upX * TORSO, hipY + upY * TORSO
		place(torso, (hipX + topX) / 2, (hipY + topY) / 2, TORSO_W, TORSO + 0.02, pose.lean)
		place(belt, hipX + upX * 0.02, hipY + upY * 0.02, TORSO_W + 0.01, 0.035, pose.lean)
		local headX, headY = topX + upX * (HEAD / 2 + 0.01), topY + upY * (HEAD / 2 + 0.01)
		place(head, headX, headY, HEAD, HEAD, pose.lean)
		place(band, headX + upX * 0.02, headY + upY * 0.02, HEAD + 0.01, 0.028, pose.lean)

		-- Руки от плеча.
		local shoulderX, shoulderY = topX - upX * 0.035, topY - upY * 0.035
		local hbx, hby = limb(armB, shoulderX - 0.01, shoulderY, pose.armB, ARM)
		place(fistB, hbx, hby, FIST, FIST, 0)
		local hfx, hfy = limb(armF, shoulderX + 0.01, shoulderY, pose.armF, ARM)
		place(fistF, hfx, hfy, FIST, FIST, 0)

		-- Свечение для особых приёмов.
		local glowAmount = pose.glow or 0
		glow.frame.Visible = glowAmount > 0.01
		if glow.frame.Visible then
			local size = 0.45 + glowAmount * 0.35
			place(glow, (hipX + topX) / 2, (hipY + topY) / 2, size, size, 0)
			glow.frame.BackgroundTransparency = 1 - glowAmount * 0.55
		end
	end

	local sprite = {} :: PuppetSprite
	sprite.root = root
	sprite.show = show
	function sprite.setFacing(newFacing: number)
		facing = if newFacing < 0 then -1 else 1
	end
	-- Вспышка при получении удара: части светлеют.
	function sprite.setFlash(amount: number)
		local t = math.clamp(amount, 0, 1)
		for _, part in allParts do
			part.frame.BackgroundColor3 = part.baseColor:Lerp(Color3.new(1, 1, 1), t)
		end
	end
	function sprite.destroy()
		root:Destroy()
	end

	show("Idle", 0, nil)
	return sprite
end

return PuppetSprite
