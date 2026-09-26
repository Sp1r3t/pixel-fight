--!strict
--[[
	Session — интерфейс сессии профиля игрока (только типы).

	Реализации:
	  • ProfileStoreBackend — настоящая игра: ProfileStore (сессионная блокировка, автосохранение,
	    сохранение при выходе и при остановке сервера);
	  • MemoryBackend — тесты (в Lune нет DataStore и ожиданий task.wait).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)

export type Session = {
	data: ProfileSchema.PlayerData,
	-- Изменения data гарантированно сохранятся, пока сессия активна.
	isActive: () -> boolean,
	-- Сохранить сейчас и дождаться записи (true — записано в хранилище).
	saveAsync: () -> boolean,
	-- Удовлетворяет ли check последний сохранённый снимок данных (проверка чеков покупок).
	isSaved: (check: (saved: ProfileSchema.PlayerData) -> boolean) -> boolean,
	-- Завершить сессию (данные сохраняются, блокировка снимается).
	endSession: () -> (),
	-- Сессия завершилась (в том числе потому, что профиль открыл другой сервер).
	onEnded: (callback: () -> ()) -> (),
}

export type Backend = {
	name: string,
	-- Открыть сессию профиля игрока (может ждать). nil — не удалось (профиль занят/нет связи).
	start: (player: Player) -> Session?,
}

return {}
