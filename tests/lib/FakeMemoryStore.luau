--!strict
--[[
	Поддельный MemoryStoreService для тестов: SortedMap и HashMap в памяти процесса.
	Один экземпляр можно отдать нескольким «серверам» (Harness) — так проверяется межсерверный подбор.

	Поведение как у настоящего: значения копируются (в MemoryStore они сериализуются),
	записи истекают по времени, UpdateAsync атомарен (в одном процессе Lune — тривиально),
	GetRangeAsync сортирует по sortKey, затем по ключу.
]]

export type Item = { key: string, value: any, sortKey: any?, expiresAt: number }

export type Store = {
	clock: () -> number,
	maps: { [string]: { [string]: Item } },
	calls: number, -- сколько запросов к хранилищу (для проверок нагрузки)
	failNext: number, -- сколько следующих запросов «упадут» (проверка устойчивости)
	failAt: number?, -- номер запроса (по счётчику calls), который «упадёт»
	GetSortedMap: (self: any, name: string) -> any,
	GetHashMap: (self: any, name: string) -> any,
}

local FakeMemoryStore = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value do
		result[deepCopy(key)] = deepCopy(inner)
	end
	return result
end

function FakeMemoryStore.new(clock: () -> number): Store
	local store = {} :: Store
	store.clock = clock
	store.maps = {}
	store.calls = 0
	store.failNext = 0

	local function touch()
		store.calls += 1
		if store.failAt == store.calls then
			error("MemoryStore: запрос отклонён (тест)")
		end
		if store.failNext > 0 then
			store.failNext -= 1
			error("MemoryStore: запрос отклонён (тест)")
		end
	end

	local function entries(name: string): { [string]: Item }
		local map = store.maps[name]
		if map == nil then
			map = {}
			store.maps[name] = map
		end
		-- Истёкшие записи исчезают.
		local now = store.clock()
		for key, item in map do
			if item.expiresAt <= now then
				map[key] = nil
			end
		end
		return map
	end

	local function makeMap(name: string, sorted: boolean): any
		local map = {}
		function map.SetAsync(_self: any, key: string, value: any, expiration: number, sortKey: any?): boolean
			touch()
			assert(type(key) == "string", "ключ должен быть строкой")
			entries(name)[key] = {
				key = key,
				value = deepCopy(value),
				sortKey = if sorted then sortKey else nil,
				expiresAt = store.clock() + expiration,
			}
			return true
		end
		function map.GetAsync(_self: any, key: string): (any, any)
			touch()
			local item = entries(name)[key]
			if item == nil then
				return nil, nil
			end
			return deepCopy(item.value), item.sortKey
		end
		function map.RemoveAsync(_self: any, key: string)
			touch()
			entries(name)[key] = nil
		end
		function map.UpdateAsync(_self: any, key: string, transform: (any, any) -> (any, any), expiration: number): any
			touch()
			local items = entries(name)
			local item = items[key]
			local newValue, newSortKey =
				transform(if item then deepCopy(item.value) else nil, if item then item.sortKey else nil)
			if newValue == nil then
				return nil
			end
			items[key] = {
				key = key,
				value = deepCopy(newValue),
				sortKey = if sorted
					then (if newSortKey ~= nil then newSortKey elseif item then item.sortKey else nil)
					else nil,
				expiresAt = store.clock() + expiration,
			}
			return deepCopy(newValue)
		end
		if sorted then
			function map.GetRangeAsync(_self: any, direction: any, count: number): { any }
				touch()
				local list: { Item } = {}
				for _, item in entries(name) do
					table.insert(list, item)
				end
				local ascending = tostring(direction) ~= "Enum.SortDirection.Descending"
					and not (type(direction) == "table" and direction.Name == "Descending")
				table.sort(list, function(a: Item, b: Item): boolean
					local ka, kb = a.sortKey or 0, b.sortKey or 0
					if ka ~= kb then
						return if ascending then ka < kb else ka > kb
					end
					return if ascending then a.key < b.key else a.key > b.key
				end)
				local result = {}
				for index = 1, math.min(count, #list) do
					local item = list[index]
					table.insert(result, { key = item.key, value = deepCopy(item.value), sortKey = item.sortKey })
				end
				return result
			end
		end
		return map
	end

	function store.GetSortedMap(_self: any, name: string): any
		return makeMap("sorted:" .. name, true)
	end
	function store.GetHashMap(_self: any, name: string): any
		return makeMap("hash:" .. name, false)
	end
	return store
end

return FakeMemoryStore
