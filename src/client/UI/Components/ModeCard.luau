--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local IconGlyph = require(script.Parent.IconGlyph)
local MapLandscape = require(script.Parent.MapLandscape)
type Scope = Fusion.Scope<typeof(Fusion)>
export type Props = {
	Name: string,
	Text: string,
	Subtitle: string?,
	Icon: string,
	Position: UDim2,
	Size: UDim2,
	Color: Color3,
	Campaign: boolean?,
	OnClick: () -> (),
}
local function ModeCard(scope: Scope, props: Props): Instance
	local hovered, pressed = scope:Value(false), scope:Value(false)
	local hover = scope:Spring(
		scope:Computed(function(use)
			return if use(hovered) then 1 else 0
		end),
		20,
		1
	)
	local lift = scope:Spring(
		scope:Computed(function(use)
			return if use(pressed) then 2 elseif use(hovered) then -3 else 0
		end),
		30,
		0.9
	)
	local decorations: { Instance } = {}
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local ax, ay = corner[1], corner[2]
		for _, dimensions in { { 24, 1 }, { 1, 17 } } do
			table.insert(
				decorations,
				scope:New "Frame" {
					AnchorPoint = Vector2.new(ax, ay),
					Position = UDim2.new(ax, if ax == 0 then 8 else -8, ay, if ay == 0 then 8 else -8),
					Size = UDim2.fromOffset(dimensions[1], dimensions[2]),
					BackgroundColor3 = Theme.Colors.Accent,
					BorderSizePixel = 0,
					ZIndex = 3,
				}
			)
		end
		table.insert(
			decorations,
			scope:New "Frame" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(ax, if ax == 0 then 8 else -8, ay, if ay == 0 then 8 else -8),
				Size = UDim2.fromOffset(5, 5),
				Rotation = 45,
				BackgroundColor3 = Theme.Colors.Accent,
				BorderSizePixel = 0,
				ZIndex = 3,
			}
		)
	end
	return scope:New "Frame" {
		Name = props.Name,
		Position = props.Position,
		Size = props.Size,
		BackgroundTransparency = 1,
		[Fusion.Children] = {
			scope:New "Frame" {
				Name = "Shadow",
				Position = UDim2.fromOffset(0, 4),
				Size = UDim2.new(1, 0, 1, -4),
				BackgroundColor3 = Theme.Colors.Outline,
				BorderSizePixel = 0,
			},
			scope:New "Frame" {
				Name = "Plate",
				Position = scope:Computed(function(use)
					return UDim2.fromOffset(0, use(lift))
				end),
				Size = UDim2.new(1, 0, 1, -4),
				BackgroundColor3 = props.Color,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 2,
				[Fusion.Children] = {
					if props.Campaign
						then MapLandscape(scope, props.Size.X.Offset, props.Size.Y.Offset, true, 1)
						else nil,
					scope:New "Frame" {
						Name = "Shade",
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Theme.Colors.Background,
						BorderSizePixel = 0,
						BackgroundTransparency = scope:Computed(function(use)
							return 0.12 + use(hover) * 0.12
						end),
						[Fusion.Children] = scope:New "UIGradient" {
							Transparency = NumberSequence.new(0, 0.78),
							Rotation = 0,
						},
					},
					scope:New "Frame" {
						Name = "HoverSweep",
						BorderSizePixel = 0,
						BackgroundColor3 = Theme.Colors.Accent,
						BackgroundTransparency = 0.85,
						Position = scope:Computed(function(use)
							return UDim2.fromScale(-0.35 + use(hover) * 1.7, 0)
						end),
						Size = UDim2.fromScale(0.28, 1),
						ZIndex = 3,
						[Fusion.Children] = scope:New "UIGradient" {
							Rotation = 18,
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.5, 0),
								NumberSequenceKeypoint.new(1, 1),
							}),
						},
					},
					scope:New "Frame" {
						Name = "Seal",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.new(1, -61, 0.5, 0),
						Size = UDim2.fromOffset(68, 68),
						Rotation = 45,
						BackgroundTransparency = 1,
						ZIndex = 3,
						[Fusion.Children] = scope:New "UIStroke" {
							Color = Theme.Colors.Accent,
							Thickness = 1,
							Transparency = scope:Computed(function(use)
								return 0.76 - use(hover) * 0.4
							end),
						},
					},
					IconGlyph(scope, {
						Name = "Emblem",
						Id = props.Icon,
						Color = Theme.Colors.Accent,
						Transparency = scope:Computed(function(use)
							return 0.5 - use(hover) * 0.22
						end),
						AnchorPoint = Vector2.new(1, 0.5),
						Position = scope:Computed(function(use)
							return UDim2.new(1, -26 + use(hover) * 3, 0.5, 0)
						end),
						Size = UDim2.fromOffset(70, 70),
					}),
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Accent,
						Thickness = 1,
						Transparency = scope:Computed(function(use)
							return 0.48 - use(hover) * 0.42
						end),
					},
					scope:New "TextLabel" {
						Name = "Eyebrow",
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(24, 13),
						Size = UDim2.new(1, -130, 0, 12),
						Font = Theme.Fonts.Body,
						TextSize = 9,
						Text = if props.Campaign
							then "КАМПАНИЯ / 20 БОССОВ"
							elseif props.Icon == "swords" then "АРЕНА"
							else "ПРАКТИКА",
						TextColor3 = Theme.Colors.Accent,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 4,
					},
					scope:New "TextButton" {
						Name = "Face",
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						AutoButtonColor = false,
						Text = props.Text,
						Font = Theme.Fonts.Title,
						TextSize = if props.Campaign then 27 else 21,
						TextColor3 = scope:Computed(function(use)
							return Theme.Colors.Text:Lerp(Theme.Colors.Accent, use(hover))
						end),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						ZIndex = 4,
						[Fusion.OnEvent "MouseEnter"] = function()
							hovered:set(true)
						end,
						[Fusion.OnEvent "MouseLeave"] = function()
							hovered:set(false)
							pressed:set(false)
						end,
						[Fusion.OnEvent "SelectionGained"] = function()
							hovered:set(true)
						end,
						[Fusion.OnEvent "SelectionLost"] = function()
							hovered:set(false)
							pressed:set(false)
						end,
						[Fusion.OnEvent "MouseButton1Down"] = function()
							pressed:set(true)
						end,
						[Fusion.OnEvent "MouseButton1Up"] = function()
							pressed:set(false)
						end,
						[Fusion.OnEvent "Activated"] = props.OnClick,
						[Fusion.Children] = scope:New "UIPadding" {
							PaddingLeft = UDim.new(0, 23),
							PaddingTop = UDim.new(0, 32),
							PaddingRight = UDim.new(0, 16),
						},
					},
					scope:New "TextLabel" {
						Name = "Subtitle",
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(24, if props.Campaign then 77 else 65),
						Size = UDim2.new(1, -48, 0, 22),
						Text = props.Subtitle or "",
						Font = Theme.Fonts.BodyRegular,
						TextColor3 = Theme.Colors.TextDim,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 4,
					},
					decorations,
				} :: { Fusion.Child },
			},
		} :: { Fusion.Child },
	}
end
return ModeCard
