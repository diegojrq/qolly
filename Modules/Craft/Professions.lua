-- Profissões: página no painel Qolly da AH com todas as receitas de cada profissão sua,
-- custo dos mats x venda do item e o lucro, para escolher o que craftar (e com o que
-- upar). As receitas são lidas quando a janela da profissão abre e ficam guardadas; os
-- preços são os do scan da AH (Craft.Prices).
local _, Qolly = ...
local Craft = Qolly.Craft
local Prices = Craft.Prices
local AH = Qolly.AH

local Professions = {}
Craft.Professions = Professions
Qolly.Professions = Professions

local AH_CUT = 0.95
-- Item que só o vendedor vende: o NPC cobra em geral 4x o que paga por ele.
local VENDOR_MARKUP = 4
local CHUNK = 40

-- Enum.TradeskillRelativeDifficulty: 0 laranja, 1 amarelo, 2 verde, 3 cinza.
local DIFFICULTY = {
    [0] = { color = "|cffff8040", label = "laranja: sempre sobe" },
    [1] = { color = "|cffffff00", label = "amarela: costuma subir" },
    [2] = { color = "|cff40c040", label = "verde: às vezes sobe" },
    [3] = { color = "|cff808080", label = "cinza: não sobe mais" },
}
local TRIVIAL = 3
local UNLEARNED = "|cff808080"
local GREEN, RED, GREY, GOLD = "|cff66ff66", "|cffff6666", "|cff999999", "|cffffd100"

-- Receitas guardadas por personagem: profissão -> { skill, max, at, recipes }.
local function Book()
    local char = ("%s-%s"):format(UnitName("player"), GetRealmName())
    Craft.db.book = Craft.db.book or {}
    Craft.db.book[char] = Craft.db.book[char] or {}
    return Craft.db.book[char]
end

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

-- Leitura das receitas --------------------------------------------------------------

local function OwnWindow()
    local api = C_TradeSkillUI
    for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
        if api[check] then
            local ok, value = pcall(api[check])
            if ok and Plain(value) then
                return false
            end
        end
    end
    return true
end

local function ProfessionInfo()
    local api = C_TradeSkillUI
    for _, getter in ipairs({ "GetChildProfessionInfo", "GetBaseProfessionInfo" }) do
        if api[getter] then
            local ok, info = pcall(api[getter])
            if ok and type(info) == "table" then
                local name = Plain(info.professionName) or Plain(info.parentProfessionName)
                local skill = Plain(info.skillLevel)
                if type(name) == "string" and name ~= "" and skill and skill > 0 then
                    return name, skill, Plain(info.maxSkillLevel) or skill
                end
            end
        end
    end
end

local function ReadRecipe(recipeID, info)
    local recipe = Craft.Recipe.Read(recipeID)
    if not recipe then
        return nil
    end
    local reagents = {}
    for _, reagent in ipairs(recipe.reagents) do
        reagents[#reagents + 1] = { reagent.qty, reagent.options }
    end
    return {
        id = recipeID,
        n = Plain(info.name) or ("receita " .. recipeID),
        out = recipe.outputItemID,
        made = recipe.made,
        r = reagents,
        learned = Plain(info.learned) == true,
        d = Plain(info.relativeDifficulty),
        icon = Plain(info.icon),
    }
end

local reading = 0
local function ReadOpenProfession()
    if not (ProfessionsFrame and ProfessionsFrame:IsShown() and OwnWindow()) then
        return
    end
    local name, skill, max = ProfessionInfo()
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not (name and ok and type(ids) == "table" and #ids > 0) then
        return
    end
    reading = reading + 1
    local token, index, found = reading, 0, {}
    local function Step()
        if token ~= reading then
            return
        end
        local last = math.min(index + CHUNK, #ids)
        for i = index + 1, last do
            local id = Plain(ids[i])
            local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
            if id and okInfo and type(info) == "table" then
                local recipe = ReadRecipe(id, info)
                if recipe then
                    found[#found + 1] = recipe
                end
            end
        end
        index = last
        if index < #ids then
            C_Timer.After(0, Step)
            return
        end
        Book()[name] = { skill = skill, max = max, at = time(), recipes = found }
        Qolly.Log(("Profissões: %s %d/%d, %d receitas lidas."):format(name, skill, max, #found))
        Professions.Refresh()
    end
    Step()
end

local readTimer
local function QueueRead()
    if readTimer then
        readTimer:Cancel()
    end
    readTimer = C_Timer.NewTimer(1, function()
        readTimer = nil
        Qolly.Safe("profissões", ReadOpenProfession)
    end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
    if Craft.db then
        QueueRead()
    end
end)

-- Conta -------------------------------------------------------------------------------

-- Preço de um mat: o da AH, ou estimado pelo vendedor. unit, origem ("ah"/"vendedor").
local function MatPrice(options)
    local bestID, bestUnit
    for _, itemID in ipairs(options) do
        local unit = Prices.Get(itemID)
        if unit and (not bestUnit or unit < bestUnit) then
            bestID, bestUnit = itemID, unit
        end
    end
    if bestUnit then
        return bestID, bestUnit, "ah"
    end
    local itemID = options[1]
    local sell = select(11, C_Item.GetItemInfo(itemID))
    if sell and sell > 0 then
        return itemID, sell * VENDOR_MARKUP, "vendedor"
    end
    return itemID, nil, nil
end

local function Evaluate(recipe)
    local result = { lines = {}, cost = 0, missing = 0, vendor = 0 }
    for _, reagent in ipairs(recipe.r) do
        local itemID, unit, source = MatPrice(reagent[2])
        local line = { id = itemID, qty = reagent[1], unit = unit, source = source }
        if unit then
            line.cost = unit * reagent[1]
            result.cost = result.cost + line.cost
            if source == "vendedor" then
                result.vendor = result.vendor + 1
            end
        else
            result.missing = result.missing + 1
        end
        result.lines[#result.lines + 1] = line
    end
    local sale = recipe.out and Prices.Get(recipe.out)
    if sale then
        result.sale = sale
        result.gross = sale * recipe.made
        result.net = result.gross * AH_CUT
        result.profit = math.floor(result.net - result.cost + 0.5)
        result.pct = result.cost > 0 and result.profit / result.cost or nil
    end
    return result
end

-- Página ---------------------------------------------------------------------------------

local ROW_HEIGHT = 20
local LINE = 13
local ACCOUNT_LINES = 13
local COLUMNS = {
    { label = "Receita", x = 8, width = 290 },
    { label = "Mats", x = 304, width = 100, right = true },
    { label = "Venda (-5%)", x = 410, width = 100, right = true },
    { label = "Lucro", x = 516, width = 110, right = true },
    { label = "%", x = 632, width = 70, right = true },
}

local frame
local rows, profButtons = {}, {}
local shown = {}

local function Pct(value)
    return (("%+.0f%%"):format(value * 100))
end

local function Signed(copper)
    copper = math.floor(copper + 0.5)
    return (copper > 0 and "+" or "") .. Qolly.Money(copper)
end

local function Colored(value, text)
    return (value >= 0 and GREEN or RED) .. text .. "|r"
end

local function ItemName(itemID)
    local name = itemID and C_Item.GetItemNameByID(itemID)
    if not name and itemID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return name or ("item " .. tostring(itemID))
end

local function Names()
    local list = {}
    for name in pairs(Book()) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

local function Current()
    local book = Book()
    if Craft.db.profession and book[Craft.db.profession] then
        return Craft.db.profession, book[Craft.db.profession]
    end
    local name = Names()[1]
    return name, name and book[name]
end

local function RecipeName(recipe)
    if not recipe.learned then
        return UNLEARNED .. recipe.n .. " (não aprendida)|r"
    end
    local difficulty = DIFFICULTY[recipe.d]
    return (difficulty and difficulty.color or "") .. recipe.n .. "|r"
end

local function Visible(recipe, result)
    local filter = Craft.db.profFilter or "skill"
    if not recipe.learned and not Craft.db.profUnlearned then
        return false
    end
    if filter == "skill" and recipe.learned and recipe.d == TRIVIAL then
        return false
    end
    if Craft.db.profOnlyProfit and not (result.profit and result.profit > 0) then
        return false
    end
    return true
end

local accountLines = {}
local function AccountLine(index)
    local line = accountLines[index]
    if not line then
        local parent = frame.account
        line = {}
        line.left = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8 - (index - 1) * LINE)
        line.left:SetJustifyH("LEFT")
        line.left:SetWordWrap(false)
        line.right = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8 - (index - 1) * LINE)
        line.right:SetWidth(160)
        line.right:SetJustifyH("RIGHT")
        accountLines[index] = line
    end
    return line
end

local function ShowAccount(recipe)
    local out = {}
    local function Add(left, right)
        out[#out + 1] = { left, right or "" }
    end
    if not recipe then
        Add(GREY .. "Clique numa receita para ver a conta.|r")
    else
        local result = Evaluate(recipe)
        local difficulty = DIFFICULTY[recipe.d]
        Add(GOLD .. recipe.n .. "|r" .. GREY .. "  " .. (not recipe.learned and "não aprendida"
            or difficulty and difficulty.label or "") .. "|r")
        for _, line in ipairs(result.lines) do
            local label = ("  %dx %s"):format(line.qty, ItemName(line.id))
            if line.unit then
                local note = line.source == "vendedor" and (GREY .. " (vendedor, estimado)|r") or ""
                Add(label .. " a " .. Qolly.Money(line.unit) .. note, "-" .. Qolly.Money(line.cost))
            else
                Add(label, RED .. "sem preço|r")
            end
        end
        Add("  Total dos mats", "-" .. Qolly.Money(result.cost))
        if not recipe.out then
            Add(GREY .. "  Não gera item para vender.|r")
        elseif not result.sale then
            Add(("  %s: sem preço na AH"):format(ItemName(recipe.out)))
        else
            local made = recipe.made ~= 1 and (" x%g"):format(recipe.made) or ""
            Add(("  Vende %s%s a %s"):format(ItemName(recipe.out), made, Qolly.Money(result.sale)), "+" .. Qolly.Money(result.gross))
            Add("  Taxa da AH (5%)", "-" .. Qolly.Money(result.gross - result.net))
            Add("  Lucro por craft", Colored(result.profit, Signed(result.profit)
                .. (result.pct and (" (" .. Pct(result.pct) .. ")") or "")))
        end
        if result.missing > 0 then
            Add(RED .. ("  %d mat(s) sem preço ficaram fora do custo: o lucro está otimista.|r"):format(result.missing))
        end
    end
    for index = 1, math.max(#out, #accountLines) do
        local line = AccountLine(index)
        local entry = out[index]
        local right = entry and entry[2] or ""
        line.left:SetText(entry and entry[1] or "")
        line.left:SetWidth(right == "" and 700 or 520)
        line.right:SetText(right)
    end
end

local function ShowRowTip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.recipe.out then
        GameTooltip:SetItemByID(row.recipe.out)
        GameTooltip:AddLine(" ")
    end
    GameTooltip:AddLine(Qolly.TAG .. "clique: ver a conta embaixo", 0.6, 0.6, 0.6)
    GameTooltip:AddLine(Qolly.TAG .. "botão direito: buscar o item na AH", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(0.3, 0.6, 1, 0.18)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", COLUMNS[1].x, 0)
    row.cells = {}
    for column, spec in ipairs(COLUMNS) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", spec.x + (column == 1 and 20 or 0), 0)
        text:SetWidth(spec.width - (column == 1 and 20 or 0))
        text:SetJustifyH(spec.right and "RIGHT" or "LEFT")
        text:SetWordWrap(false)
        row.cells[column] = text
    end
    row:SetScript("OnEnter", ShowRowTip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if self.recipe.out then
                AH.Browse(ItemName(self.recipe.out))
            end
            return
        end
        Craft.db.profSelected = self.recipe.id
        Professions.Refresh()
    end)
    rows[index] = row
    return row
end

local function ProfessionButtons()
    local names = Names()
    local previous
    for index, name in ipairs(names) do
        local button = profButtons[index]
        if not button then
            button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            button:SetHeight(22)
            button:SetScript("OnClick", function(self)
                Craft.db.profession = self.name
                Craft.db.profSelected = nil
                Professions.Refresh()
            end)
            profButtons[index] = button
        end
        button.name = name
        button:SetText(name)
        button:SetWidth(math.max(90, button:GetFontString():GetStringWidth() + 24))
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
        end
        button:Show()
        previous = button
    end
    for index = #names + 1, #profButtons do
        profButtons[index]:Hide()
    end
    return previous
end

function Professions.Refresh()
    if not frame or not frame:IsVisible() then
        return
    end
    local last = ProfessionButtons()
    local name, book = Current()
    for _, button in ipairs(profButtons) do
        if button:IsShown() and button.name == name then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    frame.status:ClearAllPoints()
    if last then
        frame.status:SetPoint("LEFT", last, "RIGHT", 10, 0)
    else
        frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    end
    for _, button in ipairs(frame.filters) do
        if button.key == (Craft.db.profFilter or "skill") then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    frame.unlearned:SetChecked(Craft.db.profUnlearned == true)
    frame.onlyProfit:SetChecked(Craft.db.profOnlyProfit == true)

    if not book then
        frame.status:SetText("Abra a janela da sua profissão uma vez para o Qolly ler as receitas.")
        for _, row in ipairs(rows) do
            row:Hide()
        end
        ShowAccount(nil)
        return
    end

    local list = {}
    for _, recipe in ipairs(book.recipes) do
        local result = Evaluate(recipe)
        if Visible(recipe, result) then
            list[#list + 1] = { recipe = recipe, result = result }
        end
    end
    table.sort(list, function(a, b)
        local pa, pb = a.result.profit, b.result.profit
        if (pa ~= nil) ~= (pb ~= nil) then
            return pa ~= nil
        end
        if pa and pa ~= pb then
            return pa > pb
        end
        return a.recipe.n < b.recipe.n
    end)

    local width = frame.scroll:GetWidth()
    local selected
    for index, entry in ipairs(list) do
        local row = Row(index)
        local recipe, result = entry.recipe, entry.result
        row.recipe = recipe
        row.icon:SetTexture(recipe.icon or (recipe.out and C_Item.GetItemIconByID(recipe.out)) or 134400)
        row.cells[1]:SetText(RecipeName(recipe))
        row.cells[2]:SetText(Qolly.Money(result.cost) .. (result.missing > 0 and (RED .. "*|r") or ""))
        row.cells[3]:SetText(result.net and Qolly.Money(result.net) or (GREY .. "sem preço|r"))
        row.cells[4]:SetText(result.profit and Colored(result.profit, Signed(result.profit)) or (GREY .. "-|r"))
        row.cells[5]:SetText(result.pct and Colored(result.pct, Pct(result.pct)) or "")
        row.selected:SetShown(recipe.id == Craft.db.profSelected)
        if recipe.id == Craft.db.profSelected then
            selected = recipe
        end
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetWidth(width)
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index]:Hide()
    end
    frame.content:SetSize(width, math.max(1, #list * ROW_HEIGHT))
    ShowAccount(selected)

    local scan = Craft.db.scanTime and Qolly.Ago(time() - Craft.db.scanTime) or nil
    frame.status:SetText(("%d/%d  ·  %d receitas aqui  ·  lidas há %s  ·  %s"):format(
        book.skill, book.max, #list, Qolly.Ago(time() - book.at),
        scan and ("preços do scan de há " .. scan) or "faça um scan da AH para os preços"))
end

local function CheckButton(label, x, key)
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -32)
    local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        Craft.db[key] = self:GetChecked() and true or false
        Professions.Refresh()
    end)
    return check
end

local function CreatePage(parent)
    frame = CreateFrame("Frame", "QollyProfessionsPage", parent)

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetJustifyH("LEFT")
    frame.status:SetWidth(560)
    frame.status:SetWordWrap(false)

    frame.filters = {}
    local previous
    for _, filter in ipairs({ { key = "skill", label = "Sobem skill" }, { key = "all", label = "Todas" } }) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(100, 22)
        button:SetText(filter.label)
        button.key = filter.key
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -32)
        end
        button:SetScript("OnClick", function()
            Craft.db.profFilter = filter.key
            Professions.Refresh()
        end)
        frame.filters[#frame.filters + 1] = button
        previous = button
    end
    frame.onlyProfit = CheckButton("Só com lucro", 224, "profOnlyProfit")
    frame.unlearned = CheckButton("Mostrar não aprendidas", 334, "profUnlearned")

    for _, column in ipairs(COLUMNS) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4 + column.x, -62)
        header:SetWidth(column.width)
        header:SetJustifyH(column.right and "RIGHT" or "LEFT")
        header:SetText(column.label)
    end

    local accountHeight = 8 + ACCOUNT_LINES * LINE + 6
    frame.account = CreateFrame("Frame", nil, frame)
    frame.account:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 6)
    frame.account:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 6)
    frame.account:SetHeight(accountHeight)
    local background = frame.account:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.3)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -76)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.account, "TOPRIGHT", -22, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(1, 1)
    frame.scroll:SetScrollChild(frame.content)

    frame:SetScript("OnShow", Professions.Refresh)
end

function Professions.Embed(parent)
    if not frame then
        CreatePage(parent)
    end
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetAllPoints(parent)
    C_Timer.After(0, Professions.Refresh)
    return frame
end

