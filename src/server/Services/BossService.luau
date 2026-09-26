--!strict
--[[
	BossService — одиночный режим: 20 боссов.  [этап 6]

	Ответственность:
	• последовательное открытие боссов (следующий — после победы над предыдущим);
	• запуск боя игрока против ИИ-босса с его параметрами сложности;
	• засчитывание победы при покупке «Пропустить босса» (через MonetizationService).

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local BossService = {
	Name = "BossService",
}

function BossService.Init() end

function BossService.Start() end

return BossService
