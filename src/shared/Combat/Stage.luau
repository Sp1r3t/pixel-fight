--!strict
--[[
	Stage — геометрия сцены боя (не путать с аренами: арена — только внешний вид).

	  Duel      — классический 1 на 1: ровный пол, бойцы толкаются, не расходятся дальше MaxSeparation.
	  TwoFloors — 2 на 2 в духе Brawlhalla: пол внизу и второй этаж слева и справа, по центру — дыра.
	              Нижние бойцы (слоты 1, 2) начинают внизу, верхние (3, 4) — на втором этаже.
	              Бойцы проходят сквозь друг друга, есть двойной прыжок и управление в воздухе:
	              снизу можно запрыгнуть наверх через дыру, сверху — спрыгнуть в неё.

	Платформа твёрдая: на неё приземляются сверху, снизу о неё бьются головой (потолок).
	Опора считается по центру бойца: за краем платформы боец падает.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local Physics = GameConfig.Physics

export type Platform = {
	left: number,
	right: number,
	top: number, -- высота верхней поверхности
	thickness: number,
}

export type Spawn = {
	x: number,
	y: number,
}

export type Layout = {
	id: string,
	halfWidth: number, -- стены арены
	platforms: { Platform },
	spawns: { Spawn }, -- по слотам
	pushboxes: boolean, -- бойцы-противники толкаются (1 на 1) или проходят сквозь (2 на 2)
	maxSeparation: number?, -- бойцы не расходятся дальше (камера 1 на 1)
	airJumps: number, -- дополнительных прыжков в воздухе
	airControl: boolean, -- можно менять направление в прыжке
	cameraMinHeight: number, -- минимальная высота кадра камеры (студы)
	cameraMaxWidth: number, -- максимальная ширина кадра (все бойцы в кадре)
	-- 2 на 2: камера отъезжает, чтобы все бойцы поместились между полом и HUD (до этой высоты кадра);
	-- nil — только поднимается за прыгнувшим (1 на 1).
	cameraFitHeight: number?,
}

local EPSILON = 1e-4

local LAYOUTS: { [string]: Layout } = {
	Duel = {
		id = "Duel",
		halfWidth = Physics.ArenaHalfWidth,
		platforms = {},
		spawns = {
			{ x = -Physics.StartDistance / 2, y = 0 },
			{ x = Physics.StartDistance / 2, y = 0 },
		},
		pushboxes = true,
		maxSeparation = Physics.MaxSeparation,
		airJumps = 0,
		airControl = false,
		cameraMinHeight = 15,
		cameraMaxWidth = 34,
		cameraFitHeight = nil,
	},
	TwoFloors = {
		id = "TwoFloors",
		halfWidth = 24,
		platforms = {
			{ left = -24, right = -3, top = 9, thickness = 0.8 },
			{ left = 3, right = 24, top = 9, thickness = 0.8 },
		},
		spawns = {
			{ x = -9, y = 0 }, -- 1: команда 1, низ
			{ x = 9, y = 0 }, -- 2: команда 2, низ
			{ x = -12, y = 9 }, -- 3: команда 1, верх
			{ x = 12, y = 9 }, -- 4: команда 2, верх
		},
		pushboxes = false,
		maxSeparation = nil,
		airJumps = 1,
		airControl = true,
		cameraMinHeight = 24,
		cameraMaxWidth = 54,
		cameraFitHeight = 34,
	},
}

local Stage = {}

Stage.LAYOUTS = deepFreeze(LAYOUTS)

function Stage.get(id: string?): Layout
	return Stage.LAYOUTS[id or "Duel"] or Stage.LAYOUTS.Duel
end

-- Высота самой высокой поверхности под точкой (x, y): пол (0) или верх платформы не выше y.
function Stage.floorBelow(layout: Layout, x: number, y: number): number
	local best = 0
	for _, platform in layout.platforms do
		if x >= platform.left and x <= platform.right and platform.top <= y + EPSILON and platform.top > best then
			best = platform.top
		end
	end
	return best
end

-- Нижняя грань платформы, которую голова пересекла при движении вверх (nil — не ударились).
function Stage.ceilingCrossed(layout: Layout, x: number, headBefore: number, headAfter: number): number?
	for _, platform in layout.platforms do
		local bottom = platform.top - platform.thickness
		if x >= platform.left and x <= platform.right and headBefore <= bottom + EPSILON and headAfter > bottom then
			return bottom
		end
	end
	return nil
end

-- Платформа, на которой стоит точка (x, y); nil — пол или воздух.
function Stage.platformAt(layout: Layout, x: number, y: number): Platform?
	for _, platform in layout.platforms do
		if x >= platform.left and x <= platform.right and math.abs(platform.top - y) <= EPSILON then
			return platform
		end
	end
	return nil
end

-- «Этаж» по высоте опоры: 0 — пол, 1 — второй этаж.
function Stage.levelOf(layout: Layout, floorY: number): number
	local lowest = math.huge
	for _, platform in layout.platforms do
		lowest = math.min(lowest, platform.top)
	end
	return if floorY >= lowest - 1 then 1 else 0
end

-- Центр дыры между платформами (куда прыгать/падать, чтобы сменить этаж); nil — этажей нет.
function Stage.holeCenter(layout: Layout): number?
	if #layout.platforms < 2 then
		return nil
	end
	local left, right = -math.huge, math.huge
	for _, platform in layout.platforms do
		if platform.right <= 0 then
			left = math.max(left, platform.right)
		elseif platform.left >= 0 then
			right = math.min(right, platform.left)
		end
	end
	if left == -math.huge or right == math.huge then
		return nil
	end
	return (left + right) / 2
end

function Stage.wall(layout: Layout): number
	return layout.halfWidth - Physics.PushWidth / 2
end

return Stage
