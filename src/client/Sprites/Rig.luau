--!strict
--[[
	Rig — детализированный процедурный боец (замена спрайт-листа, пока нет нарисованного арта).

	Скелет: бёдра → корпус → шея → голова; плечо → локоть → кисть; бедро → колено → стопа.
	Каждая часть — Frame (скруглённый, с обводкой и светотенью), поставленный между двумя суставами.
	Облик (Config/CharacterLooks): телосложение, лицо и глаза, причёска, головной убор, одежда,
	перчатки, обувь, аксессуары и оружие. Цвета — из палитры персонажа (боссы перекрашиваются сами).

	Движение:
	  • позы — Sprites/RigPoses (удары по фреймдате, особые приёмы по типу, суперы по доставке);
	  • ткань и волосы (шарф, плащ, хвост, пояс) — цепочки с простой физикой: отстают при движении,
	    развеваются в прыжке;
	  • шлейф удара — след за кулаком / стопой / оружием в активные кадры;
	  • магия — свечение в руках и искры вокруг, аура вокруг тела на суперах.
	Всё считается в пространстве «смотрит вправо» (доли клетки спрайта, y вниз), затем отражается.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local CharacterLooks = require(ReplicatedStorage.Shared.Config.CharacterLooks)
local RigPoses = require(script.Parent.RigPoses)

type Pose = RigPoses.Pose
type Look = CharacterLooks.Look

export type Rig = {
	root: Frame,
	show: (animation: Types.AnimationName, time: number, progress: number?) -> (),
	setFacing: (facing: number) -> (),
	setFlash: (amount: number) -> (),
	-- Подкраска всех частей к цвету (силуэт закрытого босса в меню); 0 — исходные цвета.
	setTint: (color: Color3, amount: number) -> (),
	-- Скорость бойца (студ/с) и время кадра — для ткани, шлейфов и искр. Вызывать перед show.
	update: (dt: number, vx: number, vy: number) -> (),
	destroy: () -> (),
}

type Dims = {
	torsoLen: number,
	torsoW: number,
	head: number,
	neck: number,
	upperArm: number,
	foreArm: number,
	armW: number,
	foreW: number,
	hand: number,
	thigh: number,
	shin: number,
	legW: number,
	shinW: number,
	footL: number,
	footH: number,
}

local BUILDS: { [string]: Dims } = {
	Normal = {
		torsoLen = 0.2,
		torsoW = 0.15,
		head = 0.115,
		neck = 0.016,
		upperArm = 0.115,
		foreArm = 0.105,
		armW = 0.05,
		foreW = 0.046,
		hand = 0.05,
		thigh = 0.145,
		shin = 0.14,
		legW = 0.064,
		shinW = 0.054,
		footL = 0.082,
		footH = 0.032,
	},
	Slim = {
		torsoLen = 0.2,
		torsoW = 0.13,
		head = 0.112,
		neck = 0.018,
		upperArm = 0.115,
		foreArm = 0.105,
		armW = 0.043,
		foreW = 0.04,
		hand = 0.046,
		thigh = 0.148,
		shin = 0.142,
		legW = 0.056,
		shinW = 0.048,
		footL = 0.078,
		footH = 0.03,
	},
	Heavy = {
		torsoLen = 0.21,
		torsoW = 0.2,
		head = 0.12,
		neck = 0.014,
		upperArm = 0.12,
		foreArm = 0.11,
		armW = 0.068,
		foreW = 0.062,
		hand = 0.062,
		thigh = 0.14,
		shin = 0.135,
		legW = 0.08,
		shinW = 0.068,
		footL = 0.092,
		footH = 0.036,
	},
	Small = {
		torsoLen = 0.17,
		torsoW = 0.13,
		head = 0.12,
		neck = 0.012,
		upperArm = 0.098,
		foreArm = 0.09,
		armW = 0.044,
		foreW = 0.04,
		hand = 0.046,
		thigh = 0.122,
		shin = 0.118,
		legW = 0.056,
		shinW = 0.048,
		footL = 0.08,
		footH = 0.032,
	},
}

local GROUND = 0.96
local OUTLINE = Color3.fromHex("#0B0814")
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local IDLE: Types.AnimationName = "Idle"
local TRAIL_POINTS = 7

local Rig = {}

----------------------------------------------------------------------------------------------
-- Части
----------------------------------------------------------------------------------------------

-- Часть скелета: Frame в корне, ставится между суставами. base — исходный цвет (для вспышки).
type Part = {
	frame: Frame,
	base: Color3,
	gradient: UIGradient?,
}

-- Деталь внутри части (лицо на голове, пояс на корпусе): свои координаты в долях части.
type Detail = {
	frame: GuiObject,
	x: number,
	y: number,
	rotation: number,
	base: Color3?,
}

type Chain = {
	points: { Vector2 },
	previous: { Vector2 },
	ready: boolean, -- точки уже повешены от якоря
	parts: { Part },
	length: number,
	widths: { number },
	gravity: number,
	drag: number,
	rest: Vector2, -- куда тянется свободная ткань (в пространстве «вправо»)
}

local function roundness(frame: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = frame
end

local function outline(frame: GuiObject, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or OUTLINE
	stroke.Thickness = thickness or 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
end

-- Светотень: передняя (правая) сторона светлее, задняя темнее.
local function shading(frame: GuiObject): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0.72, 0.72, 0.78)),
		ColorSequenceKeypoint.new(0.45, WHITE),
		ColorSequenceKeypoint.new(1, WHITE),
	})
	gradient.Parent = frame
	return gradient
end

local function newPart(
	parent: Instance,
	name: string,
	color: Color3,
	z: number,
	radius: number?,
	shaded: boolean?,
	stroke: boolean?
): Part
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Size = UDim2.fromScale(0.05, 0.05)
	if radius and radius > 0 then
		roundness(frame, radius)
	end
	if stroke ~= false then
		outline(frame)
	end
	local gradient = if shaded then shading(frame) else nil
	frame.Parent = parent
	return { frame = frame, base = color, gradient = gradient }
end

local function newDetail(
	parent: GuiObject,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	z: number,
	radius: number?,
	rotation: number?,
	transparency: number?
): Detail
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.Rotation = rotation or 0
	frame.ZIndex = z
	if radius and radius > 0 then
		roundness(frame, radius)
	end
	frame.Parent = parent
	return { frame = frame, x = x, y = y, rotation = rotation or 0, base = color }
end

----------------------------------------------------------------------------------------------
-- Геометрия
----------------------------------------------------------------------------------------------

local function dir(angle: number): (number, number)
	local radians = math.rad(angle)
	return math.sin(radians), math.cos(radians)
end

-- Поворот точки вокруг центра (градусы, по часовой на экране).
local function rotateAround(x: number, y: number, cx: number, cy: number, degrees: number): (number, number)
	if degrees == 0 then
		return x, y
	end
	local radians = math.rad(degrees)
	local c, s = math.cos(radians), math.sin(radians)
	local dx, dy = x - cx, y - cy
	return cx + dx * c - dy * s, cy + dx * s + dy * c
end

----------------------------------------------------------------------------------------------
-- Сборка
----------------------------------------------------------------------------------------------

function Rig.new(parent: Instance, def: Types.CharacterDef): Rig
	local look = CharacterLooks.get(def.id, def.visualStyle)
	local palette = def.palette
	local dims = BUILDS[look.build] or BUILDS.Normal

	local function color(value: string?, fallback: Color3): Color3
		if value == nil then
			return fallback
		elseif value == "primary" then
			return Color3.fromHex(palette.primary)
		elseif value == "secondary" then
			return Color3.fromHex(palette.secondary)
		elseif value == "accent" then
			return Color3.fromHex(palette.accent)
		end
		return Color3.fromHex(value)
	end

	local skin = color(look.skin, Color3.fromHex("#E0AC69"))
	local topColor = color(look.top.color, skin)
	local topTrim = color(look.top.trim, topColor:Lerp(WHITE, 0.4))
	local pantsColor = color(look.pants.color, topColor)
	local bootColor = color(look.boots, BLACK)
	local gloveColor = color(look.gloves, skin)
	local hairColor = color(look.hair.color, BLACK)
	local element = color(look.element, WHITE)
	local bare = look.top.style == "Bare"
	local torsoColor = if bare then skin else topColor
	local sleeveColor = if look.sleeves == "None" or bare then skin else topColor
	local foreColor = if look.sleeves == "Full" and not bare then topColor else skin
	local shinColor = if look.pants.style == "Shorts" then skin else pantsColor
	local wide = look.pants.style == "Wide"
	local robe = look.pants.style == "Robe"

	local root = Instance.new("Frame")
	root.Name = "Rig"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	local parts: { Part } = {}
	local details: { Detail } = {}
	local function part(name: string, c: Color3, z: number, radius: number?, shaded: boolean?, stroke: boolean?): Part
		local created = newPart(root, name, c, z, radius, shaded, stroke)
		table.insert(parts, created)
		return created
	end
	local function detail(
		p: Part,
		x: number,
		y: number,
		w: number,
		h: number,
		c: Color3,
		z: number,
		radius: number?,
		rotation: number?,
		transparency: number?
	): Detail
		local created = newDetail(p.frame, x, y, w, h, c, z, radius, rotation, transparency)
		table.insert(details, created)
		return created
	end

	-- Слои (z): аура < плащ < волосы сзади < задняя рука < задняя нога < таз < корпус < передняя нога
	-- < голова < передняя рука < оружие < свечение < шлейф.
	local aura = part("Aura", element:Lerp(WHITE, 0.25), 1, 0.5, false, false)
	aura.frame.BackgroundTransparency = 1
	do
		-- Аура — «пламя»: ярче внизу и в середине, тает кверху.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, 0.35),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		gradient.Parent = aura.frame
	end

	-- Цепочки ткани/волос создаются ниже; сначала — тело.
	local armB = part("UpperArmBack", sleeveColor:Lerp(BLACK, 0.18), 20, 0.5, true)
	local foreB = part("ForeArmBack", foreColor:Lerp(BLACK, 0.18), 21, 0.5, true)
	local handB = part("HandBack", gloveColor:Lerp(BLACK, 0.15), 22, 0.35, true)
	local thighB = part("ThighBack", pantsColor:Lerp(BLACK, 0.18), 24, 0.45, true)
	local shinB = part("ShinBack", shinColor:Lerp(BLACK, 0.18), 25, 0.45, true)
	local footB = part("FootBack", bootColor:Lerp(BLACK, 0.15), 26, 0.35, true)
	local pelvis = part("Pelvis", pantsColor, 30, 0.35, true)
	local torso = part("Torso", torsoColor, 32, 0.3, true)
	local neck = part("Neck", skin:Lerp(BLACK, 0.12), 31, 0.3, false, false)
	local skirt: Part? = if robe then part("RobeSkirt", pantsColor, 36, 0.2, true) else nil
	local thighF = part("ThighFront", pantsColor, 38, 0.45, true)
	local shinF = part("ShinFront", shinColor, 39, 0.45, true)
	local footF = part("FootFront", bootColor, 40, 0.35, true)
	local head = part("Head", if look.face.eyes == "Skull" then Color3.fromHex("#E8E4D8") else skin, 44, 0.38, true)
	local armF = part("UpperArmFront", sleeveColor, 50, 0.5, true)
	local foreF = part("ForeArmFront", foreColor, 51, 0.5, true)
	local handF = part("HandFront", gloveColor, 52, 0.35, true)
	if skirt then
		-- Под халатом бёдра не видны.
		thighF.frame.Visible = false
		thighB.frame.Visible = false
	end

	-- Детали корпуса.
	local style = look.top.style
	if style == "Jacket" then
		detail(torso, 0.62, 0.5, 0.08, 0.9, topTrim, 33) -- молния
		detail(torso, 0.7, 0.1, 0.35, 0.12, topTrim, 33, 0, -25) -- воротник
		detail(torso, 0.3, 0.1, 0.35, 0.12, topTrim, 33, 0, 25)
	elseif style == "Gi" then
		detail(torso, 0.55, 0.38, 0.12, 0.75, topTrim, 33, 0, -28) -- запах кимоно
		detail(torso, 0.5, 0.06, 0.6, 0.1, topTrim, 33)
	elseif style == "Tank" then
		detail(torso, 0.5, 0.06, 0.42, 0.12, skin, 33, 0.5) -- вырез майки
	elseif style == "Top" then
		detail(torso, 0.5, 0.82, 1.02, 0.36, skin, 33, 0.25) -- открытый живот
		detail(torso, 0.5, 0.62, 1.02, 0.06, topTrim, 34)
	elseif style == "Robe" or style == "Cloak" then
		detail(torso, 0.56, 0.4, 0.1, 0.9, topTrim, 33, 0, -24) -- запах халата
		detail(torso, 0.5, 0.05, 0.7, 0.1, topTrim, 33)
	elseif style == "Armor" then
		detail(torso, 0.5, 0.28, 0.9, 0.3, topColor:Lerp(WHITE, 0.25), 33, 0.3) -- нагрудник
		detail(torso, 0.5, 0.62, 0.9, 0.06, topTrim, 34)
		detail(torso, 0.5, 0.78, 0.9, 0.06, topTrim, 34)
	elseif style == "Hoodie" then
		detail(torso, 0.62, 0.72, 0.5, 0.26, topColor:Lerp(BLACK, 0.2), 33, 0.3) -- карман
		detail(torso, 0.7, 0.2, 0.05, 0.3, topTrim, 34) -- шнурок
	elseif bare then
		detail(torso, 0.68, 0.3, 0.3, 0.16, skin:Lerp(BLACK, 0.15), 33, 0.5) -- грудь
		detail(torso, 0.62, 0.58, 0.14, 0.08, skin:Lerp(BLACK, 0.15), 33, 0.4) -- пресс
		detail(torso, 0.62, 0.7, 0.14, 0.08, skin:Lerp(BLACK, 0.15), 33, 0.4)
	end
	if look.belt then
		detail(torso, 0.5, 0.95, 1.06, 0.12, color(look.belt, WHITE), 35, 0.2)
		if look.belt == "accent" and look.build == "Heavy" then
			-- Пояс чемпиона: большая пряжка.
			detail(torso, 0.7, 0.95, 0.3, 0.2, color(look.belt, WHITE):Lerp(WHITE, 0.3), 36, 0.3)
		end
	end
	local extras = look.extras
	if extras.beads then
		for index = 0, 5 do
			detail(
				torso,
				0.3 + index * 0.1,
				0.1 + math.abs(index - 2.5) * -0.02 + 0.08,
				0.1,
				0.07,
				color(extras.beads, BLACK),
				36,
				0.5
			)
		end
	end
	if extras.stars then
		local starColor = color(extras.stars, WHITE)
		detail(torso, 0.3, 0.4, 0.1, 0.06, starColor, 34, 0, 45)
		detail(torso, 0.72, 0.62, 0.08, 0.05, starColor, 34, 0, 45)
	end
	if extras.backpack then
		detail(torso, -0.12, 0.42, 0.34, 0.62, color(extras.backpack, BLACK), 31, 0.25)
	end
	if style == "Robe" or style == "Cloak" then
		-- Широкие рукава халата.
		foreF.frame.Size = UDim2.fromScale(dims.foreW * 1.3, 0.1)
	end

	-- Штанины: отвороты шорт, обувь до щиколотки.
	if look.pants.trim then
		local trim = color(look.pants.trim, WHITE)
		detail(thighF, 0.5, 0.92, 1.05, 0.14, trim, 39)
		detail(thighB, 0.5, 0.92, 1.05, 0.14, trim:Lerp(BLACK, 0.18), 25)
	end
	detail(shinF, 0.5, 0.9, 1.08, 0.2, bootColor, 40, 0.3) -- голенище
	detail(shinB, 0.5, 0.9, 1.08, 0.2, bootColor:Lerp(BLACK, 0.15), 26, 0.3)
	if extras.jets then
		detail(footF, 0.2, 0.9, 0.35, 0.3, color(extras.jets, WHITE), 41, 0.5)
	end

	-- Лицо (координаты в долях головы; смотрит вправо).
	local eyesStyle = look.face.eyes
	local glowColor = color(look.face.glow, element)
	if look.face.mask then
		detail(head, 0.55, 0.78, 1.04, 0.46, color(look.face.mask, BLACK), 46, 0.3)
	end
	if eyesStyle == "Skull" then
		detail(head, 0.66, 0.46, 0.2, 0.2, OUTLINE, 46, 0.5) -- глазница
		detail(head, 0.66, 0.46, 0.08, 0.08, glowColor, 47, 0.5)
		detail(head, 0.84, 0.66, 0.1, 0.1, OUTLINE, 46, 0.5) -- нос
		for index = 0, 3 do
			detail(head, 0.58 + index * 0.1, 0.84, 0.03, 0.12, OUTLINE, 46) -- зубы
		end
	elseif eyesStyle == "Visor" then
		detail(head, 0.62, 0.46, 0.8, 0.18, glowColor, 47, 0.3)
		detail(head, 0.62, 0.43, 0.7, 0.04, WHITE, 48, 0.5, 0, 0.3)
	elseif eyesStyle == "Glow" then
		detail(head, 0.74, 0.44, 0.2, 0.08, glowColor, 47, 0.5)
		detail(head, 0.74, 0.44, 0.34, 0.2, glowColor, 46, 0.5, 0, 0.7)
	else
		local narrow = eyesStyle == "Narrow"
		detail(head, 0.74, 0.44, 0.2, if narrow then 0.1 else 0.16, WHITE, 46, 0.4) -- белок
		detail(head, 0.8, 0.45, 0.09, if narrow then 0.09 else 0.12, OUTLINE, 47, 0.4) -- зрачок
		detail(head, 0.72, if narrow then 0.34 else 0.31, 0.26, 0.05, hairColor:Lerp(OUTLINE, 0.4), 47, 0, -8) -- бровь
	end
	if not look.face.mask and eyesStyle ~= "Skull" then
		detail(head, 0.95, 0.58, 0.1, 0.14, skin:Lerp(BLACK, 0.12), 45, 0.4) -- нос
		detail(head, 0.8, 0.8, 0.18, 0.04, OUTLINE, 46) -- рот
		detail(head, 0.34, 0.54, 0.14, 0.18, skin:Lerp(BLACK, 0.1), 45, 0.5) -- ухо
	end
	if look.face.beard then
		detail(head, 0.64, 0.86, 0.66, 0.3, color(look.face.beard, BLACK), 46, 0.4)
	end

	-- Причёска.
	local hairStyle = look.hair.style
	local function cap(depth: number)
		detail(head, 0.46, depth / 2 - 0.02, 1.04, depth, hairColor, 48, 0.45)
		detail(head, 0.12, 0.34, 0.26, 0.62, hairColor, 48, 0.4) -- затылок
	end
	if hairStyle == "Short" or hairStyle == "Long" or hairStyle == "Ponytail" then
		-- Длинные волосы и хвост — ещё и цепочки ниже.
		cap(0.34)
	elseif hairStyle == "Bob" then
		cap(0.36)
		detail(head, 0.2, 0.62, 0.34, 0.5, hairColor, 48, 0.4)
	elseif hairStyle == "Spiky" then
		cap(0.34)
		for index = 0, 4 do
			detail(
				head,
				0.12 + index * 0.18,
				-0.08 - (index % 2) * 0.05,
				0.14,
				0.34,
				hairColor,
				48,
				0,
				-35 + index * 10
			)
		end
	elseif hairStyle == "Mohawk" then
		for index = 0, 4 do
			detail(head, 0.2 + index * 0.15, -0.06, 0.12, 0.36, hairColor, 48, 0.3, -20 + index * 6)
		end
	elseif hairStyle == "Topknot" then
		cap(0.3)
		detail(head, 0.36, -0.12, 0.26, 0.24, hairColor, 48, 0.5) -- пучок
		detail(head, 0.36, -0.01, 0.3, 0.06, topTrim, 49)
	elseif hairStyle == "Bald" then
		detail(head, 0.58, 0.14, 0.34, 0.08, WHITE, 49, 0.5, 0, 0.75) -- блик
	end

	-- Головной убор.
	local headLook = look.head
	if headLook.hood then
		local hood = color(headLook.hood, BLACK)
		detail(head, 0.36, 0.3, 1.12, 0.84, hood, 49, 0.45)
		detail(head, 0.1, 0.72, 0.4, 0.66, hood, 49, 0.3)
	end
	if headLook.helmet then
		local metal = color(headLook.helmet, Color3.fromHex("#8A9199"))
		detail(head, 0.48, 0.2, 1.1, 0.44, metal, 49, 0.4)
		detail(head, 0.9, 0.44, 0.08, 0.34, metal, 49) -- наносник
		detail(head, 0.48, 0.34, 1.12, 0.06, metal:Lerp(WHITE, 0.35), 50)
	end
	if headLook.band then
		detail(head, 0.5, 0.3, 1.08, 0.12, color(headLook.band, WHITE), 50, 0.2)
	end
	if headLook.goggles then
		local lens = color(headLook.goggles, WHITE)
		detail(head, 0.5, 0.22, 1.08, 0.09, OUTLINE, 50)
		detail(head, 0.72, 0.2, 0.26, 0.2, lens, 51, 0.5)
		detail(head, 0.68, 0.16, 0.08, 0.06, WHITE, 52, 0.5, 0, 0.3)
	end
	if headLook.crown then
		local crown = color(headLook.crown, WHITE)
		for index = 0, 4 do
			detail(
				head,
				0.18 + index * 0.17,
				-0.1 - (if index == 2 then 0.08 else 0),
				0.09,
				0.3,
				crown,
				50,
				0,
				-18 + index * 9
			)
		end
		detail(head, 0.5, 0.04, 1.0, 0.08, crown, 51)
	end
	if headLook.headphones then
		local phones = color(headLook.headphones, WHITE)
		detail(head, 0.4, -0.02, 1.0, 0.08, phones, 51, 0.5)
		detail(head, 0.34, 0.5, 0.3, 0.36, phones, 52, 0.5)
	end
	if extras.shoulderPads then
		-- Меховые наплечники поверх плеч.
		detail(torso, 0.62, 0.06, 0.62, 0.22, color(extras.shoulderPads, WHITE):Lerp(WHITE, 0.15), 37, 0.5)
	end
	if extras.scarf then
		detail(torso, 0.5, 0.02, 1.08, 0.14, color(extras.scarf, WHITE), 37, 0.4)
	end

	-- Оружие в передней руке.
	type WeaponParts = { kind: string, shaft: Part?, tip: Part?, extra: { Part } }
	local weapon: WeaponParts? = nil
	if look.weapon then
		local w = look.weapon
		local main = color(w.color, WHITE)
		local trim = color(w.accent, WHITE)
		local kind = w.kind
		local extra: { Part } = {}
		local shaft: Part? = nil
		local tip: Part? = nil
		if kind == "Spear" or kind == "Staff" or kind == "Scythe" then
			shaft = part("WeaponShaft", main, 53, 0.5, true)
			tip = part("WeaponTip", trim, 54, if kind == "Staff" then 0.2 else 0, true)
			if kind == "Scythe" then
				for index = 1, 3 do
					table.insert(extra, part(`ScytheBlade{index}`, trim, 54, 0.3, true))
				end
			end
		elseif kind == "Katana" then
			shaft = part("KatanaBlade", main, 53, 0.3, true)
			tip = part("KatanaGuard", trim, 54, 0.3, true)
		elseif kind == "Fans" then
			for index = 1, 5 do
				table.insert(extra, part(`FanRib{index}`, if index % 2 == 0 then trim else main, 53, 0.3, false))
			end
		elseif kind == "Disc" then
			local disc = part("Disc", main, 54, 0.5, true)
			table.insert(details, newDetail(disc.frame, 0.5, 0.5, 0.5, 0.5, trim, 55, 0.5))
			tip = disc
		end
		weapon = { kind = kind, shaft = shaft, tip = tip, extra = extra }
	end

	-- Свечение магии в руках и искры вокруг.
	local glowF = part("GlowFront", element, 60, 0.5, false, false)
	local glowB = part("GlowBack", element, 19, 0.5, false, false)
	local sparks: { Part } = {}
	for index = 1, 4 do
		local spark = part(`Spark{index}`, if index % 2 == 0 then WHITE else element, 61, 0, false, false)
		table.insert(sparks, spark)
	end

	-- Ткань и волосы: цепочки с физикой.
	local chains: { { chain: Chain, anchor: string } } = {}
	local function addChain(
		name: string,
		anchor: string,
		c: Color3,
		count: number,
		length: number,
		width: number,
		taper: number,
		z: number,
		gravity: number,
		rest: Vector2
	)
		local chainParts: { Part } = {}
		local widths: { number } = {}
		for index = 1, count do
			table.insert(chainParts, part(`{name}{index}`, c, z, if name == "Cape" then 0.22 else 0.45, false))
			table.insert(widths, width * (1 - taper * (index - 1) / math.max(1, count - 1)))
		end
		local points: { Vector2 } = {}
		for _ = 0, count do
			table.insert(points, Vector2.new(0.5, 0.5))
		end
		table.insert(chains, {
			anchor = anchor,
			chain = {
				points = points,
				previous = table.clone(points),
				ready = false,
				parts = chainParts,
				length = length,
				widths = widths,
				gravity = gravity,
				drag = 0.86,
				rest = rest,
			},
		})
	end
	if extras.cape then
		local capeColor = color(extras.cape, topColor)
		addChain("Cape", "Shoulders", capeColor:Lerp(BLACK, 0.12), 5, 0.068, 0.055, -0.7, 5, 2.2, Vector2.new(-0.45, 1))
	end
	if extras.scarf then
		addChain("Scarf", "Neck", color(extras.scarf, WHITE), 5, 0.05, 0.034, 0.3, 6, 1.2, Vector2.new(-1, 0.25))
	end
	if hairStyle == "Ponytail" then
		addChain("Ponytail", "HeadBack", hairColor, 4, 0.045, 0.045, 0.45, 7, 2.2, Vector2.new(-0.6, 1))
	elseif hairStyle == "Long" then
		addChain("LongHair", "HeadBack", hairColor, 5, 0.046, 0.06, 0.45, 7, 2.6, Vector2.new(-0.3, 1))
	end
	if headLook.bandTails then
		addChain("BandTails", "HeadBack", color(headLook.band, WHITE), 3, 0.04, 0.022, 0.3, 8, 1, Vector2.new(-1, 0.3))
	end
	if headLook.plume then
		addChain("Plume", "HeadTop", color(headLook.plume, WHITE), 3, 0.04, 0.05, 0.5, 8, 0.8, Vector2.new(-1, -0.2))
	end
	if extras.sash then
		addChain("Sash", "HipBack", color(extras.sash, WHITE), 3, 0.05, 0.03, 0.2, 9, 1.8, Vector2.new(-0.5, 1))
	end

	-- Дрон-помощник (Byte): висит за спиной и покачивается.
	local drone: Part? = nil
	if extras.drone then
		local body = part("Drone", Color3.fromHex("#2A2F45"), 62, 0.3, true)
		table.insert(details, newDetail(body.frame, 0.6, 0.5, 0.36, 0.36, color(extras.drone, WHITE), 63, 0.5))
		drone = body
	end

	-- Шлейф удара.
	local trailParts: { Part } = {}
	for index = 1, TRAIL_POINTS - 1 do
		local trailPart = part(`Trail{index}`, element:Lerp(WHITE, 0.45), 70, 0.5, false, false)
		trailPart.frame.Visible = false
		table.insert(trailParts, trailPart)
	end
	local trail: { Vector2 } = {}

	----------------------------------------------------------------------------------------------
	-- Постановка
	----------------------------------------------------------------------------------------------

	local facing = 1
	local clock = 0
	local motion = Vector2.zero
	local stepDt = 1 / 60
	local flash = 0
	local tintColor = WHITE

	local function place(p: Part, cx: number, cy: number, w: number, h: number, rotation: number)
		local x = if facing >= 0 then cx else 1 - cx
		p.frame.Position = UDim2.fromScale(x, cy)
		p.frame.Size = UDim2.fromScale(w, h)
		p.frame.Rotation = if facing >= 0 then rotation else -rotation
	end

	-- Часть между двумя точками (ширина w).
	local function segment(p: Part, ax: number, ay: number, bx: number, by: number, w: number)
		local dx, dy = bx - ax, by - ay
		local length = math.sqrt(dx * dx + dy * dy)
		place(p, (ax + bx) / 2, (ay + by) / 2, w, length + w * 0.6, math.deg(math.atan2(-dx, dy)))
	end

	local function applyFacing()
		for _, d in details do
			d.frame.Position = UDim2.fromScale(if facing >= 0 then d.x else 1 - d.x, d.y)
			d.frame.Rotation = if facing >= 0 then d.rotation else -d.rotation
		end
		for _, p in parts do
			if p.gradient then
				p.gradient.Rotation = if facing >= 0 then 0 else 180
			end
		end
	end

	-- Точки цепочек в пространстве «вправо» (для отрисовки отражаются вместе со всем).
	local anchors: { [string]: Vector2 } = {}

	local MAX_STEP = 0.025 -- ткань не «выстреливает» от резких рывков

	local function stepChain(chain: Chain, anchor: Vector2)
		local points, previous = chain.points, chain.previous
		if not chain.ready or (points[1] - anchor).Magnitude > 0.2 then
			-- Первый кадр или телепорт: повесить свободно от якоря.
			chain.ready = true
			for index = 1, #points do
				local point = anchor + chain.rest.Unit * chain.length * (index - 1)
				points[index] = point
				previous[index] = point
			end
		end
		points[1] = anchor
		previous[1] = anchor
		local dt = math.min(stepDt, 1 / 30)
		-- Ветер: ткань отстаёт от движения бойца (в пространстве «вправо»).
		local wind = Vector2.new(-motion.X * 0.012, -motion.Y * 0.006)
		local pull = (chain.rest.Unit * chain.gravity + wind) * dt * dt
		for index = 2, #points do
			local current = points[index]
			local velocity = (current - previous[index]) * chain.drag
			if velocity.Magnitude > MAX_STEP then
				velocity = velocity.Unit * MAX_STEP
			end
			previous[index] = current
			points[index] = current + velocity + pull
		end
		for _ = 1, 3 do
			for index = 2, #points do
				local a, b = points[index - 1], points[index]
				local delta = b - a
				local distance = delta.Magnitude
				if distance > 1e-6 then
					points[index] = a + delta / distance * chain.length
				else
					points[index] = a + chain.rest.Unit * chain.length
				end
			end
		end
		for index, p in chain.parts do
			local a, b = points[index], points[index + 1]
			segment(p, a.X, a.Y, b.X, b.Y, chain.widths[index])
		end
	end

	local function samplePose(animation: Types.AnimationName, time: number, progress: number?): Pose
		local keys = RigPoses.keys(animation, def)
		local count = #keys
		if count == 1 then
			return keys[1]
		end
		local animationDef = Animations.defaults[animation]
		local position: number
		if progress ~= nil then
			position = math.clamp(progress, 0, 1) * (count - 1)
		else
			position = time * (if animationDef then animationDef.fps else 6)
			if animationDef == nil or animationDef.loop then
				position %= count
			else
				position = math.min(position, count - 1)
			end
		end
		local index = math.floor(position)
		local loop = animationDef ~= nil and animationDef.loop and progress == nil
		local nextIndex = if index + 1 > count - 1 then (if loop then 0 else index) else index + 1
		return RigPoses.lerp(keys[index + 1], keys[nextIndex + 1], position - index)
	end

	local function show(animation: Types.AnimationName, time: number, progress: number?)
		local pose = samplePose(animation, time, progress)
		local d = dims

		-- Высота бёдер: по нижней ступне, если в позе не задана.
		local function reach(h: number, k: number): number
			local _, c1 = dir(h)
			local _, c2 = dir(h - k)
			return d.thigh * c1 + d.shin * c2 + d.footH
		end
		local hipY = pose.hip or (GROUND - math.max(reach(pose.hF, pose.kF), reach(pose.hB, pose.kB)))
		hipY += pose.drop or 0
		local hipX = 0.5 + (pose.x or 0)

		local upX, upY = dir(pose.lean)
		upY = -upY -- «вверх» по корпусу
		local shoulderX, shoulderY = hipX + upX * d.torsoLen, hipY + upY * d.torsoLen
		local neckX, neckY = shoulderX + upX * d.neck, shoulderY + upY * d.neck
		local headAngle = pose.lean + (pose.head or 0)
		local hx, hy = dir(headAngle)
		local headX, headY = neckX + hx * d.head * 0.5, neckY - hy * d.head * 0.5

		-- Конечности: от сустава к концу.
		local function limbEnd(x: number, y: number, angle: number, length: number): (number, number)
			local sx, cy = dir(angle)
			return x + sx * length, y + cy * length
		end
		local shoulderFX, shoulderFY = shoulderX + 0.012, shoulderY + 0.012
		local shoulderBX, shoulderBY = shoulderX - 0.014, shoulderY + 0.006
		local elbowFX, elbowFY = limbEnd(shoulderFX, shoulderFY, pose.sF, d.upperArm)
		local handFX, handFY = limbEnd(elbowFX, elbowFY, pose.sF + pose.eF, d.foreArm)
		local elbowBX, elbowBY = limbEnd(shoulderBX, shoulderBY, pose.sB, d.upperArm)
		local handBX, handBY = limbEnd(elbowBX, elbowBY, pose.sB + pose.eB, d.foreArm)
		local hipFX, hipFY = hipX + 0.014, hipY
		local hipBX, hipBY = hipX - 0.014, hipY
		local kneeFX, kneeFY = limbEnd(hipFX, hipFY, pose.hF, d.thigh)
		local ankleFX, ankleFY = limbEnd(kneeFX, kneeFY, pose.hF - pose.kF, d.shin)
		local kneeBX, kneeBY = limbEnd(hipBX, hipBY, pose.hB, d.thigh)
		local ankleBX, ankleBY = limbEnd(kneeBX, kneeBY, pose.hB - pose.kB, d.shin)

		-- Поворот всего тела (сальто, вертушка) вокруг середины корпуса.
		local rot = pose.rot or 0
		local pivotX, pivotY = (hipX + shoulderX) / 2, (hipY + shoulderY) / 2
		local function r(x: number, y: number): (number, number)
			return rotateAround(x, y, pivotX, pivotY, rot)
		end
		hipX, hipY = r(hipX, hipY)
		shoulderX, shoulderY = r(shoulderX, shoulderY)
		neckX, neckY = r(neckX, neckY)
		headX, headY = r(headX, headY)
		shoulderFX, shoulderFY = r(shoulderFX, shoulderFY)
		shoulderBX, shoulderBY = r(shoulderBX, shoulderBY)
		elbowFX, elbowFY = r(elbowFX, elbowFY)
		handFX, handFY = r(handFX, handFY)
		elbowBX, elbowBY = r(elbowBX, elbowBY)
		handBX, handBY = r(handBX, handBY)
		hipFX, hipFY = r(hipFX, hipFY)
		hipBX, hipBY = r(hipBX, hipBY)
		kneeFX, kneeFY = r(kneeFX, kneeFY)
		ankleFX, ankleFY = r(ankleFX, ankleFY)
		kneeBX, kneeBY = r(kneeBX, kneeBY)
		ankleBX, ankleBY = r(ankleBX, ankleBY)
		local bodyAngle = pose.lean + rot

		-- Ноги.
		local legW = if wide then d.legW * 1.35 else d.legW
		local shinW = if wide then d.shinW * 1.25 else d.shinW
		segment(thighB, hipBX, hipBY, kneeBX, kneeBY, legW)
		segment(shinB, kneeBX, kneeBY, ankleBX, ankleBY, shinW)
		segment(thighF, hipFX, hipFY, kneeFX, kneeFY, legW)
		segment(shinF, kneeFX, kneeFY, ankleFX, ankleFY, shinW)
		-- Стопы: носок вперёд, по наклону голени.
		local function foot(p: Part, ax: number, ay: number, shinAngle: number)
			local footAngle = shinAngle * 0.35 + rot
			local fx, fy = dir(footAngle + 90)
			local cx, cy = ax + fx * d.footL * 0.3, ay + fy * d.footL * 0.3 + d.footH * 0.35
			place(p, cx, cy, d.footL, d.footH, -footAngle)
		end
		foot(footB, ankleBX, ankleBY, pose.hB - pose.kB)
		foot(footF, ankleFX, ankleFY, pose.hF - pose.kF)

		-- Таз, корпус, шея, голова.
		place(pelvis, hipX, hipY, d.torsoW * 0.95, d.legW * 1.1, bodyAngle)
		local torsoCX, torsoCY = (hipX + shoulderX) / 2, (hipY + shoulderY) / 2
		place(torso, torsoCX, torsoCY, d.torsoW, d.torsoLen + d.legW * 0.4, bodyAngle)
		segment(neck, shoulderX, shoulderY, neckX, neckY, d.foreW * 0.9)
		place(head, headX, headY, d.head, d.head * 1.06, headAngle + rot)
		local robeSkirt = skirt
		if robeSkirt then
			-- Подол халата: от бёдер до колен, по среднему направлению ног.
			local kx, ky = (kneeFX + kneeBX) / 2, (kneeFY + kneeBY) / 2
			local length = math.sqrt((kx - hipX) ^ 2 + (ky - hipY) ^ 2) + d.shin * 0.45
			local angle = math.deg(math.atan2(-(kx - hipX), ky - hipY))
			local rx, ry = dir(-angle)
			place(robeSkirt, hipX + rx * length * 0.5, hipY + ry * length * 0.5, d.torsoW * 1.25, length, angle)
		end

		-- Руки.
		segment(armB, shoulderBX, shoulderBY, elbowBX, elbowBY, d.armW)
		segment(foreB, elbowBX, elbowBY, handBX, handBY, d.foreW)
		segment(armF, shoulderFX, shoulderFY, elbowFX, elbowFY, d.armW)
		segment(foreF, elbowFX, elbowFY, handFX, handFY, d.foreW * (if look.top.style == "Robe" then 1.25 else 1))
		local handSize = d.hand * (if look.bigGloves then 1.55 else 1) * (if pose.open then 0.95 else 1)
		place(handB, handBX, handBY, handSize, handSize * (if pose.open then 1.25 else 1), -(pose.sB + pose.eB + rot))
		place(handF, handFX, handFY, handSize, handSize * (if pose.open then 1.25 else 1), -(pose.sF + pose.eF + rot))

		-- Оружие: по направлению предплечья передней руки.
		local foreAngle = pose.sF + pose.eF + rot
		local wx, wy = dir(foreAngle)
		local weaponTipX, weaponTipY = handFX, handFY
		local w = weapon
		if w then
			if w.kind == "Spear" or w.kind == "Staff" or w.kind == "Scythe" then
				local back, front = 0.14, if w.kind == "Spear" then 0.4 else 0.34
				local ax, ay = handFX - wx * back, handFY - wy * back
				local bx, by = handFX + wx * front, handFY + wy * front
				segment(w.shaft :: Part, ax, ay, bx, by, 0.018)
				weaponTipX, weaponTipY = bx, by
				local tipSize = if w.kind == "Staff" then 0.05 else 0.042
				place(w.tip :: Part, bx + wx * 0.02, by + wy * 0.02, tipSize, tipSize * 1.4, -foreAngle + 45)
				if w.kind == "Scythe" then
					-- Лезвие косы — изогнутое назад от верхнего конца.
					local px, py = bx, by
					for index, bladePart in w.extra do
						local angle = foreAngle - 100 - index * 25
						local sx, sy = dir(angle)
						local nx, ny = px + sx * 0.05, py + sy * 0.05
						segment(bladePart, px, py, nx, ny, 0.028 - index * 0.005)
						px, py = nx, ny
					end
				end
			elseif w.kind == "Katana" then
				local bx, by = handFX + wx * 0.3, handFY + wy * 0.3
				segment(w.shaft :: Part, handFX + wx * 0.03, handFY + wy * 0.03, bx, by, 0.02)
				place(w.tip :: Part, handFX + wx * 0.025, handFY + wy * 0.025, 0.05, 0.016, -foreAngle)
				weaponTipX, weaponTipY = bx, by
			elseif w.kind == "Fans" then
				for index, rib in w.extra do
					local angle = foreAngle - 40 + (index - 1) * 20
					local sx, sy = dir(angle)
					segment(rib, handFX, handFY, handFX + sx * 0.09, handFY + sy * 0.09, 0.02)
				end
			elseif w.kind == "Disc" then
				local disc = w.tip :: Part
				place(disc, handFX + wx * 0.03, handFY + wy * 0.03, 0.07, 0.07, clock * 360)
			end
		end

		-- Якоря ткани.
		anchors.Shoulders = Vector2.new(shoulderX - upX * 0.01 - 0.02, shoulderY + 0.01)
		anchors.Neck = Vector2.new(neckX - 0.02, neckY + 0.01)
		local backX, backY = dir(headAngle + rot - 90)
		anchors.HeadBack = Vector2.new(headX + backX * d.head * 0.45, headY - backY * d.head * 0.1)
		anchors.HeadTop = Vector2.new(headX - 0.01, headY - d.head * 0.55)
		anchors.HipBack = Vector2.new(hipX - d.torsoW * 0.45, hipY)
		for _, entry in chains do
			stepChain(entry.chain, anchors[entry.anchor] or Vector2.new(hipX, hipY))
		end

		-- Дрон.
		local droneRig = drone
		if droneRig then
			place(
				droneRig,
				shoulderX - 0.12,
				shoulderY - 0.06 + math.sin(clock * 3) * 0.015,
				0.06,
				0.04,
				math.sin(clock * 2) * 8
			)
		end

		-- Магия в руках.
		local glowAmount = pose.glow or 0
		glowF.frame.Visible = glowAmount > 0.02
		glowB.frame.Visible = glowAmount > 0.02
		if glowAmount > 0.02 then
			local size = 0.04 + glowAmount * 0.06 + math.sin(clock * 20) * 0.006
			place(glowF, handFX, handFY, size, size, 0)
			place(glowB, handBX, handBY, size * 0.8, size * 0.8, 0)
			glowF.frame.BackgroundTransparency = 1 - glowAmount * 0.6
			glowB.frame.BackgroundTransparency = 1 - glowAmount * 0.45
		end
		for index, spark in sparks do
			local visible = glowAmount > 0.3
			spark.frame.Visible = visible
			if visible then
				local angle = clock * 6 + index * math.pi / 2
				local radius = 0.04 + glowAmount * 0.03
				local size = 0.012 + (index % 2) * 0.006
				place(
					spark,
					handFX + math.cos(angle) * radius,
					handFY + math.sin(angle) * radius,
					size,
					size,
					clock * 200
				)
				spark.frame.BackgroundTransparency = 0.2 + 0.3 * math.sin(clock * 15 + index)
			end
		end
		-- Аура вокруг тела (суперы).
		local auraAmount = pose.aura or 0
		aura.frame.Visible = auraAmount > 0.02
		if auraAmount > 0.02 then
			local pulse = 1 + math.sin(clock * 12) * 0.05
			place(aura, hipX, hipY - 0.1, (d.torsoW + 0.22) * pulse, (d.torsoLen + 0.5) * pulse, 0)
			aura.frame.BackgroundTransparency = 1 - auraAmount * 0.6
		end

		-- Шлейф удара: копим точки конца ударной конечности.
		local strike = pose.strike
		if strike then
			local px, py = handFX, handFY
			if strike == "handB" then
				px, py = handBX, handBY
			elseif strike == "footF" then
				px, py = ankleFX, ankleFY
			elseif strike == "footB" then
				px, py = ankleBX, ankleBY
			elseif strike == "weapon" then
				px, py = weaponTipX, weaponTipY
			end
			table.insert(trail, 1, Vector2.new(px, py))
			if #trail > TRAIL_POINTS then
				table.remove(trail)
			end
		elseif #trail > 0 then
			table.remove(trail)
		end
		for index, trailPart in trailParts do
			local a, b = trail[index], trail[index + 1]
			if a and b and (a - b).Magnitude > 0.002 then
				trailPart.frame.Visible = true
				local fade = (index - 1) / (TRAIL_POINTS - 1)
				segment(trailPart, a.X, a.Y, b.X, b.Y, 0.045 * (1 - fade * 0.7))
				trailPart.frame.BackgroundTransparency = 0.25 + fade * 0.65
			else
				trailPart.frame.Visible = false
			end
		end
	end

	local rig = {} :: Rig
	rig.root = root
	rig.show = show
	function rig.setFacing(newFacing: number)
		local value = if newFacing < 0 then -1 else 1
		if value ~= facing then
			facing = value
			applyFacing()
		end
	end
	function rig.update(dt: number, vx: number, vy: number)
		stepDt = dt
		clock += dt
		motion = Vector2.new(vx * facing, vy)
	end
	local function tint(target: Color3, amount: number)
		local t = math.clamp(amount, 0, 1)
		if t == flash and target == tintColor then
			return
		end
		flash = t
		tintColor = target
		for _, p in parts do
			p.frame.BackgroundColor3 = p.base:Lerp(target, t)
		end
		for _, d in details do
			local base = d.base
			if base then
				(d.frame :: Frame).BackgroundColor3 = base:Lerp(target, t)
			end
		end
	end
	-- Вспышка при получении удара: все части светлеют.
	function rig.setFlash(amount: number)
		tint(WHITE, amount)
	end
	function rig.setTint(target: Color3, amount: number)
		tint(target, amount)
	end
	function rig.destroy()
		root:Destroy()
	end

	applyFacing()
	show(IDLE, 0, nil)
	-- Ткань «успокаивается» в покое, чтобы с первого кадра висеть естественно.
	for _ = 1, 30 do
		show(IDLE, 0, nil)
	end
	return rig
end

return Rig
