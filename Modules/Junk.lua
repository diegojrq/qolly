-- Vende o lixo (itens cinza) ao abrir um vendedor. Segure Shift ao abrir para pular.
-- O item é pego da bolsa e solto no vendedor, nunca "usado": usar uma arma cinza com a
-- janela fechando equiparia a arma. Os mais baratos vão primeiro, assim os mais caros
-- ficam na recompra (que guarda só os últimos 12).
-- Itens travados (Alt+clique no item da bolsa, ou /qolly travar [item]) nunca entram
-- no lixo; e se um deles for vendido sem querer, o Qolly recompra na hora.
local _, Qolly = ...

local Junk = {}
Qolly.Junk = Junk

local db

local FIRST_BAG, LAST_BAG = 0, 4
-- Um item por vez, com folga, para o servidor não recusar.
local STEP = 0.15
local POOR = 0

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function MerchantOpen()
    local frame = MerchantFrame
    if not frame or not frame:IsShown() then
        return false
    end
    -- Na aba de recompra, vender não é o que se quer.
    return not frame.selectedTab or frame.selectedTab == 1
end

-- Trava ----------------------------------------------------------------------------

function Junk.IsLocked(itemID)
    return db ~= nil and itemID ~= nil and db.locked[itemID] == true
end

function Junk.ToggleLock(itemID)
    if not itemID then
        return
    end
    db.locked[itemID] = not db.locked[itemID] or nil
    local link = select(2, C_Item.GetItemInfo(itemID)) or ("item " .. itemID)
    Qolly.Print(("%s %s."):format(link, db.locked[itemID]
        and "|cffff5555travado|r: não será vendido" or "|cff55dd55destravado|r"))
end

-- Alt+clique num item da bolsa (bolsas do jogo e Bagnon passam por aqui).
hooksecurefunc("HandleModifiedItemClick", function(link)
    if not db or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then
        return
    end
    if type(link) ~= "string" or Qolly.IsSecret(link) then
        return
    end
    local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    local parent = focus and focus.GetParent and focus:GetParent()
    -- Bolsas do jogo têm GetBagID; o Bagnon tem GetBag no botão do item.
    local inBag = focus and (focus.GetBagID or focus.GetBag or (parent and parent.GetBagID))
    if not inBag then
        return
    end
    Junk.ToggleLock(C_Item.GetItemInfoInstant(link))
end)

-- Vendeu um item travado: ele está na recompra. Compra de volta.
local function RescueLocked()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return
    end
    for index = GetNumBuybackItems(), 1, -1 do
        local link = GetBuybackItemLink(index)
        local itemID = link and C_Item.GetItemInfoInstant(link)
        if itemID and Junk.IsLocked(itemID) then
            BuybackItem(index)
            Qolly.Print(("%s está travado: recomprado. Destrave com Alt+clique para vender."):format(link))
        end
    end
end

-- Linha no tooltip do item travado.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        pcall(function()
            local itemID = data and data.id
            if type(itemID) == "number" and not Qolly.IsSecret(itemID) and Junk.IsLocked(itemID) then
                tooltip:AddLine(Qolly.TAG .. "|cffff5555travado|r: não pode ser vendido (Alt+clique destrava)")
            end
        end)
    end)
end

local function SellPrice(itemID)
    local price = select(11, C_Item.GetItemInfo(itemID))
    return Plain(price)
end

-- Itens cinza com valor de venda, do mais barato ao mais caro.
local function FindJunk()
    local list = {}
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and Plain(info.quality) == POOR and not info.isLocked and not info.hasNoValue
                and not Junk.IsLocked(info.itemID) then
                local price = info.itemID and SellPrice(info.itemID)
                if price and price > 0 then
                    local count = Plain(info.stackCount) or 1
                    list[#list + 1] = { bag = bag, slot = slot, value = price * count }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        return a.value < b.value
    end)
    return list
end

local queue, sold, total = nil, 0, 0

local function Finish()
    if sold > 0 then
        Qolly.Print(("Lixo vendido: %d %s por %s."):format(sold, sold == 1 and "item" or "itens", Qolly.Money(total)))
    end
    queue = nil
end

local function SellNext()
    if not queue then
        return
    end
    local item = table.remove(queue, 1)
    if not item or not MerchantOpen() then
        Finish()
        return
    end
    ClearCursor()
    if Qolly.Income then
        Qolly.Income.Tag("lixo")
    end
    C_Container.PickupContainerItem(item.bag, item.slot)
    if CursorHasItem() then
        PickupMerchantItem()
        if CursorHasItem() then
            -- O vendedor não aceitou: devolve para a bolsa.
            ClearCursor()
        else
            sold = sold + 1
            total = total + item.value
        end
    end
    C_Timer.After(STEP, function()
        Qolly.Safe("lixo", SellNext)
    end)
end

function Junk.Sell()
    if queue then
        return
    end
    local list = FindJunk()
    if #list == 0 then
        return
    end
    queue, sold, total = list, 0, 0
    SellNext()
end

function Junk.IsEnabled()
    return db.enabled ~= false
end

function Junk.SetEnabled(on)
    db.enabled = on and true or false
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("MERCHANT_UPDATE")
events:SetScript("OnEvent", function(_, event)
    if not db then
        return
    end
    if event == "MERCHANT_UPDATE" then
        Qolly.Safe("itens travados", RescueLocked)
        return
    end
    if event == "MERCHANT_CLOSED" then
        if queue then
            Finish()
        end
        return
    end
    if Junk.IsEnabled() and not IsShiftKeyDown() then
        -- Um instante para a janela abrir na aba de compra.
        C_Timer.After(0.2, function()
            Qolly.Safe("lixo", Junk.Sell)
        end)
    end
end)

Qolly.RegisterModule("lixo", {
    help = "(liga/desliga vender o lixo ao abrir um vendedor; com um vendedor aberto, vende agora)",
    command = function()
        if MerchantOpen() then
            Junk.Sell()
            return
        end
        Junk.SetEnabled(not Junk.IsEnabled())
        Qolly.Print("Vender lixo no vendedor " .. (Junk.IsEnabled() and "ligado." or "desligado."))
    end,
    init = function(moduleDB)
        db = moduleDB
        db.locked = db.locked or {}
    end,
})

-- /qolly travar [item]: trava ou destrava. Sem item, lista os travados.
Qolly.RegisterModule("travar", {
    help = "[item] (trava/destrava um item para não ser vendido; sem item, lista os travados. Atalho: Alt+clique no item da bolsa)",
    command = function(args)
        local itemID = args and args ~= "" and C_Item.GetItemInfoInstant(args)
        if itemID then
            Junk.ToggleLock(itemID)
            return
        end
        local any = false
        for id in pairs(db.locked) do
            any = true
            Qolly.Print("Travado: " .. (select(2, C_Item.GetItemInfo(id)) or ("item " .. id)))
        end
        if not any then
            Qolly.Print("Nenhum item travado. Alt+clique num item da bolsa para travar.")
        end
    end,
    init = function() end,
})
