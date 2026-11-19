-- Gear Score na janela de personagem padrão, à direita dos slots de arma.
local _, Qolly = ...
local Gear = Qolly.Gear

local GOLD = "|cffffd100"

local badge

-- O slot de arma mais à direita que está visível neste client.
local function LastWeaponSlot()
    for _, slot in ipairs({ CharacterRangedSlot, CharacterSecondaryHandSlot, CharacterMainHandSlot }) do
        if slot and slot:IsShown() then
            return slot
        end
    end
    return CharacterMainHandSlot
end

-- O modelo 3D fica num frame level alto e cobriria o badge; a skin do Ellesmere usa o
-- mesmo truque para o texto dela. Refeito a cada abertura: a cena pode mudar de nível.
local function Place()
    local anchor = LastWeaponSlot()
    if anchor then
        -- Centralizado no vão entre o último slot de arma e a coluna da direita, sem
        -- invadir os slots de lá.
        local width = 80
        local column = CharacterHandsSlot
        local right, left = anchor:GetRight(), column and column:GetLeft()
        if right and left and left - right > 40 then
            width = left - right - 8
        end
        badge:SetWidth(width)
        badge:ClearAllPoints()
        badge:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    end
    local scene = CharacterModelScene or CharacterModelFrame
    local level = scene and scene:GetFrameLevel() or PaperDollFrame:GetFrameLevel()
    badge:SetFrameLevel(level + 20)
end

local function Paint()
    Place()
    local score = Gear.Score
    badge.value:SetText(score.Colored(score.Unit("player"), UnitLevel("player")))
end

local function ShowTooltip(self)
    local score = Gear.Score
    local level = UnitLevel("player")
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Qolly.TAG .. "Gear Score")
    GameTooltip:AddDoubleLine("Agora", score.Colored(score.Unit("player"), level))
    GameTooltip:AddDoubleLine(("Meta do nível %d"):format(level), score.Text(score.Goal(level)), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine("Item level de cada slot ajustado pela qualidade, com o peso do slot.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function Create()
    local anchor = LastWeaponSlot()
    if not (PaperDollFrame and anchor) then
        Qolly.Log("Gear: slots de arma não encontrados, sem Gear Score na janela de personagem.")
        return
    end
    badge = CreateFrame("Frame", nil, PaperDollFrame)
    badge:SetSize(90, 36)

    badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.label:SetPoint("TOP", badge, "TOP", 0, 0)
    badge.label:SetText(GOLD .. "Gear Score|r")

    badge.value = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    badge.value:SetPoint("TOP", badge.label, "BOTTOM", 0, -2)

    badge:EnableMouse(true)
    badge:SetScript("OnEnter", ShowTooltip)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    badge:SetScript("OnShow", function()
        Qolly.Safe("gear score", Paint)
    end)
    badge:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    badge:SetScript("OnEvent", function(self)
        if self:IsVisible() then
            Qolly.Safe("gear score", Paint)
        end
    end)
end

-- /qolly gear gs: o GS calculado e onde o badge está, para quando ele não aparece.
function Gear.DebugScore()
    local score = Gear.Score
    Qolly.Print(("GS agora: %s (meta do nível: %s)"):format(
        score.Text(score.Unit("player")), score.Text(score.Goal(UnitLevel("player")))))
    if not badge then
        Qolly.Print("Badge não foi criado (slots de arma ou PaperDollFrame não encontrados).")
        return
    end
    local anchor = LastWeaponSlot()
    local scene = CharacterModelScene or CharacterModelFrame
    local left, bottom, width, height = badge:GetRect()
    Qolly.Print(("Badge: visível=%s, nível=%d, nível do modelo=%s, âncora=%s, posição=%s,%s %sx%s"):format(
        tostring(badge:IsVisible()), badge:GetFrameLevel(), tostring(scene and scene:GetFrameLevel()),
        tostring(anchor and anchor:GetName()), tostring(left), tostring(bottom), tostring(width), tostring(height)))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    Qolly.Safe("gear score", Create)
end)
