--!strict
--[[
	Шкала супера: заполняется при нанесении и получении урона.
	Когда полная — пульсирует и показывает «SUPER!» (можно нажимать I / кнопку «Супер»).

	Подпись стоит сбоку от шкалы (со стороны центра экрана), поэтому шкала помещается прямо под
	полосой здоровья и ничего не перекрывает. Compact — тонкая шкала без подписи (строки 2 на 2).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Meter: Fusion.Value<number>,
	Side: "Left" | "Right",
	Color: Color3,
	Clock: Fusion.Value<number>, -- время для пульсации
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2?,
	Compact: boolean?, -- тонкая шкала без подписи (строки 2 на 2)
	ReadyLabel: boolean?, -- у компактной шкалы: показывать «SUPER!», когда полная (своя строка)
}

local MAX = GameConfig.SuperMeter.Max
local WHITE = Color3.new(1, 1, 1)

local function SuperMeter(scope: Scope, props: Props): Instance
	local ratio = scope:Computed(function(use)
		return math.clamp(use(props.Meter) / MAX, 0, 1)
	end)
	local full = scope:Computed(function(use)
		return use(ratio) >= 1
	end)
	local fill = scope:Spring(ratio, 30, 1)
	local isLeft = props.Side == "Left"
	local anchorX = if isLeft then 0 else 1
	local pulse = scope:Computed(function(use)
		if not use(full) then
			return 0
		end
		return (math.sin(use(props.Clock) * 8) + 1) / 2
	end)

	local label: { Instance } = {}
	if not props.Compact or props.ReadyLabel then
		-- Подпись снаружи шкалы, со стороны центра экрана.
		table.insert(
			label,
			scope:New "TextLabel" {
				Name = "Label",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				-- У тонкой шкалы подпись чуть ниже центра — не задевает полосу HP над ней.
				Position = if isLeft
					then UDim2.new(1, 8, 0.5, if props.Compact then 3 else 0)
					else UDim2.new(0, -8, 0.5, if props.Compact then 3 else 0),
				Size = UDim2.fromOffset(90, if props.Compact then 14 else 18),
				Text = scope:Computed(function(use)
					return if use(full) then "SUPER!" else "SUPER"
				end),
				TextColor3 = scope:Computed(function(use)
					return if use(full) then props.Color:Lerp(WHITE, use(pulse)) else Theme.Colors.TextDim
				end),
				TextSize = if props.Compact then 15 else 18,
				TextStrokeTransparency = 0.2,
				TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
				Visible = if props.Compact then full else true,
			}
		)
	end

	return scope:New "Frame" {
		Name = "SuperMeter",
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = Color3.fromHex("#1A1233"),
		BorderSizePixel = 0,
		Position = props.Position,
		Size = props.Size,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					return Theme.Colors.Outline:Lerp(WHITE, use(pulse))
				end),
				Thickness = if props.Compact then 1.5 else 2.5,
			},
			scope:New "Frame" {
				Name = "Fill",
				AnchorPoint = Vector2.new(anchorX, 0),
				BackgroundColor3 = scope:Computed(function(use)
					return props.Color:Lerp(WHITE, use(pulse) * 0.5)
				end),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(anchorX, 0),
				Size = scope:Computed(function(use)
					return UDim2.fromScale(use(fill), 1)
				end),
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			},
			label,
		} :: { Fusion.Child },
	}
end

return SuperMeter
