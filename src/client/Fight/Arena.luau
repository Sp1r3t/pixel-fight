--!strict
--[[
	Арена боя — 3D-сцена, которую камера снимает строго сбоку:
	  • пол (плоскость Y = 0) с полосами — даёт ощущение глубины;
	  • дальний фон (небо + силуэты) и средний план — на плоскостях позади,
	    при движении камеры по X возникает параллакс;
	  • сами бойцы — BillboardGui в плоскости Z = 0 (см. FighterView);
	  • платформы второго этажа (2 на 2, Combat/Stage) — плиты с яркой кромкой.
	Всё генерируется процедурно из темы (Config/Arenas) — детерминированно по id арены.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local Stage = require(ReplicatedStorage.Shared.Combat.Stage)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)

export type Arena = {
	folder: Folder,
	theme: Arenas.ArenaTheme,
	destroy: () -> (),
}

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

local function rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

-- Силуэты вдоль нижнего края холста: «горы», «город», «колонны», «шипы» или «волны».
local function silhouettes(
	canvas: Instance,
	style: string,
	color: Color3,
	rng: Rng.Rng,
	baseline: number,
	scale: number
)
	local x = 0
	while x < 1 do
		if style == "Mountains" then
			local width = Rng.range(rng, 0.08, 0.16)
			local height = Rng.range(rng, 0.12, 0.3) * scale
			-- «Пиксельная» гора: ступеньки, сужающиеся кверху.
			local steps = 6
			for step = 0, steps - 1 do
				local t = step / steps
				local w = width * (1 - t)
				rect(
					canvas,
					x + (width - w) / 2,
					baseline - height * (t + 1 / steps),
					w,
					height / steps + 0.002,
					color,
					2
				)
			end
			x += width * 0.7
		elseif style == "City" then
			local width = Rng.range(rng, 0.03, 0.07)
			local height = Rng.range(rng, 0.1, 0.35) * scale
			local building = rect(canvas, x, baseline - height, width, height, color, 2)
			-- Окна-пиксели.
			local rows = math.max(2, math.floor(height * 30))
			local windowColor = color:Lerp(Color3.new(1, 0.9, 0.5), 0.5)
			for row = 1, rows do
				if Rng.chance(rng, 0.5) then
					local y = 0.05 + (row - 1) / rows * 0.9
					local window = rect(building, Rng.range(rng, 0.15, 0.6), y, 0.25, 0.4 / rows, windowColor, 3)
					window.BackgroundTransparency = 0.3
				end
			end
			x += width + Rng.range(rng, 0, 0.01)
		elseif style == "Pillars" then
			local width = 0.025
			local height = Rng.range(rng, 0.25, 0.4) * scale
			rect(canvas, x, baseline - height, width, height, color, 2)
			rect(canvas, x - 0.008, baseline - height, width + 0.016, 0.02, color, 2)
			x += Rng.range(rng, 0.09, 0.14)
		elseif style == "Spikes" then
			local width = Rng.range(rng, 0.02, 0.05)
			local height = Rng.range(rng, 0.1, 0.4) * scale
			local steps = 4
			for step = 0, steps - 1 do
				local t = step / steps
				local w = width * (1 - t)
				rect(
					canvas,
					x + (width - w) / 2,
					baseline - height * (t + 1 / steps),
					w,
					height / steps + 0.002,
					color,
					2
				)
			end
			x += width + Rng.range(rng, 0.01, 0.05)
		else -- Waves
			local height = 0.03 * scale
			for band = 0, 3 do
				rect(
					canvas,
					0,
					baseline - height * (band + 1) - band * 0.01,
					1,
					height,
					color:Lerp(Color3.new(1, 1, 1), band * 0.06),
					2
				)
			end
			break
		end
	end
	-- Сплошная полоса у основания, чтобы силуэты «стояли» на земле.
	rect(canvas, 0, baseline, 1, 1 - baseline, color, 2)
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
	local rng = Rng.new(Rng.seedFromString(theme.id))
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

	-- Дальний фон: небо и силуэты.
	local _, sky = billboardPlane(folder, "Sky", 260, 120, -70, 30)
	local skyFrame = rect(sky, 0, 0, 1, 1, Color3.new(1, 1, 1), 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex(theme.skyTop), Color3.fromHex(theme.skyBottom))
	gradient.Rotation = 90
	gradient.Parent = skyFrame
	local sun = rect(sky, Rng.range(rng, 0.55, 0.75), 0.18, 0.05, 0.1, Color3.fromHex(theme.accent), 1)
	sun.BackgroundTransparency = 0.2
	silhouettes(sky, theme.silhouette, Color3.fromHex(theme.far), rng, 0.62, 1)

	-- Средний план: ближние силуэты (сильнее смещаются при движении камеры).
	local _, mid = billboardPlane(folder, "Midground", 200, 40, -32, 18)
	silhouettes(
		mid,
		if theme.silhouette == "Waves" then "Pillars" else theme.silhouette,
		Color3.fromHex(theme.near),
		rng,
		0.62,
		0.9
	)

	folder.Parent = parent

	return {
		folder = folder,
		theme = theme,
		destroy = function()
			folder:Destroy()
		end,
	}
end

return Arena
