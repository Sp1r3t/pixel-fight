--!strict
--[[
	ProjectileView — отрисовка снарядов и ловушек из снапшотов (пиксельные фигуры в BillboardGui).

	Виды (Shared/Combat/Projectiles.KINDS):
	  Orb   — пульсирующий сгусток;          Comet — ромб-звезда с хвостом;
	  Disc  — вращающийся диск;              Wave  — шипы, бегущие по полу;
	  Mine  — мина с мигающим огоньком.
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
	Orb = Vector2.new(2.4, 2.4),
	Comet = Vector2.new(3.2, 2.2),
	Disc = Vector2.new(2.2, 2.2),
	Wave = Vector2.new(3, 2),
	Mine = Vector2.new(1.6, 1),
}

local ProjectileView = {}

local function square(parent: Instance, name: string, size: number, color: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size)
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

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
	local white = Color3.new(1, 1, 1)
	local parts: { Frame } = {}
	if kind == "Orb" then
		table.insert(parts, square(gui, "Glow", 0.9, accent, 1))
		table.insert(parts, square(gui, "Core", 0.5, white, 2))
	elseif kind == "Comet" then
		-- Хвост — позади по направлению полёта.
		local back = if direction < 0 then 1 else -1
		for index = 1, 3 do
			local tail = square(gui, `Tail{index}`, 0.34 - index * 0.06, accent, 1)
			tail.Position = UDim2.fromScale(0.5 + back * index * 0.12, 0.5)
			table.insert(parts, tail)
		end
		local star = square(gui, "Star", 0.5, white, 3)
		star.Rotation = 45
		star.Position = UDim2.fromScale(0.5 - back * 0.12, 0.5)
		table.insert(parts, star)
	elseif kind == "Disc" then
		table.insert(parts, square(gui, "Ring", 0.9, accent, 1))
		table.insert(parts, square(gui, "Hole", 0.45, primary, 2))
	elseif kind == "Wave" then
		for index = 1, 4 do
			local spike = Instance.new("Frame")
			spike.Name = `Spike{index}`
			spike.AnchorPoint = Vector2.new(0.5, 1)
			spike.BorderSizePixel = 0
			spike.BackgroundColor3 = if index % 2 == 0 then white else accent
			spike.Position = UDim2.fromScale(0.15 + (index - 1) * 0.23, 1)
			spike.Size = UDim2.fromScale(0.16, 0.5)
			spike.Parent = gui
			table.insert(parts, spike)
		end
	else -- Mine
		local body = square(gui, "Body", 0.9, primary, 1)
		body.Size = UDim2.fromScale(0.9, 0.55)
		body.Position = UDim2.fromScale(0.5, 0.7)
		table.insert(parts, body)
		local light = square(gui, "Light", 0.22, Color3.fromRGB(255, 60, 60), 2)
		light.Position = UDim2.fromScale(0.5, 0.45)
		table.insert(parts, light)
	end
	return { anchor = anchor, kind = kind, parts = parts }
end

local function animate(visual: Visual, projectile: Snapshot.ProjectileSnapshot)
	local age = projectile.age
	local kind = visual.kind
	local parts = visual.parts
	if kind == "Orb" then
		local pulse = 0.5 + 0.5 * math.sin(age * 0.6)
		parts[1].BackgroundTransparency = 0.25 + 0.3 * pulse
		parts[1].Rotation = age * 6
		parts[2].Rotation = -age * 9
	elseif kind == "Comet" then
		parts[4].Rotation = 45 + age * 12
		for index = 1, 3 do
			parts[index].BackgroundTransparency = 0.2 + index * 0.2
		end
	elseif kind == "Disc" then
		parts[1].Rotation = age * 24
		parts[2].Rotation = age * 24
	elseif kind == "Wave" then
		for index, spike in parts do
			local height = 0.45 + 0.4 * math.abs(math.sin(age * 0.4 + index))
			spike.Size = UDim2.fromScale(0.16, height)
		end
	elseif kind == "Mine" then
		-- До взвода огонёк горит тускло, затем мигает.
		local armed = age >= Projectiles.MINE_ARM_FRAMES
		parts[2].BackgroundTransparency = if not armed then 0.7 elseif math.floor(age / 8) % 2 == 0 then 0 else 0.8
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
