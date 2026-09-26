--!strict
--[[
	CameraController — боковая 2D-камера.

	  • Scriptable-камера смотрит строго вдоль −Z, узкий FOV → почти ортографическая картинка;
	  • в кадре всегда оба бойца: камера следит за центром между ними и плавно отъезжает,
	    когда они расходятся; не выходит за края арены;
	  • пол всегда в нижней части кадра, при высоких прыжках камера приподнимается;
	  • тряска (shake) — затухающее смещение; её вызывает EffectsController при ударах.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local FOV = 30 -- вертикальный угол обзора
local MIN_VIEW_WIDTH = 20 -- студов по горизонтали
local MAX_VIEW_WIDTH = 34
local VIEW_MARGIN = 12 -- запас по краям вокруг бойцов
local MIN_VIEW_HEIGHT = 15
local FLOOR_FRACTION = 0.18 -- пол на такой доле высоты кадра снизу
local FOLLOW_SPEED = 7
local ARENA_EDGE = GameConfig.Physics.ArenaHalfWidth + 1.5

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

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function viewTangents(camera: Camera): (number, number)
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local tanV = math.tan(math.rad(FOV / 2))
	return tanV, tanV * aspect
end

function CameraController.enterFight()
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
	local width = math.clamp(maxX - minX + VIEW_MARGIN, MIN_VIEW_WIDTH, MAX_VIEW_WIDTH)
	local distance = math.max(width / (2 * tanH), MIN_VIEW_HEIGHT / (2 * tanV))
	local halfWidth = distance * tanH
	local halfHeight = distance * tanV

	local centerX = (minX + maxX) / 2
	local limit = ARENA_EDGE - halfWidth
	centerX = if limit > 0 then math.clamp(centerX, -limit, limit) else 0

	-- Пол на FLOOR_FRACTION от низа кадра; если кто-то высоко прыгнул — поднимаемся.
	local centerY = halfHeight * (1 - 2 * FLOOR_FRACTION)
	local highest = topY + 1.5
	if highest > centerY + halfHeight * 0.8 then
		centerY = highest - halfHeight * 0.8
	end

	target.x, target.y, target.distance = centerX, centerY, distance
	if snapNext then
		current.x, current.y, current.distance = centerX, centerY, distance
		snapNext = false
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
