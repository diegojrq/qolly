-- Ganhos: toda mudança no seu ouro é anotada com a origem (missão, saque, vendedor,
-- AH, correio...). A origem vem da janela aberta no momento (vendedor, correio, AH,
-- recompensa de missão, saque) ou de uma marca curta que outra ação deixa (vender o
-- lixo, consertar, pegar o ouro de uma carta da AH).
-- Fica guardado por dia, personagem e origem: db.days[AAAAMMDD][personagem][origem] =
-- { i = ganho, o = gasto }, em cobre.
local _, Qolly = ...

local Income = {}
Qolly.Income = Income

local db

local DAY = 86400
-- Uma marca vale por este tempo: o ouro chega do servidor um instante depois da ação.
local TAG_SECONDS = 2.5

-- Origens, na ordem em que aparecem na tabela.
local SOURCES = {
    { key = "missao", label = "Missões", icon = "Interface/Icons/INV_Misc_Note_01" },
    { key = "saque", label = "Saque", icon = "Interface/Icons/INV_Misc_Bag_10" },
    { key = "lixo", label = "Lixo vendido", icon = "Interface/Icons/INV_Misc_Bone_HumanSkull_01" },
    { key = "vendedor", label = "Vendedor (vendas e compras)", icon = "Interface/Icons/INV_Misc_Coin_02" },
    { key = "ah", label = "AH (vendas, lances e depósitos)", icon = "Interface/Icons/INV_Hammer_15" },
    { key = "correio", label = "Correio", icon = "Interface/Icons/INV_Letter_15" },
    { key = "troca", label = "Trocas", icon = "Interface/Icons/INV_Misc_Coin_04" },
    { key = "reparo", label = "Reparos", icon = "Interface/Icons/Trade_BlackSmithing" },
    { key = "treinador", label = "Treinador", icon = "Interface/Icons/INV_Misc_Book_09" },
    { key = "voo", label = "Voos", icon = "Interface/Icons/Ability_Mount_Wyvern_01" },
    { key = "guilda", label = "Banco da guilda", icon = "Interface/Icons/INV_Misc_Bag_EnchantedRunecloth" },
    { key = "outros", label = "Outros", icon = "Interface/Icons/INV_Misc_QuestionMark" },
}
local LABELS = {}
for _, source in ipairs(SOURCES) do
    LABELS[source.key] = source
end

-- Janelas que dizem a origem enquanto estão abertas, da mais específica para a menos.
local WINDOW_ORDER = { "missao", "saque", "correio", "ah", "vendedor", "troca", "treinador", "voo", "guilda" }
local WINDOW_EVENTS = {
    QUEST_COMPLETE = { "missao", true }, QUEST_FINISHED = { "missao", false },
    LOOT_OPENED = { "saque", true }, LOOT_CLOSED = { "saque", false },
    MAIL_SHOW = { "correio", true }, MAIL_CLOSED = { "correio", false },
    AUCTION_HOUSE_SHOW = { "ah", true }, AUCTION_HOUSE_CLOSED = { "ah", false },
    MERCHANT_SHOW = { "vendedor", true }, MERCHANT_CLOSED = { "vendedor", false },
    TRADE_SHOW = { "troca", true }, TRADE_CLOSED = { "troca", false },
    TRAINER_SHOW = { "treinador", true }, TRAINER_CLOSED = { "treinador", false },
    TAXIMAP_OPENED = { "voo", true }, TAXIMAP_CLOSED = { "voo", false },
    GUILDBANKFRAME_OPENED = { "guilda", true }, GUILDBANKFRAME_CLOSED = { "guilda", false },
}

local open = {}
local tag, tagUntil = nil, 0
local lastMoney
local session = { start = nil, money = nil }

-- Marca a origem do próximo ouro (por alguns segundos).
function Income.Tag(source, seconds)
    tag, tagUntil = source, GetTime() + (seconds or TAG_SECONDS)
end

local function Source()
    if tag and GetTime() <= tagUntil then
        return tag
    end
    for _, key in ipairs(WINDOW_ORDER) do
        if open[key] then
            return key
        end
    end
    return "outros"
end

local function Character()
    return ("%s-%s"):format(UnitName("player"), GetRealmName())
end

local function DayKey(t)
    return tonumber(date("%Y%m%d", t))
end

local function Record(amount, source)
    local day = DayKey(time())
    local days = db.days
    days[day] = days[day] or {}
    local char = Character()
    days[day][char] = days[day][char] or {}
    local row = days[day][char][source]
    if not row then
        row = { i = 0, o = 0 }
        days[day][char][source] = row
    end
    if amount > 0 then
        row.i = row.i + amount
    else
        row.o = row.o - amount
    end
    if Income.Refresh then
        Income.Refresh()
    end
end

local function OnMoney()
    local money = GetMoney()
    if lastMoney then
        local delta = money - lastMoney
        if delta ~= 0 then
            Record(delta, Source())
        end
    end
    lastMoney = money
end

-- Pegar o ouro de uma carta: carta de venda/lance da AH conta como AH.
local function OnTakeMail(index)
    local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
    local _, _, sender = GetInboxHeaderInfo(index)
    if invoiceType == "seller" or invoiceType == "buyer" then
        Income.Tag("ah")
    elseif type(sender) == "string" and not Qolly.IsSecret(sender) and sender:find("Leil") then
        Income.Tag("ah")
    else
        Income.Tag("correio")
    end
end

for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
    if _G[name] then
        hooksecurefunc(name, function(index)
            pcall(OnTakeMail, index)
        end)
    end
end
if RepairAllItems then
    hooksecurefunc("RepairAllItems", function()
        Income.Tag("reparo")
    end)
end

local events = CreateFrame("Frame")
for event in pairs(WINDOW_EVENTS) do
    pcall(events.RegisterEvent, events, event)
end
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("CHAT_MSG_MONEY")
events:SetScript("OnEvent", function(_, event)
    if not db then
        return
    end
    if event == "PLAYER_LOGIN" then
        -- Antes do login o ouro ainda pode vir zerado: só aqui ele é o de verdade.
        lastMoney = GetMoney()
        session.start, session.money = time(), lastMoney
    elseif event == "PLAYER_MONEY" then
        Qolly.Safe("ganhos", OnMoney)
    elseif event == "QUEST_TURNED_IN" then
        Income.Tag("missao")
    elseif event == "CHAT_MSG_MONEY" then
        Income.Tag("saque")
    else
        local window = WINDOW_EVENTS[event]
        open[window[1]] = window[2] or nil
        -- O ouro de um voo, troca ou saque rápido chega depois da janela fechar.
        if not window[2] then
            Income.Tag(window[1])
        end
    end
end)

-- Relatório ----------------------------------------------------------------------

local PERIODS = {
    { key = "today", label = "Hoje", days = 0 },
    { key = "week", label = "7 dias", days = 6 },
    { key = "month", label = "30 dias", days = 29 },
    { key = "all", label = "Tudo" },
}

local function FirstDay(period)
    for _, option in ipairs(PERIODS) do
        if option.key == period and option.days then
            return DayKey(time() - option.days * DAY)
        end
    end
    return 0
end

-- Linhas por origem (ou por personagem) no período: { label, icon, i, o }, e o total.
function Income.Summary(period, byCharacter, onlyMe)
    local first = FirstDay(period)
    local me = Character()
    local groups, total = {}, { i = 0, o = 0 }
    for day, chars in pairs(db.days) do
        if day >= first then
            for char, sources in pairs(chars) do
                if not onlyMe or char == me then
                    for source, row in pairs(sources) do
                        local key = byCharacter and char or source
                        local group = groups[key]
                        if not group then
                            local info = not byCharacter and LABELS[source]
                            group = {
                                key = key,
                                label = info and info.label or key,
                                icon = info and info.icon or nil,
                                i = 0, o = 0,
                            }
                            groups[key] = group
                        end
                        group.i = group.i + row.i
                        group.o = group.o + row.o
                        total.i = total.i + row.i
                        total.o = total.o + row.o
                    end
                end
            end
        end
    end
    local list = {}
    if byCharacter then
        for _, group in pairs(groups) do
            list[#list + 1] = group
        end
        table.sort(list, function(a, b) return a.i - a.o > b.i - b.o end)
    else
        for _, source in ipairs(SOURCES) do
            if groups[source.key] then
                list[#list + 1] = groups[source.key]
            end
        end
    end
    return list, total
end

-- Janela -------------------------------------------------------------------------
-- Página "Ganhos" do painel: abas "Ganhos e gastos" e "Vendas na AH".

local ROW_HEIGHT = 20
local COLUMNS = {
    { label = "Origem", x = 26, width = 250, left = true },
    { label = "Ganho", x = 390, width = 110 },
    { label = "Gasto", x = 500, width = 110 },
    { label = "Saldo", x = 610, width = 110 },
}

local body, rows = nil, {}
local state = { period = "today", byCharacter = false, onlyMe = false, tab = "income" }

local function Cell(parent, column, template)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
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

local function Signed(copper)
    if copper > 0 then
        return "|cff55dd55+|r" .. Qolly.Money(copper)
    elseif copper < 0 then
        return "|cffff5555-|r" .. Qolly.Money(-copper)
    end
    return "0"
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, body.content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", body.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", body.content, "RIGHT", 0, 0)
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.04)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.cells = {}
    for i, column in ipairs(COLUMNS) do
        row.cells[i] = Cell(row, column)
    end
    rows[index] = row
    return row
end

local function SessionText()
    if not session.start then
        return ""
    end
    local elapsed = math.max(60, time() - session.start)
    local gained = GetMoney() - session.money
    local perHour = gained / elapsed * 3600
    return ("Nesta sessão: %s em %s  |cff999999(%s por hora)|r"):format(
        Signed(gained), SecondsToTime and SecondsToTime(elapsed, true) or (math.floor(elapsed / 60) .. " min"),
        Signed(perHour))
end

function Income.Refresh()
    if not (body and body.income:IsVisible()) then
        return
    end
    local list, total = Income.Summary(state.period, state.byCharacter, state.onlyMe)
    for index, group in ipairs(list) do
        local row = Row(index)
        row.icon:SetTexture(group.icon or "Interface/Icons/Achievement_Character_Orc_Male")
        row.cells[1]:SetText(group.label)
        row.cells[2]:SetText(group.i > 0 and Qolly.Money(group.i) or "|cff666666-|r")
        row.cells[3]:SetText(group.o > 0 and Qolly.Money(group.o) or "|cff666666-|r")
        row.cells[4]:SetText(Signed(group.i - group.o))
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index]:Hide()
    end
    body.content:SetHeight(math.max(1, #list * ROW_HEIGHT))
    body.empty:SetShown(#list == 0)
    for _, button in ipairs(body.periods) do
        button:SetEnabled(button.period ~= state.period)
    end
    body.bySource:SetEnabled(state.byCharacter)
    body.byCharacter:SetEnabled(not state.byCharacter)
    body.onlyMe:SetChecked(state.onlyMe)
    body.total:SetText(("Ganho %s   Gasto %s   Saldo %s"):format(
        Qolly.Money(total.i), Qolly.Money(total.o), Signed(total.i - total.o)))
    body.session:SetText(SessionText())
end

local function Button(parent, label, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(label)
    button:SetScript("OnClick", function()
        Qolly.Safe("ganhos", onClick)
    end)
    return button
end

local function ShowTab(tab)
    state.tab = tab
    body.income:SetShown(tab == "income")
    body.ah:SetShown(tab == "ah")
    body.tabIncome:SetEnabled(tab ~= "income")
    body.tabAH:SetEnabled(tab ~= "ah")
    if tab == "ah" then
        Qolly.Sales.Embed(body.ah)
    else
        Income.Refresh()
    end
end
Income.ShowTab = function(tab)
    state.tab = tab
    if body then
        ShowTab(tab)
    end
end

local function CreateIncomePage(page)
    body.periods = {}
    local previous
    for _, option in ipairs(PERIODS) do
        local button = Button(page, option.label, 64, function()
            state.period = option.key
            Income.Refresh()
        end)
        button.period = option.key
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
        end
        previous = button
        body.periods[#body.periods + 1] = button
    end

    body.byCharacter = Button(page, "Por personagem", 116, function()
        state.byCharacter = true
        Income.Refresh()
    end)
    body.byCharacter:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -4)
    body.bySource = Button(page, "Por origem", 90, function()
        state.byCharacter = false
        Income.Refresh()
    end)
    body.bySource:SetPoint("RIGHT", body.byCharacter, "LEFT", -4, 0)

    body.onlyMe = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    body.onlyMe:SetSize(24, 24)
    body.onlyMe:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -30)
    body.onlyMe:SetScript("OnClick", function(self)
        state.onlyMe = self:GetChecked() and true or false
        Income.Refresh()
    end)
    local onlyMeLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    onlyMeLabel:SetPoint("LEFT", body.onlyMe, "RIGHT", 2, 0)
    onlyMeLabel:SetText("Só este personagem")

    local header = CreateFrame("Frame", nil, page)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -58)
    header:SetPoint("RIGHT", page, "RIGHT", -24, 0)
    for _, column in ipairs(COLUMNS) do
        Cell(header, column, "GameFontNormal"):SetText(column.label)
    end

    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -24, 44)
    body.content = CreateFrame("Frame", nil, scroll)
    body.content:SetSize(1, 1)
    scroll:SetScrollChild(body.content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        body.content:SetWidth(width)
    end)

    body.empty = page:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    body.empty:SetPoint("CENTER", scroll, "CENTER")
    body.empty:SetText("Nada anotado no período.\nA partir de agora, todo ouro que entra ou sai é anotado aqui.")

    body.total = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body.total:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 24)
    body.session = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    body.session:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 6)

    page:SetScript("OnShow", function()
        Qolly.Safe("ganhos", Income.Refresh)
    end)
end

local function CreateBody()
    body = CreateFrame("Frame", "QollyIncomeBody", UIParent)
    body.tabIncome = Button(body, "Ganhos e gastos", 130, function() ShowTab("income") end)
    body.tabIncome:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -2)
    body.tabAH = Button(body, "Vendas na AH", 130, function() ShowTab("ah") end)
    body.tabAH:SetPoint("LEFT", body.tabIncome, "RIGHT", 4, 0)
    local line = body:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -28)
    line:SetPoint("TOPRIGHT", body, "TOPRIGHT", -4, -28)
    line:SetColorTexture(1, 0.82, 0, 0.25)

    body.income = CreateFrame("Frame", nil, body)
    body.income:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -32)
    body.income:SetPoint("BOTTOMRIGHT")
    body.ah = CreateFrame("Frame", nil, body)
    body.ah:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -32)
    body.ah:SetPoint("BOTTOMRIGHT")
    CreateIncomePage(body.income)
end

function Income.Embed(parent)
    if not body then
        CreateBody()
    end
    body:SetParent(parent)
    body:ClearAllPoints()
    body:SetAllPoints(parent)
    body:Show()
    ShowTab(state.tab)
    return body
end

Qolly.RegisterModule("ganhos", {
    help = "(todo ouro que entra e sai, por origem: missões, saque, vendedor, AH...)",
    command = function()
        Income.ShowTab("income")
        Qolly.Options.Open("Ganhos")
    end,
    init = function(moduleDB)
        db = moduleDB
        db.days = db.days or {}
    end,
})
