-- Pesca com uma tecla: com o modo pesca ligado, a tecla escolhida lança a linha; com a
-- boia na água, a mesma tecla puxa (interage com a boia, que o jogo marca como alvo
-- de interação). Cada ação ainda é um aperto seu: o jogo não deixa addon pescar sozinho.
-- Enquanto a linha está na água o som da boia fica em destaque (música e ambiente
-- baixam), porque o jogo não avisa addon quando o peixe morde.
local _, Qolly = ...

local Fishing = {}
Qolly.Fishing = Fishing

local db
local fishing = false
local pendingApply = false

-- Pesca muda de id entre versões: vale a que o personagem conhece.
local FISHING_SPELLS = { 131474, 18248, 7732, 7731, 7620 }

-- Com o modo ligado: a boia vira alvo de interação, com o ícone em cima dela.
local INTERACT_CVARS = {
    SoftTargetInteract = "3",
    SoftTargetInteractRange = "15",
    SoftTargetInteractRangeIsHard = "0",
    SoftTargetInteractArc = "2",
    SoftTargetIconGameObject = "1",
}
local LOOT_CVARS = { autoLootDefault = "1" }
-- Com a linha na água: só os efeitos sonoros, no máximo.
local SOUND_CVARS = {
    Sound_EnableAllSound = "1",
    Sound_EnableSFX = "1",
    Sound_SFXVolume = "1",
    Sound_MusicVolume = "0",
    Sound_AmbienceVolume = "0",
    Sound_DialogVolume = "0",
}

local owner = CreateFrame("Frame")

-- CVars temporárias ----------------------------------------------------------------
-- O valor original fica no banco: se o jogo fechar no meio, volta no próximo login.

local function SetTemp(cvars)
    for name, value in pairs(cvars) do
        local current = C_CVar.GetCVar(name)
        if current ~= nil then
            if db.saved[name] == nil then
                db.saved[name] = current
            end
            C_CVar.SetCVar(name, value)
        end
    end
end

local function Restore(cvars)
    for name in pairs(cvars) do
        if db.saved[name] ~= nil then
            C_CVar.SetCVar(name, db.saved[name])
            db.saved[name] = nil
        end
    end
end

-- Teclas -----------------------------------------------------------------------------

local function SpellName()
    for _, spellID in ipairs(FISHING_SPELLS) do
        if IsPlayerSpell(spellID) then
            return C_Spell.GetSpellName(spellID), spellID
        end
    end
end

local function IsFishingSpell(spellID)
    local name = SpellName()
    return name ~= nil and spellID ~= nil and not Qolly.IsSecret(spellID) and C_Spell.GetSpellName(spellID) == name
end

local indicator

-- Nome da tecla como o jogo mostra ("Botão do Mouse 4"), ou o código dela.
local function KeyText()
    local text = db.key and GetBindingText and GetBindingText(db.key)
    if type(text) ~= "string" or text == "" then
        text = db.key
    end
    return text or "?"
end

-- Vara de pesca na mão principal: só então o modo pesca age.
local MAIN_HAND = 16
local WEAPON, FISHING_POLE = 2, 20

local function HasPole()
    local itemID = GetInventoryItemID("player", MAIN_HAND)
    if not itemID then
        return false
    end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return classID == WEAPON and subClassID == FISHING_POLE
end

-- Ativo = modo ligado e vara na mão.
local active = false

local function UpdateIndicator()
    if not indicator then
        return
    end
    if not active then
        indicator:Hide()
        return
    end
    if not db.key then
        indicator.text:SetText("Pesca: escolha a tecla em /qolly config")
    elseif not SpellName() then
        indicator.text:SetText("Pesca: você não tem a profissão")
    elseif InCombatLockdown() then
        indicator.text:SetText("Pesca: pausada em combate")
    elseif fishing then
        indicator.text:SetText(("Boia na água: |cff55dd55[%s]|r quando ela mexer"):format(KeyText()))
    else
        indicator.text:SetText(("Pesca: |cff55dd55[%s]|r lança a linha"):format(KeyText()))
    end
    indicator:SetWidth(indicator.text:GetStringWidth() + 40)
    indicator:Show()
end

-- Atalhos mudam só fora de combate.
local function Apply()
    if InCombatLockdown() then
        pendingApply = true
        UpdateIndicator()
        return
    end
    pendingApply = false
    ClearOverrideBindings(owner)
    local spell = SpellName()
    if active and db.key and spell then
        if fishing then
            SetOverrideBinding(owner, true, db.key, "INTERACTTARGET")
        else
            SetOverrideBindingSpell(owner, true, db.key, spell)
        end
    end
    UpdateIndicator()
end

-- Liga ou desliga de fato conforme o modo e a vara; as CVars acompanham.
local function Sync()
    local want = db.enabled == true and HasPole()
    if want ~= active then
        active = want
        if active then
            SetTemp(INTERACT_CVARS)
            if db.autoLoot ~= false then
                SetTemp(LOOT_CVARS)
            end
        else
            fishing = false
            Restore(SOUND_CVARS)
            Restore(LOOT_CVARS)
            Restore(INTERACT_CVARS)
        end
    end
    Apply()
end

local function CreateIndicator()
    indicator = CreateFrame("Button", "QollyFishingIndicator", UIParent, "BackdropTemplate")
    indicator:SetHeight(32)
    indicator:SetFrameStrata("HIGH")
    Qolly.StyleNotice(indicator)
    local icon = indicator:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", indicator, "LEFT", 6, 0)
    local _, spellID = SpellName()
    icon:SetTexture(C_Spell.GetSpellTexture(spellID or 7620) or 136245)
    indicator.text = indicator:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    indicator.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    indicator:RegisterForClicks("RightButtonUp")
    indicator:SetScript("OnClick", function()
        Fishing.SetEnabled(false)
    end)
    indicator:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(Qolly.TAG .. "modo pesca")
        GameTooltip:AddLine(("%s lança. Com a boia na água, %s de novo puxa: aperte quando ela mexer (o som fica em destaque)."):format(KeyText(), KeyText()), 1, 1, 1, true)
        GameTooltip:AddLine("Só age com a vara de pesca na mão.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Botão direito: desligar o modo pesca", 0, 1, 0)
        GameTooltip:Show()
    end)
    indicator:SetScript("OnLeave", GameTooltip_Hide)
    indicator:Hide()
    -- Na pilha de avisos do alto da tela, com os outros do Qolly.
    Qolly.StackNotice(indicator)
end

-- Modo -------------------------------------------------------------------------------

function Fishing.SetEnabled(on)
    db.enabled = on and true or false
    if db.enabled and not db.key then
        Qolly.Print("Pesca: escolha a tecla em /qolly config (seção Pesca).")
    end
    Qolly.Safe("pesca", Sync)
    local suffix = db.enabled and not HasPole() and " Equipe a vara de pesca para usar." or ""
    Qolly.Print("Modo pesca " .. (db.enabled and "ligado." or "desligado.") .. suffix)
end

function Fishing.IsEnabled()
    return db.enabled == true
end

function Fishing.SetKey(key)
    if key == "" then
        key = nil
    end
    db.key = key
    Qolly.Safe("pesca", Apply)
end

function Fishing.KeyText()
    return db.key and KeyText() or "nenhuma"
end

local function OnChannel(started, spellID)
    if not IsFishingSpell(spellID) then
        return
    end
    fishing = started
    if not active then
        return
    end
    if started and db.sound ~= false then
        SetTemp(SOUND_CVARS)
    elseif not started then
        Restore(SOUND_CVARS)
    end
    Qolly.Safe("pesca", Apply)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if not db then
        return
    end
    if event == "PLAYER_LOGIN" then
        -- Sobra de uma sessão que fechou no meio da pesca: volta tudo e liga de novo
        -- só se estiver com a vara.
        Restore(SOUND_CVARS)
        Restore(LOOT_CVARS)
        Restore(INTERACT_CVARS)
        CreateIndicator()
        Qolly.Safe("pesca", Sync)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        OnChannel(true, spellID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        OnChannel(false, spellID)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Em combate a tecla volta a ser a sua: limpa enquanto ainda pode.
        ClearOverrideBindings(owner)
        UpdateIndicator()
    else
        -- Trocou a arma, fim do combate, ou aprendeu/esqueceu a Pesca.
        Qolly.Safe("pesca", Sync)
    end
end)


Qolly.RegisterModule("pesca", {
    help = "(liga/desliga o modo pesca; a tecla fica em /qolly config)",
    command = function()
        Fishing.SetEnabled(not db.enabled)
    end,
    init = function(moduleDB)
        db = moduleDB
        db.saved = db.saved or {}
    end,
})
