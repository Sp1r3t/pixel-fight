--!strict
--[[
	MatchmakingService — матчмейкинг.  [этап 7]

	Ответственность:
	• очередь 1 на 1 и 2 на 2 через MemoryStoreService (SortedMap), между серверами;
	• приватные матчи с другом по коду;
	• телепорт в зарезервированный сервер матча (TeleportService:ReserveServer).

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local MatchmakingService = {
	Name = "MatchmakingService",
}

function MatchmakingService.Init() end

function MatchmakingService.Start() end

return MatchmakingService
