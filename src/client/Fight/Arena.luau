--!strict
--[[
	Арена боя — 3D-сцена, которую камера снимает строго сбоку:
	  • пол (плоскость Y = 0) с полосами — даёт ощущение глубины;
	  • дальний фон (небо, детали, силуэты), средний план и слой погоды — плоскости с SurfaceGui позади
	    бойцов, при движении камеры по X возникает параллакс; рисует их Fight/ArenaArt (слегка
	    пиксельный процедурный арт, анимированный: update(dt) каждый кадр);
	  • сами бойцы — BillboardGui в плоскости Z = 0 (см. FighterView);
	  • платформы второго этажа (2 на 2, Combat/Stage) — плиты с яркой кромкой.
	Всё генерируется из темы карты (Config/Arenas) — детерминированно по id арены.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Stage = require(ReplicatedStorage.Shared.Combat.Stage)
local ArenaArt = require(script.Parent.ArenaArt)

export type Arena = {
	folder: Folder,
	theme: Arenas.ArenaTheme,
	update: (dt: number) -> (), -- анимация фона (погода, дракон, вывески, ...)
	destroy: () -> (),
}

--[[
	Плоскости фона: размер (студы) и положение. 1 пиксель арта = 1 студ.
	Высоты подобраны так, что линия горизонта рисунка (ArenaArt: 0.62 высоты холста) проецируется
	на дальний край пола (Z = −30) для камеры 1 на 1 и 2 на 2: силуэты «стоят» на горизонте.
]]
local SKY = { width = 260, height = 120, z = -70, y = 11.4 } -- горизонт на Y ≈ −3
local MID = { width = 200, height = 40, z = -32, y = 5.3 } -- горизонт на Y ≈ 0.5
local WEATHER = { width = 100, height = 40, z = -12, y = 12 }

local PLATFORM_DEPTH = 7 -- глубина плиты второго этажа (студы, вдоль Z)

local Arena = {}

local function part(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Color = color
	p.Parent = parent
	return p
end

-- Плоскость с SurfaceGui, повёрнутая лицом к камере (камера смотрит вдоль −Z).
local function billboardPlane(parent: Instance, name: string, width: number, height: number, z: number, y: number)
	local plane = part(parent, name, Vector3.new(width, height, 0.2), Vector3.new(0, y, z), Color3.new(0, 0, 0))
	plane.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Canvas"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(width * 4, height * 4)
	gui.LightInfluence = 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Adornee = plane
	gui.Parent = plane
	return plane, gui
end

-- Плиты второго этажа: верх на platform.top, яркая кромка спереди и опоры-колонны до пола.
local function buildPlatforms(folder: Instance, layout: Stage.Layout, theme: Arenas.ArenaTheme)
	local body = Color3.fromHex(theme.floor)
	local edge = Color3.fromHex(theme.accent)
	local line = Color3.fromHex(theme.floorLine)
	for index, platform in layout.platforms do
		local width = platform.right - platform.left
		local centerX = (platform.left + platform.right) / 2
		local centerY = platform.top - platform.thickness / 2
		part(
			folder,
			`Platform{index}`,
			Vector3.new(width, platform.thickness, PLATFORM_DEPTH),
			Vector3.new(centerX, centerY, -PLATFORM_DEPTH / 2 + 1),
			body
		)
		-- Светящаяся кромка по переднему краю и по краю у дыры: видно, где можно спрыгнуть.
		local rim = part(
			folder,
			"PlatformRim",
			Vector3.new(width, 0.2, 0.3),
			Vector3.new(centerX, platform.top - 0.05, 1.1),
			edge
		)
		rim.Material = Enum.Material.Neon
		local innerX = if math.abs(platform.left) < math.abs(platform.right) then platform.left else platform.right
		local lip = part(
			folder,
			"PlatformLip",
			Vector3.new(0.3, platform.thickness + 0.1, PLATFORM_DEPTH),
			Vector3.new(innerX, centerY, -PLATFORM_DEPTH / 2 + 1),
			edge
		)
		lip.Material = Enum.Material.Neon
		-- Полосы на плите, как на полу.
		local x = platform.left + 2
		while x < platform.right - 1 do
			part(
				folder,
				"PlatformLine",
				Vector3.new(0.2, 0.04, PLATFORM_DEPTH),
				Vector3.new(x, platform.top + 0.01, -PLATFORM_DEPTH / 2 + 1),
				line
			)
			x += 4
		end
		-- Колонны позади: этаж держится не в воздухе.
		local outerX = if innerX == platform.left then platform.right else platform.left
		for _, columnX in { innerX + (if innerX < outerX then 1.2 else -1.2), (innerX + outerX) / 2 } do
			part(
				folder,
				"PlatformColumn",
				Vector3.new(1, platform.top - platform.thickness, 1),
				Vector3.new(columnX, (platform.top - platform.thickness) / 2, -PLATFORM_DEPTH + 1.5),
				body:Lerp(Color3.new(0, 0, 0), 0.35)
			)
		end
	end
end

function Arena.build(themeId: string, parent: Instance, stageId: string?): Arena
	local theme = Arenas.byId[themeId] or Arenas.byId[Arenas.default]
	local layout = Stage.get(stageId)
	local halfWidth = layout.halfWidth

	local folder = Instance.new("Folder")
	folder.Name = "Arena"

	-- Пол: верх на Y = 0, тянется от горизонта (Z = −30) почти до камеры,
	-- чтобы нижняя часть кадра всегда была землёй.
	local floorWidth = halfWidth * 2 + 120
	local floorDepth = 110
	local floorCenterZ = -30 + floorDepth / 2
	part(
		folder,
		"Floor",
		Vector3.new(floorWidth, 2, floorDepth),
		Vector3.new(0, -1, floorCenterZ),
		Color3.fromHex(theme.floor)
	)
	local lineColor = Color3.fromHex(theme.floorLine)
	local x = -floorWidth / 2
	while x <= floorWidth / 2 do
		part(folder, "FloorLine", Vector3.new(0.25, 0.04, floorDepth), Vector3.new(x, 0.01, floorCenterZ), lineColor)
		x += 4
	end
	part(folder, "FloorEdge", Vector3.new(floorWidth, 0.06, 0.4), Vector3.new(0, 0.02, 4), lineColor)
	-- Отметки краёв арены.
	for _, side in { -1, 1 } do
		part(
			folder,
			"Boundary",
			Vector3.new(0.4, 0.08, 6),
			Vector3.new(side * halfWidth, 0.03, 0),
			Color3.fromHex(theme.accent)
		)
	end
	buildPlatforms(folder, layout, theme)

	-- Фон: небо с деталями и дальними силуэтами, средний план, погода.
	local _, sky = billboardPlane(folder, "Sky", SKY.width, SKY.height, SKY.z, SKY.y)
	local _, mid = billboardPlane(folder, "Midground", MID.width, MID.height, MID.z, MID.y)
	local _, weather = billboardPlane(folder, "Weather", WEATHER.width, WEATHER.height, WEATHER.z, WEATHER.y)
	local weatherLayer: ArenaArt.Layer = { canvas = weather, cols = WEATHER.width, rows = WEATHER.height }
	local art = ArenaArt.build({
		sky = { canvas = sky, cols = SKY.width, rows = SKY.height },
		mid = { canvas = mid, cols = MID.width, rows = MID.height },
		weather = weatherLayer,
	}, theme)

	folder.Parent = parent

	return {
		folder = folder,
		theme = theme,
		update = art.update,
		destroy = function()
			folder:Destroy()
		end,
	}
end

return Arena
