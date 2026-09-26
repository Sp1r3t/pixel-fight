--!strict
--[[
	DataService — сохранения игрока.  [этап 9]

	Ответственность:
	• профиль игрока через ProfileStore (сессионная блокировка — защита от дюпа и потери данных);
	• открытые персонажи, прогресс по боссам, валюта, настройки управления;
	• миграции версий профиля и значения по умолчанию;
	• публикация состояния профиля клиенту (→ Fusion Values в UI).

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local DataService = {
	Name = "DataService",
}

function DataService.Init() end

function DataService.Start() end

return DataService
