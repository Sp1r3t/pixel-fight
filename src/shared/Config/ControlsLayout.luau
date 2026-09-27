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

export type ControlId = "Joystick" | "Light" | "Heavy" | "Special" | "Super" | "Dash" | "Jump" | "Block"
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

local CONTROL_IDS: { string } = { "Joystick", "Light", "Heavy", "Special", "Super", "Dash", "Jump", "Block" }

-- Базовый диаметр (логические пиксели) при size = 1.
local BASE_SIZE: { [string]: number } = {
	Joystick = 160,
	Light = 100,
	Heavy = 100,
	Special = 80,
	Super = 86,
	Dash = 64,
	Jump = 80,
	Block = 76,
}

-- Какому краю экрана принадлежит элемент.
local SIDE: { [string]: "Left" | "Right" } = {
	Joystick = "Left",
	Light = "Right",
	Heavy = "Right",
	Special = "Right",
	Super = "Right",
	Dash = "Right",
	Jump = "Right",
	Block = "Right",
}

--[[
	Раскладка по умолчанию (версия 3) — компактная дуга у правого нижнего угла под большой палец:
	  • крупные «Рука» и «Нога» — ближе всего к пальцу, «Прыжок» — в самом углу, «Блок» — слева от «Руки»;
	  • «Приём» — по диагонали, «Супер» — вверху у правого края (нужен редко, случайно не нажмёшь);
	  • «Рывок» по умолчанию спрятан: рывок делается двойным толчком джойстика (включается в настройках).
	Середина экрана выше пола свободна — там стоят бойцы (камера с сенсорным управлением держит пол
	на 25% высоты). Кнопки не перекрываются и не заходят в зону бойцов — это проверяют тесты.
]]
local DEFAULT: Layout = {
	version = 3,
	mode = "Auto",
	opacity = 0.6,
	dashButton = false,
	controls = {
		Joystick = { x = 135, y = 130, size = 1 },
		Light = { x = 175, y = 75, size = 1 },
		Heavy = { x = 75, y = 165, size = 1 },
		Jump = { x = 65, y = 55, size = 1 },
		Block = { x = 280, y = 70, size = 1 },
		Special = { x = 190, y = 190, size = 1 },
		Super = { x = 75, y = 280, size = 1 },
		Dash = { x = 290, y = 180, size = 1 },
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
	if type(raw.version) == "number" and raw.version < DEFAULT.version then
		-- Старая раскладка (до компактной дуги) — берём новую по умолчанию, режим показа сохраняем.
		if raw.mode == "Auto" or raw.mode == "Always" or raw.mode == "Never" then
			result.mode = raw.mode
		end
		return result
	end
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

-- Пары элементов одной стороны экрана, которые перекрываются (для проверки раскладки).
function ControlsLayout.overlaps(layout: Layout): { { string } }
	local result: { { string } } = {}
	for i, a in CONTROL_IDS do
		for j = i + 1, #CONTROL_IDS do
			local b = CONTROL_IDS[j]
			local pa, pb = layout.controls[a], layout.controls[b]
			if pa and pb and SIDE[a] == SIDE[b] then
				local distance = math.sqrt((pa.x - pb.x) ^ 2 + (pa.y - pb.y) ^ 2)
				if distance < (ControlsLayout.diameter(layout, a) + ControlsLayout.diameter(layout, b)) / 2 then
					table.insert(result, { a, b })
				end
			end
		end
	end
	return result
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
	overlaps = ControlsLayout.overlaps,
})
