--!strict
--[[
	Точка входа сервера.
	1. Проверяет конфиг персонажей (бюджет силы) — при нарушении сервер не стартует.
	2. Вызывает Init() у всех сервисов по порядку (синхронно, без yield'ов),
	   затем Start() у каждого в отдельном потоке.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)

CharacterRegistry.assertValid()

local Services = script.Services

-- Порядок важен: сервисы ниже могут зависеть от сервисов выше.
local services: { Types.Lifecycle } = {
	require(Services.DataService),
	require(Services.MonetizationService),
	require(Services.CombatService),
	require(Services.InputService),
	require(Services.MatchService),
	require(Services.BossService),
	require(Services.MatchmakingService),
}

for _, service in services do
	service.Init()
end

for _, service in services do
	task.spawn(service.Start)
end

print(
	`[Server] Запущено сервисов: {#services}. Персонажей в ростере: {#CharacterRegistry.list()}.`
)
