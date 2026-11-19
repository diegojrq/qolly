-- Quests de masmorra: aba lateral na janela do DungeonJournal (e /qolly masmorras) com
-- as quests das masmorras do seu nível, em que passo da cadeia você está e um clique
-- que marca no mapa onde pegar o próximo passo.
--
-- Os dados (quem dá cada quest, coordenadas, cadeias de pré-requisito) são do addon
-- DungeonJournal e são lidos dele em tempo de jogo; o Qolly não copia nada. Sem o
-- DungeonJournal instalado o módulo fica desligado e não pode ser ligado.
local _, Qolly = ...

local DQ = {}
Qolly.DungeonQuests = DQ

local DJ_ADDON = "ForeverDungeonJournal"
local DJ_FRAME = "ForeverDungeonJournalFrame"
local WIDTH, HEIGHT = 440, 560
local ROW_HEIGHT, HEADER_HEIGHT = 34, 22
-- Masmorras "do seu nível": a faixa dela, com esta folga para baixo e para cima.
local BELOW, ABOVE = 3, 2

local db
local panel, tab
local rows, headers = {}, {}
local collapsed = {}

-- Dados do DungeonJournal ---------------------------------------------------------------

local function Data()
    local ns = _G.ForeverDungeonJournal_NS
    if type(ns) == "table" and type(ns.DB) == "table" then
        return ns
    end
end

-- Motivo para não poder ligar, ou nil.
function DQ.Unavailable()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(DJ_ADDON)
    if not loaded or not Data() then
        return "precisa do DungeonJournal"
    end
end

function DQ.IsEnabled()
    return db ~= nil and db.enabled ~= false and not DQ.Unavailable()
end

local function Done(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
end

local function InLog(id)
    local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    return index ~= nil and index > 0
end

-- Nome da quest no idioma do jogo quando ele já conhece; senão o do DungeonJournal.
local function Title(id, fallback)
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if type(title) == "string" and title ~= "" then
        return title
    end
    return fallback or ("quest " .. id)
end

local function LevelRange(text)
    local low, high = tostring(text or ""):match("(%d+)%D+(%d+)")
    low, high = tonumber(low), tonumber(high)
    if not low then
        low = tonumber(tostring(text or ""):match("%d+"))
        high = low
    end
    return low or 0, high or low or 0
end

local function ForMe(quest)
    local faction = UnitFactionGroup("player")
    if quest.faction and quest.faction ~= "Both" and quest.faction ~= faction then
        return false
    end
    if quest.classOnly and quest.classOnly ~= select(2, UnitClass("player")) then
        return false
    end
    return true
end

-- Onde pegar uma quest: { mapID, x, y, label } ou nil.
local function StartMap(ns, id)
    local details = ns.QUEST_PREREQ_DETAILS and ns.QUEST_PREREQ_DETAILS[id]
    local map = (details and (details.map or details.hubMap)) or (ns.QUEST_START_MAPS and ns.QUEST_START_MAPS[id])
    if type(map) == "table" and map.mapID and map.x and map.y then
        return map
    end
end

-- Estado de uma quest de masmorra:
--   done      feita
--   log       na mochila (entregar em quest.turnin)
--   chain     falta um passo anterior: next = { id, name, index, total, inLog, pickup, map }
--   low       nível baixo para pegar
--   ready     dá para pegar agora: pickup e map
local function State(ns, quest)
    local level = UnitLevel("player") or 0
    if Done(quest.id) then
        return { kind = "done" }
    end
    if InLog(quest.id) then
        return { kind = "log" }
    end
    local chain = ns.QUEST_PREREQ_CHAINS and ns.QUEST_PREREQ_CHAINS[quest.id]
    if type(chain) == "table" then
        local total = #chain
        for index, step in ipairs(chain) do
            if type(step) == "table" and step.id and not step.itemStep and not Done(step.id) then
                local details = (ns.QUEST_PREREQ_DETAILS and ns.QUEST_PREREQ_DETAILS[step.id]) or {}
                return {
                    kind = "chain",
                    next = {
                        id = step.id,
                        name = Title(step.id, step.name),
                        index = index,
                        total = total,
                        inLog = InLog(step.id),
                        pickup = details.pickup,
                        requires = details.requires,
                        inside = details.startsInDungeon,
                        map = StartMap(ns, step.id),
                    },
                }
            end
        end
    end
    if quest.requires and level < quest.requires then
        return { kind = "low" }
    end
    return { kind = "ready", map = StartMap(ns, quest.id) }
end

-- Masmorras com quests para você, ordenadas pelo nível.
local function Dungeons(all)
    local ns = Data()
    local list = {}
    if not ns then
        return list
    end
    local level = UnitLevel("player") or 0
    for name, dungeon in pairs(ns.DB) do
        if type(dungeon) == "table" and type(dungeon.quests) == "table" then
            local low, high = LevelRange(dungeon.level)
            if all or (level >= low - BELOW and level <= high + ABOVE) then
                local quests = {}
                local done = 0
                for _, quest in ipairs(dungeon.quests) do
                    if type(quest) == "table" and quest.id and ForMe(quest) then
                        local state = State(ns, quest)
                        if state.kind == "done" then
                            done = done + 1
                        end
                        if state.kind ~= "done" or db.showDone then
                            quests[#quests + 1] = { quest = quest, state = state }
                        end
                    end
                end
                if #quests > 0 or (done > 0 and db.showDone) then
                    table.sort(quests, function(a, b)
                        return (a.quest.level or 0) < (b.quest.level or 0)
                    end)
                    list[#list + 1] = { name = name, low = low, high = high, quests = quests, done = done, icon = dungeon.icon }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.low ~= b.low then
            return a.low < b.low
        end
        return a.name < b.name
    end)
    return list
end

-- Mapa ----------------------------------------------------------------------------------

local function Waypoint(map, label)
    if not (map and C_Map and C_Map.SetUserWaypoint and UiMapPoint) then
        return false
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map.mapID) then
        return false
    end
    local ok = pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map.mapID, map.x, map.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    if ok then
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map.mapID)
        Qolly.Print(("Marcado no mapa: %s (%s %.1f, %.1f)."):format(label or map.label or "",
            info and info.name or "?", map.x * 100, map.y * 100))
    end
    return ok
end

-- Onde ir para avançar nesta quest: map, rótulo.
local function Target(entry)
    local state = entry.state
    if state.kind == "chain" and not state.next.inLog then
        return state.next.map, state.next.name
    elseif state.kind == "ready" or state.kind == "low" then
        return state.map, Title(entry.quest.id, entry.quest.name)
    end
end

-- Texto -------------------------------------------------------------------------------

local STATUS = {
    done = "|cff66ff66feita|r",
    log = "|cffffd200na mochila|r",
    chain = "|cffaaaaaafalta cadeia|r",
    low = "|cffff6666nível baixo|r",
    ready = "|cff66ccffpegar|r",
}

local function Detail(entry)
    local quest, state = entry.quest, entry.state
    if state.kind == "done" then
        return "Concluída."
    elseif state.kind == "log" then
        return "Entregar: " .. (quest.turnin or "?")
    elseif state.kind == "chain" then
        local step = state.next
        local where = step.inLog and "na mochila" or (step.pickup and ("pegar: " .. step.pickup)) or "sem local"
        return ("Passo %d/%d: %s - %s"):format(step.index, step.total, step.name, where)
    elseif state.kind == "low" then
        return ("A partir do nível %d. Pegar: %s"):format(quest.requires or 0, quest.pickup or "?")
    end
    return "Pegar: " .. (quest.pickup or "?")
end

local function ShowRowTip(row)
    local entry = row.entry
    local ns = Data()
    if not (entry and ns) then
        return
    end
    local quest = entry.quest
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Title(quest.id, quest.name), 1, 0.82, 0)
    if quest.level then
        GameTooltip:AddLine(("Nível %d (pega a partir do %d)"):format(quest.level, quest.requires or quest.level), 0.8, 0.8, 0.8)
    end
    if quest.objective then
        GameTooltip:AddLine(quest.objective, 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    if quest.pickup then
        GameTooltip:AddDoubleLine("Pegar", quest.pickup, 0.6, 0.8, 1, 1, 1, 1)
    end
    if quest.turnin then
        GameTooltip:AddDoubleLine("Entregar", quest.turnin, 0.6, 0.8, 1, 1, 1, 1)
    end
    local chain = ns.QUEST_PREREQ_CHAINS and ns.QUEST_PREREQ_CHAINS[quest.id]
    if type(chain) == "table" and #chain > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Cadeia até ela:", 0.6, 0.8, 1)
        for index, step in ipairs(chain) do
            if type(step) == "table" and step.id then
                local mark
                if step.itemStep then
                    mark = "|TInterface/RaidFrame/ReadyCheck-Waiting:12|t"
                elseif Done(step.id) then
                    mark = "|TInterface/RaidFrame/ReadyCheck-Ready:12|t"
                elseif InLog(step.id) then
                    mark = "|TInterface/RaidFrame/ReadyCheck-Waiting:12|t"
                else
                    mark = "|TInterface/RaidFrame/ReadyCheck-NotReady:12|t"
                end
                GameTooltip:AddLine(("%s %d. %s"):format(mark, index, Title(step.id, step.name)), 1, 1, 1)
            end
        end
    end
    if quest.rewardSummary and quest.rewardSummary ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Recompensa", quest.rewardSummary, 0.6, 0.8, 1, 1, 1, 1)
    end
    local map = Target(entry)
    GameTooltip:AddLine(" ")
    if map then
        GameTooltip:AddLine(Qolly.TAG .. "clique: marcar no mapa onde pegar", 0.4, 1, 0.4)
    elseif entry.state.kind == "chain" and entry.state.next.inside then
        GameTooltip:AddLine(Qolly.TAG .. "o próximo passo começa dentro da masmorra", 0.8, 0.8, 0.8)
    elseif entry.state.kind ~= "done" and entry.state.kind ~= "log" then
        GameTooltip:AddLine(Qolly.TAG .. "sem coordenada: siga o texto de \"Pegar\"", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

-- Painel --------------------------------------------------------------------------------

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, panel.content)
    row:SetHeight(ROW_HEIGHT)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("TOPRIGHT", -6, -4)
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.level:SetPoint("TOPLEFT", 14, -4)
    row.level:SetWidth(22)
    row.level:SetJustifyH("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.level, "TOPRIGHT", 2, 1)
    row.name:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", -6, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row:SetScript("OnEnter", ShowRowTip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        local map, label = Target(self.entry)
        if not Waypoint(map, label) then
            Qolly.Print("Sem coordenada para essa quest. " .. Detail(self.entry))
        end
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
    header.background = header:CreateTexture(nil, "BACKGROUND")
    header.background:SetAllPoints()
    header.background:SetColorTexture(1, 0.82, 0, 0.12)
    header.icon = header:CreateTexture(nil, "ARTWORK")
    header.icon:SetSize(16, 16)
    header.icon:SetPoint("LEFT", 4, 0)
    header.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.text:SetPoint("LEFT", header.icon, "RIGHT", 6, 0)
    header.info = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    header.info:SetPoint("RIGHT", -6, 0)
    header:SetScript("OnClick", function(self)
        collapsed[self.key] = not collapsed[self.key]
        DQ.Refresh()
    end)
    headers[index] = header
    return header
end

function DQ.Refresh()
    if not (panel and panel:IsShown()) then
        return
    end
    for _, row in ipairs(rows) do
        row:Hide()
    end
    for _, header in ipairs(headers) do
        header:Hide()
    end
    local list = Dungeons(db.all)
    local y, rowIndex, headerIndex = 0, 0, 0
    local width = panel.scroll:GetWidth()
    local available = 0
    for _, dungeon in ipairs(list) do
        headerIndex = headerIndex + 1
        local header = Header(headerIndex)
        header.key = dungeon.name
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetWidth(width)
        header.icon:SetTexture(dungeon.icon or "Interface/Icons/INV_Misc_Book_09")
        header.text:SetText((collapsed[dungeon.name] and "+ " or "") .. dungeon.name)
        header.info:SetText(("nível %d-%d  ·  %d feita(s)"):format(dungeon.low, dungeon.high, dungeon.done))
        header:Show()
        y = y + HEADER_HEIGHT + 2
        for _, entry in ipairs(dungeon.quests) do
            local kind = entry.state.kind
            if kind == "ready" or (kind == "chain" and not entry.state.next.inLog) then
                available = available + 1
            end
            if not collapsed[dungeon.name] then
                rowIndex = rowIndex + 1
                local row = Row(rowIndex)
                row.entry = entry
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetWidth(width)
                row.level:SetText(entry.quest.level or "")
                row.name:SetText(Title(entry.quest.id, entry.quest.name))
                row.status:SetText(STATUS[kind] or "")
                row.detail:SetText(Detail(entry))
                row:Show()
                y = y + ROW_HEIGHT
            end
        end
        y = y + 6
    end
    panel.content:SetHeight(math.max(1, y))
    panel.empty:SetShown(#list == 0)
    if tab then
        tab:SetCount(available)
    end
end

local function DJFrame()
    return _G[DJ_FRAME]
end

local function Layout()
    local open = panel and panel:IsShown()
    local host = DJFrame()
    if panel then
        panel:ClearAllPoints()
        if host and host:IsShown() then
            panel:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
        else
            panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    if tab and host then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", (open and host:IsShown()) and panel or host, "TOPRIGHT", (open and host:IsShown()) and 8 or 0, -60)
        tab:SetActive(open)
    end
end

local function OptionButton(label, key, previous)
    local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    button:SetSize(22, 22)
    if previous then
        button:SetPoint("LEFT", previous.label, "RIGHT", 12, 0)
    else
        button:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", -2, -4)
    end
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    button.label:SetText(label)
    button:SetScript("OnShow", function(self)
        self:SetChecked(db[key] and true or false)
    end)
    button:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        DQ.Refresh()
    end)
    return button
end

local function CreatePanel()
    panel = Qolly.SidePanel(UIParent, "QollyDungeonQuests", "Quests de masmorra", WIDTH, function()
        DQ.SetOpen(false)
    end)
    panel:SetHeight(HEIGHT)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "QollyDungeonQuests")

    local all = OptionButton("Todas as masmorras", "all")
    OptionButton("Mostrar feitas", "showDone", all)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", 8, -66)
    panel.scroll:SetPoint("BOTTOMRIGHT", -30, 26)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(WIDTH - 40, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetText("Nenhuma quest de masmorra para o seu nível.")
    panel.empty:Hide()
    panel.credit = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.credit:SetPoint("BOTTOMLEFT", 12, 8)
    panel.credit:SetText("Dados: DungeonJournal. Clique numa quest para marcar no mapa.")

    panel:SetScript("OnShow", function()
        Layout()
        DQ.Refresh()
    end)
    panel:SetScript("OnHide", Layout)
end

function DQ.SetOpen(open)
    if open and not DQ.IsEnabled() then
        Qolly.Print("Quests de masmorra: " .. (DQ.Unavailable() or "desligado nas configurações") .. ".")
        return
    end
    if not panel then
        CreatePanel()
    end
    panel:SetShown(open)
    Layout()
end

local function CreateTab()
    local host = DJFrame()
    if tab or not host or not DQ.IsEnabled() then
        return
    end
    tab = Qolly.SideTab(host, "Interface/Icons/INV_Misc_Map_01", "Quests de masmorra",
        "Onde pegar cada quest e em que passo da cadeia você está.", function()
            DQ.SetOpen(not (panel and panel:IsShown()))
        end)
    host:HookScript("OnHide", function()
        if panel and panel:IsShown() then
            panel:Hide()
        end
    end)
    host:HookScript("OnShow", Layout)
    Layout()
end

function DQ.SetEnabled(on)
    db.enabled = on and true or false
    if on then
        CreateTab()
    end
    if tab then
        tab:SetShown(DQ.IsEnabled())
    end
    if not DQ.IsEnabled() and panel then
        panel:Hide()
    end
end

-- Eventos -------------------------------------------------------------------------------

local pending = false
local function Later()
    if pending or not (panel and panel:IsShown()) then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Qolly.Safe("quests de masmorra", DQ.Refresh)
    end)
end

-- A janela do DungeonJournal só existe depois de aberta a primeira vez: procura ela
-- de tempos em tempos até achar.
local finder
local function FindHost()
    if tab or not DQ.IsEnabled() then
        return
    end
    if DJFrame() then
        Qolly.Safe("quests de masmorra", CreateTab)
    elseif not finder then
        finder = C_Timer.NewTicker(2, function()
            if tab or not DQ.IsEnabled() then
                finder:Cancel()
                finder = nil
            elseif DJFrame() then
                finder:Cancel()
                finder = nil
                Qolly.Safe("quests de masmorra", CreateTab)
            end
        end)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_REMOVED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event)
    if not db then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        FindHost()
        return
    end
    Later()
end)

Qolly.RegisterModule("masmorras", {
    help = "- quests das masmorras do seu nível e onde pegar (precisa do DungeonJournal)",
    init = function(saved)
        db = saved
        if db.showDone == nil then
            db.showDone = false
        end
    end,
    command = function()
        DQ.SetOpen(not (panel and panel:IsShown()))
    end,
})
