--!strict
--[[
	MonetizationService — монетизация.  [этап 9]

	Ответственность:
	• Game Pass'ы платных персонажей (проверка владения при входе и после покупки);
	• Developer Product «Пропустить босса» через MarketplaceService.ProcessReceipt;
	• идемпотентная выдача: PurchaseId сохраняется в профиле, повторный чек не выдаёт награду дважды;
	• платные персонажи дают только косметику — боевые параметры не меняются.

	Сейчас это пустой модуль-заглушка: только жизненный цикл Init/Start.
]]

local MonetizationService = {
	Name = "MonetizationService",
}

function MonetizationService.Init() end

function MonetizationService.Start() end

return MonetizationService
