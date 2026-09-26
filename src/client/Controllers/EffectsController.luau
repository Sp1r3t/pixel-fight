--!strict
--[[
	EffectsController — визуальные эффекты боя.  [этап 3–4]

	Ответственность:
	• хитстоп (визуальная заморозка на несколько кадров);
	• тряска камеры, частицы при ударе, вспышки при суперах;
	• кинематографичные ролики суперов (этап 8), ауры платных персонажей.

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local EffectsController = {
	Name = "EffectsController",
}

function EffectsController.Init() end

function EffectsController.Start() end

return EffectsController
