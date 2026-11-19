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

-- Operações: compras de essência na AH -------------------------------------------------
-- A compra de commodity passa por StartCommoditiesPurchase (o jogo devolve o preço total
-- em COMMODITY_PRICE_UPDATED) e ConfirmCommoditiesPurchase; o sucesso chega por evento
-- ou pela mensagem "Você ganhou um leilão de ...". As vendas vêm do módulo de vendas
-- (cartas da AH no correio).

local MAX_TRADES = 2000
local pendingBuy

local function Estimate(itemID, quantity)
    local price = db.prices[itemID]
    if not price then
        return nil
    end
    local left, total = quantity, 0
    for _, listing in ipairs(price.l or {}) do
        local take = math.min(left, listing[2])
        total, left = total + take * listing[1], left - take
        if left == 0 then
            return total
        end
    end
    return total + left * price.p
end

local function AddTrade(itemID, quantity, total, source)
    db.trades[#db.trades + 1] = { t = time(), id = itemID, qty = quantity, total = total, src = source }
    while #db.trades > MAX_TRADES do
        table.remove(db.trades, 1)
    end
    local name = C_Item.GetItemNameByID(itemID) or ("item " .. itemID)
    Qolly.Log(("Essências: compra %dx %s por %s (%s)"):format(quantity, name, tostring(total), source))
    Qolly.Print(("Essências: compra de %dx %s por %s registrada."):format(quantity, name, Qolly.Money(total or 0)))
end

local function FinishBuy()
    local buy = pendingBuy
    pendingBuy = nil
    if not (buy and buy.confirmed and buy.qty and buy.qty > 0) then
        return
    end
    local total = buy.total or Estimate(buy.id, buy.qty)
    AddTrade(buy.id, buy.qty, total, buy.total and "ah" or "ah estimado")
    Changed()
end

local function HookAH(name, handler)
    if C_AuctionHouse and C_AuctionHouse[name] then
        hooksecurefunc(C_AuctionHouse, name, function(...)
            if db then
                pcall(handler, ...)
            end
        end)
    end
end

HookAH("StartCommoditiesPurchase", function(itemID, quantity)
    if WANTED[itemID] then
        pendingBuy = { id = itemID, qty = quantity }
    else
        pendingBuy = nil
    end
end)

HookAH("ConfirmCommoditiesPurchase", function(itemID, quantity)
    if not WANTED[itemID] then
        return
    end
    if not (pendingBuy and pendingBuy.id == itemID) then
        pendingBuy = { id = itemID }
    end
    pendingBuy.qty = quantity or pendingBuy.qty
    pendingBuy.confirmed = true
end)

local buyEvents = CreateFrame("Frame")
for _, event in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "CHAT_MSG_SYSTEM" }) do
    pcall(buyEvents.RegisterEvent, buyEvents, event)
end
buyEvents:SetScript("OnEvent", function(_, event, first, second)
    if not (db and pendingBuy) then
        return
    end
    if event == "COMMODITY_PRICE_UPDATED" then
        if Plain(second) and not pendingBuy.confirmed then
            pendingBuy.total = second
        end
    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        Qolly.Safe("essências", FinishBuy)
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        pendingBuy = nil
    elseif event == "CHAT_MSG_SYSTEM" and pendingBuy.confirmed and Plain(first) then
        local name = C_Item.GetItemNameByID(pendingBuy.id)
        if name and first:find(name, 1, true) then
            Qolly.Safe("essências", FinishBuy)
        end
    end
end)

-- Compras e vendas de um tipo: totais e a lista, mais nova primeiro.
local function Operations(pair)
    local names = {}
    for _, id in ipairs(pair) do
        local name = C_Item.GetItemNameByID(id)
        if name then
            names[name] = id
        end
    end
    local ops = { bought = { [pair[1]] = 0, [pair[2]] = 0 }, sold = { [pair[1]] = 0, [pair[2]] = 0 },
        spent = 0, got = 0, list = {} }
    local first
    for _, trade in ipairs(db.trades) do
        if trade.id == pair[1] or trade.id == pair[2] then
            first = first or trade.t
            ops.bought[trade.id] = ops.bought[trade.id] + trade.qty
            ops.spent = ops.spent + (trade.total or 0)
            ops.list[#ops.list + 1] = { t = trade.t, id = trade.id, qty = trade.qty, money = -(trade.total or 0), buy = true }
        end
    end
    if first and Qolly.Sales and Qolly.Sales.Entries then
        for _, sale in ipairs(Qolly.Sales.Entries()) do
            local id = (sale.id == pair[1] or sale.id == pair[2]) and sale.id or names[sale.name]
            if id and sale.t >= first - 60 then
                local net = (sale.sale or 0) - (sale.cut or 0)
                ops.sold[id] = ops.sold[id] + (sale.count or 1)
                ops.got = ops.got + net
                ops.list[#ops.list + 1] = { t = sale.t, id = id, qty = sale.count or 1, money = net }
            end
        end
    end
    table.sort(ops.list, function(a, b)
        return a.t > b.t
    end)
    -- Estoque contado em inferiores: cada maior vale 3.
    ops.stock = 3 * (ops.bought[pair[2]] - ops.sold[pair[2]]) + ops.bought[pair[1]] - ops.sold[pair[1]]
    ops.any = first ~= nil
    return ops
end

-- Página ---------------------------------------------------------------------------------

local GREEN, RED, GREY, GOLD = "|cff66ff66", "|cffff6666", "|cff999999", "|cffffd100"
local ROW_HEIGHT = 30
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

-- Preço e, embaixo, quantas há e de quando.
local function PriceText(price)
    if not price then
        return GREY .. "sem preço|r", ""
    end
    return Qolly.Money(price.p), ("%d · %s %s"):format(price.q, price.src or "scan", Qolly.Ago(time() - price.at))
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
        line.left:SetWidth(230)
        line.left:SetJustifyH("LEFT")
        line.left:SetWordWrap(false)
        line.right = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8 - (index - 1) * LINE)
        line.right:SetWidth(130)
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
    Add(GREY .. ("Na fila de venda: %d Inferiores e %d Maiores.|r"):format(lesser.q, greater.q))
    Add(GREY .. "O depósito do anúncio não entra na conta.|r")
    return out
end

local function Size(id, pair)
    return id == pair[2] and "Maior" or "Inferior"
end

local function OperationsLines(index)
    local pair = PAIRS[index]
    local ops = Operations(pair)
    local out = {}
    local function Add(left, right)
        out[#out + 1] = { left, right or "" }
    end
    if not ops.any then
        Add(GREY .. "Nenhuma compra registrada deste tipo.|r")
        Add(GREY .. "Compras na AH entram sozinhas; as vendas entram|r")
        Add(GREY .. "quando você abre o correio. Para uma compra antiga:|r")
        Add(GREY .. "/qolly essencias compra 6 eterna maior 2g50s80c|r")
        return out
    end
    for _, id in ipairs({ pair[2], pair[1] }) do
        if ops.bought[id] > 0 then
            local spent = 0
            for _, op in ipairs(ops.list) do
                if op.buy and op.id == id then
                    spent = spent - op.money
                end
            end
            Add(("  Comprou %d %s"):format(ops.bought[id], Size(id, pair)), "-" .. Qolly.Money(spent))
        end
    end
    for _, id in ipairs({ pair[1], pair[2] }) do
        if ops.sold[id] > 0 then
            local got = 0
            for _, op in ipairs(ops.list) do
                if not op.buy and op.id == id then
                    got = got + op.money
                end
            end
            Add(("  Vendeu %d %s (já sem a taxa)"):format(ops.sold[id], Size(id, pair)), "+" .. Qolly.Money(got))
        end
    end
    local balance = ops.got - ops.spent
    Add("  Saldo até agora", Colored(balance, Signed(balance)))
    local lesser = db.prices[pair[1]]
    if ops.stock > 0 then
        local value = lesser and ops.stock * lesser.p * AH_CUT
        Add(("  Falta vender: %d Inferiores (contando 3 por Maior)"):format(ops.stock),
            value and ("~" .. Qolly.Money(value)) or "")
        if value then
            local result = balance + value
            Add("  Resultado vendendo o resto a " .. Qolly.Money(lesser.p),
                Colored(result, Signed(result) .. (ops.spent > 0 and (" (" .. Pct(result / ops.spent) .. ")") or "")))
        end
    elseif ops.spent > 0 then
        Add("  Resultado", Colored(balance, Signed(balance) .. " (" .. Pct(balance / ops.spent) .. ")"))
    end
    Add("")
    Add(GOLD .. "Últimas|r")
    for line = 1, math.min(#ops.list, 8) do
        local op = ops.list[line]
        Add(("  %s  %s %d %s"):format(date("%d/%m %H:%M", op.t), op.buy and "compra" or "venda", op.qty, Size(op.id, pair)),
            Colored(op.money, Signed(op.money)))
    end
    Add(GREY .. "Vendas entram quando você abre o correio.|r")
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
        row.lesser.price:SetText((PriceText(db.prices[pair[1]])))
        row.lesser.sub:SetText(select(2, PriceText(db.prices[pair[1]])))
        row.greater.price:SetText((PriceText(db.prices[pair[2]])))
        row.greater.sub:SetText(select(2, PriceText(db.prices[pair[2]])))
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

    local account
    if db.view == "ops" then
        account = OperationsLines(selected)
        frame.accountTitle:SetText(GOLD .. "Minhas operações: " .. TierName(selected) .. "|r")
    else
        local deal = Deal(PAIRS[selected])
        account = deal and Account(deal) or {
            { GREY .. "Sem os preços de " .. TierName(selected) .. ".|r", "" },
            { GREY .. "Faça um scan ou clique em Atualizar preços.|r", "" },
        }
        frame.accountTitle:SetText(GOLD .. "A conta: " .. TierName(selected) .. "|r")
    end
    for index = 1, math.max(#account, #lines) do
        local line = Line(index)
        local entry = account[index]
        local right = entry and entry[2] or ""
        line.left:SetText(entry and entry[1] or "")
        line.left:SetWidth(right == "" and 364 or 230)
        line.right:SetText(right)
    end
    for _, button in ipairs(frame.views) do
        if button.key == (db.view or "conta") then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    ShowHistory(selected)

    if oldest then
        frame.status:SetText(("Preço mais antigo: %s. Atualizar pesquisa \"%s\"; abrir uma essência na AH traz os anúncios dela."):format(
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
    local function Price(column)
        local cell = {}
        cell.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.price:SetPoint("TOPLEFT", row, "TOPLEFT", COLUMNS[column].x, -3)
        cell.price:SetWidth(COLUMNS[column].width)
        cell.price:SetJustifyH("LEFT")
        cell.price:SetWordWrap(false)
        cell.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        cell.sub:SetPoint("TOPLEFT", row, "TOPLEFT", COLUMNS[column].x, -16)
        cell.sub:SetWidth(COLUMNS[column].width)
        cell.sub:SetJustifyH("LEFT")
        cell.sub:SetWordWrap(false)
        return cell
    end
    row.lesser = Price(2)
    row.greater = Price(3)
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
    frame.status:SetWidth(380)
    frame.status:SetWordWrap(true)

    frame.views = {}
    local previous
    for _, view in ipairs({ { key = "ops", label = "Operações" }, { key = "conta", label = "A conta" } }) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(100, 22)
        button:SetText(view.label)
        button.key = view.key
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
        end
        button:SetScript("OnClick", function()
            db.view = view.key
            Essences.Refresh()
        end)
        frame.views[#frame.views + 1] = button
        previous = button
    end
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

local TIER_WORDS = {
    magica = 1, ["mágica"] = 1, astral = 2, mistica = 3, ["mística"] = 3,
    eter = 4, eterea = 4, ["etérea"] = 4, eterna = 5,
}

-- "2g50s80c", "50s", "25080" -> cobre
local function ParseMoney(text)
    if not text then
        return nil
    end
    if text:match("^%d+$") then
        return tonumber(text)
    end
    local total, found = 0, false
    for amount, unit in text:gmatch("(%d+)([gsc])") do
        total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        found = true
    end
    return found and total or nil
end

-- /qolly essencias compra <qtd> <tipo> <maior|inferior> <preço de cada>
local function ManualBuy(argument)
    local qty, tier, size, price = argument:match("^compra%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)")
    local index = tier and TIER_WORDS[tier:lower()]
    local unit = ParseMoney(price)
    size = size and size:lower()
    if not (qty and index and unit and (size == "maior" or size == "inferior" or size == "menor")) then
        Qolly.Print("Uso: /qolly essencias compra 6 eterna maior 2g50s80c  (tipos: magica, astral, mistica, eterea, eterna)")
        return
    end
    local id = PAIRS[index][size == "maior" and 2 or 1]
    qty = tonumber(qty)
    AddTrade(id, qty, unit * qty, "manual")
    Changed()
end

Qolly.RegisterModule("essencias", {
    help = "(lucro de quebrar/juntar; \"compra 6 eterna maior 2g50s80c\" registra uma compra; \"desfaz\" apaga a última)",
    command = function(argument)
        argument = argument or ""
        if argument:match("^compra") then
            ManualBuy(argument)
            return
        elseif argument == "desfaz" then
            local last = table.remove(db.trades)
            Qolly.Print(last and ("Essências: removida a compra de %dx %s."):format(last.qty,
                C_Item.GetItemNameByID(last.id) or last.id) or "Essências: nenhuma compra para remover.")
            Essences.Refresh()
            return
        end
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
        db.trades = db.trades or {}
    end,
})
