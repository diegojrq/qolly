-- Página "Melhorias" da aba Qolly da AH: equipamento à venda que melhora o seu,
-- ordenado por preço ou por ganho.
local _, Qolly = ...
local Gear = Qolly.Gear
local AH = Qolly.AH

local List = {}
Gear.List = List

local ROW_HEIGHT = 22
local GREEN, GRAY = "|cff33dd33", "|cff999999"

local frame, content, status
local rows = {}
local sortBy = "price"

-- Filtro por tipo de item, como as categorias da AH (que ficam escondidas na aba Qolly).
local FILTER_WIDTH = 120
local FILTER_HEIGHT = 18
local FILTERS = {
    { label = "Tudo" },
    { label = "Cabeça", locs = { "INVTYPE_HEAD" } },
    { label = "Pescoço", locs = { "INVTYPE_NECK" } },
    { label = "Ombros", locs = { "INVTYPE_SHOULDER" } },
    { label = "Costas", locs = { "INVTYPE_CLOAK" } },
    { label = "Peito", locs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
    { label = "Pulsos", locs = { "INVTYPE_WRIST" } },
    { label = "Mãos", locs = { "INVTYPE_HAND" } },
    { label = "Cintura", locs = { "INVTYPE_WAIST" } },
    { label = "Pernas", locs = { "INVTYPE_LEGS" } },
    { label = "Pés", locs = { "INVTYPE_FEET" } },
    { label = "Anel", locs = { "INVTYPE_FINGER" } },
    { label = "Berloque", locs = { "INVTYPE_TRINKET" } },
    { label = "Uma mão", locs = { "INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
    { label = "Duas mãos", locs = { "INVTYPE_2HWEAPON" } },
    { label = "Escudo / mão sec.", locs = { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
    { label = "À distância", locs = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" } },
}
for _, filter in ipairs(FILTERS) do
    if filter.locs then
        filter.set = {}
        for _, loc in ipairs(filter.locs) do
            filter.set[loc] = true
        end
    end
end
local filterIndex = 1
local filterButtons = {}
local shownCount = 0

local function Matches(entry, filter)
    return not filter.set or filter.set[entry.equipLoc] == true
end

-- Slot vazio conta como o maior ganho possível.
local function PercentOf(entry)
    return entry.percent or math.huge
end

local SORTS = {
    price = function(a, b)
        if a.price ~= b.price then
            return a.price < b.price
        end
        return PercentOf(a) > PercentOf(b)
    end,
    percent = function(a, b)
        if PercentOf(a) ~= PercentOf(b) then
            return PercentOf(a) > PercentOf(b)
        end
        return a.price < b.price
    end,
    score = function(a, b)
        local gainA, gainB = a.scoreGain or -math.huge, b.scoreGain or -math.huge
        if gainA ~= gainB then
            return gainA > gainB
        end
        return a.price < b.price
    end,
}

local function ScoreGainText(gain)
    if not gain then
        return ""
    end
    if gain > 0.05 then
        return ("%s+%.1f|r"):format(GREEN, gain)
    elseif gain < -0.05 then
        return ("|cffff5555%.1f|r"):format(gain)
    end
    return GRAY .. "0|r"
end

local function OnRowClick(self)
    local entry = self.entry
    if not entry then
        return
    end
    if IsModifiedClick("CHATLINK") then
        ChatEdit_InsertLink(entry.link)
        return
    end
    -- O nome base (sem "da Baleia") acha todas as variantes na busca da AH.
    local name = entry.itemID and C_Item.GetItemNameByID(entry.itemID) or entry.name
    Qolly.Safe("busca na AH", AH.Browse, name)
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 2, 0)

    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.price:SetPoint("RIGHT", -4, 0)
    row.price:SetWidth(100)
    row.price:SetJustifyH("RIGHT")

    row.percent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.percent:SetPoint("RIGHT", row.price, "LEFT", -6, 0)
    row.percent:SetWidth(52)
    row.percent:SetJustifyH("RIGHT")

    row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.score:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
    row.score:SetWidth(40)
    row.score:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.score, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", function(self)
        if self.entry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.entry.link)
            GameTooltip:AddLine(Qolly.TAG .. "Clique: buscar na AH · Shift+clique: linkar", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
    return row
end

local function StatusText()
    if Gear.state == "noquestmaster" then
        return "Precisa do addon QuestMaster ativo para calcular melhorias."
    elseif Gear.state == "working" then
        return ("Calculando melhorias... %d%%"):format((Gear.progress or 0) * 100)
    elseif not Gear.db.scanTime then
        return "Sem scan ainda: clique em Scan da AH, à esquerda."
    end
    local count = ("%d melhorias"):format(#Gear.upgrades)
    if filterIndex ~= 1 then
        count = ("%d de %d em %s"):format(shownCount, #Gear.upgrades, FILTERS[filterIndex].label)
    end
    local text = GRAY .. ("%s · scan de há %s|r"):format(count, Qolly.Ago(time() - Gear.db.scanTime))
    if Gear.scoreNow then
        text = "Seu GS: " .. Gear.Score.Colored(Gear.scoreNow, UnitLevel("player")) .. "   " .. text
    end
    return text
end

function List.Refresh()
    if not frame or not frame:IsVisible() then
        return
    end
    local entries = {}
    if Gear.state == "done" then
        for _, entry in ipairs(Gear.upgrades) do
            if Matches(entry, FILTERS[filterIndex]) then
                entries[#entries + 1] = entry
            end
        end
    end
    shownCount = #entries
    -- Quantas melhorias em cada filtro; filtro vazio fica apagado.
    for index, filter in ipairs(FILTERS) do
        local total = 0
        for _, entry in ipairs(Gear.state == "done" and Gear.upgrades or {}) do
            if Matches(entry, filter) then
                total = total + 1
            end
        end
        local button = filterButtons[index]
        button:SetText(("%s |cff999999%d|r"):format(filter.label, total))
        button.selected:SetShown(index == filterIndex)
        button:GetFontString():SetTextColor(total > 0 and 1 or 0.5, total > 0 and 0.82 or 0.5, total > 0 and 0 or 0.5)
    end
    table.sort(entries, SORTS[sortBy])
    status:SetText(StatusText())
    for index, entry in ipairs(entries) do
        local row = rows[index] or CreateRow(index)
        row.entry = entry
        row.icon:SetTexture(entry.icon)
        row.name:SetText(entry.link)
        row.percent:SetText(entry.percent and (GREEN .. "+" .. entry.percent .. "%|r") or (GREEN .. "vazio|r"))
        row.score:SetText(ScoreGainText(entry.scoreGain))
        row.price:SetText(Qolly.Money(entry.price))
        row:Show()
    end
    for index = #entries + 1, #rows do
        rows[index].entry = nil
        rows[index]:Hide()
    end
    content:SetHeight(math.max(1, #entries * ROW_HEIGHT))
end

local function SortButton(label, key, anchor)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(90, 20)
    if anchor then
        button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", FILTER_WIDTH + 8, -4)
    end
    button:SetText(label)
    button:SetScript("OnClick", function()
        sortBy = key
        Qolly.Safe("lista de melhorias", List.Refresh)
    end)
    return button
end

local function FilterButton(index)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(FILTER_WIDTH, FILTER_HEIGHT)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -4 - (index - 1) * FILTER_HEIGHT)
    button:SetNormalFontObject("GameFontNormalSmall")
    button:SetText(FILTERS[index].label)
    local text = button:GetFontString()
    text:ClearAllPoints()
    text:SetPoint("LEFT", button, "LEFT", 6, 0)
    button:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    button.selected = button:CreateTexture(nil, "BACKGROUND")
    button.selected:SetAllPoints()
    button.selected:SetColorTexture(1, 0.82, 0, 0.2)
    button.selected:Hide()
    button:SetScript("OnClick", function()
        filterIndex = index
        Qolly.Safe("lista de melhorias", List.Refresh)
    end)
    filterButtons[index] = button
end

local function CreateWindow(parent)
    frame = CreateFrame("Frame", "QollyUpgradeList", parent)
    frame:Hide()

    for index in ipairs(FILTERS) do
        FilterButton(index)
    end

    local byPrice = SortButton("Preço", "price")
    local byPercent = SortButton("Melhoria", "percent", byPrice)
    SortButton("GS", "score", byPercent)

    status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", byPrice, "BOTTOMLEFT", 0, -6)
    status:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    status:SetJustifyH("LEFT")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", FILTER_WIDTH + 4, -50)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    -- As linhas ocupam a largura que a página tiver.
    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(width)
    end)

    frame:SetScript("OnShow", function()
        -- Só recalcula se scan, nível, papel ou equipamento mudaram desde o último cálculo.
        if Gear.NeedsEvaluate() then
            Qolly.Safe("melhorias", Gear.Evaluate)
        else
            Qolly.Safe("lista de melhorias", List.Refresh)
        end
    end)
    -- A idade do scan no status envelhece com a página aberta.
    local sinceStatus = 0
    frame:SetScript("OnUpdate", function(_, delta)
        sinceStatus = sinceStatus + delta
        if sinceStatus >= 5 then
            sinceStatus = 0
            status:SetText(StatusText())
        end
    end)
end

function List.IsShown()
    return frame ~= nil and frame:IsVisible()
end

-- A lista é uma página da aba Qolly da AH: a aba dá o lugar dela.
function List.Embed(parent)
    if not frame then
        CreateWindow(parent)
    end
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetAllPoints(parent)
    return frame
end

-- Scan novo terminou: a aba abre nas melhorias para mostrar o resultado.
function List.Show()
    if AH.IsOpen() and Qolly.AHTab then
        Qolly.AHTab.Select("upgrades")
    end
end
