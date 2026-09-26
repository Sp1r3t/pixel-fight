--!strict
--[[
	Хранилище профилей в памяти — для тестов (и как образец поведения ProfileStore).

	Повторяет важные свойства настоящего хранилища:
	  • сессионная блокировка: пока сессия открыта, второй сервер профиль не получит;
	  • данные сохраняются копией (изменения после сохранения не попадают в «хранилище» сами);
	  • сохранение можно «сломать» (saveFails), а сессию — завершить извне (как если бы профиль
	    забрал другой сервер).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)

local Session = require(script.Parent.Session)

type PlayerData = ProfileSchema.PlayerData

export type MemoryBackend = {
	name: string,
	start: (player: Player) -> Session.Session?,
	saved: { [number]: PlayerData }, -- «DataStore»: последнее сохранение по UserId
	sessions: { [number]: Session.Session }, -- открытые сессии
	failStart: boolean, -- следующие start() вернут nil
	saveFails: boolean, -- сохранения не проходят
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, inner in value do
		result[key] = deepCopy(inner)
	end
	return result
end

local MemoryBackend = {}

function MemoryBackend.new(): MemoryBackend
	local backend = {} :: MemoryBackend
	backend.name = "Memory"
	backend.saved = {}
	backend.sessions = {}
	backend.failStart = false
	backend.saveFails = false

	function backend.start(player: Player): Session.Session?
		local userId = player.UserId
		if backend.failStart or backend.sessions[userId] ~= nil then
			return nil
		end
		local stored = backend.saved[userId]
		local data = ProfileSchema.migrate(if stored then deepCopy(stored) else ProfileSchema.default())
		local lastSaved: PlayerData = deepCopy(data)
		local ended = false
		local callbacks: { () -> () } = {}

		local session: Session.Session = {
			data = data,
			isActive = function(): boolean
				return not ended
			end,
			saveAsync = function(): boolean
				if ended or backend.saveFails then
					return false
				end
				lastSaved = deepCopy(data)
				backend.saved[userId] = deepCopy(data)
				return true
			end,
			isSaved = function(check: (PlayerData) -> boolean): boolean
				return check(lastSaved)
			end,
			endSession = function()
				if ended then
					return
				end
				ended = true
				if not backend.saveFails then
					backend.saved[userId] = deepCopy(data)
				end
				backend.sessions[userId] = nil
				for _, callback in callbacks do
					callback()
				end
			end,
			onEnded = function(callback: () -> ())
				table.insert(callbacks, callback)
			end,
		}
		backend.sessions[userId] = session
		return session
	end

	return backend
end

return MemoryBackend
