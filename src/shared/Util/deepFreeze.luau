--!strict
--[[
	Рекурсивно замораживает таблицу (защита конфигов от случайных изменений во время игры).
	Тип значения не меняется — в отличие от table.freeze, который в новом солвере Luau
	делает поля read-only на уровне типов.
]]

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

return deepFreeze
