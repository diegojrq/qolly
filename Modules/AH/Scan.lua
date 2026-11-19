-- Varredura completa da AH (C_AuctionHouse.ReplicateItems), compartilhada pelos módulos.
-- Cada módulo se inscreve com AH.AddListener e recebe as linhas do scan.
local _, Qolly = ...

local AH = {}
Qolly.AH = AH

-- A Blizzard só libera um scan completo a cada 15 min, por conta.
AH.COOLDOWN = 15 * 60
-- Linhas lidas por frame, para o jogo não travar num scan de dezenas de milhares.
local CHUNK = 1500
-- REPLICATE_ITEM_LIST_UPDATE dispara centenas de vezes num scan só. A leitura espera
-- DEBOUNCE segundos, e eventos até QUIET segundos depois dela são do mesmo scan.
local DEBOUNCE = 1
local QUIET = 10

local listeners, rowHandlers = {}, {}
local isOpen = false
local pending, reading, lastRead = false, false, nil
local progress = 0
-- Quando pedimos o scan (GetTime) e até quando mostrar "scan concluído".
local requestedAt, doneUntil, doneTotal = nil, 0, 0
local BAR_WAIT = 90
local DONE_SHOW = 6
-- Muda a cada leitura nova ou AH fechada; uma leitura com token velho é abandonada.
local token = 0

-- listener = {
--   begin  = function()                              -- antes da primeira linha
--   row    = function(index, itemID, count, buyout)  -- buyout é o da pilha inteira
--   finish = function(listings)                      -- leitura completa
--   show   = function(auctionFrame)                  -- AH aberta (botões, janelas)
-- }
function AH.AddListener(listener)
    listeners[#listeners + 1] = listener
    if listener.row then
        rowHandlers[#rowHandlers + 1] = listener.row
    end
end

local function Notify(method, ...)
    for _, listener in ipairs(listeners) do
        if listener[method] then
            Qolly.Safe("scan: " .. method, listener[method], ...)
        end
    end
end

function AH.IsOpen()
    return isOpen
end

function AH.CooldownLeft()
    local last = AH.db.lastScanRequest
    if not last then
        return 0
    end
    return math.max(0, AH.COOLDOWN - (time() - last))
end

function AH.Request()
    if not isOpen then
        Qolly.Print("Abra a casa de leilão para varrer.")
        return
    end
    local left = AH.CooldownLeft()
    if left > 0 then
        Qolly.Print(("Scan da AH liberado em %s."):format(Qolly.Ago(left)))
        return
    end
    if not pcall(C_AuctionHouse.ReplicateItems) then
        Qolly.Print("Este client não deixou pedir o scan da AH.")
        return
    end
    AH.db.lastScanRequest = time()
    requestedAt = GetTime()
    Qolly.Print("Varrendo a AH... (pode levar alguns segundos)")
end

-- Busca um texto na aba de compra da AH, como se fosse digitado.
function AH.Browse(text)
    local frame = AuctionHouseFrame
    local bar = frame and frame.SearchBar
    local box = bar and bar.SearchBox
    if not (isOpen and box) then
        return
    end
    if frame.SetDisplayMode and AuctionHouseFrameDisplayMode then
        frame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
    end
    box:SetText(text)
    bar:StartSearch()
end

local function ReadRows(first, last)
    local count = #rowHandlers
    for index = first, last do
        local _, _, quantity, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
            C_AuctionHouse.GetReplicateItemInfo(index)
        if not (Qolly.IsSecret(quantity) or Qolly.IsSecret(buyout) or Qolly.IsSecret(itemID))
            and itemID and quantity and quantity > 0 and buyout and buyout > 0 then
            for handler = 1, count do
                rowHandlers[handler](index, itemID, quantity, buyout)
            end
        end
    end
end

local function ReadSnapshot()
    local total = C_AuctionHouse.GetNumReplicateItems()
    if Qolly.IsSecret(total) or not total or total == 0 then
        Qolly.Log("Scan: lista vazia, nada lido.")
        return
    end
    token = token + 1
    local myToken = token
    reading, progress = true, 0
    Notify("begin")
    local index = 0

    local function Step()
        if myToken ~= token then
            return
        end
        local last = math.min(index + CHUNK, total)
        -- Um erro no meio encerra a leitura: `reading` nunca pode ficar preso em true.
        if not Qolly.Safe("leitura do scan", ReadRows, index + 1, last) then
            reading = false
            lastRead = GetTime()
            return
        end
        index = last
        progress = index / total
        if index < total then
            C_Timer.After(0, Step)
        else
            reading = false
            lastRead = GetTime()
            requestedAt = nil
            doneUntil, doneTotal = GetTime() + DONE_SHOW, total
            Qolly.Print(("Scan da AH: %d anúncios lidos."):format(total))
            Notify("finish", total)
        end
    end
    Step()
end

local function UpdateButton(button)
    if reading then
        button:SetText(("Lendo %d%%"):format(progress * 100))
        button:Disable()
        return
    end
    local left = AH.CooldownLeft()
    if left > 0 then
        button:SetText("Scan em " .. Qolly.Ago(left))
        button:Disable()
    else
        button:SetText("Scan da AH")
        button:Enable()
    end
end

-- O botão de scan mora na aba Qolly da AH (Tab.lua chama isto ao montar a aba).
function AH.CreateButton(parent)
    if AH.button then
        return AH.button
    end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetScript("OnClick", function()
        Qolly.Safe("scan", AH.Request)
    end)
    local elapsed = 1
    button:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            UpdateButton(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Qolly.TAG .. "scan completo da AH")
        GameTooltip:AddLine("Lê todos os anúncios: preços para o Craft e melhorias para o Gear.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    AH.button = button
    return button
end

-- Barra de progresso em cima da janela da AH, em qualquer aba: servidor mandando os
-- dados, leitura dos anúncios e cálculo das melhorias.
local bar

-- Texto e fração (nil = sem porcentagem) do momento, ou nil sem scan em andamento.
local function ScanStatus()
    local gear = Qolly.Gear
    if reading then
        return ("Qolly: lendo anúncios %d%%"):format(progress * 100), progress
    elseif pending or (requestedAt and GetTime() - requestedAt < BAR_WAIT) then
        local count = C_AuctionHouse.GetNumReplicateItems()
        if Qolly.IsSecret(count) or not count or count == 0 then
            return "Qolly: esperando o servidor mandar a AH...", nil
        end
        return ("Qolly: recebendo a AH do servidor (%d anúncios)..."):format(count), nil
    elseif gear and gear.state == "working" then
        return ("Qolly: calculando melhorias %d%%"):format((gear.progress or 0) * 100), gear.progress or 0
    elseif GetTime() < doneUntil then
        local text = ("Qolly: scan concluído, %d anúncios"):format(doneTotal)
        if gear and gear.state == "done" then
            text = text .. (", %d melhorias"):format(#gear.upgrades)
        end
        return text, 1
    end
end

local function UpdateBar()
    local text, fraction = ScanStatus()
    if not text then
        bar:Hide()
        return
    end
    bar.text:SetText(text)
    if fraction then
        bar:SetValue(fraction)
    else
        -- Sem porcentagem: a barra vai e volta, para mostrar que está andando.
        bar:SetValue((math.sin(GetTime() * 3) + 1) / 2)
    end
    bar:Show()
end

local function CreateBar()
    bar = CreateFrame("StatusBar", "QollyScanBar", AuctionHouseFrame, "BackdropTemplate")
    bar:SetHeight(18)
    bar:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "TOPLEFT", 60, 4)
    bar:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "TOPRIGHT", -60, 4)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.6, 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    bar:SetBackdropColor(0, 0, 0, 0.7)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar:Hide()
    -- Um relógio à parte: a barra escondida não roda OnUpdate.
    local clock = CreateFrame("Frame", nil, AuctionHouseFrame)
    local elapsed = 0
    clock:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.05 then
            elapsed = 0
            UpdateBar()
        end
    end)
end

local function OnEvent(event)
    if event == "AUCTION_HOUSE_SHOW" then
        isOpen = true
        if not bar then
            Qolly.Safe("barra do scan", CreateBar)
        end
        Notify("show", AuctionHouseFrame)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        isOpen = false
        token = token + 1
        pending, reading, requestedAt = false, false, nil
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- Também chega para scans pedidos por outros addons: é o mesmo dado, aproveitamos.
        -- O cooldown da Blizzard vale para eles também, então o nosso conta a partir daqui.
        if AH.CooldownLeft() == 0 then
            AH.db.lastScanRequest = time()
        end
        if pending or reading or (lastRead and GetTime() - lastRead < QUIET) then
            return
        end
        pending = true
        local myToken = token
        C_Timer.After(DEBOUNCE, function()
            if myToken ~= token then
                return
            end
            pending = false
            Qolly.Safe("scan", ReadSnapshot)
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
events:SetScript("OnEvent", function(_, event)
    Qolly.Safe(event, OnEvent, event)
end)

Qolly.RegisterModule("ah", {
    help = "scan | status",
    command = function(input)
        local command = strtrim(input):lower()
        if command == "scan" then
            AH.Request()
        else
            local left = AH.CooldownLeft()
            Qolly.Print(left > 0 and ("Próximo scan liberado em " .. Qolly.Ago(left) .. ".")
                or "Scan da AH liberado.")
        end
    end,
    init = function(moduleDB)
        AH.db = moduleDB
    end,
})
