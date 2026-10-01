--!strict
-- Baked illustration spans. Geometry and the SVG review sheet share the same source.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Artwork = require(script.Parent.Parent.CampaignArtwork)
type Scope = Fusion.Scope<typeof(Fusion)>

local function MapLandscape(scope: Scope, width: number, height: number, dark: boolean?, chapter: number?): Instance
	local region = Artwork.chapters[chapter or 1]
	local children: { Instance } = {}
	local colors: { [string]: Color3 } = {}
	for _, span in region.rects do
		local color = colors[span[5]]
		if not color then
			color = Color3.fromHex(span[5])
			if dark then
				color = color:Lerp(Color3.fromHex("#182129"), 0.55)
			end
			colors[span[5]] = color
		end
		table.insert(
			children,
			scope:New "Frame" {
				Name = "Ink",
				Position = UDim2.fromScale(span[1] / Artwork.width, span[2] / Artwork.height),
				Size = UDim2.fromScale(span[3] / Artwork.width, span[4] / Artwork.height),
				Rotation = span[7],
				BackgroundColor3 = color,
				BackgroundTransparency = span[6],
				BorderSizePixel = 0,
				[Fusion.Children] = if span[8] > 0
					then scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) }
					else nil,
			}
		)
	end
	return scope:New "Frame" {
		Name = "Landscape",
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.fromHex(region.color),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		[Fusion.Children] = children,
	}
end
return MapLandscape
