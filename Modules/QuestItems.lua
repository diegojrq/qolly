-- Itens de missão na bolsa que não servem mais. Para cada item de missão vê quais
-- missões usam ou iniciam ele (banco do QuestMaster, quando carregado, e o que o jogo
-- diz do item) e confere no seu histórico:
--   não serve mais   todas as missões dele já foram concluídas
--   missão fora do diário   alguma missão dele não foi feita e não está no diário
--                           (abandonada, ou ainda não pegou: confira antes de apagar)
--   sem missão conhecida    nenhuma missão ligada ao item e nada no diário pede ele
-- Itens de missão ativa no diário não aparecem. Nada é apagado sem você confirmar.
local _, Qolly = ...

local QuestItems = {}
Qolly.QuestItems = QuestItems

local db

local FIRST_BAG, LAST_BAG = 0, 4
local QUEST_CLASS = 12

local STATUS = {
    done = { order = 1, text = "não serve mais", color = "|cffff5050" },
    alt = { order = 2, text = "missão feita por outro personagem", color = "|cffff9933" },
    later = { order = 3, text = "missão fora do diário", color = "|cffffd100" },
    unknown = { order = 4, text = "sem missão conhecida", color = "|cff999999" },
}
QuestItems.STATUS = STATUS

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

-- Banco do QuestMaster (GPL-3): item -> missões relacionadas e a que ele inicia.
local function QuestDB()
    local qm = _G.QuestMaster
    local qdb = qm and qm.DB
    if qdb and qdb.GetItem and qdb.items then
        return qdb
    end
end

-- Item -> missões, montado uma vez a partir do banco de missões do QuestMaster: o banco
-- de itens nem sempre liga o item à missão (ex.: Teronis' Journal só aparece na
-- missão 1023). Entra item de objetivo, o que a missão entrega ou pede, e o que a inicia.
local byItem

local function AddIndex(itemID, questID)
    if type(itemID) ~= "number" then
        return
    end
    local list = byItem[itemID]
    if not list then
        list = {}
        byItem[itemID] = list
    end
    list[#list + 1] = questID
end

local function AddIndexList(list, questID)
    if type(list) == "number" then
        AddIndex(list, questID)
    elseif type(list) == "table" then
        for _, entry in pairs(list) do
            AddIndex(type(entry) == "table" and entry[1] or entry, questID)
        end
    end
end

local function QuestsOfItem(itemID)
    local qdb = QuestDB()
    local schema = _G.QMData and _G.QMData.questSchema
    if not (qdb and qdb.quests and schema) then
        return nil
    end
    if not byItem then
        byItem = {}
        local goalsAt, startAt = schema.qGoals, schema.qStartItem
        local requiredAt, originAt = schema.qRequiredItems, schema.qOrigin
        for questID, row in pairs(qdb.quests) do
            if type(row) == "table" then
                local goals = goalsAt and row[goalsAt]
                if type(goals) == "table" then
                    AddIndexList(goals[3], questID)
                end
                AddIndexList(startAt and row[startAt], questID)
                AddIndexList(requiredAt and row[requiredAt], questID)
                local origin = originAt and row[originAt]
                if type(origin) == "table" then
                    AddIndexList(origin[3], questID)
                end
            end
        end
    end
    return byItem[itemID]
end

local function QuestTitle(questID)
    local qdb = QuestDB()
    local quest = qdb and qdb.GetQuest and qdb:GetQuest(questID)
    local title = quest and quest.name
    if not title and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID)
    end
    return Plain(title) or ("#" .. questID)
end

local function Done(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID) == true
end

-- Missões concluídas por qualquer personagem da conta. O QollyDB é da conta inteira:
-- cada personagem anota as suas ao logar e a cada entrega. O nome de quem fez fica junto.
local function DoneByAlt(questID)
    if C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) == true then
        return true
    end
    return db.account[questID] ~= nil
end

local function PlayerName()
    return UnitName("player") .. "-" .. (GetRealmName() or "")
end

local function RecordAll()
    local me = PlayerName()
    local ids = C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()
    if type(ids) == "table" then
        for _, questID in ipairs(ids) do
            if not db.account[questID] then
                db.account[questID] = me
            end
        end
    end
end

local function OnQuest(questID)
    return C_QuestLog.IsOnQuest(questID) == true
end

-- Texto de todos os objetivos do diário, para itens que o banco não conhece.
local function LogText()
    local parts = {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local text = Plain(objective.text)
                if text then
                    parts[#parts + 1] = text:lower()
                end
            end
        end
    end
    return table.concat(parts, "\n")
end

local function AddQuest(quests, questID)
    questID = Plain(questID)
    if type(questID) == "number" and questID > 0 then
        quests[questID] = true
    end
end

local function AddQuests(quests, list)
    if type(list) == "number" then
        AddQuest(quests, list)
    elseif type(list) == "table" then
        for _, questID in pairs(list) do
            AddQuest(quests, questID)
        end
    end
end

-- status, missões do item (lista), ou nil quando o item ainda serve / não é de missão.
local function Classify(bag, slot, itemID, logText)
    local questInfo = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    local isQuest = classID == QUEST_CLASS
        or (questInfo and (Plain(questInfo.isQuestItem) or Plain(questInfo.questID)))
    if not isQuest then
        return nil
    end
    if questInfo and Plain(questInfo.isActive) then
        return nil
    end

    local quests = {}
    if questInfo then
        AddQuest(quests, questInfo.questID)
    end
    local qdb = QuestDB()
    local item = qdb and qdb:GetItem(itemID)
    if item then
        AddQuests(quests, item.relatedQuests)
        AddQuests(quests, item.startQuest)
    end
    AddQuests(quests, QuestsOfItem(itemID))

    -- pending: alguma missão nem você nem outro personagem fez; alt: alguma só outro fez.
    local list, pending, alt = {}, false, false
    for questID in pairs(quests) do
        if OnQuest(questID) then
            return nil
        end
        if not Done(questID) then
            if DoneByAlt(questID) then
                alt = true
            else
                pending = true
            end
        end
        list[#list + 1] = questID
    end
    table.sort(list)

    if #list == 0 then
        local name = Plain(C_Item.GetItemNameByID(itemID))
        if name and logText:find(name:lower(), 1, true) then
            return nil
        end
        return "unknown", list
    end
    if pending then
        return "later", list
    end
    return alt and "alt" or "done", list
end

-- Itens de missão que sobraram, um por item (a quantidade somada das bolsas).
function QuestItems.Scan()
    local logText = LogText()
    local seen, result = {}, {}
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and Plain(info.itemID)
            if itemID and not (db.ignore and db.ignore[itemID]) then
                local entry = seen[itemID]
                if entry then
                    entry.count = entry.count + (Plain(info.stackCount) or 1)
                else
                    local ok, status, quests = pcall(Classify, bag, slot, itemID, logText)
                    if ok and status then
                        entry = {
                            itemID = itemID,
                            link = Plain(info.hyperlink) or ("item:" .. itemID),
                            icon = Plain(info.iconFileID),
                            count = Plain(info.stackCount) or 1,
                            status = status,
                            quests = quests,
                            bag = bag,
                            slot = slot,
                        }
                        seen[itemID] = entry
                        result[#result + 1] = entry
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.status ~= b.status then
            return STATUS[a.status].order < STATUS[b.status].order
        end
        return a.itemID < b.itemID
    end)
    return result
end

local function QuestsText(entry, limit)
    local names = {}
    for index, questID in ipairs(entry.quests) do
        if index > limit then
            names[#names + 1] = ("+%d"):format(#entry.quests - limit)
            break
        end
        local mark = Done(questID) and "|TInterface/RaidFrame/ReadyCheck-Ready:12|t "
            or DoneByAlt(questID) and "|TInterface/RaidFrame/ReadyCheck-Waiting:12|t "
            or "|cffffd100•|r "
        local who = not Done(questID) and type(db.account[questID]) == "string" and db.account[questID]
        if who then
            mark = mark .. ("|cff999999(%s)|r "):format(who:match("^[^-]+") or who)
        end
        names[#names + 1] = mark .. QuestTitle(questID)
    end
    return table.concat(names, ", ")
end

-- Apagar --------------------------------------------------------------------------
-- O item pode ter mudado de lugar: procura de novo pelo id antes de apagar.

local function FindSlot(itemID)
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                return bag, slot
            end
        end
    end
end

local Refresh

StaticPopupDialogs["QOLLY_DELETE_QUEST_ITEM"] = {
    text = "Qolly: apagar %s?\n\n%s",
    button1 = DELETE or "Apagar",
    button2 = CANCEL or "Cancelar",
    OnAccept = function(_, itemID)
        local remaining = 0
        while remaining < 20 do
            local bag, slot = FindSlot(itemID)
            if not bag then
                break
            end
            ClearCursor()
            C_Container.PickupContainerItem(bag, slot)
            if not CursorHasItem() then
                break
            end
            DeleteCursorItem()
            remaining = remaining + 1
        end
        C_Timer.After(0.3, function()
            if Refresh then
                Qolly.Safe("itens de missão", Refresh)
            end
        end)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function AskDelete(entry)
    local warning = entry.status == "done" and "Todas as missões dele já foram concluídas."
        or entry.status == "alt" and "Você não fez a missão, mas outro personagem da conta já fez."
        or entry.status == "later" and "Atenção: alguma missão dele ainda não foi feita."
        or "Nenhuma missão conhecida usa este item."
    local dialog = StaticPopup_Show("QOLLY_DELETE_QUEST_ITEM", entry.link, warning)
    if dialog then
        dialog.data = entry.itemID
    end
end

-- Lista no painel ------------------------------------------------------------------

local ROW = 34
local body, scroll, content, empty, summary
local rows = {}

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 0, 0)
    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetSize(70, 22)
    row.delete:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.delete:SetText("Apagar")
    row.ignore = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.ignore:SetSize(70, 22)
    row.ignore:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
    row.ignore:SetText("Manter")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.ignore, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.detail:SetPoint("RIGHT", row.ignore, "LEFT", -8, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.delete:SetScript("OnClick", function()
        AskDelete(row.entry)
    end)
    row.ignore:SetScript("OnClick", function()
        db.ignore[row.entry.itemID] = true
        Qolly.Safe("itens de missão", Refresh)
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.entry.bag, self.entry.slot)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(self.entry.link)
        end
    end)
    rows[index] = row
    return row
end

function Refresh()
    if not body or not body:IsVisible() then
        return
    end
    local list = QuestItems.Scan()
    for index, entry in ipairs(list) do
        local row = Row(index)
        row.entry = entry
        row.icon:SetTexture(entry.icon or C_Item.GetItemIconByID(entry.itemID))
        row.count:SetText(entry.count > 1 and entry.count or "")
        row.name:SetText(entry.link)
        local status = STATUS[entry.status]
        local quests = #entry.quests > 0 and ("  |cffbbbbbb" .. QuestsText(entry, 3) .. "|r") or ""
        row.detail:SetText(status.color .. status.text .. "|r" .. quests)
        row:Show()
    end
    for index = #list + 1, #rows do
        rows[index]:Hide()
    end
    content:SetHeight(math.max(1, #list * ROW))
    empty:SetShown(#list == 0)
    local ignored = 0
    for _ in pairs(db.ignore) do
        ignored = ignored + 1
    end
    local source = QuestDB() and "banco do QuestMaster" or "só o diário (QuestMaster desligado)"
    summary:SetText(("%d itens  ·  %s%s"):format(#list, source,
        ignored > 0 and ("  ·  %d mantidos"):format(ignored) or ""))
end

local function CreateBody()
    body = CreateFrame("Frame", "QollyQuestItemsBody")
    summary = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summary:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -4)
    local reset = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
    reset:SetSize(150, 20)
    reset:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, 0)
    reset:SetText("Mostrar os mantidos")
    reset:SetScript("OnClick", function()
        wipe(db.ignore)
        Qolly.Safe("itens de missão", Refresh)
    end)
    scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 4, -26)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)
    empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", scroll, "CENTER")
    empty:SetText("Nenhum item de missão sobrando na bolsa.")
    body:SetScript("OnShow", function()
        Qolly.Safe("itens de missão", Refresh)
    end)
end

function QuestItems.Embed(parent)
    if not body then
        CreateBody()
    end
    body:SetParent(parent)
    body:ClearAllPoints()
    body:SetAllPoints(parent)
    body:Show()
    Qolly.Safe("itens de missão", Refresh)
    return body
end

-- Bolsa ou diário mudou com a lista aberta: atualiza (um pouco depois, juntando eventos).
local account = CreateFrame("Frame")
account:RegisterEvent("PLAYER_LOGIN")
account:RegisterEvent("QUEST_TURNED_IN")
account:SetScript("OnEvent", function(_, event, questID)
    if not db then
        return
    end
    if event == "PLAYER_LOGIN" then
        Qolly.Safe("missões da conta", RecordAll)
    elseif type(questID) == "number" and not Qolly.IsSecret(questID) then
        db.account[questID] = db.account[questID] or PlayerName()
    end
end)

local pending = false
local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function()
    if pending or not body or not body:IsVisible() then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Qolly.Safe("itens de missão", Refresh)
    end)
end)

-- Linha no tooltip do item da bolsa ---------------------------------------------------

local function OnItem(tooltip, data)
    if not db or db.tooltip == false or tooltip:IsForbidden() then
        return
    end
    local owner = tooltip:GetOwner()
    if not owner or not owner.GetID then
        return
    end
    -- Bolsa do jogo tem GetBagID; o Bagnon, GetBag.
    local getBag = owner.GetBagID or owner.GetBag
    if not getBag then
        return
    end
    local itemID = data and Plain(data.id)
    if type(itemID) ~= "number" then
        return
    end
    local bag, slot = getBag(owner), owner:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" then
        return
    end
    local status, quests = Classify(bag, slot, itemID, LogText())
    if not status then
        return
    end
    local info = STATUS[status]
    tooltip:AddLine(Qolly.TAG .. info.color .. "Item de missão: " .. info.text .. "|r")
    if #quests > 0 then
        tooltip:AddLine(QuestsText({ quests = quests }, 4), 0.75, 0.75, 0.75, true)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        pcall(OnItem, tooltip, data)
    end)
end

function QuestItems.Open()
    Qolly.Options.Open("Itens de missão")
end

Qolly.RegisterModule("missao", {
    help = "(itens de missão na bolsa que não servem mais)",
    command = function()
        QuestItems.Open()
    end,
    init = function(moduleDB)
        db = moduleDB
        db.ignore = db.ignore or {}
        db.account = db.account or {}
    end,
})
