--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local MapLandscape = require(script.Parent.MapLandscape)
type Scope = Fusion.Scope<typeof(Fusion)>
export type Props = { Visible: Fusion.UsedAs<boolean>, ArenaId: string? }

local function MenuBackdrop(scope: Scope, props: Props): Instance
	return scope:New "Frame" {
		Name = "Background",
		BackgroundColor3 = Theme.Colors.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Visible = props.Visible,
		ZIndex = 0,
		[Fusion.Children] = {
			scope:New "Frame" {
				Name = "Scene",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(1920, 593),
				BackgroundTransparency = 1,
				[Fusion.Children] = MapLandscape(scope, 1920, 593, true, 5),
			},
			scope:New "Frame" {
				Name = "Veil",
				BackgroundColor3 = Theme.Colors.Background,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 30,
				[Fusion.Children] = scope:New "UIGradient" {
					Rotation = 0,
					Transparency = NumberSequence.new(0.05, 0.35),
				},
			},
		},
	}
end
return MenuBackdrop
