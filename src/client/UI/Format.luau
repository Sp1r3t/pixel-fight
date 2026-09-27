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

--[[
	Заглавные буквы с кириллицей: string.upper меняет только латиницу (а-я и ё остаются строчными).
]]
function Format.upper(text: string): string
	local parts: { string } = {}
	for _, code in utf8.codes(text) do
		local latin = code >= 0x61 and code <= 0x7A -- a-z
		local cyrillic = code >= 0x430 and code <= 0x44F -- а-я
		if latin or cyrillic then
			code -= 0x20
		elseif code >= 0x450 and code <= 0x45F then
			code -= 0x50 -- ѐ-џ (ё → Ё)
		end
		table.insert(parts, utf8.char(code))
	end
	return table.concat(parts)
end

return Format
