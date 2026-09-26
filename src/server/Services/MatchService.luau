--!strict
--[[
	MatchService — раунды и матчи.  [этап 4]

	Ответственность:
	• жизненный цикл матча: вступление → «Round N» → «Fight!» → бой → «K.O.» → итоги;
	• таймер раунда 60 с; по истечении времени побеждает больший % HP;
	• счёт побед в раундах (до 2 в PvP, до 3 против босса);
	• рассылка событий раунда клиентам для HUD.

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local MatchService = {
	Name = "MatchService",
}

function MatchService.Init() end

function MatchService.Start() end

return MatchService
