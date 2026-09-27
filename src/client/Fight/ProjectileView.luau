--!strict
--[[
	ProjectileView — отрисовка снарядов и ловушек из снапшотов (пиксельные фигуры в BillboardGui).

	Виды (Shared/Combat/Projectiles.KINDS):
	  Orb   — светящаяся сфера с ореолом, шлейфом и искрами;
	  Comet — звезда с длинным хвостом;      Disc  — вращающийся диск со следом;
	  Wave  — ледяные кристаллы по полу;     Mine  — глитч-мина с мигающим огоньком.
	Цвета — из палитры владельца. Сам ничего не решает: позиции приходят с сервера.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local Projectiles = require(ReplicatedStorage.Shared.Combat.Projectiles)

export type ProjectileViews = {
	update: (projectiles: { Snapshot.ProjectileSnapshot }, paletteOf: (owner: number) -> Types.Palette?) -> (),
	count: () -> number,
	destroy: () -> (),
}

type Visual = {
	anchor: Part,
	kind: string,
	parts: { Frame },
}

-- Размер BillboardGui по виду снаряда (студы).
local SIZES: { [string]: Vector2 } = {
	Orb = Vector2.new(4.4, 2.6),
	Comet = Vector2.new(5, 2.6),
	Disc = Vector2.new(3.4, 2.4),
	Wave = Vector2.new(3.4, 2.4),
	Mine = Vector2.new(1.8, 1.4),
}

local ProjectileView = {}

-- Фигура в долях BillboardGui; round — круг, rotation — поворот.
local function shape(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number,
	round: boolean?,
	transparency: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.ZIndex = z
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	frame.Parent = parent
	return frame
end

local WHITE = Color3.new(1, 1, 1)

local function build(folder: Instance, kind: string, palette: Types.Palette, direction: number): Visual
	local anchor = Instance.new("Part")
	anchor.Name = `Projectile{kind}`
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = folder

	local size = SIZES[kind] or SIZES.Orb
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sprite"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = anchor

	local primary = Color3.fromHex(palette.primary)
	local accent = Color3.fromHex(palette.accent)
	local back = if direction < 0 then 1 else -1 -- сторона хвоста (позади по полёту)
	local parts: { Frame } = {}
	local aspect = size.Y / size.X -- чтобы круги были круглыми
	if kind == "Orb" then
		-- Шлейф: круги позади, меньше и прозрачнее.
		for index = 1, 4 do
			local r = 0.46 - index * 0.07
			table.insert(
				parts,
				shape(
					gui,
					`Trail{index}`,
					0.5 + back * index * 0.09,
					0.5,
					r * aspect,
					r,
					accent,
					1,
					true,
					0.3 + index * 0.15
				)
			)
		end
		table.insert(parts, shape(gui, "Halo", 0.5, 0.5, 0.95 * aspect, 0.95, accent, 2, true, 0.6))
		table.insert(parts, shape(gui, "Body", 0.5, 0.5, 0.62 * aspect, 0.62, accent, 3, true))
		table.insert(parts, shape(gui, "Core", 0.5, 0.5, 0.34 * aspect, 0.34, WHITE, 4, true))
		for index = 1, 3 do
			table.insert(parts, shape(gui, `Spark{index}`, 0.5, 0.5, 0.09 * aspect, 0.09, WHITE, 5))
		end
	elseif kind == "Comet" then
		for index = 1, 5 do
			local r = 0.5 - index * 0.075
			table.insert(
				parts,
				shape(
					gui,
					`Tail{index}`,
					0.55 + back * index * 0.08,
					0.5,
					r * aspect,
					r,
					if index % 2 == 0 then WHITE else accent,
					1,
					true,
					0.2 + index * 0.13
				)
			)
		end
		table.insert(parts, shape(gui, "Halo", 0.55, 0.5, 0.8 * aspect, 0.8, accent, 2, true, 0.55))
		local star1 = shape(gui, "Star1", 0.55, 0.5, 0.42 * aspect, 0.42, WHITE, 3)
		local star2 = shape(gui, "Star2", 0.55, 0.5, 0.42 * aspect, 0.42, accent, 3)
		star2.Rotation = 45
		table.insert(parts, star1)
		table.insert(parts, star2)
	elseif kind == "Disc" then
		for index = 1, 2 do
			local blur = shape(gui, `Blur{index}`, 0.5 + back * index * 0.1, 0.5, 0.8 * aspect, 0.8, accent, 1, true, 1)
			local stroke = Instance.new("UIStroke")
			stroke.Color = accent
			stroke.Thickness = 3
			stroke.Transparency = 0.4 + index * 0.2
			stroke.Parent = blur
			table.insert(parts, blur)
		end
		local ring = shape(gui, "Ring", 0.5, 0.5, 0.85 * aspect, 0.85, accent, 2, true)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = WHITE
		ringStroke.Thickness = 2
		ringStroke.Parent = ring
		table.insert(parts, ring)
		table.insert(parts, shape(gui, "Hole", 0.5, 0.5, 0.36 * aspect, 0.36, primary, 3, true))
		table.insert(parts, shape(gui, "Notch", 0.5, 0.2, 0.12 * aspect, 0.14, WHITE, 4))
	elseif kind == "Wave" then
		-- Ледяные кристаллы: ромбы разной высоты с бликами.
		for index = 1, 4 do
			local crystal = Instance.new("Frame")
			crystal.Name = `Crystal{index}`
			crystal.AnchorPoint = Vector2.new(0.5, 1)
			crystal.BorderSizePixel = 0
			crystal.BackgroundColor3 = if index % 2 == 0 then WHITE else accent
			crystal.Position = UDim2.fromScale(0.14 + (index - 1) * 0.24, 1)
			crystal.Size = UDim2.fromScale(0.18, 0.5)
			crystal.ZIndex = 2
			local stroke = Instance.new("UIStroke")
			stroke.Color = primary
			stroke.Thickness = 1.5
			stroke.Parent = crystal
			crystal.Parent = gui
			table.insert(parts, crystal)
		end
		for index = 1, 3 do
			table.insert(parts, shape(gui, `Frost{index}`, 0.2 + index * 0.25, 0.85, 0.07, 0.1, WHITE, 3, false, 0.3))
		end
	else -- Mine
		local body = shape(gui, "Body", 0.5, 0.72, 0.9, 0.5, primary, 2, true)
		local stroke = Instance.new("UIStroke")
		stroke.Color = accent
		stroke.Thickness = 1.5
		stroke.Parent = body
		table.insert(parts, body)
		table.insert(parts, shape(gui, "Light", 0.5, 0.42, 0.24, 0.3, Color3.fromRGB(255, 60, 60), 3, true))
		for index = 1, 3 do
			table.insert(parts, shape(gui, `Glitch{index}`, 0.5, 0.5, 0.14, 0.12, accent, 4, false, 0.3))
		end
	end
	return { anchor = anchor, kind = kind, parts = parts }
end

local function animate(visual: Visual, projectile: Snapshot.ProjectileSnapshot)
	local age = projectile.age
	local kind = visual.kind
	local parts = visual.parts
	if kind == "Orb" then
		local pulse = 0.5 + 0.5 * math.sin(age * 0.6)
		parts[5].BackgroundTransparency = 0.45 + 0.3 * pulse -- ореол
		parts[7].Size = UDim2.fromScale(parts[7].Size.X.Scale, 0.3 + 0.08 * pulse)
		for index = 8, 10 do
			local angle = age * 0.35 + index * 2.1
			parts[index].Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.14, 0.5 + math.sin(angle) * 0.32)
			parts[index].Rotation = age * 12
		end
	elseif kind == "Comet" then
		parts[7].Rotation = age * 10
		parts[8].Rotation = 45 + age * 10
		parts[6].BackgroundTransparency = 0.45 + 0.25 * math.sin(age * 0.8)
	elseif kind == "Disc" then
		for index = 1, #parts do
			parts[index].Rotation = age * 24
		end
		parts[5].Position = UDim2.fromScale(0.5 + math.sin(age * 0.42) * 0.14, 0.5 - math.cos(age * 0.42) * 0.3)
	elseif kind == "Wave" then
		for index = 1, 4 do
			local height = 0.45 + 0.45 * math.abs(math.sin(age * 0.35 + index))
			parts[index].Size = UDim2.fromScale(0.18, height)
			parts[index].Rotation = math.sin(age * 0.2 + index) * 6
		end
		for index = 5, 7 do
			parts[index].BackgroundTransparency = 0.2 + 0.7 * math.abs(math.sin(age * 0.3 + index))
		end
	elseif kind == "Mine" then
		-- До взвода огонёк горит тускло, затем мигает; вокруг — «глитч».
		local armed = age >= Projectiles.MINE_ARM_FRAMES
		parts[2].BackgroundTransparency = if not armed then 0.7 elseif math.floor(age / 8) % 2 == 0 then 0 else 0.8
		for index = 3, 5 do
			local seed = math.floor(age / 4) + index * 13
			parts[index].Position = UDim2.fromScale(0.2 + (seed * 37 % 60) / 100, 0.3 + (seed * 53 % 50) / 100)
			parts[index].Visible = armed and seed % 3 ~= 0
		end
	end
end

function ProjectileView.new(folder: Instance): ProjectileViews
	local visuals: { [number]: Visual } = {}
	local views = {} :: ProjectileViews

	function views.update(projectiles: { Snapshot.ProjectileSnapshot }, paletteOf: (owner: number) -> Types.Palette?)
		local seen: { [number]: boolean } = {}
		for _, projectile in projectiles do
			local kind = Projectiles.indexToKind(projectile.kind) or "Orb"
			local visual = visuals[projectile.id]
			if visual == nil then
				local palette = paletteOf(projectile.owner)
				if palette then
					visual = build(folder, kind, palette, projectile.direction)
					visuals[projectile.id] = visual
				end
			end
			if visual then
				seen[projectile.id] = true
				-- Снаряд чуть ближе к камере, чем бойцы.
				visual.anchor.CFrame = CFrame.new(projectile.x, projectile.y, 0.5)
				animate(visual, projectile)
			end
		end
		for id, visual in visuals do
			if not seen[id] then
				visual.anchor:Destroy()
				visuals[id] = nil
			end
		end
	end

	function views.count(): number
		local total = 0
		for _ in visuals do
			total += 1
		end
		return total
	end

	function views.destroy()
		for _, visual in visuals do
			visual.anchor:Destroy()
		end
		table.clear(visuals)
	end

	return views
end

return ProjectileView
