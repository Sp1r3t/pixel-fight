--!strict
--[[
	Все сетевые каналы игры в одном месте.
	  Unreliable — UnreliableRemoteEvent (частые данные, потеря не страшна: ввод, снапшоты);
	  Reliable   — RemoteEvent (события матча, профиль);
	  Function   — RemoteFunction (запросы клиента к серверу: начать бой, купить и т.п.).
]]

export type ChannelKind = "Unreliable" | "Reliable" | "Function"

local Channels: { [string]: ChannelKind } = {
	Input = "Unreliable", -- клиент → сервер: (seq, held, counters)
	Snapshot = "Unreliable", -- сервер → клиент: buffer снапшота
	MatchEvent = "Reliable", -- сервер → клиент: (kind, payload)
	Profile = "Reliable", -- сервер → клиент: данные профиля
	Request = "Function", -- клиент → сервер: (action, payload) → (ok, result)
}

return table.freeze(Channels)
