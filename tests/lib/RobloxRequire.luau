--!strict
--[[
	Мини-эмуляция Roblox-style require для Lune.

	Позволяет запускать ЧИСТЫЕ модули проекта (без Roblox API) вне Studio:
	`require(script.Parent.Config.Characters)` и `game:GetService("ReplicatedStorage").Shared...`
	разрешаются в файлы по тем же правилам, что и в Rojo:
	  • Foo.luau / Foo.lua              → ModuleScript "Foo"
	  • Foo.server.luau / Foo.client.luau → Script / LocalScript "Foo"
	  • Foo/init.luau                   → ModuleScript "Foo" с детьми из папки Foo
	  • Foo/default.project.json        → узел из "$path" проекта (так устроены пакеты Wally)
	  • Foo/                            → Folder "Foo"

	Дерево файлов сканируется заранее (Lune-вызовы fs могут уступать поток,
	а внутри метаметода __index это запрещено).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

type Node = {
	name: string,
	className: string,
	source: string?, -- файл с кодом (только у скриптов)
	children: { [string]: Node },
}

-- Повторяет default.project.json: строка — путь в ФС, таблица — промежуточная папка.
type Mapping = { [string]: string | Mapping }

local SERVICE_MAPPING: Mapping = {
	ReplicatedStorage = {
		Shared = "src/shared",
		Packages = "Packages",
	},
	ServerScriptService = {
		Server = "src/server",
	},
	StarterPlayer = {
		StarterPlayerScripts = {
			Client = "src/client",
		},
	},
}

local SCRIPT_SUFFIXES: { { suffix: string, className: string } } = {
	{ suffix = ".server.luau", className = "Script" },
	{ suffix = ".client.luau", className = "LocalScript" },
	{ suffix = ".luau", className = "ModuleScript" },
	{ suffix = ".server.lua", className = "Script" },
	{ suffix = ".client.lua", className = "LocalScript" },
	{ suffix = ".lua", className = "ModuleScript" },
}

local function scriptInfo(fileName: string): (string?, string?)
	for _, entry in SCRIPT_SUFFIXES do
		if string.sub(fileName, -#entry.suffix) == entry.suffix then
			return string.sub(fileName, 1, -#entry.suffix - 1), entry.className
		end
	end
	return nil, nil
end

local scanDirectory: (path: string, name: string) -> Node

function scanDirectory(path: string, name: string): Node
	local projectFile = `{path}/default.project.json`
	if fs.isFile(projectFile) then
		local project = serde.decode("json", fs.readFile(projectFile))
		local innerPath = project.tree and project.tree["$path"]
		if type(innerPath) == "string" then
			local innerFull = `{path}/{innerPath}`
			if fs.isDir(innerFull) then
				return scanDirectory(innerFull, name)
			end
			local _, className = scriptInfo(innerFull)
			return { name = name, className = className or "ModuleScript", source = innerFull, children = {} }
		end
	end

	local node: Node = { name = name, className = "Folder", source = nil, children = {} }
	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in entries do
		local full = `{path}/{entry}`
		if fs.isDir(full) then
			node.children[entry] = scanDirectory(full, entry)
		else
			local childName, className = scriptInfo(entry)
			if childName == "init" and className ~= nil then
				node.className = className
				node.source = full
			elseif childName ~= nil and className ~= nil then
				node.children[childName] = { name = childName, className = className, source = full, children = {} }
			end
		end
	end
	return node
end

local function buildVirtual(name: string, className: string, mapping: Mapping): Node
	local node: Node = { name = name, className = className, source = nil, children = {} }
	for childName, target in mapping do
		if type(target) == "string" then
			if fs.isDir(target) then
				node.children[childName] = scanDirectory(target, childName)
			end
		else
			node.children[childName] = buildVirtual(childName, "Folder", target)
		end
	end
	return node
end

local serviceNodes: { [string]: Node } = {}
for serviceName, mapping in SERVICE_MAPPING do
	serviceNodes[serviceName] = buildVirtual(serviceName, serviceName, mapping :: Mapping)
end

export type LoaderOptions = {
	-- Дополнительные глобальные переменные для модулей (например, эмуляция Roblox API).
	globals: { [string]: any }?,
	-- Сервисы, которых нет в дереве файлов (Players, RunService, ...).
	services: { [string]: any }?,
	-- Подмена модулей: путь к файлу ("src/shared/Net/Transport.luau") → готовое значение.
	overrides: { [string]: any }?,
}

export type Loader = {
	game: any,
	require: (module: any) -> any,
	get: (serviceName: string, ...string) -> any,
	run: (scriptInstance: any) -> (),
}

local RobloxRequire = {}

-- Создаёт независимый загрузчик со своим кэшем модулей.
function RobloxRequire.new(options: LoaderOptions?): Loader
	local globals = if options and options.globals then options.globals else {}
	local extraServices = if options and options.services then options.services else {}
	local overrides = if options and options.overrides then options.overrides else {}

	-- Обёртки-«инстансы» над узлами дерева.
	local wrappers: { [Node]: any } = {}
	local nodeOf: { [any]: Node } = {}
	local moduleCache: { [string]: { value: any } } = {}
	local loading: { [string]: boolean } = {}

	local wrap: (node: Node, parent: any) -> any

	local methods = {
		FindFirstChild = function(self: any, name: string): any
			local child = nodeOf[self].children[name]
			return if child then wrap(child, self) else nil
		end,
		WaitForChild = function(self: any, name: string): any
			local child = nodeOf[self].children[name]
			return wrap(assert(child, `WaitForChild: нет {name} в {nodeOf[self].name}`), self)
		end,
		IsA = function(self: any, className: string): boolean
			return nodeOf[self].className == className
		end,
		GetChildren = function(self: any): { any }
			local result = {}
			for _, child in nodeOf[self].children do
				table.insert(result, wrap(child, self))
			end
			return result
		end,
		GetFullName = function(self: any): string
			local node = nodeOf[self]
			local parent = rawget(self, "__parent")
			return if parent then `{parent:GetFullName()}.{node.name}` else node.name
		end,
	}

	function wrap(node: Node, parent: any): any
		local existing = wrappers[node]
		if existing ~= nil then
			return existing
		end
		local instance = setmetatable({ __parent = parent }, {
			__index = function(self: any, key: string): any
				if key == "Name" then
					return node.name
				elseif key == "ClassName" then
					return node.className
				elseif key == "Parent" then
					return parent
				end
				local method = (methods :: any)[key]
				if method ~= nil then
					return method
				end
				local child = node.children[key]
				if child == nil then
					error(`{key} is not a valid member of {node.name}`, 2)
				end
				return wrap(child, self)
			end,
			__tostring = function(): string
				return node.name
			end,
		})
		wrappers[node] = instance
		nodeOf[instance] = node
		return instance
	end

	local fakeGame = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "GetService" then
				return function(_self: any, serviceName: string): any
					local node = serviceNodes[serviceName]
					if node ~= nil then
						return wrap(node, nil)
					end
					local service = extraServices[serviceName]
					if service == nil then
						error(`Сервис {serviceName} недоступен в тестах`, 2)
					end
					return service
				end
			end
			error(`game.{key} недоступен в тестах`, 2)
		end,
	})

	local loader = {} :: Loader
	loader.game = fakeGame

	local function load(node: Node, instance: any): any
		local source = node.source :: string
		local environment: { [string]: any } = table.clone(globals)
		environment.script = instance
		environment.game = fakeGame
		environment.require = loader.require
		local chunk = luau.load(fs.readFile(source), {
			debugName = source,
			environment = environment,
		})
		return chunk()
	end

	function loader.require(module: any): any
		local node = nodeOf[module]
		if node == nil or node.className ~= "ModuleScript" or node.source == nil then
			error(`{tostring(module)} — не ModuleScript`, 2)
		end
		local source = node.source :: string
		if overrides[source] ~= nil then
			return overrides[source]
		end
		local cached = moduleCache[source]
		if cached ~= nil then
			return cached.value
		end
		if loading[source] then
			error(`Циклический require: {source}`, 2)
		end
		loading[source] = true
		local result = load(node, module)
		loading[source] = nil
		moduleCache[source] = { value = result }
		return result
	end

	-- Выполнить Script/LocalScript (например, init.client.luau).
	function loader.run(scriptInstance: any)
		local node = nodeOf[scriptInstance]
		if node == nil or node.source == nil or node.className == "ModuleScript" then
			error(`{tostring(scriptInstance)} — не Script/LocalScript`, 2)
		end
		load(node, scriptInstance)
	end

	-- Инстанс по пути внутри сервиса: loader.get("ReplicatedStorage", "Shared", "Config").
	function loader.get(serviceName: string, ...: string): any
		local current: any = fakeGame:GetService(serviceName)
		for _, name in { ... } do
			current = current[name]
		end
		return current
	end

	return loader
end

return RobloxRequire
