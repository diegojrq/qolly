-- Ícones dos nós gravados no minimapa, posicionados pela distância em jardas até o
-- jogador. Leva em conta zoom, interior/exterior, minimapa girando e formato redondo
-- ou quadrado.
local _, Qolly = ...
local Gather = Qolly.Gather

local UPDATE = 0.1
local PIN_SIZE = 10
-- Com o rastreamento do jogo ligado, o ícone vai para a esquerda do nó com uma setinha
-- apontando para ele: o ponto exato fica livre para o pontinho amarelo do jogo (que
-- addon não consegue ler), que aparece ali quando o nó existe agora.
local ARROW = "Interface/AddOns/Qolly/Media/Arrow"
local ARROW_SIZE = 8
-- Espaço entre a ponta da seta e o centro do nó, para não cobrir o pontinho.
local GAP = 4
local ARROW_COLORS = { herb = { 0.4, 1, 0.4 }, ore = { 1, 0.8, 0.35 } }

-- Diâmetro do minimapa em jardas em cada nível de zoom (0 a 5).
local OUTDOOR = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { 300, 240, 180, 120, 80, 50 }

local ICONS = {
    herb = "Interface\\Icons\\INV_Misc_Flower_02",
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
}
local PROFESSIONS = { herb = "Herborismo", ore = "Mineração" }

local pins = {}
local used = 0

-- Cor da perícia como nas receitas: vermelho (não coleta), laranja, amarelo, verde,
-- cinza (não sobe mais). Níveis = { laranja, amarelo, verde, cinza }.
local function SkillColor(skill, levels)
    if not skill or skill < levels[1] then
        return "|cffff2020"
    elseif not levels[2] then
        return "|cffffffff"
    elseif skill < levels[2] then
        return "|cffff8040"
    elseif skill < levels[3] then
        return "|cffffff00"
    elseif skill < levels[4] then
        return "|cff40bf40"
    end
    return "|cff808080"
end

local function ItemLine(itemID, nodeName)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        name = "item " .. itemID
    end
    local icon = C_Item.GetItemIconByID(itemID)
    local label = icon and ("|T%s:14|t %s"):format(icon, name) or name
    -- Chance pelo seu saque, com a amostra: poucas coletas dão número pouco confiável.
    local times, gathers = Gather.DropRate(nodeName, itemID)
    if times then
        label = ("%s |cff999999%d%% (%d/%d)|r"):format(label, math.floor(times / gathers * 100 + 0.5), times, gathers)
    end
    local prices = Qolly.Craft and Qolly.Craft.Prices
    local unit, seen = prices and prices.Get(itemID)
    if unit then
        return label, Qolly.Money(unit) .. (seen and ("|cff999999 (%s)|r"):format(Qolly.Ago(time() - seen)) or "")
    end
    return label, "|cff999999sem preço|r"
end

-- Tooltip de um nó, usado no minimapa e no mapa-múndi.
function Gather.ShowNodeTooltip(owner, node)
    local name, levels, main, extras = Gather.Info(node)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Qolly.TAG .. (name or PROFESSIONS[node.kind]))
    local skill = Gather.Skill(node.kind)
    if levels then
        local mine = skill and ("você tem %d"):format(skill) or "você não tem a profissão"
        GameTooltip:AddDoubleLine(("%sRequer %s %d|r"):format(SkillColor(skill, levels), PROFESSIONS[node.kind], levels[1]),
            mine, 1, 1, 1, 0.7, 0.7, 0.7)
    end
    if main then
        GameTooltip:AddDoubleLine(ItemLine(main, name))
    else
        GameTooltip:AddLine("Item desconhecido: colete uma vez e o Qolly aprende.", 0.7, 0.7, 0.7, true)
    end
    if #extras > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Loot adicional", 1, 0.82, 0)
        for _, itemID in ipairs(extras) do
            GameTooltip:AddDoubleLine(ItemLine(itemID, name))
        end
    end
    if node.count then
        GameTooltip:AddLine(("Coletado por você %dx"):format(node.count), 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function ShowTooltip(pin)
    if pin.node then
        Gather.ShowNodeTooltip(pin, pin.node)
    end
end

-- Ícone do item que o nó dá; sem item conhecido, o genérico do tipo.
function Gather.NodeIcon(node)
    local itemID = node.info and node.info.item
    return itemID and itemID ~= 0 and C_Item.GetItemIconByID(itemID) or ICONS[node.kind]
end

local function Pin(index)
    local pin = pins[index]
    if not pin then
        pin = CreateFrame("Frame", nil, Minimap)
        pin:SetSize(PIN_SIZE, PIN_SIZE)
        pin:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints()
        -- Ícone recortado em círculo.
        pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pin.mask = pin:CreateMaskTexture()
        pin.mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        pin.mask:SetAllPoints(pin.icon)
        pin.icon:AddMaskTexture(pin.mask)
        pin.arrow = pin:CreateTexture(nil, "OVERLAY")
        pin.arrow:SetTexture(ARROW)
        pin.arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
        pin.arrow:SetPoint("RIGHT", pin, "RIGHT", 0, 0)
        pin.arrow:Hide()
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", ShowTooltip)
        pin:SetScript("OnLeave", GameTooltip_Hide)
        pins[index] = pin
    end
    return pin
end

local function Clear(from)
    for index = from, used do
        pins[index].node = nil
        pins[index]:Hide()
    end
    used = from - 1
end

local function Facing()
    if GetCVar("rotateMinimap") ~= "1" then
        return 0
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing == nil or Qolly.IsSecret(facing) then
        return nil
    end
    return facing
end

local function Update()
    if not Gather.db.enabled then
        Clear(1)
        return
    end
    local continent, north, west = Gather.PlayerPosition()
    local lists = continent and Gather.Lists(continent)
    local facing = Facing()
    if not lists or not facing then
        Clear(1)
        return
    end

    local zoom = (Minimap:GetZoom() or 0) + 1
    local diameter = (IsIndoors and IsIndoors() and INDOOR or OUTDOOR)[zoom] or OUTDOOR[1]
    local radius = diameter / 2
    local scale = Minimap:GetWidth() / diameter -- pixels por jarda
    local round = not GetMinimapShape or GetMinimapShape() == "ROUND"
    -- Ícone inteiro dentro da borda.
    local limit = radius - (PIN_SIZE / 2) / scale
    local cos, sin = math.cos(facing), math.sin(facing)

    local count = 0
    for _, nodes in ipairs(lists) do
        for _, node in ipairs(nodes) do
            local east, up = west - node.west, node.north - north
            if math.abs(east) <= radius and math.abs(up) <= radius and Gather.Shown(node.kind) then
                -- Minimapa girando: o lado para onde o personagem olha fica para cima.
                local x = east * cos + up * sin
                local y = -east * sin + up * cos
                local inside
                if round then
                    inside = x * x + y * y <= limit * limit
                else
                    inside = math.abs(x) <= limit and math.abs(y) <= limit
                end
                if inside then
                    count = count + 1
                    local pin = Pin(count)
                    pin.node = node
                    local pointed = Gather.db.rings ~= false and Gather.TrackingOn and Gather.TrackingOn(node.kind) and true or false
                    if pin.pointed ~= pointed then
                        pin.pointed = pointed
                        pin.icon:ClearAllPoints()
                        if pointed then
                            pin:SetSize(PIN_SIZE + ARROW_SIZE, PIN_SIZE)
                            pin.icon:SetSize(PIN_SIZE, PIN_SIZE)
                            pin.icon:SetPoint("LEFT", pin, "LEFT", 0, 0)
                            pin.arrow:Show()
                        else
                            pin:SetSize(PIN_SIZE, PIN_SIZE)
                            pin.icon:SetAllPoints()
                            pin.arrow:Hide()
                        end
                    end
                    if pointed then
                        pin.arrow:SetVertexColor(unpack(ARROW_COLORS[node.kind]))
                    end
                    pin.icon:SetTexture(Gather.NodeIcon(node))
                    pin:ClearAllPoints()
                    if pointed then
                        pin:SetPoint("RIGHT", Minimap, "CENTER", x * scale - GAP, y * scale)
                    else
                        pin:SetPoint("CENTER", Minimap, "CENTER", x * scale, y * scale)
                    end
                    pin:Show()
                end
            end
        end
    end
    Clear(count + 1)
end

local elapsed = 0
local driver = CreateFrame("Frame", nil, Minimap)
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < UPDATE then
        return
    end
    elapsed = 0
    if not Qolly.Safe("coleta no minimapa", Update) then
        -- Erro a cada 0,1s inundaria o chat: para até o próximo /reload.
        driver:SetScript("OnUpdate", nil)
    end
end)
