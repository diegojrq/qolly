-- Vendas da AH: cada carta de "Leilão bem-sucedido" vira um registro (item, quantidade,
-- valor, taxa da AH), anotado quando o correio abre, antes de você pegar o ouro. Uma
-- janela soma o líquido por item ou por categoria (ervas, minérios...) num período.
local _, Qolly = ...

local Sales = {}
Qolly.Sales = Sales

local db

-- Carta da AH dura 30 dias: com o tempo restante dá para saber quando ela chegou.
local MAIL_DAYS = 30
local DAY = 86400
-- Uma carta lida de novo (outra abertura do correio) bate com o registro dela se a
-- chegada calculada fica a menos disso.
local TOLERANCE = 300
local MAX_SALES = 20000

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemClassInfo = (C_Item and C_Item.GetItemClassInfo) or GetItemClassInfo
local GetItemSubClassInfo = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo

local TRADE_GOODS = 7
-- Nomes das categorias de material pela profissão que coleta ou usa.
local TRADE_NAMES = {
    [1] = "Engenharia (peças)",
    [4] = "Joalheria",
    [5] = "Tecido",
    [6] = "Couro",
    [7] = "Mineração",
    [8] = "Culinária",
    [9] = "Herborismo",
    [10] = "Elemental",
    [12] = "Encantamento",
}
local UNKNOWN = "Desconhecido"

-- Nome -> itemID ---------------------------------------------------------------

-- A carta só traz o nome do item. O id (para ícone e categoria) vem do que já passou
-- pelas suas bolsas ou foi posto à venda, ou do cache do client.
local function Learn(itemID)
    if not itemID then
        return
    end
    local name = C_Item.GetItemNameByID(itemID)
    if name and not Qolly.IsSecret(name) then
        db.ids[name] = itemID
    end
end

local function LearnBags()
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                Learn(info.itemID)
            end
        end
    end
end

local function ItemID(name)
    return db.ids[name] or (GetItemInfoInstant(name))
end

local categoryCache = {}

local function Category(itemID)
    if not itemID then
        return UNKNOWN
    end
    local known = categoryCache[itemID]
    if known then
        return known
    end
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    local label
    if classID == TRADE_GOODS then
        label = TRADE_NAMES[subClassID] or (GetItemSubClassInfo and GetItemSubClassInfo(classID, subClassID))
    elseif classID then
        label = GetItemClassInfo and GetItemClassInfo(classID)
    end
    label = label or UNKNOWN
    categoryCache[itemID] = label
    return label
end

-- Leitura do correio -------------------------------------------------------------

local function Character()
    return ("%s-%s"):format(UnitName("player"), GetRealmName())
end

local function Key(name, sale, count)
    return ("%s|%d|%d"):format(name, sale, count)
end

local function ScanInbox()
    local now = time()
    -- Registros recentes por chave, para reconhecer cartas já anotadas.
    local recent = {}
    for _, sale in ipairs(db.sales) do
        if now - sale.t < (MAIL_DAYS + 1) * DAY then
            local key = Key(sale.name, sale.sale, sale.count)
            recent[key] = recent[key] or {}
            table.insert(recent[key], sale)
        end
    end
    local matched, added = {}, 0
    for index = 1, GetInboxNumItems() do
        local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(index)
        local invoiceType, itemName, buyer, bid, buyout, _, cut, _, _, _, count = GetInboxInvoiceInfo(index)
        if invoiceType == "seller" and type(itemName) == "string" and not Qolly.IsSecret(itemName)
            and type(daysLeft) == "number" then
            -- Clients sem a quantidade na nota: o assunto termina em "(20)" para pilhas.
            count = tonumber(count)
                or (type(subject) == "string" and tonumber(subject:match("%((%d+)%)%s*$")))
                or 1
            local sale = (bid and bid > 0) and bid or buyout or 0
            local arrival = math.floor(now - (MAIL_DAYS - daysLeft) * DAY)
            local key = Key(itemName, sale, count)
            local found = false
            for _, old in ipairs(recent[key] or {}) do
                if not matched[old] and math.abs(old.t - arrival) <= TOLERANCE then
                    matched[old], found = true, true
                    break
                end
            end
            if not found then
                local entry = {
                    t = arrival,
                    name = itemName,
                    id = ItemID(itemName),
                    count = count,
                    sale = sale,
                    cut = cut or 0,
                    char = Character(),
                    buyer = type(buyer) == "string" and not Qolly.IsSecret(buyer) and buyer or nil,
                }
                table.insert(db.sales, entry)
                matched[entry] = true
                added = added + 1
            end
        end
    end
    while #db.sales > MAX_SALES do
        table.remove(db.sales, 1)
    end
    if added > 0 then
        Qolly.Log(("Vendas: %d novas no correio."):format(added))
        if Sales.Refresh then
            Sales.Refresh()
        end
    end
end

-- O correio dispara MAIL_INBOX_UPDATE várias vezes seguidas: lê uma vez só.
local pending = false
local function QueueScan()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Qolly.Safe("vendas da AH", ScanInbox)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function(_, event)
    if not db then
        return
    end
    if event == "MAIL_INBOX_UPDATE" then
        QueueScan()
    else
        Qolly.Safe("vendas da AH", LearnBags)
    end
end)

-- O item posto à venda some da bolsa: aprende o nome dele na hora de postar.
local function LearnPosted(itemLocation)
    if db and itemLocation and C_Item.DoesItemExist(itemLocation) then
        Learn(C_Item.GetItemID(itemLocation))
    end
end
if C_AuctionHouse then
    for _, name in ipairs({ "PostCommodity", "PostItem" }) do
        if C_AuctionHouse[name] then
            hooksecurefunc(C_AuctionHouse, name, function(itemLocation)
                pcall(LearnPosted, itemLocation)
            end)
        end
    end
end

-- Relatório ---------------------------------------------------------------------

local PERIODS = {
    { key = "today", label = "Hoje" },
    { key = "week", label = "7 dias", days = 7 },
    { key = "month", label = "30 dias", days = 30 },
    { key = "all", label = "Tudo" },
}

local function Since(period)
    if period == "all" then
        return 0
    end
    local now = time()
    if period == "today" then
        local t = date("*t", now)
        return now - (t.hour * 3600 + t.min * 60 + t.sec)
    end
    for _, option in ipairs(PERIODS) do
        if option.key == period then
            return now - option.days * DAY
        end
    end
    return 0
end

-- Linhas somadas: por item ou por categoria, só de uma categoria se pedida.
function Sales.Summary(period, byCategory, onlyCategory)
    local since = Since(period)
    local groups, list = {}, {}
    local total = { sales = 0, count = 0, net = 0 }
    for _, sale in ipairs(db.sales) do
        if sale.t >= since then
            if not sale.id then
                sale.id = ItemID(sale.name)
            end
            local category = Category(sale.id)
            if not onlyCategory or category == onlyCategory then
                local key = byCategory and category or sale.name
                local group = groups[key]
                if not group then
                    group = { label = key, category = byCategory and key or nil, sales = 0, count = 0, net = 0, best = 0 }
                    groups[key] = group
                    list[#list + 1] = group
                end
                local net = sale.sale - sale.cut
                group.sales = group.sales + 1
                group.count = group.count + sale.count
                group.net = group.net + net
                -- Ícone: o do item, ou na categoria o do item que mais rendeu.
                if sale.id and net > group.best then
                    group.best, group.icon = net, C_Item.GetItemIconByID(sale.id)
                end
                total.sales = total.sales + 1
                total.count = total.count + sale.count
                total.net = total.net + net
            end
        end
    end
    table.sort(list, function(a, b)
        return a.net > b.net
    end)
    return list, total
end

-- Janela -------------------------------------------------------------------------
-- O conteúdo (body) vive na aba Qolly da AH ou no painel do Qolly (/qolly vendas).

local ROW_HEIGHT = 18
-- Colunas: rótulo, x (borda esquerda no nome, direita nos números), largura.
local COLUMNS = {
    { label = "Item", x = 24, width = 230, left = true },
    { label = "Vendas", x = 310, width = 50 },
    { label = "Qtd", x = 370, width = 50 },
    { label = "Líquido", x = 480, width = 110 },
    { label = "Média/un", x = 580, width = 100 },
}

local body, rows = nil, {}
local state = { period = "week", byCategory = false, category = nil }

local function Cell(parent, column, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    text:SetWidth(column.width)
    text:SetWordWrap(false)
    if column.left then
        text:SetPoint("LEFT", parent, "LEFT", column.x, 0)
        text:SetJustifyH("LEFT")
    else
        text:SetPoint("RIGHT", parent, "LEFT", column.x, 0)
        text:SetJustifyH("RIGHT")
    end
    return text
end

-- Clicar numa categoria abre os itens dela.
local function OnRowClick(self)
    if self.group and self.group.category then
        state.byCategory, state.category = false, self.group.category
        Sales.Refresh()
    end
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, body.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", body.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", body.content, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.cells = {}
    for i, column in ipairs(COLUMNS) do
        row.cells[i] = Cell(row, column)
    end
    row:SetScript("OnClick", OnRowClick)
    rows[index] = row
    return row
end

function Sales.Refresh()
    if not (body and body:IsVisible()) then
        return
    end
    local list, total = Sales.Summary(state.period, state.byCategory, state.category)
    for index, group in ipairs(list) do
        local row = Row(index)
        row.group = group
        row.icon:SetTexture(group.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.cells[1]:SetText(group.category and (group.label .. " |cff999999»|r") or group.label)
        row.cells[2]:SetText(group.sales)
        row.cells[3]:SetText(group.count)
        row.cells[4]:SetText(Qolly.Money(group.net))
        row.cells[5]:SetText(group.count > 0 and Qolly.Money(group.net / group.count) or "")
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index].group = nil
        rows[index]:Hide()
    end
    body.content:SetHeight(math.max(1, #list * ROW_HEIGHT))
    body.empty:SetShown(#list == 0)

    for _, button in ipairs(body.periods) do
        button:SetEnabled(button.period ~= state.period)
    end
    body.byItem:SetEnabled(state.byCategory or state.category ~= nil)
    body.byCategory:SetEnabled(not state.byCategory)
    body.filter:SetText(state.category and ("Categoria: |cffffffff%s|r"):format(state.category) or "")
    body.clear:SetShown(state.category ~= nil)
    body.total:SetText(("Total líquido: %s  |cff999999em %d vendas, %d unidades|r"):format(
        Qolly.Money(total.net), total.sales, total.count))
end

local function Button(label, width, onClick)
    local button = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(label)
    button:SetScript("OnClick", function()
        Qolly.Safe("vendas da AH", onClick)
    end)
    return button
end

local function CreateBody()
    body = CreateFrame("Frame", "QollySalesBody", UIParent)
    body:Hide()

    body.periods = {}
    local previous
    for _, option in ipairs(PERIODS) do
        local button = Button(option.label, 64, function()
            state.period = option.key
            Sales.Refresh()
        end)
        button.period = option.key
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -4)
        end
        previous = button
        body.periods[#body.periods + 1] = button
    end

    body.byCategory = Button("Por categoria", 100, function()
        state.byCategory, state.category = true, nil
        Sales.Refresh()
    end)
    body.byCategory:SetPoint("TOPRIGHT", body, "TOPRIGHT", -4, -4)
    body.byItem = Button("Por item", 80, function()
        state.byCategory = false
        Sales.Refresh()
    end)
    body.byItem:SetPoint("RIGHT", body.byCategory, "LEFT", -4, 0)

    body.filter = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body.filter:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -36)
    body.clear = Button("Todas", 60, function()
        state.category = nil
        Sales.Refresh()
    end)
    body.clear:SetPoint("LEFT", body.filter, "RIGHT", 8, 0)

    local header = CreateFrame("Frame", nil, body)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -58)
    header:SetPoint("RIGHT", body, "RIGHT", -24, 0)
    for _, column in ipairs(COLUMNS) do
        Cell(header, column, "GameFontNormalSmall"):SetText(column.label)
    end

    local scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -24, 24)
    body.content = CreateFrame("Frame", nil, scroll)
    body.content:SetSize(1, 1)
    scroll:SetScrollChild(body.content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        body.content:SetWidth(width)
    end)

    body.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    body.empty:SetPoint("CENTER", scroll, "CENTER")
    body.empty:SetText("Nenhuma venda no período.\nAs vendas são anotadas quando você abre o correio.")

    body.total = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body.total:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 4)

    body:SetScript("OnShow", function()
        Qolly.Safe("vendas da AH", Sales.Refresh)
    end)
end

local function Host(parent, left, top, right, bottom)
    if not body then
        CreateBody()
    end
    body:SetParent(parent)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", parent, "TOPLEFT", left or 0, top or 0)
    body:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right or 0, bottom or 0)
    body:Show()
    return body
end

-- Página "Vendas" da aba Qolly da AH.
function Sales.Embed(parent)
    return Host(parent)
end

-- Fora da AH as vendas abrem no painel do Qolly, aba Vendas.
function Sales.Toggle()
    Qolly.Income.ShowTab("ah")
    Qolly.Options.Open("Ganhos")
end

Qolly.RegisterModule("vendas", {
    help = "(lucro na AH por item e por categoria)",
    command = function()
        Sales.Toggle()
    end,
    init = function(moduleDB)
        db = moduleDB
        db.sales = db.sales or {}
        db.ids = db.ids or {}
    end,
})
