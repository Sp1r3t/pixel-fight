--!strict
--[[
	Тонкая обёртка над RemoteEvent / UnreliableRemoteEvent / RemoteFunction.
	Весь сетевой код игры ходит через этот модуль, поэтому в тестах его можно подменить
	на «петлю» (tests/lib/NetHub.luau) и прогонять сервер и клиентов в одном процессе.

	Сервер создаёт папку ReplicatedStorage.Remotes со всеми каналами из Channels.
	ВАЖНО: всё, что приходит от клиента, — недоверенные данные; проверка — в обработчиках.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Channels = require(script.Parent.Channels)

local FOLDER_NAME = "Remotes"

type Remote = {
	reliable: RemoteEvent?,
	unreliable: UnreliableRemoteEvent?,
	func: RemoteFunction?,
}

local Transport = {}

local cachedFolder: Folder? = nil
local remotes: { [string]: Remote } = {}

local function createFolder(): Folder
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	for name, kind in Channels do
		local remote: Instance
		if kind == "Unreliable" then
			remote = Instance.new("UnreliableRemoteEvent")
		elseif kind == "Reliable" then
			remote = Instance.new("RemoteEvent")
		else
			remote = Instance.new("RemoteFunction")
		end
		remote.Name = name
		remote.Parent = created
	end
	created.Parent = ReplicatedStorage
	return created
end

local function getFolder(): Folder
	local existing = cachedFolder
	if existing then
		return existing
	end
	local result: Folder
	if RunService:IsServer() then
		local found = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		result = if found and found:IsA("Folder") then found else createFolder()
	else
		result = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
	cachedFolder = result
	return result
end

local function getRemote(name: string): Remote
	local cached = remotes[name]
	if cached then
		return cached
	end
	assert(Channels[name] ~= nil, `Неизвестный канал: {name}`)
	local instance = getFolder():WaitForChild(name)
	local remote: Remote = {
		reliable = if instance:IsA("RemoteEvent") then instance else nil,
		unreliable = if instance:IsA("UnreliableRemoteEvent") then instance else nil,
		func = if instance:IsA("RemoteFunction") then instance else nil,
	}
	remotes[name] = remote
	return remote
end

-- Создать каналы (сервер) или дождаться их (клиент).
function Transport.init()
	getFolder()
end

----------------------------------------------------------------------------------------------
-- Сервер
----------------------------------------------------------------------------------------------

function Transport.onServerEvent(name: string, handler: (player: Player, ...any) -> ())
	local remote = getRemote(name)
	local reliable, unreliable = remote.reliable, remote.unreliable
	if reliable then
		reliable.OnServerEvent:Connect(handler)
	elseif unreliable then
		unreliable.OnServerEvent:Connect(handler)
	else
		error(`{name} — не событие`)
	end
end

function Transport.fireClient(name: string, player: Player, ...: any)
	local remote = getRemote(name)
	local reliable, unreliable = remote.reliable, remote.unreliable
	if reliable then
		reliable:FireClient(player, ...)
	elseif unreliable then
		unreliable:FireClient(player, ...)
	else
		error(`{name} — не событие`)
	end
end

function Transport.onServerInvoke(name: string, handler: (player: Player, ...any) -> ...any)
	local func = getRemote(name).func
	assert(func, `{name} — не функция`)
	func.OnServerInvoke = handler
end

----------------------------------------------------------------------------------------------
-- Клиент
----------------------------------------------------------------------------------------------

function Transport.fireServer(name: string, ...: any)
	local remote = getRemote(name)
	local reliable, unreliable = remote.reliable, remote.unreliable
	if reliable then
		reliable:FireServer(...)
	elseif unreliable then
		unreliable:FireServer(...)
	else
		error(`{name} — не событие`)
	end
end

function Transport.onClientEvent(name: string, handler: (...any) -> ())
	local remote = getRemote(name)
	local reliable, unreliable = remote.reliable, remote.unreliable
	if reliable then
		reliable.OnClientEvent:Connect(handler)
	elseif unreliable then
		unreliable.OnClientEvent:Connect(handler)
	else
		error(`{name} — не событие`)
	end
end

function Transport.invokeServer(name: string, ...: any): ...any
	local func = getRemote(name).func
	assert(func, `{name} — не функция`)
	return func:InvokeServer(...)
end

return Transport
