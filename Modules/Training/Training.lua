-- Treino: o que aprender no instrutor da classe agora, em breve e mais tarde, com o
-- custo. Para o bruxo, também os tomos de cada demônio (comprados no vendedor de
-- demônios), que o instrutor não mostra.
-- Abre por uma aba na lateral direita do grimório, ou /qolly treino.
--
-- Os tomos que o demônio já sabe: o jogo só diz quais magias o demônio que está
-- invocado tem. O Qolly olha o grimório dele toda vez que você invoca e guarda.
-- Invoque cada demônio uma vez para a lista ficar certa.
local _, Qolly = ...

local Training = {}
Qolly.Training = Training

local db, mine
local SOON = 2 -- níveis à frente que contam como "em breve"

local SUMMONS = { Imp = 688, Voidwalker = 697, Succubus = 712, Incubus = 713, Felhunter = 691 }
local PET_ORDER = { "Imp", "Voidwalker", "Succubus", "Incubus", "Felhunter" }
local PET_ICONS = { Imp = 136218, Voidwalker = 136221, Succubus = 136220, Incubus = 4352492, Felhunter = 136217 }

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function PlayerLevel()
    return Plain(UnitLevel("player")) or 1
end

-- Magias ----------------------------------------------------------------------------

local PLAYER_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
local PET_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet

local function InBook(id, bank)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook and bank then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id, bank, false)
        if ok and known then
            return true
        end
    end
    if bank == PLAYER_BANK and C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id, bank)
        if ok and known then
            return true
        end
    end
    return bank == PLAYER_BANK and IsPlayerSpell ~= nil and IsPlayerSpell(id)
end

-- Grau anterior de uma magia de grupo: sabido se um grau maior é sabido.
local overrideOf -- magia -> { lista do grupo, posição }

local function BuildOverrides(data)
    overrideOf = {}
    for _, group in ipairs(data.overrides or {}) do
        for index, id in ipairs(group) do
            overrideOf[id] = { group, index }
        end
    end
end

local function Known(id)
    if InBook(id, PLAYER_BANK) then
        return true
    end
    local entry = overrideOf and overrideOf[id]
    if entry then
        local group, index = entry[1], entry[2]
        for later = index + 1, #group do
            if InBook(group[later], PLAYER_BANK) then
                return true
            end
        end
    end
    return false
end

-- Tomos de demônio ------------------------------------------------------------------

local function TomeKey(tome)
    return tome[4] .. ":" .. tome[5]
end

-- Família do demônio invocado. Súcubo e íncubo têm os mesmos tomos: o nome da
-- família separa os dois.
local function PetIsIncubus()
    local family = Plain(UnitCreatureFamily("pet"))
    return family ~= nil and family:lower():find("ncub") ~= nil
end

local function ScanPet()
    if not mine or not PET_BANK or not UnitExists("pet") then
        return
    end
    local incubus = PetIsIncubus()
    local changed = false
    for _, tome in ipairs(Qolly.TrainingData.TOMES) do
        local family, spell = tome[4], tome[5]
        local fits = (family ~= "Succubus" or not incubus) and (family ~= "Incubus" or incubus)
        if spell and fits and not mine.pet[TomeKey(tome)] and InBook(spell, PET_BANK) then
            mine.pet[TomeKey(tome)] = true
            changed = true
        end
    end
    if changed then
        Training.Refresh()
    end
end

-- Um tomo conta como sabido se ele, ou um tomo maior da mesma magia e do mesmo
-- demônio, foi visto no grimório do demônio.
local function TomeKnown(tome)
    if mine.pet[TomeKey(tome)] then
        return true
    end
    local name = tome[5] and C_Spell.GetSpellName(tome[5])
    if not name then
        return false
    end
    for _, other in ipairs(Qolly.TrainingData.TOMES) do
        if other[4] == tome[4] and other[1] > tome[1] and other[5]
            and mine.pet[TomeKey(other)] and C_Spell.GetSpellName(other[5]) == name then
            return true
        end
    end
    return false
end

local function PetName(family)
    local name = C_Spell.GetSpellName(SUMMONS[family])
    -- "Evocar Diabrete" -> "Diabrete"
    return name and name:match("^%S+%s+(.+)$") or family
end

-- Lista ------------------------------------------------------------------------------
-- Seções: { title, rows = { { kind, id, level, cost, ... } } }

local function Status(level, playerLevel, ready)
    if level > playerLevel + SOON then
        return "later"
    elseif level > playerLevel then
        return "soon"
    end
    return ready and "now" or "missing"
end

local SECTIONS = {
    { key = "now", title = "Disponível agora" },
    { key = "missing", title = "Falta a magia anterior" },
    { key = "soon", title = "Em breve" },
    { key = "later", title = "Mais tarde", collapsed = true },
    { key = "ignored", title = "Ignorados (botão direito)", collapsed = true },
}

local function Build()
    local class = select(2, UnitClass("player"))
    local data = Qolly.TrainingData[class]
    local buckets = {}
    for _, section in ipairs(SECTIONS) do
        buckets[section.key] = {}
    end
    if not data then
        return buckets
    end
    if not overrideOf then
        BuildOverrides(data)
    end
    local playerLevel = PlayerLevel()
    local faction = UnitFactionGroup("player")
    for _, spell in ipairs(data.spells) do
        local level, id, cost = spell[1], spell[2], spell[3]
        local allowed = (not spell.faction or spell.faction == faction) and (not spell.talent or Known(spell.talent))
        if allowed and not Known(id) then
            local ready = true
            for _, required in ipairs(spell.req or {}) do
                if not Known(required) then
                    ready = false
                end
            end
            local key = db.ignored[id] and "ignored" or Status(level, playerLevel, ready)
            table.insert(buckets[key], { spell = id, level = level, cost = cost, skill = spell.skill })
        end
    end
    if class == "WARLOCK" then
        for _, tome in ipairs(Qolly.TrainingData.TOMES) do
            local level, item, cost, family = tome[1], tome[2], tome[3], tome[4]
            if not TomeKnown(tome) then
                local key = db.ignored[TomeKey(tome)] and "ignored" or Status(level, playerLevel, true)
                table.insert(buckets[key], { item = item, level = level, cost = cost, family = family, taught = tome[5], key = TomeKey(tome) })
            end
        end
    end
    -- Por nível; no mesmo nível, magias antes dos tomos e os demônios em ordem.
    local order = {}
    for index, family in ipairs(PET_ORDER) do
        order[family] = index
    end
    for _, list in pairs(buckets) do
        table.sort(list, function(a, b)
            if a.level ~= b.level then
                return a.level < b.level
            end
            local ka, kb = a.family and order[a.family] or 0, b.family and order[b.family] or 0
            if ka ~= kb then
                return ka < kb
            end
            return (a.spell or a.item) < (b.spell or b.item)
        end)
    end
    return buckets
end

local function Total(rows)
    local total = 0
    for _, row in ipairs(rows) do
        total = total + row.cost
    end
    return total
end

-- Painel -----------------------------------------------------------------------------

local ROW_HEIGHT, HEADER_HEIGHT, WIDTH = 22, 22, 380
local panel, tab
local rows, headers = {}, {}
local collapsed = {}

local BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function ShowRowTip(row)
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.item then
        GameTooltip:SetItemByID(entry.item)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Qolly.TAG .. "tomo do " .. PetName(entry.family) .. ", no vendedor de demônios", 0.4, 0.8, 1, true)
    else
        GameTooltip:SetSpellByID(entry.spell)
        if entry.skill then
            GameTooltip:AddLine(Qolly.TAG .. ("precisa de %d de perícia em Venenos"):format(entry.skill[2]), 1, 0.5, 0.3)
        end
    end
    GameTooltip:AddLine(Qolly.TAG .. "botão direito: ignorar / voltar", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, panel.content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("RightButtonUp")
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.pet = row:CreateTexture(nil, "OVERLAY")
    row.pet:SetSize(12, 12)
    row.pet:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 3, -3)
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("RIGHT", -6, 0)
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.level:SetPoint("RIGHT", -96, 0)
    row.level:SetWidth(46)
    row.level:SetJustifyH("RIGHT")
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.rank, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", ShowRowTip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        local key = self.entry.key or self.entry.spell
        db.ignored[key] = not db.ignored[key] or nil
        Training.Refresh()
    end)
    rows[index] = row
    return row
end

local function Header(index)
    local header = headers[index]
    if header then
        return header
    end
    header = CreateFrame("Button", nil, panel.content)
    header:SetHeight(HEADER_HEIGHT)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(1, 0.82, 0, 0.12)
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", 8, 0)
    header.total = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.total:SetPoint("RIGHT", -6, 0)
    header:SetScript("OnClick", function(self)
        collapsed[self.key] = not collapsed[self.key]
        Training.Refresh()
    end)
    headers[index] = header
    return header
end

-- Cabeçalho de seção (dourado) ou de grupo dentro dela (mais discreto).
local function StyleHeader(header, sub)
    header.bg:SetColorTexture(1, 0.82, 0, sub and 0.05 or 0.12)
    header.text:SetFontObject(sub and "GameFontNormalSmall" or "GameFontNormal")
    if sub then
        header.text:SetTextColor(0.85, 0.75, 0.5)
    else
        header.text:SetTextColor(1, 0.82, 0)
    end
end

-- grouped: a linha está sob o cabeçalho do demônio, então o nome dele não se repete.
local function FillRow(row, entry, playerLevel, grouped)
    row.entry = entry
    local name, icon, rank
    if entry.item then
        name = C_Item.GetItemNameByID(entry.item)
        if not name then
            C_Item.RequestLoadItemDataByID(entry.item)
        end
        icon = C_Item.GetItemIconByID(entry.item)
        local taught = entry.taught and C_Spell.GetSpellName(entry.taught)
        if taught then
            name = grouped and taught or (PetName(entry.family) .. ": " .. taught)
        end
        name = name or ("item " .. entry.item)
        rank = entry.taught and C_Spell.GetSpellSubtext(entry.taught)
        row.pet:SetTexture(PET_ICONS[entry.family])
        row.pet:SetShown(not grouped)
    else
        name = C_Spell.GetSpellName(entry.spell) or ("magia " .. entry.spell)
        icon = C_Spell.GetSpellTexture(entry.spell)
        rank = C_Spell.GetSpellSubtext(entry.spell)
        row.pet:Hide()
    end
    row.icon:SetTexture(icon or 134400)
    row.name:SetText(name)
    row.rank:SetText(rank or "")
    if entry.level > playerLevel then
        row.level:SetText(("|cffff6060nível %d|r"):format(entry.level))
    else
        row.level:SetText(("nível %d"):format(entry.level))
    end
    row.cost:SetText(entry.cost > 0 and C_CurrencyInfo.GetCoinTextureString(entry.cost) or "")
end

function Training.Refresh()
    if not panel or not panel:IsShown() then
        if tab then
            local buckets = Build()
            Training.UpdateTab(#buckets.now)
        end
        return
    end
    local buckets = Build()
    local playerLevel = PlayerLevel()
    local y, rowIndex, headerIndex = 0, 0, 0
    local width = panel.scroll:GetWidth()
    for _, section in ipairs(SECTIONS) do
        local list = buckets[section.key]
        if #list > 0 then
            if collapsed[section.key] == nil then
                collapsed[section.key] = section.collapsed or false
            end
            headerIndex = headerIndex + 1
            local header = Header(headerIndex)
            header.key = section.key
            header.text:SetText(("%s %s  ·  %d"):format(collapsed[section.key] and "+" or "-", section.title, #list))
            local total = Total(list)
            header.total:SetText(total > 0 and C_CurrencyInfo.GetCoinTextureString(total) or "")
            header:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
            header:SetWidth(width)
            StyleHeader(header, false)
            header:Show()
            y = y + HEADER_HEIGHT + 2
            if not collapsed[section.key] then
                -- Dentro da seção: magias e tomos separados, e os tomos por demônio.
                local function SubHeader(key, title, entries, indent, icon)
                    headerIndex = headerIndex + 1
                    local sub = Header(headerIndex)
                    sub.key = key
                    local mark = icon and ("|T%s:14|t "):format(icon) or ""
                    sub.text:SetText(("%s %s%s  ·  %d"):format(collapsed[key] and "+" or "-", mark, title, #entries))
                    local subTotal = Total(entries)
                    sub.total:SetText(subTotal > 0 and C_CurrencyInfo.GetCoinTextureString(subTotal) or "")
                    sub:SetPoint("TOPLEFT", panel.content, "TOPLEFT", indent, -y)
                    sub:SetWidth(width - indent)
                    StyleHeader(sub, true)
                    sub:Show()
                    y = y + HEADER_HEIGHT
                    return not collapsed[key]
                end
                local function Rows(entries, indent, grouped)
                    for _, entry in ipairs(entries) do
                        rowIndex = rowIndex + 1
                        local row = Row(rowIndex)
                        FillRow(row, entry, playerLevel, grouped)
                        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", indent, -y)
                        row:SetWidth(width - indent)
                        row:Show()
                        y = y + ROW_HEIGHT
                    end
                end
                local spells, tomes = {}, {}
                for _, entry in ipairs(list) do
                    table.insert(entry.item and tomes or spells, entry)
                end
                local split = #spells > 0 and #tomes > 0
                local indent = split and 10 or 0
                if #spells > 0 and (not split or SubHeader(section.key .. ":spells", "Magias do instrutor", spells, indent)) then
                    Rows(spells, indent)
                end
                if #tomes > 0 and (not split or SubHeader(section.key .. ":tomes", "Tomos de demônio", tomes, indent)) then
                    for _, family in ipairs(PET_ORDER) do
                        local ofPet = {}
                        for _, entry in ipairs(tomes) do
                            if entry.family == family then
                                ofPet[#ofPet + 1] = entry
                            end
                        end
                        if #ofPet > 0 and SubHeader(section.key .. ":" .. family, PetName(family), ofPet, indent + 10, PET_ICONS[family]) then
                            Rows(ofPet, indent + 10, true)
                        end
                    end
                end
            end
            y = y + 6
        end
    end
    for index = rowIndex + 1, #rows do
        rows[index]:Hide()
    end
    for index = headerIndex + 1, #headers do
        headers[index]:Hide()
    end
    panel.content:SetSize(width, math.max(y, 1))
    panel.empty:SetShown(headerIndex == 0)

    local now = Total(buckets.now)
    local color = GetMoney() >= now and "|cffffffff" or "|cffff6060"
    panel.total:SetText(("Para aprender agora: %s%s|r"):format(color, C_CurrencyInfo.GetCoinTextureString(now)))
    local missingPets = {}
    if select(2, UnitClass("player")) == "WARLOCK" then
        for _, family in ipairs(PET_ORDER) do
            local seen = false
            for key in pairs(mine.pet) do
                if key:find("^" .. family .. ":") then
                    seen = true
                    break
                end
            end
            if not seen and Known(SUMMONS[family]) then
                missingPets[#missingPets + 1] = PetName(family)
            end
        end
    end
    if #missingPets > 0 then
        panel.hint:SetText("Invoque uma vez para conferir os tomos: " .. table.concat(missingPets, ", "))
    else
        panel.hint:SetText("")
    end
    Training.UpdateTab(#buckets.now)
end

local function SpellBook()
    return _G.PlayerSpellsFrame or _G.SpellBookFrame
end

-- A janela do grimório também mostra os talentos: a aba e o painel são filhos da
-- página do grimório, para sumirem quando a página de talentos está aberta.
local function Page()
    local book = SpellBook()
    return book and book.SpellBookFrame or book
end

local function CreatePanel()
    local book = SpellBook()
    panel = CreateFrame("Frame", "QollyTrainingPanel", Page() or UIParent, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetBackdrop(BACKDROP)
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    panel:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    panel:EnableMouse(true)
    panel:SetFrameStrata(book and book:GetFrameStrata() or "HIGH")
    panel:SetToplevel(true)
    if book then
        panel:SetPoint("TOPLEFT", book, "TOPRIGHT", 2, -20)
        panel:SetPoint("BOTTOMLEFT", book, "BOTTOMRIGHT", 2, 10)
    else
        panel:SetPoint("CENTER")
        panel:SetHeight(560)
    end

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetText(Qolly.TAG .. "Treino")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        Training.SetOpen(false)
    end)
    panel.total = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    panel.total:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
    panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.hint:SetPoint("TOPLEFT", panel.total, "BOTTOMLEFT", 0, -4)
    panel.hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    panel.hint:SetJustifyH("LEFT")

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 8, -64)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(WIDTH - 40, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetText("Nada para aprender. Tudo em dia!")

    panel:SetScript("OnShow", Training.Refresh)
    panel:Hide()
end

-- Aba na lateral direita do grimório; com o painel aberto, fica na borda dele.
function Training.UpdateTab(count)
    if not tab then
        return
    end
    local open = panel and panel:IsShown()
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", open and panel or SpellBook(), "TOPRIGHT", open and 8 or 0, open and -20 or -60)
    tab.glow:SetShown(open)
    if count then
        tab.count:SetText(count > 0 and count or "")
    end
end

local function CreateTab()
    local book = SpellBook()
    if not book or tab then
        return
    end
    tab = CreateFrame("Button", "QollyTrainingTab", Page(), "BackdropTemplate")
    tab:SetSize(40, 40)
    tab:SetBackdrop(BACKDROP)
    tab:SetBackdropColor(0, 0, 0, 0.85)
    tab:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("TOPLEFT", 5, -5)
    tab.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    tab.icon:SetTexture("Interface/Icons/INV_Misc_Book_11")
    tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tab.glow = tab:CreateTexture(nil, "OVERLAY")
    tab.glow:SetPoint("TOPLEFT", -6, 6)
    tab.glow:SetPoint("BOTTOMRIGHT", 6, -6)
    tab.glow:SetTexture("Interface/Buttons/CheckButtonHilight")
    tab.glow:SetBlendMode("ADD")
    tab.glow:Hide()
    tab:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    tab.count = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    tab.count:SetPoint("BOTTOMRIGHT", -3, 3)
    tab:SetScript("OnClick", function()
        Training.SetOpen(not (panel and panel:IsShown()))
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Qolly.TAG .. "Treino")
        GameTooltip:AddLine("O que aprender no instrutor agora e nos próximos níveis.", 1, 1, 1, true)
        if select(2, UnitClass("player")) == "WARLOCK" then
            GameTooltip:AddLine("Inclui os tomos dos demônios.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    if db.open then
        Training.SetOpen(true)
    end
    Training.UpdateTab()
    Training.Refresh()
end

function Training.SetOpen(open)
    if not panel then
        CreatePanel()
    end
    db.open = open and true or false
    panel:SetShown(open)
    Training.UpdateTab()
end

local function OpenBook()
    local page = Page()
    if page and page:IsVisible() then
        return true
    end
    if PlayerSpellsUtil and PlayerSpellsUtil.OpenToSpellBookTab then
        pcall(PlayerSpellsUtil.OpenToSpellBookTab)
    elseif ToggleSpellBook then
        pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
    end
    page = Page()
    return page ~= nil and page:IsVisible()
end

-- Eventos ----------------------------------------------------------------------------

local pending = false
local function Later()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Qolly.Safe("treino", ScanPet)
        Qolly.Safe("treino", Training.Refresh)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PET_BAR_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterUnitEvent("UNIT_PET", "player")
events:SetScript("OnEvent", function(_, event, name)
    if not db then
        return
    end
    if event == "ADDON_LOADED" then
        if SpellBook() and not tab then
            Qolly.Safe("treino", CreateTab)
        end
        return
    end
    if event == "GET_ITEM_INFO_RECEIVED" and not (panel and panel:IsShown()) then
        return
    end
    Later()
end)

Qolly.RegisterModule("treino", {
    help = "- abre o painel de treino (o que aprender no instrutor e, no bruxo, os tomos)",
    init = function(saved)
        db = saved
        db.ignored = db.ignored or {}
        db.chars = db.chars or {}
        local key = UnitName("player") .. "-" .. GetRealmName()
        db.chars[key] = db.chars[key] or {}
        mine = db.chars[key]
        mine.pet = mine.pet or {}
        if SpellBook() then
            CreateTab()
        end
    end,
    command = function()
        if OpenBook() then
            Training.SetOpen(true)
        else
            Training.SetOpen(not (panel and panel:IsShown()))
        end
    end,
})
