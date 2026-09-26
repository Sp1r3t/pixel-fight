--!strict
--[[
	Хранилище профилей для настоящей игры — ProfileStore (ServerPackages/ProfileStore, MAD STUDIO).

	  • сессионная блокировка: профиль открыт только на одном сервере — нет дюпа и потери данных;
	  • автосохранение, сохранение при выходе игрока и при остановке сервера (BindToClose внутри ProfileStore);
	  • в Studio без доступа к API ProfileStore сам переключается на тестовое хранилище (Mock).
	В тестах (Lune) этот модуль подменяется на MemoryBackend.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileSchema = require(ReplicatedStorage.Shared.Data.ProfileSchema)
local ProfileStore = require(ServerScriptService:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any

local Session = require(script.Parent.Session)

-- Имя хранилища: менять только вместе с миграцией данных.
local STORE_NAME = "PixelFightProfiles_v1"
local SAVE_TIMEOUT = 20 -- секунд ждать подтверждения сохранения

local store = ProfileStore.New(STORE_NAME, ProfileSchema.default())

local ProfileStoreBackend = {
	name = "ProfileStore",
}

function ProfileStoreBackend.start(player: Player): Session.Session?
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		-- Игрок вышел, пока ждали профиль, — прекращаем попытки.
		Cancel = function(): boolean
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		return nil
	end
	profile:AddUserId(player.UserId) -- для запросов на удаление данных (GDPR)
	profile:Reconcile()
	ProfileSchema.migrate(profile.Data)
	if player.Parent ~= Players then
		profile:EndSession()
		return nil
	end

	local session: Session.Session = {
		data = profile.Data,
		isActive = function(): boolean
			return profile:IsActive()
		end,
		saveAsync = function(): boolean
			if not profile:IsActive() then
				return false
			end
			local saved = false
			local connection = profile.OnAfterSave:Connect(function()
				saved = true
			end)
			profile:Save()
			local deadline = os.clock() + SAVE_TIMEOUT
			while not saved and profile:IsActive() and os.clock() < deadline do
				task.wait(0.1)
			end
			connection:Disconnect()
			return saved
		end,
		isSaved = function(check: (ProfileSchema.PlayerData) -> boolean): boolean
			local last = profile.LastSavedData
			return type(last) == "table" and type(last.purchases) == "table" and check(last)
		end,
		endSession = function()
			profile:EndSession()
		end,
		onEnded = function(callback: () -> ())
			profile.OnSessionEnd:Connect(callback)
		end,
	}
	return session
end

return ProfileStoreBackend
