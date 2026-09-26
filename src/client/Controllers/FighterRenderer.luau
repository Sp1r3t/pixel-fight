--!strict
--[[
	FighterRenderer — отрисовка бойцов.  [этап 2]

	Ответственность:
	• визуальные модели бойцов в плоскости арены (SurfaceGui + ImageLabel);
	• интерполяция серверных снапшотов, выбор анимации по состоянию бойца;
	• зеркалирование спрайта по направлению взгляда.

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local FighterRenderer = {
	Name = "FighterRenderer",
}

function FighterRenderer.Init() end

function FighterRenderer.Start() end

return FighterRenderer
