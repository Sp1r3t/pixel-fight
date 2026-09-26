--!strict
--[[
	Процедурный пиксельный «манекен» из цветов палитры персонажа.
	Временный портрет, пока нет настоящего арта (этап 2 заменит его спрайтами).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Palette: Types.Palette,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
}

-- Части фигуры в долях контейнера: { x, y, w, h, слот палитры }.
type Part = { x: number, y: number, w: number, h: number, slot: "primary" | "secondary" | "accent" | "outline" }

local OUTLINE = Color3.fromHex("#05030B")

local PARTS: { Part } = {
	{ x = 0.36, y = 0.06, w = 0.28, h = 0.24, slot = "secondary" }, -- голова
	{ x = 0.36, y = 0.13, w = 0.28, h = 0.05, slot = "accent" }, -- повязка
	{ x = 0.30, y = 0.30, w = 0.40, h = 0.30, slot = "primary" }, -- торс
	{ x = 0.16, y = 0.31, w = 0.13, h = 0.26, slot = "primary" }, -- левая рука
	{ x = 0.71, y = 0.31, w = 0.13, h = 0.26, slot = "primary" }, -- правая рука
	{ x = 0.16, y = 0.55, w = 0.13, h = 0.07, slot = "secondary" }, -- левый кулак
	{ x = 0.71, y = 0.55, w = 0.13, h = 0.07, slot = "secondary" }, -- правый кулак
	{ x = 0.30, y = 0.58, w = 0.40, h = 0.06, slot = "accent" }, -- пояс
	{ x = 0.30, y = 0.64, w = 0.17, h = 0.30, slot = "secondary" }, -- левая нога
	{ x = 0.53, y = 0.64, w = 0.17, h = 0.30, slot = "secondary" }, -- правая нога
}

local function PixelFigure(scope: Scope, props: Props): Instance
	local colors: { [string]: Color3 } = {
		primary = Color3.fromHex(props.Palette.primary),
		secondary = Color3.fromHex(props.Palette.secondary),
		accent = Color3.fromHex(props.Palette.accent),
		outline = OUTLINE,
	}
	local zIndex = props.ZIndex or 1

	local parts: { Instance } = {}
	for index, part in PARTS do
		table.insert(
			parts,
			scope:New "Frame" {
				Name = `Part{index}`,
				BackgroundColor3 = colors[part.slot],
				BorderSizePixel = 0,
				Position = UDim2.fromScale(part.x, part.y),
				Size = UDim2.fromScale(part.w, part.h),
				ZIndex = zIndex + 1,
				[Children] = scope:New "UIStroke" {
					Color = OUTLINE,
					Thickness = 2,
				},
			}
		)
	end

	return scope:New "Frame" {
		Name = "PixelFigure",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = zIndex,
		[Children] = {
			scope:New "UIAspectRatioConstraint" {
				AspectRatio = 1,
			},
			parts,
		} :: { Fusion.Child },
	}
end

return PixelFigure
