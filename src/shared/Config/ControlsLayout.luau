--!strict
--[[
	Раскладка сенсорного управления (телефон), настраивается игроком и хранится в профиле.

	Координаты — в «логических» пикселях интерфейса (макет 960×540, масштабируется под экран):
	  x — расстояние центра элемента от ЕГО края экрана (джойстик — от левого, кнопки — от правого);
	  y — расстояние центра от нижнего края экрана;
	  size — множитель базового размера.
	sanitize() приводит любые присланные клиентом данные к допустимым значениям (сервер доверяет только ей).
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type ControlId = "Joystick" | "Light" | "Heavy" | "Special" | "Super" | "Dash"
export type ShowMode = "Auto" | "Always" | "Never"

export type Placement = {
	x: number,
	y: number,
	size: number,
}

export type Layout = {
	version: number,
	mode: ShowMode,
	opacity: number, -- непрозрачность кнопок 0.2..0.9
	dashButton: boolean,
	controls: { [string]: Placement },
}

local CONTROL_IDS: { string } = { "Joystick", "Light", "Heavy", "Special", "Super", "Dash" }

-- Базовый диаметр (логические пиксели) при size = 1.
local BASE_SIZE: { [string]: number } = {
	Joystick = 170,
	Light = 104,
	Heavy = 104,
	Special = 86,
	Super = 86,
	Dash = 64,
}

-- Какому краю экрана принадлежит элемент.
local SIDE: { [string]: "Left" | "Right" } = {
	Joystick = "Left",
	Light = "Right",
	Heavy = "Right",
	Special = "Right",
	Super = "Right",
	Dash = "Right",
}

local DEFAULT: Layout = {
	version = 1,
	mode = "Auto",
	opacity = 0.55,
	dashButton = true,
	controls = {
		Joystick = { x = 140, y = 140, size = 1 },
		Light = { x = 190, y = 90, size = 1 },
		Heavy = { x = 80, y = 150, size = 1 },
		Special = { x = 250, y = 200, size = 1 },
		Super = { x = 130, y = 270, size = 1 },
		Dash = { x = 300, y = 80, size = 1 },
	},
}

local LIMITS = {
	minSize = 0.6,
	maxSize = 1.6,
	minOpacity = 0.2,
	maxOpacity = 0.9,
	maxX = 700,
	maxY = 480,
	minEdge = 20,
}

local ControlsLayout = {}

ControlsLayout.IDS = table.freeze(CONTROL_IDS)
ControlsLayout.BASE_SIZE = table.freeze(BASE_SIZE)
ControlsLayout.SIDE = table.freeze(SIDE)
ControlsLayout.LIMITS = table.freeze(LIMITS)

local function copyLayout(layout: Layout): Layout
	local controls: { [string]: Placement } = {}
	for id, placement in layout.controls do
		controls[id] = { x = placement.x, y = placement.y, size = placement.size }
	end
	return {
		version = layout.version,
		mode = layout.mode,
		opacity = layout.opacity,
		dashButton = layout.dashButton,
		controls = controls,
	}
end

-- Новая копия раскладки по умолчанию (можно изменять).
function ControlsLayout.default(): Layout
	return copyLayout(DEFAULT)
end

function ControlsLayout.copy(layout: Layout): Layout
	return copyLayout(layout)
end

local function number(value: unknown, fallback: number, min: number, max: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, min, max)
end

--[[
	Привести недоверенные данные к корректной раскладке. Неизвестные поля отбрасываются,
	числа ограничиваются допустимыми диапазонами, отсутствующее берётся из раскладки по умолчанию.
]]
function ControlsLayout.sanitize(data: unknown): Layout
	local result = ControlsLayout.default()
	if type(data) ~= "table" then
		return result
	end
	local raw = data :: { [any]: any }
	if raw.mode == "Auto" or raw.mode == "Always" or raw.mode == "Never" then
		result.mode = raw.mode
	end
	result.opacity = number(raw.opacity, result.opacity, LIMITS.minOpacity, LIMITS.maxOpacity)
	if type(raw.dashButton) == "boolean" then
		result.dashButton = raw.dashButton
	end
	local controls = raw.controls
	if type(controls) == "table" then
		for _, id in CONTROL_IDS do
			local placement = (controls :: any)[id]
			if type(placement) == "table" then
				local fallback = result.controls[id]
				local size = number(placement.size, fallback.size, LIMITS.minSize, LIMITS.maxSize)
				local radius = BASE_SIZE[id] * size / 2
				result.controls[id] = {
					x = number(placement.x, fallback.x, LIMITS.minEdge + radius * 0.5, LIMITS.maxX),
					y = number(placement.y, fallback.y, LIMITS.minEdge + radius * 0.5, LIMITS.maxY),
					size = size,
				}
			end
		end
	end
	return result
end

-- Диаметр элемента с учётом масштаба.
function ControlsLayout.diameter(layout: Layout, id: string): number
	local placement = layout.controls[id]
	return BASE_SIZE[id] * (if placement then placement.size else 1)
end

return deepFreeze({
	IDS = ControlsLayout.IDS,
	BASE_SIZE = ControlsLayout.BASE_SIZE,
	SIDE = ControlsLayout.SIDE,
	LIMITS = ControlsLayout.LIMITS,
	default = ControlsLayout.default,
	copy = ControlsLayout.copy,
	sanitize = ControlsLayout.sanitize,
	diameter = ControlsLayout.diameter,
})
