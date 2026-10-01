--!strict
--[[
	Рисует одну пиксельную иконку (UI/PixelIcons) — сетку маленьких Frame поверх прозрачного
	контейнера. Id может быть реактивным (scope:Computed/Value) — сетка пересобирается при смене.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local PixelIcons = require(script.Parent.Parent.PixelIcons)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Name: string?,
	Id: UsedAs<string>,
	Size: UsedAs<UDim2>?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	LayoutOrder: UsedAs<number>?,
	ZIndex: number?,
	Visible: UsedAs<boolean>?,
	Transparency: UsedAs<number>?, -- 0..1, поверх собственных цветов иконки (например, «не готово»)
	Color: UsedAs<Color3>?, -- одноцветный знак для сдержанного оформления меню
}

local GRID = PixelIcons.Size
local CELL = 1 / GRID

local function IconGlyph(scope: Scope, props: Props): Instance
	local cells = scope:Computed(function(use, innerScope: Scope): { Instance }
		local id = use(props.Id)
		local def = PixelIcons.icons[id]
		assert(def, `Неизвестная пиксельная иконка "{id}"`)

		local list: { Instance } = {}
		for row = 1, GRID do
			local rowText = def.rows[row]
			for col = 1, GRID do
				local color = def.palette[rowText:sub(col, col)]
				if color then
					table.insert(
						list,
						innerScope:New "Frame" {
							BackgroundColor3 = props.Color or color,
							BackgroundTransparency = props.Transparency or 0,
							BorderSizePixel = 0,
							Position = UDim2.fromScale((col - 1) * CELL, (row - 1) * CELL),
							Size = UDim2.fromScale(CELL, CELL),
						}
					)
				end
			end
		end
		return list
	end)

	return scope:New "Frame" {
		Name = props.Name or "Icon",
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		Position = props.Position,
		Size = props.Size or UDim2.fromScale(1, 1),
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = cells,
	}
end

return IconGlyph
