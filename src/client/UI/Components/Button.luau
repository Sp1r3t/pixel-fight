--!strict
--[[
	Металлическая рамка, внутренняя гравировка и световой блик при наведении.
	Лицевая часть приподнимается и возвращается при нажатии (Spring-анимации).

	Варианты:
	  • обычная — текст по центру, слева можно поставить пиксельную иконку (Icon — id из UI/PixelIcons);
	  • Tile = true — большая плитка меню: крупная иконка сверху, название и подпись снизу;
	  • Badge — наклейка в углу («NEW», «x2»).
	Текст кнопки — это Text самой TextButton «Face» (по нему кнопку находят тесты и читалки).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local IconGlyph = require(script.Parent.IconGlyph)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Name: string?,
	Text: UsedAs<string>,
	OnClick: () -> (),
	Icon: UsedAs<string>?, -- id пиксельной иконки (UI/PixelIcons), не эмодзи; может быть реактивным
	IconSize: number?,
	IconOnly: boolean?, -- без текста рядом — иконка по центру кнопки (Text всё равно нужен тестам, можно "")
	Subtitle: UsedAs<string>?,
	Tile: boolean?,
	Badge: UsedAs<string>?,
	Size: UsedAs<UDim2>?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	LayoutOrder: UsedAs<number>?,
	Color: UsedAs<Color3>?,
	TextColor: UsedAs<Color3>?,
	Disabled: UsedAs<boolean>?,
	Font: Enum.Font?,
	TextSize: number?,
	Visible: UsedAs<boolean>?,
	ZIndex: number?,
}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function Button(scope: Scope, props: Props): Instance
	local depth = math.max(3, Theme.ShadowDepth)
	local hovering = scope:Value(false)
	local pressing = scope:Value(false)
	local disabled: UsedAs<boolean> = props.Disabled or false
	local baseColor: UsedAs<Color3> = props.Color or Theme.Colors.Button
	local zIndex = props.ZIndex or 1
	local hover = scope:Spring(
		scope:Computed(function(use)
			return if use(hovering) and not use(disabled) then 1 else 0
		end),
		22,
		1
	)
	local rimColor = scope:Computed(function(use)
		return Theme.Colors.PanelEdge:Lerp(Theme.Colors.Accent, use(hover))
	end)

	local bodyColor = scope:Computed(function(use)
		local color = use(baseColor)
		if use(disabled) then
			return Theme.Colors.Disabled
		elseif use(pressing) then
			return color:Lerp(BLACK, 0.12)
		elseif use(hovering) then
			return color:Lerp(Theme.Colors.Accent, 0.15)
		end
		return color
	end)
	local shadowColor = scope:Computed(function(use)
		local color: Color3 = if use(disabled) then Theme.Colors.Disabled else use(baseColor)
		return color:Lerp(Theme.Colors.Outline, 0.62)
	end)
	local press = scope:Spring(
		scope:Computed(function(use)
			return if use(disabled) then 0 elseif use(pressing) then depth - 1 elseif use(hovering) then -2 else 0
		end),
		45,
		1
	)
	local facePosition = scope:Computed(function(use)
		return UDim2.fromOffset(0, use(press))
	end)
	local faceSize = UDim2.new(1, 0, 1, -depth)

	local textColor = scope:Computed(function(use)
		if use(disabled) then
			return Theme.Colors.TextDim
		end
		return if props.TextColor ~= nil then use(props.TextColor) else Theme.Colors.Text
	end)

	local tile = props.Tile == true
	local textSize = props.TextSize or (if tile then 24 else 22)
	local hasIcon = props.Icon ~= nil
	local iconSize = props.IconSize or math.floor(textSize * 1.35)

	-- Отступы текста на «лице» и слой над ним: иконка, подпись, наклейка (без отступов).
	local extras: { Instance } = {}
	local padding: Instance
	if tile then
		padding = scope:New "UIPadding" {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(if hasIcon then 0.46 else 0, 0),
			PaddingBottom = UDim.new(if props.Subtitle ~= nil then 0.28 else 0.06, 0),
		}
		if hasIcon then
			table.insert(
				extras,
				IconGlyph(scope, {
					Name = "Icon",
					Color = Theme.Colors.Text,
					Id = props.Icon :: UsedAs<string>,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0.1),
					Size = UDim2.fromOffset(iconSize, iconSize),
				})
			)
		end
		if props.Subtitle ~= nil then
			table.insert(
				extras,
				scope:New "TextLabel" {
					Name = "Subtitle",
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Body,
					Position = UDim2.new(0.5, 0, 1, -8),
					Size = UDim2.new(1, -16, 0.2, 0),
					Text = props.Subtitle,
					TextColor3 = WHITE,
					TextScaled = true,
					TextTransparency = 0.12,
					ZIndex = zIndex + 4,
					[Children] = scope:New "UITextSizeConstraint" {
						MaxTextSize = 15,
					},
				}
			)
		end
	else
		local iconOnly = props.IconOnly == true
		padding = scope:New "UIPadding" {
			PaddingLeft = UDim.new(0, if iconOnly then 0 elseif hasIcon then iconSize + 14 else 10),
			PaddingRight = UDim.new(0, 10),
			PaddingBottom = UDim.new(if props.Subtitle ~= nil then 0.4 else 0, 0),
		}
		-- Подпись под текстом обычной кнопки: нижние 40% высоты.
		if props.Subtitle ~= nil then
			table.insert(
				extras,
				scope:New "TextLabel" {
					Name = "Subtitle",
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Body,
					Position = UDim2.new(0.5, 0, 1, -4),
					Size = UDim2.new(1, -20, 0.36, 0),
					Text = props.Subtitle,
					TextColor3 = WHITE,
					TextScaled = true,
					TextTransparency = 0.12,
					ZIndex = zIndex + 4,
					[Children] = scope:New "UITextSizeConstraint" {
						MaxTextSize = 14,
					},
				}
			)
		end
		if hasIcon then
			table.insert(
				extras,
				IconGlyph(scope, {
					Name = "Icon",
					Color = Theme.Colors.Text,
					Id = props.Icon :: UsedAs<string>,
					AnchorPoint = if iconOnly then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5),
					Position = if iconOnly then UDim2.fromScale(0.5, 0.5) else UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.fromOffset(iconSize, iconSize),
				})
			)
		end
	end
	if props.Badge ~= nil then
		local badgeText = props.Badge
		table.insert(
			extras,
			scope:New "TextLabel" {
				Name = "Badge",
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Colors.Danger,
				Font = Theme.Fonts.Title,
				Position = UDim2.new(1, -4, 0, 2),
				Size = UDim2.fromOffset(22, 22),
				Text = badgeText,
				TextColor3 = WHITE,
				TextSize = 14,
				Visible = scope:Computed(function(use)
					return use(badgeText) ~= ""
				end),
				ZIndex = zIndex + 5,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
					},
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.PanelEdge,
						Thickness = 2,
					},
				},
			}
		)
	end

	return scope:New "Frame" {
		Name = props.Name or "Button",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(220, 48),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = zIndex,

		[Children] = {
			-- Ступенька-тень.
			scope:New "Frame" {
				Name = "Shadow",
				BackgroundColor3 = shadowColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, depth),
				Size = faceSize,
				ZIndex = zIndex,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.ButtonRadius) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
				},
			},
			-- Цветное тело с бликом сверху.
			scope:New "Frame" {
				Name = "Body",
				BackgroundColor3 = scope:Spring(bodyColor, 30, 1),
				BorderSizePixel = 0,
				Position = facePosition,
				Size = faceSize,
				ClipsDescendants = true,
				ZIndex = zIndex + 1,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.ButtonRadius) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = rimColor,
						Thickness = Theme.Outline,
					},
					scope:New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, WHITE),
							ColorSequenceKeypoint.new(0.35, Color3.new(0.94, 0.94, 0.94)),
							ColorSequenceKeypoint.new(1, Color3.new(0.55, 0.58, 0.6)),
						}),
						Rotation = 90,
					},
					scope:New "Frame" {
						Name = "Shine",
						BackgroundColor3 = WHITE,
						BackgroundTransparency = scope:Computed(function(use)
							return 0.7 - use(hover) * 0.35
						end),
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(6, 1),
						Size = UDim2.new(1, -12, 0, 1),
						ZIndex = zIndex + 2,
						[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					},
					scope:New "Frame" {
						Name = "EngravedRim",
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(4, 4),
						Size = UDim2.new(1, -8, 1, -8),
						ZIndex = zIndex + 2,
						[Children] = scope:New "UIStroke" {
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
							Color = rimColor,
							Thickness = 1,
							Transparency = scope:Computed(function(use)
								return 0.72 - use(hover) * 0.38
							end),
						},
					},
					scope:New "Frame" {
						Name = "HoverSweep",
						BackgroundColor3 = Theme.Colors.Accent,
						BackgroundTransparency = 0.82,
						BorderSizePixel = 0,
						Position = scope:Computed(function(use)
							return UDim2.fromScale(-0.4 + use(hover) * 1.8, 0)
						end),
						Size = UDim2.fromScale(0.3, 1),
						ZIndex = zIndex + 2,
						[Children] = scope:New "UIGradient" {
							Rotation = 20,
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.5, 0),
								NumberSequenceKeypoint.new(1, 1),
							}),
						},
					},
					scope:New "Frame" {
						Name = "CornerInlay",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(1, -6, 0, 6),
						Size = UDim2.fromOffset(4, 4),
						Rotation = 45,
						BackgroundColor3 = rimColor,
						BorderSizePixel = 0,
						ZIndex = zIndex + 2,
					},
				},
			},
			-- Текст и события.
			scope:New "TextButton" {
				Name = "Face",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Position = facePosition,
				Size = faceSize,
				Font = props.Font or Theme.Fonts.Title,
				Text = props.Text,
				TextColor3 = textColor,
				-- Длинная надпись уменьшается, а не вылезает за кнопку.
				TextScaled = true,
				TextSize = textSize,
				TextWrapped = true,
				ZIndex = zIndex + 3,

				[OnEvent "MouseEnter"] = function()
					hovering:set(true)
				end,
				[OnEvent "SelectionGained"] = function()
					hovering:set(true)
				end,
				[OnEvent "SelectionLost"] = function()
					hovering:set(false)
					pressing:set(false)
				end,
				[OnEvent "MouseLeave"] = function()
					hovering:set(false)
					pressing:set(false)
				end,
				[OnEvent "MouseButton1Down"] = function()
					pressing:set(true)
				end,
				[OnEvent "MouseButton1Up"] = function()
					pressing:set(false)
				end,
				[OnEvent "Activated"] = function()
					if not peek(disabled) then
						props.OnClick()
					end
				end,

				[Children] = {
					padding,
					scope:New "UITextSizeConstraint" {
						MaxTextSize = textSize,
						MinTextSize = 9,
					},
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
						Color = Theme.Colors.Outline,
						Thickness = 1,
						Transparency = 0.8,
					},
				},
			},
			-- Иконка, подпись и наклейка — поверх, не мешают нажатию.
			scope:New "Frame" {
				Name = "Content",
				BackgroundTransparency = 1,
				Position = facePosition,
				Size = faceSize,
				ZIndex = zIndex + 4,
				[Children] = extras,
			},
		},
	}
end

return Button
