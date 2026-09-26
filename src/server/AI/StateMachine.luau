--!strict
--[[
	StateMachine — универсальный конечный автомат для ИИ боссов.  [этап 6]

	План:
	  • состояния (Approach, Pressure, Zoning, Defend, Punish, Combo, Super, Recover…)
	    с колбэками enter/update/exit;
	  • переходы по условиям с приоритетами;
	  • задержка реакции и «человеческие» ошибки задаются параметрами босса, а не кодом.

	Сейчас это пустой модуль-заглушка.
]]

local StateMachine = {}

return StateMachine
