-- Gear: melhorias de equipamento à venda na AH, calculadas pelo QuestMaster.
-- Durante o scan separamos armas e armaduras até o nível do personagem, pelo link
-- completo (itens "da Baleia", "da Coruja" têm o mesmo id e stats diferentes). No fim,
-- o QuestMaster diz quais são melhoria e se o personagem pode usar.
local _, Qolly = ...
local AH = Qolly.AH

local Gear = {}
Qolly.Gear = Gear

-- Links avaliados por frame: o QuestMaster lê stats e o tooltip de cada item.
local CHUNK = 100
local WEAPON, ARMOR = 2, 4

Gear.upgrades = {}
Gear.state = "idle" -- "idle", "working", "done", "noquestmaster"

local candidates, equippable, scanLevel
local token = 0

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- A parte do QuestMaster que compara equipamento, ou nil se ele não estiver carregado.
function Gear.QuestMaster()
    local qm = _G.QuestMaster
    local gear = type(qm) == "table" and qm.Gear
    if type(gear) == "table" and gear.Compare and gear.IsUpgrade and gear.Wearable and gear.ItemInfo then
        return gear
    end
end

-- O que está equipado agora, slot -> link, nos slots que o Gear Score conta.
local function WornLinks(score)
    local links = {}
    for slot in pairs(score.SLOTS) do
        links[slot] = GetInventoryItemLink("player", slot)
    end
    return links
end

-- Quanto o GS sobe trocando o item do slot pelo link. Arma de duas mãos tira a off-hand.
local function ScoreGain(score, worn, now, link, slot, info)
    local links = {}
    for wornSlot, wornLink in pairs(worn) do
        links[wornSlot] = wornLink
    end
    links[slot] = link
    if info.equipLoc == "INVTYPE_2HWEAPON" then
        links[17] = nil
    end
    return (score.Links(links)) - now
end

-- Arma ou armadura que pode ser usada até o nível do personagem. Cacheado por itemID
-- durante o scan, que tem dezenas de milhares de linhas.
local function IsCandidate(itemID)
    local known = equippable[itemID]
    if known ~= nil then
        return known
    end
    local _, _, _, equipLoc, _, classID = GetItemInfoInstant(itemID)
    local ok = (classID == WEAPON or classID == ARMOR) and equipLoc ~= nil and equipLoc ~= ""
    if ok then
        -- Item ainda fora do cache não tem nível: fica, e o QuestMaster decide no fim.
        local minLevel = select(5, GetItemInfo(itemID))
        ok = minLevel == nil or minLevel <= scanLevel
    end
    equippable[itemID] = ok
    return ok
end

AH.AddListener({
    begin = function()
        candidates, equippable = {}, {}
        scanLevel = UnitLevel("player")
    end,
    row = function(index, itemID, count, buyout)
        if not IsCandidate(itemID) then
            return
        end
        local link = C_AuctionHouse.GetReplicateItemLink(index)
        if not link or Qolly.IsSecret(link) then
            return
        end
        local unit = buyout / count
        if not candidates[link] or unit < candidates[link] then
            candidates[link] = unit
        end
    end,
    finish = function()
        Gear.db.candidates = candidates
        Gear.db.scanTime = time()
        candidates, equippable = nil, nil
        Gear.Evaluate()
        Gear.List.Show()
    end,
})

-- O que decide o resultado: scan, nível, papel do QuestMaster e o que está equipado.
-- Igual ao do último cálculo, a lista pronta continua valendo.
local function Signature()
    local qm = Gear.QuestMaster()
    local parts = { Gear.db.scanTime or 0, UnitLevel("player"), qm and qm:Role() or "" }
    for slot in pairs(Gear.Score.SLOTS) do
        parts[#parts + 1] = slot .. "=" .. (GetInventoryItemLink("player", slot) or "")
    end
    table.sort(parts, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return table.concat(parts, ";")
end

-- Precisa recalcular? Não enquanto um cálculo roda, nem se nada mudou desde o último.
function Gear.NeedsEvaluate()
    if Gear.state == "working" or not Gear.db.candidates then
        return false
    end
    if Gear.state ~= "done" then
        return true
    end
    return Gear.signature ~= Signature()
end

-- Recalcula as melhorias a partir dos candidatos do último scan, alguns por frame.
function Gear.Evaluate()
    local qm = Gear.QuestMaster()
    if not qm then
        Gear.state = "noquestmaster"
        Gear.upgrades = {}
        Gear.List.Refresh()
        return
    end

    token = token + 1
    local myToken = token
    Gear.signature = Signature()
    local links = {}
    for link in pairs(Gear.db.candidates or {}) do
        links[#links + 1] = link
    end
    local level = UnitLevel("player")
    local found, index = {}, 0
    local score = Gear.Score
    local worn = WornLinks(score)
    local now = score.Unit("player")
    Gear.scoreNow = now
    Gear.state = "working"
    Gear.progress = 0
    Gear.List.Refresh()

    local function Check(first, last)
        for i = first, last do
            local link = links[i]
            local info = qm.ItemInfo(link)
            if info and (info.minLevel or 0) <= level then
                local result = qm:Compare(link, info)
                if qm.IsUpgrade(result) and qm:Wearable(info, nil, nil, link) == "yes" then
                    local itemID = qm.ItemId(link)
                    -- Classe, subclasse e tipo de slot: o que as categorias da AH filtram.
                    local _, _, _, equipLoc, _, classID, subClassID = GetItemInfoInstant(link)
                    found[#found + 1] = {
                        equipLoc = equipLoc,
                        classID = classID,
                        subClassID = subClassID,
                        inventoryType = itemID and C_Item.GetItemInventoryTypeByID
                            and C_Item.GetItemInventoryTypeByID(itemID),
                        link = link,
                        name = info.name,
                        icon = info.icon,
                        itemID = itemID,
                        price = Gear.db.candidates[link],
                        -- nil quando o slot está vazio
                        percent = qm.Percent(result),
                        scoreGain = ScoreGain(score, worn, now, link, result.slot, info),
                    }
                end
            end
        end
    end

    local function Step()
        if myToken ~= token then
            return
        end
        local last = math.min(index + CHUNK, #links)
        if not Qolly.Safe("melhorias", Check, index + 1, last) then
            Gear.state = "idle"
            Gear.List.Refresh()
            return
        end
        index = last
        Gear.progress = #links > 0 and index / #links or 1
        if index < #links then
            Gear.List.Refresh()
            C_Timer.After(0, Step)
        else
            Gear.upgrades = found
            Gear.state = "done"
            Qolly.Print(("Gear: %d melhorias na AH para o seu nível."):format(#found))
            Gear.List.Refresh()
        end
    end
    Step()
end

-- Trocou equipamento ou subiu de nível com a lista aberta: o que é melhoria mudou.
local pendingRefresh = false
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function()
    if pendingRefresh or not Gear.List.IsShown() or Gear.state == "working" then
        return
    end
    pendingRefresh = true
    C_Timer.After(0.5, function()
        pendingRefresh = false
        if Gear.NeedsEvaluate() then
            Qolly.Safe("melhorias", Gear.Evaluate)
        end
    end)
end)

Qolly.RegisterModule("gear", {
    help = "list (melhorias na aba Qolly da AH, precisa do QuestMaster) | gs (diagnóstico do Gear Score)",
    command = function(input)
        if strtrim(input):lower() == "gs" then
            Gear.DebugScore()
            return
        end
        if not AH.IsOpen() then
            Qolly.Print("Abra a casa de leilão para ver as melhorias.")
            return
        end
        Qolly.AHTab.Select("upgrades")
    end,
    init = function(moduleDB)
        Gear.db = moduleDB
    end,
})
