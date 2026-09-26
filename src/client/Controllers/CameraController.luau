--!strict
--[[
	CameraController — боковая 2D-камера.  [этап 2]

	Ответственность:
	• Scriptable-камера сбоку, узкий FOV (почти ортографическая проекция);
	• следит за центром между бойцами, плавный зум по дистанции;
	• тряска камеры и кинематографичные ракурсы суперов (совместно с EffectsController).

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local CameraController = {
	Name = "CameraController",
}

function CameraController.Init() end

function CameraController.Start() end

return CameraController
