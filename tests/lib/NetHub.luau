--!strict
--[[
	Сетевая «петля» для интеграционных тестов: подменяет Shared/Net/Transport так,
	что сервер и клиенты общаются внутри одного процесса.

	• latencyFrames — задержка доставки событий в кадрах (в одну сторону);
	• dropEveryNth — терять каждый N-й ненадёжный пакет (проверка устойчивости ввода);
	• данные копируются при передаче (как при сериализации в Roblox).
	RemoteFunction (invokeServer) выполняется сразу.
]]

local Channels = nil :: any -- заполняется при создании хаба

local NetHub = {}

local function deepCopy(value: any): any
	if type(value) == "table" then
		local copy = {}
		for key, child in value do
			copy[deepCopy(key)] = deepCopy(child)
		end
		return copy
	elseif type(value) == "buffer" then
		local copy = buffer.create(buffer.len(value))
		buffer.copy(copy, 0, value)
		return copy
	end
	return value
end

local function copyArgs(...: any): { n: number, [number]: any }
	local args = table.pack(...)
	for index = 1, args.n do
		args[index] = deepCopy(args[index])
	end
	return args
end

export type Hub = {
	latencyFrames: number,
	dropEveryNth: number?,
	frame: number,
	sent: { [string]: number }, -- статистика отправленных сообщений по каналам
	serverTransport: () -> any,
	clientTransport: (player: any) -> any,
	step: () -> (),
}

function NetHub.new(options: { latencyFrames: number?, dropEveryNth: number?, channels: any }): Hub
	Channels = options.channels
	local hub = {} :: Hub
	hub.latencyFrames = options.latencyFrames or 0
	hub.dropEveryNth = options.dropEveryNth
	hub.frame = 0
	hub.sent = {}

	local queue: { { at: number, deliver: () -> () } } = {}
	local serverEvents: { [string]: { (player: any, ...any) -> () } } = {}
	local serverInvokes: { [string]: (player: any, ...any) -> ...any } = {}
	local clientEvents: { [any]: { [string]: { (...any) -> () } } } = {}
	local unreliableCounters: { [string]: number } = {}

	local function enqueue(channel: string, deliver: () -> ())
		hub.sent[channel] = (hub.sent[channel] or 0) + 1
		if Channels and Channels[channel] == "Unreliable" and hub.dropEveryNth then
			local count = (unreliableCounters[channel] or 0) + 1
			unreliableCounters[channel] = count
			if count % (hub.dropEveryNth :: number) == 0 then
				return -- пакет «потерян» (счёт отдельно для каждого канала)
			end
		end
		if hub.latencyFrames <= 0 then
			deliver()
		else
			table.insert(queue, { at = hub.frame + hub.latencyFrames, deliver = deliver })
		end
	end

	function hub.step()
		hub.frame += 1
		local due = {}
		local rest = {}
		for _, item in queue do
			if item.at <= hub.frame then
				table.insert(due, item)
			else
				table.insert(rest, item)
			end
		end
		queue = rest
		for _, item in due do
			item.deliver()
		end
	end

	function hub.serverTransport(): any
		local transport = {}
		function transport.init() end
		function transport.onServerEvent(name: string, handler: (player: any, ...any) -> ())
			serverEvents[name] = serverEvents[name] or {}
			table.insert(serverEvents[name], handler)
		end
		function transport.onServerInvoke(name: string, handler: (player: any, ...any) -> ...any)
			serverInvokes[name] = handler
		end
		function transport.fireClient(name: string, player: any, ...: any)
			local args = copyArgs(...)
			enqueue(name, function()
				local handlers = clientEvents[player] and clientEvents[player][name]
				if handlers then
					for _, handler in handlers do
						handler(table.unpack(args, 1, args.n))
					end
				end
			end)
		end
		return transport
	end

	function hub.clientTransport(player: any): any
		clientEvents[player] = clientEvents[player] or {}
		local transport = {}
		function transport.init() end
		function transport.onClientEvent(name: string, handler: (...any) -> ())
			local handlers = clientEvents[player]
			handlers[name] = handlers[name] or {}
			table.insert(handlers[name], handler)
		end
		function transport.fireServer(name: string, ...: any)
			local args = copyArgs(...)
			enqueue(name, function()
				for _, handler in serverEvents[name] or {} do
					handler(player, table.unpack(args, 1, args.n))
				end
			end)
		end
		function transport.invokeServer(name: string, ...: any): ...any
			local handler = serverInvokes[name]
			if handler == nil then
				error(`Нет обработчика RemoteFunction {name}`)
			end
			local args = copyArgs(...)
			local results = copyArgs(handler(player, table.unpack(args, 1, args.n)))
			return table.unpack(results, 1, results.n)
		end
		return transport
	end

	return hub
end

return NetHub
