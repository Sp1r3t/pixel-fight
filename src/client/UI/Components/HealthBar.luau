--!strict
--[[
	Полоса здоровья с задержанной «белой» полосой урона:
	  • цветная полоса сразу показывает текущее HP (с лёгкой пружиной);
	  • белая полоса стоит на месте, пока идёт комбо, и догоняет через DELAY секунд —
	    так видно, сколько снесла вся серия ударов.
	Полоса «прижата» к внешнему краю экрана: у левого бойца — к левому, у правого — к правому.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children, peek = Fusion.Children, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Health: Fusion.Value<number>,
	MaxHealth: Fusion.Value<number>,
	Side: "Left" | "Right",
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2?,
}

local DELAY = 0.7

local HIGH = Color3.fromHex("#859370")
local MID = Color3.fromHex("#C4A46A")
local LOW = Color3.fromHex("#AB6251")

local function HealthBar(scope: Scope, props: Props): Instance
	local ratio = scope:Computed(function(use)
		local maxHealth = use(props.MaxHealth)
		return if maxHealth > 0 then math.clamp(use(props.Health) / maxHealth, 0, 1) else 0
	end)

	-- Белая полоса: догоняет текущее HP с задержкой после последнего удара.
	local delayed = scope:Value(peek(ratio))
	local serial = 0
	local alive = true
	table.insert(scope, function()
		alive = false
	end)
	scope:Observer(ratio):onChange(function()
		local current = peek(ratio)
		if current >= peek(delayed) then
			delayed:set(current) -- лечение / новый раунд — сразу
			return
		end
		serial += 1
		local mine = serial
		task.delay(DELAY, function()
			if alive and mine == serial then
				delayed:set(peek(ratio))
			end
		end)
	end)

	local whiteRatio = scope:Tween(delayed, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	local colorRatio = scope:Spring(ratio, 45, 1)
	local anchorX = if props.Side == "Left" then 0 else 1

	return scope:New "Frame" {
		Name = "HealthBar",
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = Color3.fromHex("#272B25"),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = props.Position,
		Size = props.Size,
		[Children] = {
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Outline,
				Thickness = 3,
			},
			scope:New "Frame" {
				Name = "Delayed",
				AnchorPoint = Vector2.new(anchorX, 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(anchorX, 0),
				Size = scope:Computed(function(use)
					return UDim2.fromScale(use(whiteRatio), 1)
				end),
				ZIndex = 2,
			},
			scope:New "Frame" {
				Name = "Current",
				AnchorPoint = Vector2.new(anchorX, 0),
				BackgroundColor3 = scope:Computed(function(use)
					local value = use(ratio)
					if value > 0.5 then
						return MID:Lerp(HIGH, (value - 0.5) * 2)
					end
					return LOW:Lerp(MID, value * 2)
				end),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(anchorX, 0),
				Size = scope:Computed(function(use)
					return UDim2.fromScale(use(colorRatio), 1)
				end),
				ZIndex = 3,
				[Children] = scope:New "Frame" {
					Name = "Shine",
					BackgroundColor3 = Color3.new(1, 1, 1),
					BackgroundTransparency = 0.7,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 0.3),
					ZIndex = 4,
				},
			},
		},
	}
end

return HealthBar
