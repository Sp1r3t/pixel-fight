--!strict
--[[
	Шкала супера: заполняется при нанесении и получении урона.
	Когда полная — пульсирует и показывает «SUPER!» (можно нажимать I / кнопку «Супер»).
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
}

local MAX = GameConfig.SuperMeter.Max

local function SuperMeter(scope: Scope, props: Props): Instance
	local ratio = scope:Computed(function(use)
		return math.clamp(use(props.Meter) / MAX, 0, 1)
	end)
	local full = scope:Computed(function(use)
		return use(ratio) >= 1
	end)
	local fill = scope:Spring(ratio, 30, 1)
	local anchorX = if props.Side == "Left" then 0 else 1
	local pulse = scope:Computed(function(use)
		if not use(full) then
			return 0
		end
		return (math.sin(use(props.Clock) * 8) + 1) / 2
	end)

	return scope:New "Frame" {
		Name = "SuperMeter",
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = Color3.fromHex("#1A1233"),
		BorderSizePixel = 0,
		Position = props.Position,
		Size = props.Size,
		[Children] = {
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					return Theme.Colors.Outline:Lerp(Color3.new(1, 1, 1), use(pulse))
				end),
				Thickness = 3,
			},
			scope:New "Frame" {
				Name = "Fill",
				AnchorPoint = Vector2.new(anchorX, 0),
				BackgroundColor3 = scope:Computed(function(use)
					return props.Color:Lerp(Color3.new(1, 1, 1), use(pulse) * 0.5)
				end),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(anchorX, 0),
				Size = scope:Computed(function(use)
					return UDim2.fromScale(use(fill), 1)
				end),
			},
			scope:New "TextLabel" {
				Name = "Label",
				AnchorPoint = Vector2.new(anchorX, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.new(anchorX, 0, 0, -2),
				Size = UDim2.fromOffset(160, 20),
				Text = scope:Computed(function(use)
					return if use(full) then "SUPER!" else "SUPER"
				end),
				TextColor3 = scope:Computed(function(use)
					return if use(full) then props.Color:Lerp(Color3.new(1, 1, 1), use(pulse)) else Theme.Colors.TextDim
				end),
				TextSize = 20,
				TextStrokeTransparency = 0.3,
				TextXAlignment = if props.Side == "Left" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			},
		},
	}
end

return SuperMeter
