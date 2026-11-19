-- Essências: 1 maior quebra em 3 inferiores e 3 inferiores juntam em 1 maior (botão
-- direito na essência, qualquer um pode). Página no painel Qolly da AH com a margem dos
-- dois sentidos para cada tipo, a conta passo a passo e o histórico das margens.
-- Os preços vêm do scan completo e também das buscas normais na AH: pesquisar
-- "Essência" atualiza todas de uma vez, e abrir uma essência traz os anúncios dela.
local _, Qolly = ...
local AH = Qolly.AH

local Essences = {}
Qolly.Essences = Essences

local db

local AH_CUT = 0.95      -- a AH fica com 5% da venda
local KEEP_LISTINGS = 20 -- faixas de preço guardadas por essência
local LOG_SIZE = 60      -- registros de histórico por tipo
local LOG_SAME = 1800    -- preços iguais dentro de 30 min não viram registro novo

-- { inferior, maior }
local PAIRS = {
    { 10938, 10939 }, -- Mágica
    { 10998, 11082 }, -- Astral
    { 11134, 11135 }, -- Mística
    { 11174, 11175 }, -- Éter
    { 16202, 16203 }, -- Eterna
}
local WANTED = {}
for _, pair in ipairs(PAIRS) do
    WANTED[pair[1]], WANTED[pair[2]] = true, true
end

-- Preços -----------------------------------------------------------------------------

-- listings: { {preço unitário, quantidade}, ... } em qualquer ordem.
local function SetListings(itemID, listings, source)
    if #listings == 0 then
        return
    end
    table.sort(listings, function(a, b)
        return a[1] < b[1]
    end)
    local total, kept = 0, {}
    for index, listing in ipairs(listings) do
        total = total + listing[2]
        if index <= KEEP_LISTINGS then
            kept[index] = { listing[1], listing[2] }
        end
    end
    db.prices[itemID] = { p = listings[1][1], q = total, l = kept, at = time(), src = source }
end

-- Só o menor preço e o total (resultado da busca, sem as faixas).
local function SetSummary(itemID, price, quantity)
    if not price or price <= 0 then
        return
    end
    db.prices[itemID] = { p = price, q = quantity or 0, at = time(), src = "busca" }
end

-- Unidades da lista abaixo de `limit` e o lucro de cada uma valendo `value`.
local function Depth(listings, limit, value)
    local qty, profit = 0, 0
    for _, listing in ipairs(listings) do
        if listing[1] >= limit then
            break
        end
        qty = qty + listing[2]
        profit = profit + (value - listing[1]) * listing[2]
    end
    return qty, profit
end

-- As duas contas de um tipo, ou nil sem os dois preços.
local function Deal(pair)
    local lesser, greater = db.prices[pair[1]], db.prices[pair[2]]
    if not (lesser and greater) then
        return nil
    end
    local deal = { lesser = lesser, greater = greater }

    -- Quebrar: compra 1 maior, vende 3 inferiores.
    local split = { cost = greater.p, gross = 3 * lesser.p }
    split.net = split.gross * AH_CUT
    split.profit = split.net - split.cost
    split.pct = split.profit / split.cost
    split.limit = split.net -- maior até este preço ainda dá lucro
    if greater.l then
        split.qty, split.total = Depth(greater.l, split.limit, split.net)
    end
    deal.split = split

    -- Juntar: compra 3 inferiores, vende 1 maior.
    local join = { cost = 3 * lesser.p, gross = greater.p }
    join.net = join.gross * AH_CUT
    join.profit = join.net - join.cost
    join.pct = join.profit / join.cost
    join.limit = join.net / 3 -- inferior até este preço ainda dá lucro
    if lesser.l then
        local qty, total = Depth(lesser.l, join.limit, join.limit)
        join.qty, join.total = qty - qty % 3, total
    end
    deal.join = join
    return deal
end

local function Log()
    local now = time()
    for index, pair in ipairs(PAIRS) do
        local lesser, greater = db.prices[pair[1]], db.prices[pair[2]]
        if lesser and greater then
            local log = db.log[index] or {}
            db.log[index] = log
            local last = log[#log]
            if not (last and last.l == lesser.p and last.g == greater.p and now - last.t < LOG_SAME) then
                log[#log + 1] = { t = now, l = lesser.p, g = greater.p }
                while #log > LOG_SIZE do
                    table.remove(log, 1)
                end
            end
        end
    end
end

local updateTimer
local function Changed()
    if updateTimer then
        return
    end
    updateTimer = C_Timer.NewTimer(0.5, function()
        updateTimer = nil
        Log()
        Essences.Refresh()
    end)
end

-- Scan completo
local collecting
AH.AddListener({
    begin = function()
        collecting = {}
    end,
    row = function(_, itemID, count, buyout)
        if collecting and WANTED[itemID] and count > 0 and buyout and buyout > 0 then
            local list = collecting[itemID] or {}
            collecting[itemID] = list
            list[#list + 1] = { buyout / count, count }
        end
    end,
    finish = function()
        if not collecting then
            return
        end
        for itemID, listings in pairs(collecting) do
            SetListings(itemID, listings, "scan")
        end
        collecting = nil
        Changed()
    end,
})

-- Buscas normais na AH
local function Plain(value)
    return value ~= nil and not Qolly.IsSecret(value)
end

local function ReadBrowse()
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then
        return
    end
    local changed = false
    for _, result in ipairs(results) do
        local key = result.itemKey
        local itemID = key and key.itemID
        if Plain(itemID) and WANTED[itemID] and Plain(result.minPrice) and Plain(result.totalQuantity) then
            SetSummary(itemID, result.minPrice, result.totalQuantity)
            changed = true
        end
    end
    if changed then
        Changed()
    end
end

local function ReadCommodity(itemID)
    if not (Plain(itemID) and WANTED[itemID]) then
        return
    end
    local ok, count = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    if not ok or not Plain(count) or count == 0 then
        return
    end
    local listings = {}
    for index = 1, math.min(count, 60) do
        local found, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, index)
        if found and info and Plain(info.unitPrice) and Plain(info.quantity) then
            listings[#listings + 1] = { info.unitPrice, info.quantity }
        end
    end
    SetListings(itemID, listings, "busca")
    Changed()
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if not db then
        return
    end
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        Qolly.Safe("essências", ReadCommodity, ...)
    else
        Qolly.Safe("essências", ReadBrowse)
    end
end)

-- Página ---------------------------------------------------------------------------------

local GREEN, RED, GREY, GOLD = "|cff66ff66", "|cffff6666", "|cff999999", "|cffffd100"
local ROW_HEIGHT = 26
local HISTORY_LINES = 14
local LINE = 13
local COLUMNS = {
    { label = "Essência", x = 8, width = 180 },
    { label = "Inferior", x = 192, width = 120 },
    { label = "Maior", x = 316, width = 120 },
    { label = "Quebrar 1 Maior", x = 440, width = 150 },
    { label = "Juntar 3 Inferiores", x = 594, width = 150 },
}

local frame
local rows = {}

local function Pct(value)
    return (("%+.1f%%"):format(value * 100):gsub("%.", ","))
end

local function Signed(copper)
    copper = math.floor(copper + 0.5)
    return (copper > 0 and "+" or "") .. Qolly.Money(copper)
end

local function Colored(value, text)
    return (value > 0 and GREEN or RED) .. text .. "|r"
end

local function Name(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return name
end

local function TierName(index)
    local name = Name(PAIRS[index][2])
    if not name then
        return "Essência " .. index
    end
    return (name:gsub("%s+Maior$", ""):gsub("^Greater%s+", ""))
end

local function SearchWord()
    local name = Name(PAIRS[1][1])
    return name and name:match("^(%S+)") or "Essência"
end

local function PriceText(price)
    if not price then
        return GREY .. "sem preço|r"
    end
    return Qolly.Money(price.p) .. "\n" .. GREY .. ("%d na AH · %s há %s"):format(
        price.q, price.src or "scan", Qolly.Ago(time() - price.at)) .. "|r"
end

local function DealText(side)
    if not side then
        return GREY .. "-|r"
    end
    return Colored(side.profit, Signed(side.profit) .. "  " .. Pct(side.pct))
end

-- Linhas da conta: left, right, (cor do texto da esquerda).
local lines = {}
local function Line(index)
    local line = lines[index]
    if not line then
        local parent = frame.detail
        line = {}
        line.left = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8 - (index - 1) * LINE)
        line.left:SetWidth(250)
        line.left:SetJustifyH("LEFT")
        line.left:SetWordWrap(false)
        line.right = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.right:SetPoint("TOPLEFT", parent, "TOPLEFT", 262, -8 - (index - 1) * LINE)
        line.right:SetWidth(110)
        line.right:SetJustifyH("RIGHT")
        lines[index] = line
    end
    return line
end

local function Account(deal)
    local out = {}
    local function Add(left, right)
        out[#out + 1] = { left, right or "" }
    end
    local lesser, greater = deal.lesser, deal.greater
    local split, join = deal.split, deal.join

    Add(GOLD .. "Quebrar 1 Maior em 3 Inferiores|r")
    Add("  Compra 1 Maior", Qolly.Money(split.cost))
    Add("  Vende 3 Inferiores a " .. Qolly.Money(lesser.p), Qolly.Money(split.gross))
    Add("  Taxa da AH (5%)", "-" .. Qolly.Money(split.gross - split.net))
    Add("  Lucro por Maior", Colored(split.profit, Signed(split.profit) .. " (" .. Pct(split.pct) .. ")"))
    Add(GREY .. "  Compensa pagar até " .. Qolly.Money(split.limit) .. " na Maior|r")
    if split.qty then
        if split.qty > 0 then
            Add(GREY .. ("  Na AH: %d Maiores abaixo disso, lucro ~%s|r"):format(split.qty, Qolly.Money(split.total)))
        else
            Add(GREY .. "  Na AH: nenhuma Maior abaixo disso|r")
        end
    end
    Add("")
    Add(GOLD .. "Juntar 3 Inferiores em 1 Maior|r")
    Add("  Compra 3 Inferiores a " .. Qolly.Money(lesser.p), Qolly.Money(join.cost))
    Add("  Vende 1 Maior", Qolly.Money(join.gross))
    Add("  Taxa da AH (5%)", "-" .. Qolly.Money(join.gross - join.net))
    Add("  Lucro por Maior", Colored(join.profit, Signed(join.profit) .. " (" .. Pct(join.pct) .. ")"))
    Add(GREY .. "  Compensa pagar até " .. Qolly.Money(join.limit) .. " na Inferior|r")
    if join.qty then
        if join.qty > 0 then
            Add(GREY .. ("  Na AH: %d Inferiores abaixo disso, lucro ~%s|r"):format(join.qty, Qolly.Money(join.total)))
        else
            Add(GREY .. "  Na AH: nenhuma Inferior abaixo disso|r")
        end
    end
    Add("")
    Add(GREY .. ("Vender pelo menor preço depende da fila: há %d Inferiores|r"):format(lesser.q))
    Add(GREY .. ("e %d Maiores anunciadas. O depósito do anúncio não entra.|r"):format(greater.q))
    return out
end

local function ShowHistory(index)
    local log = db.log[index] or {}
    local splitSum, joinSum, splitWins = 0, 0, 0
    for _, entry in ipairs(log) do
        local split = (3 * entry.l * AH_CUT - entry.g) / entry.g
        local join = (entry.g * AH_CUT - 3 * entry.l) / (3 * entry.l)
        splitSum, joinSum = splitSum + split, joinSum + join
        if split > 0 then
            splitWins = splitWins + 1
        end
    end
    if #log == 0 then
        frame.historyTitle:SetText(GOLD .. "Histórico|r")
        frame.historySummary:SetText(GREY .. "Ainda sem registros. Cada scan ou busca na AH adiciona um.|r")
    else
        frame.historyTitle:SetText(GOLD .. ("Histórico (%d registros)|r"):format(#log))
        frame.historySummary:SetText(("Média: quebrar %s, juntar %s. Quebrar deu lucro em %d de %d."):format(
            Colored(splitSum, Pct(splitSum / #log)), Colored(joinSum, Pct(joinSum / #log)), splitWins, #log))
    end
    for line = 1, HISTORY_LINES do
        local entry = log[#log - line + 1]
        local text = frame.history[line]
        if entry then
            local split = (3 * entry.l * AH_CUT - entry.g) / entry.g
            local join = (entry.g * AH_CUT - 3 * entry.l) / (3 * entry.l)
            text.left:SetText(("%s   %s / %s"):format(date("%d/%m %H:%M", entry.t), Qolly.Money(entry.l), Qolly.Money(entry.g)))
            text.right:SetText(Colored(split, Pct(split)) .. "  " .. Colored(join, Pct(join)))
        else
            text.left:SetText("")
            text.right:SetText("")
        end
    end
end

local function Best()
    local best, bestProfit
    for index, pair in ipairs(PAIRS) do
        local deal = Deal(pair)
        if deal then
            local profit = math.max(deal.split.pct, deal.join.pct)
            if not bestProfit or profit > bestProfit then
                best, bestProfit = index, profit
            end
        end
    end
    return best or 1
end

function Essences.Refresh()
    if not frame or not frame:IsVisible() then
        return
    end
    local selected = db.selected or Best()
    local oldest
    for index, pair in ipairs(PAIRS) do
        local row = rows[index]
        local deal = Deal(pair)
        row.icon:SetTexture(C_Item.GetItemIconByID(pair[2]) or 134400)
        row.name:SetText(TierName(index))
        row.lesser:SetText(PriceText(db.prices[pair[1]]))
        row.greater:SetText(PriceText(db.prices[pair[2]]))
        row.split:SetText(DealText(deal and deal.split))
        row.join:SetText(DealText(deal and deal.join))
        row.selected:SetShown(index == selected)
        for _, id in ipairs(pair) do
            local price = db.prices[id]
            if price and (not oldest or price.at < oldest) then
                oldest = price.at
            end
        end
    end

    local deal = Deal(PAIRS[selected])
    local account = deal and Account(deal) or {
        { GREY .. "Sem os preços de " .. TierName(selected) .. ".|r", "" },
        { GREY .. "Faça um scan ou clique em Atualizar preços.|r", "" },
    }
    frame.accountTitle:SetText(GOLD .. "A conta: " .. TierName(selected) .. "|r")
    for index = 1, math.max(#account, #lines) do
        local line = Line(index)
        local entry = account[index]
        line.left:SetText(entry and entry[1] or "")
        line.right:SetText(entry and entry[2] or "")
    end
    ShowHistory(selected)

    if oldest then
        frame.status:SetText(("Preço mais antigo: há %s. Atualizar preços pesquisa \"%s\" na AH; abrir uma essência na AH traz os anúncios dela."):format(
            Qolly.Ago(time() - oldest), SearchWord()))
    else
        frame.status:SetText("Sem preços ainda: faça um scan ou clique em Atualizar preços.")
    end
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -60 - (index - 1) * ROW_HEIGHT)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(0.3, 0.6, 1, 0.18)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", COLUMNS[1].x, 0)
    local function Text(column, font)
        local text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", COLUMNS[column].x, 0)
        text:SetWidth(COLUMNS[column].width)
        text:SetJustifyH("LEFT")
        return text
    end
    row.name = Text(1, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(COLUMNS[1].width - 30)
    row.name:SetWordWrap(false)
    row.lesser = Text(2)
    row.greater = Text(3)
    row.split = Text(4)
    row.join = Text(5)
    row:SetScript("OnClick", function()
        db.selected = index
        Essences.Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(PAIRS[index][2])
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Qolly.TAG .. "clique: ver a conta e o histórico", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
end

local function CreatePage(parent)
    frame = CreateFrame("Frame", "QollyEssencesPage", parent)

    local refresh = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refresh:SetSize(140, 22)
    refresh:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    refresh:SetText("Atualizar preços")
    refresh:SetScript("OnClick", function()
        AH.Browse(SearchWord())
    end)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    frame.status:SetWidth(590)
    frame.status:SetJustifyH("LEFT")

    for _, column in ipairs(COLUMNS) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4 + column.x, -40)
        header:SetText(column.label)
    end
    for index = 1, #PAIRS do
        CreateRow(index)
    end

    local top = -60 - #PAIRS * ROW_HEIGHT - 10
    frame.accountTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.accountTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, top)
    frame.detail = CreateFrame("Frame", nil, frame)
    frame.detail:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, top - 16)
    frame.detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 6)
    frame.detail:SetWidth(380)
    local background = frame.detail:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.3)

    frame.historyTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.historyTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 396, top)
    local history = CreateFrame("Frame", nil, frame)
    history:SetPoint("TOPLEFT", frame, "TOPLEFT", 390, top - 16)
    history:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 6)
    local historyBackground = history:CreateTexture(nil, "BACKGROUND")
    historyBackground:SetAllPoints()
    historyBackground:SetColorTexture(0, 0, 0, 0.3)
    frame.historySummary = history:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.historySummary:SetPoint("TOPLEFT", history, "TOPLEFT", 8, -8)
    frame.historySummary:SetWidth(340)
    frame.historySummary:SetJustifyH("LEFT")
    local legend = history:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    legend:SetPoint("TOPLEFT", history, "TOPLEFT", 8, -40)
    legend:SetWidth(340)
    legend:SetJustifyH("LEFT")
    legend:SetText("quando   Inferior / Maior                    quebrar   juntar")
    frame.history = {}
    for line = 1, HISTORY_LINES do
        local y = -56 - (line - 1) * LINE
        local left = history:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", history, "TOPLEFT", 8, y)
        left:SetWidth(230)
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = history:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOPRIGHT", history, "TOPRIGHT", -8, y)
        right:SetWidth(120)
        right:SetJustifyH("RIGHT")
        frame.history[line] = { left = left, right = right }
    end

    frame:SetScript("OnShow", Essences.Refresh)
end

function Essences.IsOpen()
    return frame ~= nil and frame:IsVisible()
end

function Essences.Embed(parent)
    if not frame then
        CreatePage(parent)
    end
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetAllPoints(parent)
    C_Timer.After(0, Essences.Refresh)
    return frame
end

Qolly.RegisterModule("essencias", {
    help = "(quebrar ou juntar essências: lucro de cada tipo com os últimos preços)",
    command = function()
        local any = false
        for index, pair in ipairs(PAIRS) do
            local deal = Deal(pair)
            if deal then
                any = true
                Qolly.Print(("%s: quebrar %s, juntar %s"):format(TierName(index),
                    Colored(deal.split.profit, Signed(deal.split.profit) .. " " .. Pct(deal.split.pct)),
                    Colored(deal.join.profit, Signed(deal.join.profit) .. " " .. Pct(deal.join.pct))))
            end
        end
        if not any then
            Qolly.Print("Sem preços de essência. Faça um scan ou uma busca na AH.")
        end
    end,
    init = function(saved)
        db = saved
        db.prices = db.prices or {}
        db.log = db.log or {}
    end,
})
