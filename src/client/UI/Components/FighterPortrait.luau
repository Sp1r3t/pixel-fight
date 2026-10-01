--!strict
--[[
	FighterPortrait — портрет бойца в интерфейсе. Это тот же детализированный боец, что и на
	арене (Sprites/Rig или спрайт-лист через SpriteAnimator), только в рамке нужного кадрирования:

	  • Framing = "Full" — во весь рост (превью в меню, панели бойца и босса);
	  • Framing = "Bust" — крупно по пояс (сетки выбора, HUD, магазин);
	  • Animated — дышит в стойке, ткань и волосы колышутся;
	  • Showcase — по кругу показывает стойку, удары, особый приём, супер и победу;
	  • Silhouette — тёмный силуэт (закрытый босс);
	  • Palette — другая палитра (босс, облик из магазина).

	Все анимированные портреты обновляет одна общая подписка RenderStepped (~30 кадров/с), так
	что десятки карточек не нагружают телефон. Портрет убирается вместе со scope.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local SpriteAnimator = require(script.Parent.Parent.Parent.Sprites.SpriteAnimator)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Framing = "Full" | "Bust"

export type Props = {
	Character: Types.CharacterDef,
	Palette: Types.Palette?,
	Framing: Framing?,
	Facing: number?, -- 1 — смотрит вправо (по умолчанию), -1 — влево
	Animated: boolean?,
	Showcase: boolean?,
	Pose: Types.AnimationName?, -- поза без анимации (по умолчанию Idle)
	Silhouette: boolean?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
}

-- Кадрирование: во сколько раз клетка бойца больше рамки и какая точка клетки
-- (доли, y вниз) оказывается в центре рамки. Боец стоит на y ≈ 0.96, макушка ≈ 0.32.
type Crop = { scale: number, centerX: number, centerY: number }

local FRAMINGS: { [Framing]: Crop } = {
	Full = { scale = 1.4, centerX = 0.5, centerY = 0.63 },
	Bust = { scale = 2.5, centerX = 0.52, centerY = 0.5 },
}

-- Витрина: что показывает анимированный портрет на экране выбора (длительности в секундах).
type Beat = { animation: Types.AnimationName, duration: number, attack: boolean }

local SHOWCASE: { Beat } = {
	{ animation = "Idle", duration = 1.6, attack = false },
	{ animation = "Light", duration = 0.34, attack = true },
	{ animation = "Idle", duration = 0.45, attack = false },
	{ animation = "Heavy", duration = 0.6, attack = true },
	{ animation = "Idle", duration = 0.6, attack = false },
	{ animation = "Special", duration = 0.95, attack = true },
	{ animation = "Idle", duration = 0.7, attack = false },
	{ animation = "Super", duration = 1.2, attack = true },
	{ animation = "Idle", duration = 0.6, attack = false },
	{ animation = "Win", duration = 1.8, attack = false },
}

local SILHOUETTE = Color3.fromHex("#211E17")
local STEP = 1 / 30

----------------------------------------------------------------------------------------------
-- Общие «часы» для всех анимированных портретов
----------------------------------------------------------------------------------------------

type Entry = { step: (dt: number) -> () }

local active: { [Entry]: boolean } = {}
local connection: RBXScriptConnection? = nil
local pending = 0

local function tick(dt: number)
	pending += dt
	if pending < STEP then
		return
	end
	local elapsed = math.min(pending, 0.1)
	pending = 0
	for entry in active do
		entry.step(elapsed)
	end
end

local function register(entry: Entry)
	active[entry] = true
	if connection == nil then
		connection = RunService.RenderStepped:Connect(tick)
	end
end

local function unregister(entry: Entry)
	active[entry] = nil
	local current = connection
	if next(active) == nil and current ~= nil then
		current:Disconnect()
		connection = nil
		pending = 0
	end
end

----------------------------------------------------------------------------------------------
-- Компонент
----------------------------------------------------------------------------------------------

local function FighterPortrait(scope: Scope, props: Props): Instance
	local framingName: Framing = props.Framing or "Bust"
	local framing = FRAMINGS[framingName]
	local facing = if (props.Facing or 1) < 0 then -1 else 1
	local zIndex = props.ZIndex or 1

	-- Центр кадра отражается вместе с бойцом.
	local centerX = 0.5 + (framing.centerX - 0.5) * facing
	local stage = scope:New "Frame" {
		Name = "Stage",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5 - centerX * framing.scale, 0.5 - framing.centerY * framing.scale),
		Size = UDim2.fromScale(framing.scale, framing.scale),
		ZIndex = zIndex,
	}

	local frame = scope:New "Frame" {
		Name = "FighterPortrait",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = zIndex,
		[Children] = {
			scope:New "UIAspectRatioConstraint" {
				AspectRatio = 1,
			},
			stage,
		} :: { Fusion.Child },
	}

	local def = props.Character
	local palette = props.Palette
	if palette ~= nil and palette ~= def.palette then
		local recolored = table.clone(def)
		recolored.palette = palette
		def = recolored
	end

	local animator = SpriteAnimator.new(stage, def)
	animator.setFacing(facing)
	if props.Silhouette then
		animator.setTint(SILHOUETTE, 0.9)
	end
	local pose: Types.AnimationName = props.Pose or "Idle"
	animator.show(pose, 0, nil)

	local entry: Entry? = nil
	if props.Showcase then
		local beat = 1
		local elapsed = 0
		entry = {
			step = function(dt: number)
				elapsed += dt
				local current = SHOWCASE[beat]
				if elapsed >= current.duration then
					elapsed -= current.duration
					beat = beat % #SHOWCASE + 1
					current = SHOWCASE[beat]
					elapsed = math.min(elapsed, current.duration)
				end
				animator.update(dt, 0, 0)
				if current.attack then
					animator.show(current.animation, elapsed, elapsed / current.duration)
				else
					animator.show(current.animation, elapsed, nil)
				end
			end,
		}
	elseif props.Animated then
		local elapsed = 0
		entry = {
			step = function(dt: number)
				elapsed += dt
				animator.update(dt, 0, 0)
				animator.show(pose, elapsed, nil)
			end,
		}
	end

	local registered = entry
	if registered ~= nil then
		register(registered)
	end
	table.insert(scope, function()
		if registered ~= nil then
			unregister(registered)
		end
		animator.destroy()
	end)

	return frame
end

return FighterPortrait
