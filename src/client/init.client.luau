--!strict
--[[
	Точка входа клиента.
	Вызывает Init() у всех контроллеров по порядку, затем Start() у каждого в отдельном потоке.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

-- Дождаться сетевых каналов, которые создаёт сервер.
Transport.init()

local Controllers = script.Controllers

local controllers: { Types.Lifecycle } = {
	require(Controllers.UIController),
	require(Controllers.InputController),
	require(Controllers.CameraController),
	require(Controllers.EffectsController),
	require(Controllers.FightController),
}

for _, controller in controllers do
	controller.Init()
end

for _, controller in controllers do
	task.spawn(controller.Start)
end

print(`[Client] Запущено контроллеров: {#controllers}.`)
