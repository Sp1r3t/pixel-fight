--!strict
-- Export the actual UI instance tree; the browser review is not a separate mockup.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Harness = require("../../tests/lib/Harness")
local game = Harness.new({ studio = true, testBackend = true, startInput = "Keyboard" })
local client = game.addClient("Review")
game.step(2)
local function read(node: any, key: string): any
	local ok, value = pcall(function()
		return node[key]
	end)
	if not ok then
		return nil
	end
	local kind = typeof(value)
	if kind == "Color3" then
		return { value.R, value.G, value.B }
	end
	if kind == "UDim2" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	end
	if kind == "UDim" then
		return { value.Scale, value.Offset }
	end
	if kind == "Vector2" then
		return { value.X, value.Y }
	end
	if kind == "EnumItem" then
		return value.Name
	end
	if kind == "ColorSequence" or kind == "NumberSequence" then
		local result = {}
		for _, point in value.Keypoints do
			local v = point.Value
			table.insert(result, { point.Time, if typeof(v) == "Color3" then { v.R, v.G, v.B } else v })
		end
		return result
	end
	if kind == "number" or kind == "string" or kind == "boolean" then
		return value
	end
	return nil
end
local properties = {
	"Size",
	"Position",
	"AnchorPoint",
	"Rotation",
	"ZIndex",
	"Visible",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderSizePixel",
	"ClipsDescendants",
	"Text",
	"TextColor3",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextTransparency",
	"TextXAlignment",
	"TextYAlignment",
	"Font",
	"AutomaticSize",
	"CanvasPosition",
	"Image",
	"ImageRectOffset",
	"ImageRectSize",
	"ImageTransparency",
	"ImageColor3",
	"CornerRadius",
	"Thickness",
	"Color",
	"Transparency",
	"MaxTextSize",
	"MinTextSize",
	"Scale",
	"PaddingLeft",
	"PaddingRight",
	"PaddingTop",
	"PaddingBottom",
	"FillDirection",
	"Padding",
	"HorizontalAlignment",
	"VerticalAlignment",
	"LayoutOrder",
	"AspectRatio",
}
local function export(node: any): any
	local result = { name = node.Name, class = node.ClassName, props = {}, children = {} }
	for _, key in properties do
		result.props[key] = read(node, key)
	end
	for _, child in node:GetChildren() do
		table.insert(result.children, export(child))
	end
	return result
end
local function snapshot(): any
	return { background = export(client.find("Background")), layout = export(client.find("Layout")) }
end
local pages = { snapshot() }
if #game.errors() > 0 then
	error(table.concat(game.errors(), "\n"))
end
client.click("Одиночная игра")
game.step(2)
table.insert(pages, snapshot())
for _ = 1, 4 do
	client.press("MapNext")
	game.step(30)
	table.insert(pages, snapshot())
end
client.click("← Назад")
game.step(3)
local tile = client.find("Tile1")
client.runtime.fire(tile:FindFirstChild("Face", true), "MouseEnter")
local combos = client.find("Combos")
if combos then
	client.runtime.fire(combos:FindFirstChild("Face", true), "MouseEnter")
end
game.step(8)
table.insert(pages, snapshot())
fs.writeFile("art/ui/campaign/screens.json", serde.encode("json", pages))
print("Exported lobby and five campaign views")
