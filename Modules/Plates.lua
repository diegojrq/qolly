-- Placas: complementos para a placa de nome padrão dos mobs que você pode atacar.
--   vida      número e porcentagem dentro da barra
--   ameaça    cor da barra pela sua ameaça (o jogo devolve a cor normal quando acaba)
--   cast      tempo restante, alvo do cast e moldura amarela quando dá para interromper
--   ameaça %  sua porcentagem de ameaça, à direita da barra
--   debuffs   os debuffs da placa padrão maiores e com o tempo restante
--   substituir esconde os textos que o jogo põe na barra de vida
-- Em combate o client esconde vários números (valores secretos). Eles só passam por
-- funções do próprio jogo (string.format, SetText, cooldowns), nunca por conta em Lua;
-- quando nada funciona, o texto some em vez de dar erro.
local _, Qolly = ...

local Plates = {}
Qolly.Plates = Plates

local db

local TICK = 0.1
-- A ameaça é relida a cada tantos ticks; os eventos cobrem o resto.
local THREAT_EVERY = 5
local GLOW = { 1, 0.85, 0.1 }

-- UnitThreatSituation: 3 tanqueando firme, 2 tanqueando mas perdendo, 1 outro tanqueia
-- e você está quase puxando, 0 outro tanqueia.
local THREAT_COLORS = {
    tank = { [3] = { 0.2, 0.8, 0.2 }, [2] = { 1, 0.55, 0 }, [1] = { 1, 0.15, 0.15 }, [0] = { 1, 0.15, 0.15 } },
    other = { [3] = { 1, 0.15, 0.15 }, [2] = { 1, 0.55, 0 }, [1] = { 1, 0.9, 0.1 } },
}

local DEFAULTS = {
    health = true, healthAmount = true, threat = true, threatPercent = true, override = true,
    cast = true, debuffs = true,
    -- Ajustáveis na configuração.
    textSize = 12, castTextSize = 11, debuffScale = 1, debuffFont = 9,
}

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function On(key)
    return db and db[key] ~= false
end

-- Um erro aqui se repetiria a cada décimo de segundo: avisa uma vez só por parte.
local warned = {}
local function Guard(label, fn, ...)
    local ok, failure = pcall(fn, ...)
    if not ok and not warned[label] then
        warned[label] = true
        Qolly.Print("ERRO nas placas (" .. label .. "): " .. tostring(failure))
    end
end

local function HealthBar(frame)
    return frame.healthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
end

local function CastBar(frame)
    return frame.castBar or frame.CastBar
end

local function IsTank()
    local role = UnitGroupRolesAssigned and Plain(UnitGroupRolesAssigned("player"))
    if role and role ~= "NONE" then
        return role == "TANK"
    end
    if GetSpecialization and GetSpecializationRole then
        local spec = GetSpecialization()
        return spec and GetSpecializationRole(spec) == "TANK" or false
    end
    return false
end

-- Placa -> estado nosso (as placas são reaproveitadas entre unidades).
local states = {}
-- Unidade da placa -> placa, só das que estamos cuidando.
local units = {}

-- Vida -----------------------------------------------------------------------------

local function HealthText(unit)
    if UnitHealthPercent and CurveConstants then
        local ok, text = pcall(function()
            local percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
            if db.healthAmount then
                return format("%s (%d%%)", AbbreviateNumbers(UnitHealth(unit)), percent)
            end
            return format("%d%%", percent)
        end)
        if ok then
            return text
        end
    end
    local health, max = Plain(UnitHealth(unit)), Plain(UnitHealthMax(unit))
    if not health or not max or max <= 0 then
        return nil
    end
    local percent = math.floor(health / max * 100 + 0.5)
    if db.healthAmount then
        return format("%s (%d%%)", AbbreviateNumbers(health), percent)
    end
    return format("%d%%", percent)
end

local function UpdateHealth(state, unit)
    if not On("health") then
        state.health:Hide()
        return
    end
    local text = HealthText(unit)
    state.health:SetText(text or "")
    state.health:Show()
end

-- Ameaça ---------------------------------------------------------------------------

local function Paint(state, color)
    local bar = state.bar
    if not bar or not color then
        return
    end
    state.painting = true
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    state.painting = false
end

-- O jogo só repinta a barra quando a cor dele muda; a nossa cor por cima não conta.
-- Então a cor do jogo fica guardada e volta quando a nossa sai.
local function HookBar(state, bar)
    if state.hooked == bar then
        return
    end
    state.hooked = bar
    local r, g, b, a = bar:GetStatusBarColor()
    state.gameColor = { r, g, b, a }
    hooksecurefunc(bar, "SetStatusBarColor", function(_, r2, g2, b2, a2)
        if state.painting then
            return
        end
        state.gameColor = { r2, g2, b2, a2 }
        if state.color then
            Paint(state, state.color)
        end
    end)
end

local function SetThreatColor(state, color)
    if color == state.color then
        return
    end
    state.color = color
    Paint(state, color or state.gameColor)
end

-- Sua ameaça no mob em %, à direita da barra. Só em combate e se você está na lista.
local function UpdateThreatText(state, unit)
    local text = state.threat
    if not On("threatPercent") or not UnitDetailedThreatSituation or not Plain(UnitAffectingCombat(unit)) then
        text:Hide()
        return
    end
    local _, _, percent = UnitDetailedThreatSituation("player", unit)
    if not Qolly.IsSecret(percent) and percent == nil then
        text:Hide()
        return
    end
    text:SetFormattedText("%d%%", percent)
    text:Show()
end

local function UpdateThreat(state, unit)
    UpdateThreatText(state, unit)
    local color
    if On("threat") and Plain(UnitAffectingCombat(unit)) then
        local status = Plain(UnitThreatSituation("player", unit))
        if status then
            color = THREAT_COLORS[IsTank() and "tank" or "other"][status]
        end
    end
    SetThreatColor(state, color)
end

-- Cast -----------------------------------------------------------------------------

local function CastInfo(unit)
    local name, _, _, _, endMs, _, _, notInterruptible = UnitCastingInfo(unit)
    if Qolly.IsSecret(name) or name ~= nil then
        return true, false, endMs, notInterruptible
    end
    local _
    name, _, _, _, endMs, _, notInterruptible = UnitChannelInfo(unit)
    if Qolly.IsSecret(name) or name ~= nil then
        return true, true, endMs, notInterruptible
    end
    return false
end

local function Remaining(unit, channel, endMs)
    local Duration = channel and UnitChannelDuration or UnitCastingDuration
    if Duration then
        local ok, duration = pcall(Duration, unit)
        if ok and duration then
            return duration:GetRemainingDuration()
        end
    end
    endMs = Plain(endMs)
    if endMs then
        return math.max(0, endMs / 1000 - GetTime())
    end
end

-- Moldura acesa quando o cast pode ser interrompido (o valor pode vir secreto).
local function ShowInterruptible(glow, notInterruptible)
    if Qolly.IsSecret(notInterruptible) then
        if glow.SetAlphaFromBoolean then
            glow:SetAlphaFromBoolean(notInterruptible, 0, 1)
        else
            glow:SetAlpha(0)
        end
    else
        glow:SetAlpha(notInterruptible and 0 or 1)
    end
end

local function HideCast(state)
    state.timer:Hide()
    state.target:Hide()
    state.glow:Hide()
end

local function UpdateCast(state, unit)
    local castBar = state.castBar
    if not On("cast") or not castBar or not castBar:IsShown() then
        HideCast(state)
        return
    end
    local casting, channel, endMs, notInterruptible = CastInfo(unit)
    if not casting then
        HideCast(state)
        return
    end
    local remaining = Remaining(unit, channel, endMs)
    if remaining then
        state.timer:SetFormattedText("%.1f", remaining)
        state.timer:Show()
    else
        state.timer:Hide()
    end

    local target = unit .. "target"
    if Plain(UnitExists(target)) then
        state.target:SetText(UnitName(target))
        if Plain(UnitIsUnit(target, "player")) then
            state.target:SetTextColor(1, 0.3, 0.3)
        else
            state.target:SetTextColor(1, 1, 1)
        end
        state.target:Show()
    else
        state.target:Hide()
    end

    ShowInterruptible(state.glow, notInterruptible)
    state.glow:Show()
end

-- Debuffs --------------------------------------------------------------------------
-- Em combate os debuffs são secretos e um addon não pode lê-los. A lista da placa
-- padrão (que é do jogo e pode) fica maior e com o tempo restante nos ícones.

local function GameAuras(frame)
    local auras = frame.AurasFrame
    return auras and auras.DebuffListFrame or frame.BuffFrame
end

local function ShowCountdowns(list)
    for _, icon in ipairs({ list:GetChildren() }) do
        local cooldown = icon.Cooldown or icon.cooldown
        if cooldown and cooldown.SetHideCountdownNumbers and cooldown.qollyFont ~= db.debuffFont then
            cooldown.qollyFont = db.debuffFont
            cooldown:SetHideCountdownNumbers(false)
            pcall(function()
                cooldown:GetCountdownFontString():SetFont(STANDARD_TEXT_FONT, db.debuffFont, "OUTLINE")
            end)
        end
    end
end

local function UpdateAuras(state)
    local list = state.frame and GameAuras(state.frame)
    if not list then
        return
    end
    if On("debuffs") then
        list:SetScale(db.debuffScale)
        -- O jogo monta os ícones no mesmo evento: confere logo depois dele.
        C_Timer.After(0, function()
            Guard("debuffs", ShowCountdowns, list)
        end)
    else
        list:SetScale(1)
    end
end

local function RestoreAuras(state)
    local list = state.frame and GameAuras(state.frame)
    if list then
        list:SetScale(1)
    end
end

-- Textos da placa padrão -----------------------------------------------------------
-- Com "substituir" ligado, os textos que o jogo põe na barra de vida somem e ficam só
-- os nossos. O nome do mob continua.

local function CollectTexts(frame, found, depth, skip)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region ~= skip then
            found[#found + 1] = region
        end
    end
    if depth > 0 then
        for _, child in ipairs({ frame:GetChildren() }) do
            CollectTexts(child, found, depth - 1, skip)
        end
    end
end

local function HideGameTexts(state)
    local frame = state.frame
    local root = frame.HealthBarsContainer or state.bar
    local found = {}
    CollectTexts(root, found, 2, frame.name)
    state.gameTexts = found
    for _, text in ipairs(found) do
        text:SetAlpha(0)
    end
end

local function ShowGameTexts(state)
    for _, text in ipairs(state.gameTexts or {}) do
        text:SetAlpha(1)
    end
    state.gameTexts = nil
end

-- Placa ----------------------------------------------------------------------------

local function Border(parent)
    local glow = CreateFrame("Frame", nil, parent)
    local function Edge(a, b, horizontal)
        local edge = glow:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(GLOW[1], GLOW[2], GLOW[3], 1)
        edge:SetPoint(a)
        edge:SetPoint(b)
        if horizontal then
            edge:SetHeight(2)
        else
            edge:SetWidth(2)
        end
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    return glow
end

local function State(plate)
    local state = states[plate]
    if state then
        return state
    end
    state = {}
    local overlay = CreateFrame("Frame", nil, plate)
    overlay:SetAllPoints(plate)
    state.overlay = overlay

    state.health = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.health:SetJustifyH("LEFT")
    state.threat = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.threat:SetJustifyH("RIGHT")

    state.timer = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.target = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    state.glow = Border(overlay)

    states[plate] = state
    return state
end

-- As peças da placa padrão podem mudar de lugar entre unidades: reancora a cada uso.
local function Anchor(state)
    local frame, bar, castBar = state.frame, state.bar, state.castBar
    state.overlay:SetFrameStrata(frame:GetFrameStrata())
    state.overlay:SetFrameLevel(frame:GetFrameLevel() + 20)
    state.health:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
    state.threat:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
    state.timer:SetFont(STANDARD_TEXT_FONT, db.castTextSize, "OUTLINE")
    state.target:SetFont(STANDARD_TEXT_FONT, db.castTextSize, "OUTLINE")

    state.health:ClearAllPoints()
    state.health:SetPoint("LEFT", bar, "LEFT", 4, 0)
    state.threat:ClearAllPoints()
    state.threat:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

    if castBar then
        state.timer:ClearAllPoints()
        state.timer:SetPoint("RIGHT", castBar, "RIGHT", -2, 0)
        state.target:ClearAllPoints()
        state.target:SetPoint("TOP", castBar, "BOTTOM", 0, -1)
        state.glow:ClearAllPoints()
        state.glow:SetPoint("TOPLEFT", castBar, "TOPLEFT", -2, 2)
        state.glow:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 2, -2)
    end
end

local function Detach(unit)
    local plate = units[unit]
    units[unit] = nil
    local state = plate and states[plate]
    if not state then
        return
    end
    SetThreatColor(state, nil)
    RestoreAuras(state)
    ShowGameTexts(state)
    state.overlay:Hide()
end

local function Attach(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        return
    end
    local frame = plate.UnitFrame
    local bar = frame and HealthBar(frame)
    if not bar or Plain(UnitCanAttack("player", unit)) ~= true then
        return
    end
    local state = State(plate)
    state.frame, state.bar, state.castBar, state.unit = frame, bar, CastBar(frame), unit
    HookBar(state, bar)
    Anchor(state)
    units[unit] = plate
    state.overlay:Show()
    if On("override") then
        HideGameTexts(state)
    end
    UpdateHealth(state, unit)
    UpdateThreat(state, unit)
    UpdateCast(state, unit)
    UpdateAuras(state, unit)
end

local function With(unit, label, Update)
    local plate = units[unit]
    if plate then
        Guard(label, Update, states[plate], unit)
    end
end

function Plates.RefreshAll()
    for unit in pairs(units) do
        Detach(unit)
    end
    if not db then
        return
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            Guard("placa", Attach, unit)
        end
    end
end

function Plates.Get(key)
    return On(key)
end

local previews = {}

local function RefreshPreviews()
    for _, preview in ipairs(previews) do
        if preview:IsVisible() then
            preview:Refresh()
        end
    end
end

function Plates.Set(key, on)
    db[key] = on and true or false
    Plates.RefreshAll()
    RefreshPreviews()
end

function Plates.GetValue(key)
    return db[key] or DEFAULTS[key]
end

function Plates.SetValue(key, value)
    db[key] = value
    Plates.RefreshAll()
    RefreshPreviews()
end

-- Prévia ---------------------------------------------------------------------------
-- Uma placa de mentira na configuração, com as opções atuais: mob a 42% de vida,
-- lançando em você um cast que dá para interromper, com três debuffs seus.

local PREVIEW_ICON = 20
local PREVIEW_DEBUFFS = {
    { "Interface/Icons/Spell_Shadow_AbominationExplosion", "12" },
    { "Interface/Icons/Spell_Shadow_CurseOfSargeras", "9" },
    { "Interface/Icons/Spell_Shadow_UnholyStrength", "4" },
}

local function PreviewBar(parent, width, height, r, g, b, value)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(value)
    bar:SetStatusBarColor(r, g, b)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetPoint("TOPLEFT", -1, 1)
    back:SetPoint("BOTTOMRIGHT", 1, -1)
    back:SetColorTexture(0, 0, 0, 0.85)
    return bar
end

function Plates.Preview(parent)
    local preview = CreateFrame("Frame", nil, parent)
    preview:SetSize(420, 130)
    local back = preview:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0.12, 0.14, 0.1, 0.9)
    local caption = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("TOPLEFT", 6, -4)
    caption:SetText("Prévia")

    local bar = PreviewBar(preview, 220, 16, 0.85, 0.1, 0.1, 42)
    bar:SetPoint("CENTER", preview, "CENTER", 0, 4)
    local name = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("BOTTOM", bar, "TOP", 0, 3)
    name:SetText("Caçador de Cabeças")

    -- Os debuffs crescem a partir de baixo, como na placa de verdade.
    local auras = CreateFrame("Frame", nil, preview)
    auras:SetSize(#PREVIEW_DEBUFFS * (PREVIEW_ICON + 2), PREVIEW_ICON)
    local counts = {}
    for index, debuff in ipairs(PREVIEW_DEBUFFS) do
        local icon = auras:CreateTexture(nil, "ARTWORK")
        icon:SetSize(PREVIEW_ICON, PREVIEW_ICON)
        icon:SetPoint("LEFT", auras, "LEFT", (index - 1) * (PREVIEW_ICON + 2), 0)
        icon:SetTexture(debuff[1])
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local count = auras:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        count:SetPoint("CENTER", icon, "CENTER", 0, 0)
        count:SetText(debuff[2])
        counts[index] = count
    end

    local overlay = CreateFrame("Frame", nil, preview)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(bar:GetFrameLevel() + 5)
    local gameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gameText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    gameText:SetText("741 42%")
    local health = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    health:SetPoint("LEFT", bar, "LEFT", 4, 0)
    local threat = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    threat:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    threat:SetText("49%")

    local castBar = PreviewBar(preview, 220, 10, 1, 0.7, 0, 60)
    castBar:SetPoint("TOP", bar, "BOTTOM", 0, -6)
    local spell = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spell:SetPoint("CENTER")
    spell:SetText("Bola de Fogo")
    local castOverlay = CreateFrame("Frame", nil, preview)
    castOverlay:SetAllPoints()
    castOverlay:SetFrameLevel(castBar:GetFrameLevel() + 5)
    local timer = castOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timer:SetPoint("RIGHT", castBar, "RIGHT", -2, 0)
    timer:SetText("1.3")
    local target = castOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    target:SetPoint("TOP", castBar, "BOTTOM", 0, -1)
    target:SetText(UnitName("player"))
    target:SetTextColor(1, 0.3, 0.3)
    local glow = Border(castOverlay)
    glow:SetPoint("TOPLEFT", castBar, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 2, -2)

    function preview:Refresh()
        health:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
        threat:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
        timer:SetFont(STANDARD_TEXT_FONT, db.castTextSize, "OUTLINE")
        target:SetFont(STANDARD_TEXT_FONT, db.castTextSize, "OUTLINE")
        health:SetText(db.healthAmount and "741 (42%)" or "42%")
        health:SetShown(On("health"))
        gameText:SetShown(not On("override"))
        threat:SetShown(On("threatPercent"))
        -- Exemplo de ameaça: você está quase puxando (amarelo).
        local color = On("threat") and THREAT_COLORS.other[1] or { 0.85, 0.1, 0.1 }
        bar:SetStatusBarColor(color[1], color[2], color[3])
        timer:SetShown(On("cast"))
        target:SetShown(On("cast"))
        glow:SetShown(On("cast"))
        local scale = On("debuffs") and db.debuffScale or 1
        auras:SetScale(scale)
        auras:ClearAllPoints()
        auras:SetPoint("BOTTOM", name, "TOP", 0, 3 / scale)
        for _, count in ipairs(counts) do
            count:SetFont(STANDARD_TEXT_FONT, db.debuffFont, "OUTLINE")
            count:SetShown(On("debuffs"))
        end
    end

    previews[#previews + 1] = preview
    preview:Refresh()
    return preview
end

local ticks = 0
local clock = CreateFrame("Frame")
local elapsed = 0
clock:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then
        return
    end
    elapsed = 0
    ticks = ticks + 1
    local threat = ticks % THREAT_EVERY == 0
    for unit in pairs(units) do
        With(unit, "cast", UpdateCast)
        if threat then
            With(unit, "ameaça", UpdateThreat)
        end
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("UNIT_MAXHEALTH")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
events:RegisterEvent("UNIT_FACTION")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if not db then
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        Guard("placa", Attach, unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        Guard("placa", Detach, unit)
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        With(unit, "vida", UpdateHealth)
    elseif event == "UNIT_AURA" then
        With(unit, "debuffs", UpdateAuras)
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        With(unit, "ameaça", UpdateThreat)
    elseif event == "UNIT_FACTION" then
        if unit and unit:find("^nameplate") then
            Guard("placa", Detach, unit)
            Guard("placa", Attach, unit)
        end
    else
        for each in pairs(units) do
            With(each, "ameaça", UpdateThreat)
        end
    end
end)

Qolly.RegisterModule("placas", {
    help = "(liga/desliga os complementos das placas: vida, ameaça, cast e debuffs)",
    command = function()
        local on = not (On("health") or On("threat") or On("cast") or On("debuffs"))
        for key in pairs(DEFAULTS) do
            if key ~= "healthAmount" and key ~= "override" then
                db[key] = on
            end
        end
        Plates.RefreshAll()
        Qolly.Print("Complementos das placas " .. (on and "ligados." or "desligados."))
    end,
    init = function(moduleDB)
        db = moduleDB
        for key, value in pairs(DEFAULTS) do
            if db[key] == nil then
                db[key] = value
            end
        end
    end,
})
