--!strict
--[[
	InputController — ввод игрока.  [этап 2, 5]

	Ответственность:
	• автоопределение платформы (сенсор / клавиатура / геймпад) через UserInputService;
	• ПК: WASD + J (рука) / K (нога) / L (особый) / I (супер); геймпад — аналогично;
	• телефон (этап 5): джойстик слева, кнопки «Рука», «Нога», «Особый», «Супер» справа,
	  настраиваемые размер и положение; блок — движение назад от противника;
	• отправка на сервер ТОЛЬКО состояния кнопок (битовая маска) через ContextActionService.

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local InputController = {
	Name = "InputController",
}

function InputController.Init() end

function InputController.Start() end

return InputController
