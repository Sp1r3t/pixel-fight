--!strict
--[[
	CameraController — боковая 2D-камера.

	  • Scriptable-камера смотрит строго вдоль −Z, узкий FOV → почти ортографическая картинка;
	  • в кадре всегда все бойцы: камера следит за центром между ними и плавно отъезжает,
	    когда они расходятся (в 2 на 2 — как в Brawlhalla, до всей сцены); не выходит за края арены;
	  • пол всегда в нижней части кадра; верхние HUD_FRACTION кадра заняты интерфейсом — бойцы туда
	    не заходят: при высоком прыжке камера приподнимается (1 на 1) или отъезжает (2 на 2);
	  • тряска (shake) — затухающее смещение; её вызывает EffectsController при ударах;
	  • с сенсорным управлением (setTouchFraming) кнопки занимают низ экрана у краёв: пол в кадре
	    выше, а запас по бокам больше — бойцы стоят над кнопками и ближе к центру, их не закрывает.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Stage = require(ReplicatedStorage.Shared.Combat.Stage)

local FOV = 30 -- вертикальный угол обзора
local MIN_VIEW_WIDTH = 20 -- студов по горизонтали
local VIEW_MARGIN = 12 -- запас по краям вокруг бойцов
local FLOOR_FRACTION = 0.15 -- пол на такой доле высоты кадра снизу
local HUD_FRACTION = 0.22 -- верх кадра под полосами здоровья и таймером
local FOLLOW_SPEED = 7
local EDGE_MARGIN = 1.5
-- С сенсорным управлением.
local TOUCH_FLOOR_FRACTION = 0.25
local TOUCH_VIEW_MARGIN = 18

type Shake = { amplitude: number, duration: number, age: number, seed: number }

local CameraController = {
	Name = "CameraController",
}

local inFight = false
local snapNext = true
local current = { x = 0, y = 5, distance = 60 }
local target = { x = 0, y = 5, distance = 60 }
local shakes: { Shake } = {}
local shakeSeed = 0
-- Постановка ролика супера: камера наезжает на точку (x, y) с шириной кадра width.
local override: { x: number, y: number, width: number }? = nil
-- Параметры сцены текущего боя.
local maxViewWidth = Stage.get("Duel").cameraMaxWidth
local minViewHeight = Stage.get("Duel").cameraMinHeight
local fitViewHeight: number? = nil
local arenaEdge = Stage.get("Duel").halfWidth + EDGE_MARGIN
-- На экране сенсорные кнопки.
local touchFraming = false

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function viewTangents(camera: Camera): (number, number)
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanV = math.tan(math.rad(FOV / 2))
	return tanV, tanV * aspect
end

function CameraController.enterFight(stageId: string?)
	local layout = Stage.get(stageId)
	maxViewWidth = layout.cameraMaxWidth
	minViewHeight = layout.cameraMinHeight
	fitViewHeight = layout.cameraFitHeight
	arenaEdge = layout.halfWidth + EDGE_MARGIN
	inFight = true
	snapNext = true
	table.clear(shakes)
	local camera = getCamera()
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FOV
	end
end

function CameraController.exitFight()
	inFight = false
	override = nil
	table.clear(shakes)
end

function CameraController.isInFight(): boolean
	return inFight
end

--[[
	Задать, что должно быть в кадре: горизонтальный отрезок [minX, maxX] и самая высокая точка topY.
	Вызывается каждый кадр боя.
]]
function CameraController.setFocus(minX: number, maxX: number, topY: number)
	local camera = getCamera()
	if camera == nil then
		return
	end
	local tanV, tanH = viewTangents(camera)
	local focus = override
	if focus then
		local distance = focus.width / (2 * tanH)
		target.x, target.y, target.distance = focus.x, focus.y, distance
		return
	end
	local floorFraction = if touchFraming then TOUCH_FLOOR_FRACTION else FLOOR_FRACTION
	local margin = if touchFraming then TOUCH_VIEW_MARGIN else VIEW_MARGIN
	local width = math.clamp(maxX - minX + margin, MIN_VIEW_WIDTH, maxViewWidth)
	local distance = math.max(width / (2 * tanH), minViewHeight / (2 * tanV))
	local highest = topY + 1
	local fit = fitViewHeight
	if fit then
		-- Все между полом и HUD: при высоких прыжках камера отъезжает (не больше fit).
		local needed = math.min(highest / (1 - HUD_FRACTION - floorFraction), fit)
		distance = math.max(distance, needed / (2 * tanV))
	end
	local halfWidth = distance * tanH
	local halfHeight = distance * tanV

	local centerX = (minX + maxX) / 2
	local limit = arenaEdge - halfWidth
	centerX = if limit > 0 then math.clamp(centerX, -limit, limit) else 0

	-- Пол на floorFraction от низа кадра; если кто-то поднялся выше границы HUD — поднимаемся.
	local centerY = halfHeight * (1 - 2 * floorFraction)
	local headroom = halfHeight * (1 - 2 * HUD_FRACTION)
	if highest > centerY + headroom then
		centerY = highest - headroom
	end

	target.x, target.y, target.distance = centerX, centerY, distance
	if snapNext then
		current.x, current.y, current.distance = centerX, centerY, distance
		snapNext = false
	end
end

-- Сенсорные кнопки на экране: бойцы держатся выше и ближе к центру кадра.
function CameraController.setTouchFraming(enabled: boolean)
	touchFraming = enabled
end

function CameraController.getTouchFraming(): boolean
	return touchFraming
end

-- Наезд камеры на время ролика супера (nil — вернуть обычное слежение).
function CameraController.setOverride(x: number?, y: number?, width: number?)
	if x and y and width then
		override = { x = x, y = y, width = width }
	else
		override = nil
	end
end

-- Тряска камеры: amplitude в студах, duration в секундах.
function CameraController.shake(amplitude: number, duration: number)
	shakeSeed += 1
	table.insert(shakes, { amplitude = amplitude, duration = math.max(duration, 0.01), age = 0, seed = shakeSeed })
end

local function shakeOffset(dt: number): (number, number)
	local ox, oy = 0, 0
	for index = #shakes, 1, -1 do
		local shake = shakes[index]
		shake.age += dt
		if shake.age >= shake.duration then
			table.remove(shakes, index)
		else
			local strength = shake.amplitude * (1 - shake.age / shake.duration) ^ 2
			local t = shake.age * 60 + shake.seed * 17.3
			ox += math.sin(t * 1.7) * strength
			oy += math.cos(t * 2.3) * strength * 0.7
		end
	end
	return ox, oy
end

local function onRenderStep(dt: number)
	if not inFight then
		return
	end
	local camera = getCamera()
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local alpha = 1 - math.exp(-FOLLOW_SPEED * dt)
	current.x += (target.x - current.x) * alpha
	current.y += (target.y - current.y) * alpha
	current.distance += (target.distance - current.distance) * alpha

	local ox, oy = shakeOffset(dt)
	local position = Vector3.new(current.x + ox, current.y + oy, current.distance)
	local lookAt = Vector3.new(current.x + ox, current.y + oy, 0)
	camera.CFrame = CFrame.lookAt(position, lookAt)
end

function CameraController.Init() end

function CameraController.Start()
	RunService:BindToRenderStep("PixelFightCamera", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

return CameraController
