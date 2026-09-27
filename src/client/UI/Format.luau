--!strict
--[[
	Форматирование чисел и времени для интерфейса.
]]

local Format = {}

-- «12500» → «12 500»: крупные числа детям проще читать с пробелами.
function Format.number(value: number): string
	local text = tostring(math.floor(value))
	local negative = string.sub(text, 1, 1) == "-"
	if negative then
		text = string.sub(text, 2)
	end
	local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1 ")))
	grouped = (string.gsub(grouped, "^ ", ""))
	return if negative then "-" .. grouped else grouped
end

return Format
