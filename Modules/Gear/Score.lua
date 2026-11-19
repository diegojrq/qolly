-- Gear Score do Qolly: um "item level efetivo" médio do equipamento. Cada slot vale o
-- item level mais um ajuste pela qualidade (azul é a referência), com o peso do slot
-- no orçamento de atributos do jogo (cabeça, peito e pernas valem mais que pulso ou
-- anel). A meta do nível é um item azul de nível + 5 em todo slot.
local _, Qolly = ...
local Gear = Qolly.Gear

local Score = {}
Gear.Score = Score

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo

local MAIN, OFF = 16, 17
local TWO_HAND = "INVTYPE_2HWEAPON"
local RARE = 3
local GOAL_AHEAD = 5

-- Peso de cada slot: a fração do orçamento de atributos que um item daquele slot
-- recebe. As armas dividem um slot inteiro: duas mãos ganha o peso das duas.
Score.SLOTS = {
    [1] = 1, [2] = 0.56, [3] = 0.75, [5] = 1, [6] = 0.75, [7] = 1, [8] = 0.75, [9] = 0.56,
    [10] = 0.75, [11] = 0.56, [12] = 0.56, [13] = 0.7, [14] = 0.7, [15] = 0.56, [16] = 0.5,
    [17] = 0.5, [18] = 0.32,
}
-- Ajuste em item levels pela qualidade: cinza, branco, verde, azul, roxo, laranja...
local QUALITY = { [0] = -10, [1] = -6, [2] = -3, [3] = 0, [4] = 6, [5] = 10, [6] = 10, [7] = 0 }
local ORDER = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local TOTAL = 0
for _, slot in ipairs(ORDER) do
    TOTAL = TOTAL + Score.SLOTS[slot]
end

-- Cor pela fração da meta, nas cores de qualidade dos itens: cinza bem abaixo, branco,
-- verde, azul perto da meta, roxo na meta e laranja acima dela.
local RAMP = {
    { 0.00, 0.62, 0.62, 0.62 }, { 0.60, 1.00, 1.00, 1.00 }, { 0.80, 0.12, 1.00, 0.00 },
    { 0.92, 0.00, 0.44, 0.87 }, { 1.00, 0.64, 0.21, 0.93 }, { 1.10, 1.00, 0.50, 0.00 },
}

local function Worth(level, quality)
    return level + (QUALITY[quality] or 0)
end

-- read(slot) -> item level, qualidade, é arma de duas mãos. Duas mãos somam o peso da off-hand.
local function Of(read)
    local sum, twoHand = 0, false
    for _, slot in ipairs(ORDER) do
        if not (slot == OFF and twoHand) then
            local weight = Score.SLOTS[slot]
            local level, quality, two = read(slot)
            if slot == MAIN and two then
                twoHand = true
                weight = weight + Score.SLOTS[OFF]
            end
            if level and quality then
                local worth = Worth(level, quality)
                if worth > 0 then
                    sum = sum + weight * worth
                end
            end
        end
    end
    return sum / TOTAL
end

local function ReadLink(link)
    if not link then
        return nil
    end
    local level = GetDetailedItemLevelInfo(link)
    local _, _, quality = GetItemInfo(link)
    local _, _, _, equipLoc = GetItemInfoInstant(link)
    return level, quality, equipLoc == TWO_HAND
end

-- GS de um conjunto slot -> link.
function Score.Links(links)
    return Of(function(slot)
        return ReadLink(links[slot])
    end)
end

function Score.Unit(unit)
    return Of(function(slot)
        return ReadLink(GetInventoryItemLink(unit, slot))
    end)
end

-- Meta do nível: um item azul (raro) de nível + 5 em todo slot.
function Score.Goal(level)
    return Worth(level + GOAL_AHEAD, RARE)
end

local function ColorCode(share)
    share = math.max(0, math.min(RAMP[#RAMP][1], share))
    local low, high = RAMP[1], RAMP[#RAMP]
    for i = 2, #RAMP do
        if share <= RAMP[i][1] then
            low, high = RAMP[i - 1], RAMP[i]
            break
        end
    end
    local t = high[1] > low[1] and (share - low[1]) / (high[1] - low[1]) or 1
    local function Mix(k)
        return math.floor((low[k] + (high[k] - low[k]) * t) * 255 + 0.5)
    end
    return ("|cff%02x%02x%02x"):format(Mix(2), Mix(3), Mix(4))
end

function Score.Text(score)
    return ("%.1f"):format(score)
end

-- O número na cor de quão perto está da meta do nível.
function Score.Colored(score, level)
    local goal = Score.Goal(level)
    if goal <= 0 then
        return Score.Text(score)
    end
    return ColorCode(score / goal) .. Score.Text(score) .. "|r"
end
