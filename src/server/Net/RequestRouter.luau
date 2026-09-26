--!strict
--[[
	RequestRouter — единая точка для запросов клиента (канал "Request").
	Сервисы регистрируют обработчики действий; роутер проверяет тип действия,
	ограничивает частоту запросов и изолирует ошибки обработчиков.

	Обработчик получает (player, payload) — payload НЕ проверен, это делает сам обработчик.
	Возвращает (ok, result): при ошибке result — короткий код ошибки для клиента.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Transport = require(ReplicatedStorage.Shared.Net.Transport)

export type Handler = (player: Player, payload: unknown) -> (boolean, any)

local MAX_REQUESTS_PER_SECOND = 12

local RequestRouter = {}

local handlers: { [string]: Handler } = {}
local rate: { [Player]: { windowStart: number, count: number } } = {}

function RequestRouter.register(action: string, handler: Handler)
	assert(handlers[action] == nil, `Действие {action} уже зарегистрировано`)
	handlers[action] = handler
end

-- Обработать запрос (вынесено отдельно для тестов). now — os.clock().
function RequestRouter.handle(player: Player, action: unknown, payload: unknown, now: number): (boolean, any)
	local entry = rate[player]
	if entry == nil or now - entry.windowStart >= 1 then
		entry = { windowStart = now, count = 0 }
		rate[player] = entry
	end
	entry.count += 1
	if entry.count > MAX_REQUESTS_PER_SECOND then
		return false, "RateLimited"
	end

	if type(action) ~= "string" then
		return false, "BadRequest"
	end
	local handler = handlers[action]
	if handler == nil then
		return false, "UnknownAction"
	end

	local ok, success, result = pcall(handler, player, payload)
	if not ok then
		warn(`[RequestRouter] Ошибка в обработчике {action}: {success}`)
		return false, "ServerError"
	end
	return success, result
end

function RequestRouter.init()
	Transport.onServerInvoke("Request", function(player: Player, action: unknown, payload: unknown)
		return RequestRouter.handle(player, action, payload, os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		rate[player] = nil
	end)
end

return RequestRouter
