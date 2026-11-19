-- Linha de melhoria no tooltip de equipamento: quanto o item vale a mais (ou a menos)
-- que o equipado no mesmo slot, pelos pesos de atributo do QuestMaster para o seu papel,
-- e quanto o Gear Score muda com a troca.
local _, Qolly = ...
local Gear = Qolly.Gear

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local MAIN, OFF = 16, 17
local GREEN, RED, GRAY, GOLD = "|cff55dd55", "|cffff5050", "|cff999999", "|cffffd100"

-- Quanto o GS muda trocando o item do slot pelo link. Duas mãos tiram a off-hand.
local function ScoreGain(link, slot)
    local score = Gear.Score
    local links = {}
    for wornSlot in pairs(score.SLOTS) do
        links[wornSlot] = GetInventoryItemLink("player", wornSlot)
    end
    local now = score.Links(links)
    links[slot] = link
    local equipLoc = select(4, GetItemInfoInstant(link))
    if equipLoc == "INVTYPE_2HWEAPON" then
        links[OFF] = nil
    elseif slot == OFF and links[MAIN] and select(4, GetItemInfoInstant(links[MAIN])) == "INVTYPE_2HWEAPON" then
        links[MAIN] = nil
    end
    return score.Links(links) - now
end

local function GainText(gain)
    local rounded = math.floor(gain + 0.5)
    if rounded > 0 then
        return ("%sGS +%d|r"):format(GREEN, rounded)
    elseif rounded < 0 then
        return ("%sGS %d|r"):format(RED, rounded)
    end
    return GRAY .. "GS igual|r"
end

-- Texto da esquerda e da direita, ou nil quando o item não é equipamento para você.
local function Lines(link)
    local qm = Gear.QuestMaster()
    if not qm then
        return nil
    end
    local info = qm.ItemInfo(link)
    if not info then
        return nil
    end
    local result = qm:Compare(link, info)
    if not result then
        return nil
    end
    local wearable, level = qm:Wearable(info, nil, nil, link)
    if not wearable then
        return nil
    end
    local percent = qm.Percent(result)
    local text
    if not percent then
        text = GREEN .. "Melhoria: slot vazio|r"
    elseif percent > 0 then
        text = ("%sMelhoria +%d%%|r"):format(GREEN, percent)
    elseif percent < 0 then
        text = ("%sPior %d%%|r"):format(RED, percent)
    else
        text = GRAY .. "Igual ao equipado|r"
    end
    local role = qm.RoleName and qm:RoleName(qm:Role())
    if role then
        text = ("%s %s(%s)|r"):format(text, GRAY, role)
    end
    if wearable == "level" then
        text = ("%sNo nível %d:|r %s"):format(GOLD, level or info.minLevel or 0, text)
    end
    return text, GainText(ScoreGain(link, result.slot))
end

-- O QuestMaster pode ler o item num tooltip de varredura, que passa por este mesmo
-- gancho: sem a trava, um chamaria o outro sem fim.
local busy = false

local function OnItem(tooltip)
    if busy or (Gear.db and Gear.db.tooltip == false) then
        return
    end
    if tooltip:IsForbidden() or not tooltip.GetItem then
        return
    end
    local _, link = tooltip:GetItem()
    if type(link) ~= "string" or Qolly.IsSecret(link) then
        return
    end
    busy = true
    local ok, left, right = pcall(Lines, link)
    busy = false
    if ok and left then
        tooltip:AddDoubleLine(Qolly.TAG .. left, right)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
else
    Qolly.Log("Gear: sem TooltipDataProcessor, sem melhoria no tooltip.")
end
