-- Radar: avisa quando um jogador da facção inimiga aparece por perto.
-- Três fontes: a placa de nome (precisa das placas de inimigos ligadas, tecla V), o log
-- de combate (quem lança magia ou luta no alcance do log) e alvo/mouseover.
local _, Qolly = ...

local Radar = {}
Qolly.Radar = Radar

-- Mesmo jogador só avisa de novo depois disso, para não repetir a cada placa recriada.
local REPEAT = 120
-- Nome secreto não serve de chave: esses avisos só respeitam um intervalo geral.
local ANONYMOUS_REPEAT = 15

local lastSeen = {}
local lastAnonymous = 0

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

-- Em battleground e arena todo mundo é inimigo: aviso ali só atrapalha.
local function Quiet()
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

local function IsEnemyPlayer(unit)
    if not Plain(UnitIsPlayer(unit)) then
        return false
    end
    local mine, theirs = Plain(UnitFactionGroup("player")), Plain(UnitFactionGroup(unit))
    if mine and theirs then
        return theirs ~= mine and theirs ~= "Neutral"
    end
    return Plain(UnitIsEnemy("player", unit)) == true
end

local function Describe(unit, name)
    local _, classFile = UnitClass(unit)
    classFile = Plain(classFile)
    local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    local shown = color and color:WrapTextInColorCode(name) or name

    local level = Plain(UnitLevel(unit))
    local levelText = (level and level > 0) and tostring(level) or "??"
    local className = Plain((UnitClass(unit))) or ""
    local race = Plain((UnitRace(unit))) or ""
    local text = ("%s (%s %s %s)"):format(shown, levelText, race, className):gsub("%s+%)", ")")
    if Plain(UnitIsPVP(unit)) then
        text = text .. " |cffff5555PvP|r"
    end
    return text
end

local function Alert(text)
    Qolly.Print("|cffff3333Inimigo por perto:|r " .. text)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, "Inimigo: " .. text, ChatTypeInfo["RAID_WARNING"])
    end
    if Radar.db.sound ~= false then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- Marca própria em cima da placa de nome do inimigo, visível só para você. A marca de
-- raide de verdade (SetRaidTarget) é bloqueada para addons neste client: o jogo pede
-- para desativar o addon. Ordem: caveira, X, quadrado, lua, triângulo, diamante,
-- círculo, estrela; o nono inimigo volta para a caveira.
local MARKS = { 8, 7, 6, 5, 4, 3, 2, 1 }
local MARK_TEXTURE = "Interface/TargetingFrame/UI-RaidTargetingIcon_%d"
local markOf = {} -- nome -> marca
local nextMark = 1
local icons = {} -- placa -> textura

local function MarkFor(name)
    local mark = markOf[name]
    if not mark then
        mark = MARKS[nextMark]
        nextMark = nextMark % #MARKS + 1
        markOf[name] = mark
    end
    return mark
end

local function Mark(unit, name)
    if Radar.db.mark == false or not C_NamePlate then
        return
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        return
    end
    local icon = icons[plate]
    if not icon then
        icon = plate:CreateTexture(nil, "OVERLAY")
        icon:SetSize(28, 28)
        icon:SetPoint("BOTTOM", plate, "TOP", 0, 4)
        icons[plate] = icon
    end
    icon:SetTexture(MARK_TEXTURE:format(MarkFor(name)))
    icon:Show()
end

-- A placa é reaproveitada para outra unidade: a marca não pode ir junto.
local function Unmark(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and icons[plate] then
        icons[plate]:Hide()
    end
end

local function Check(unit)
    if not Radar.db.enabled or Quiet() or not IsEnemyPlayer(unit) then
        return
    end
    local now = GetTime()
    local name = Plain(GetUnitName(unit, true))
    if name then
        Mark(unit, name)
    end
    if not name then
        if now - lastAnonymous >= ANONYMOUS_REPEAT then
            lastAnonymous = now
            Alert("jogador da facção inimiga")
        end
        return
    end
    if lastSeen[name] and now - lastSeen[name] < REPEAT then
        lastSeen[name] = now
        return
    end
    lastSeen[name] = now
    Alert(Describe(unit, name))
end

-- Log de combate: pega quem lança magia, apanha ou bate em algo dentro do alcance do
-- log, sem placa nem clique. Não tem nível, só classe e raça pelo GUID.
local band = bit.band
local PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40

local function HostilePlayer(flags)
    return flags and not Qolly.IsSecret(flags)
        and band(flags, PLAYER) ~= 0 and band(flags, HOSTILE) ~= 0
end

local function CheckLog(guid, name)
    name = Plain(name)
    guid = Plain(guid)
    if not name or not Radar.db.enabled or Quiet() then
        return
    end
    local now = GetTime()
    if lastSeen[name] and now - lastSeen[name] < REPEAT then
        lastSeen[name] = now
        return
    end
    lastSeen[name] = now
    local text = name
    if guid and GetPlayerInfoByGUID then
        local className, classFile, race = GetPlayerInfoByGUID(guid)
        classFile = Plain(classFile)
        local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
        if color then
            text = color:WrapTextInColorCode(name)
        end
        local about = strtrim(("%s %s"):format(Plain(race) or "", Plain(className) or ""))
        if about ~= "" then
            text = ("%s (%s)"):format(text, about)
        end
    end
    Alert(text)
end

local function OnCombatLog()
    local _, _, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
    if HostilePlayer(sourceFlags) then
        CheckLog(sourceGUID, sourceName)
    end
    if HostilePlayer(destFlags) then
        CheckLog(destGUID, destName)
    end
end

local events = CreateFrame("Frame")
if CombatLogGetCurrentEventInfo then
    local log = CreateFrame("Frame")
    if pcall(log.RegisterEvent, log, "COMBAT_LOG_EVENT_UNFILTERED") then
        log:SetScript("OnEvent", function()
            Qolly.Safe("radar (log)", OnCombatLog)
        end)
    else
        Qolly.Log("Radar: log de combate indisponível, só placas, alvo e mouseover.")
    end
end
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        if GetCVar("nameplateShowEnemies") ~= "1" then
            Qolly.Print("Radar: placas de nome de inimigos estão desligadas (tecla V); "
                .. "sem elas o radar só vê quem aparece no log de combate, alvo e mouseover. /qolly radar placas liga.")
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        Qolly.Safe("radar", Unmark, unit)
        return
    end
    if event == "PLAYER_TARGET_CHANGED" then
        unit = "target"
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        unit = "mouseover"
    end
    if unit then
        Qolly.Safe("radar", Check, unit)
    end
end)

local function OnOff(value)
    return value and "|cff33dd33ligado|r" or "|cffff5555desligado|r"
end

Qolly.RegisterModule("radar", {
    help = "on | off | som (liga/desliga o som) | marca (liga/desliga a marca na placa do inimigo) | placas (liga placas de inimigos) | teste",
    command = function(input)
        local command = strtrim(input):lower()
        local db = Radar.db
        if command == "on" then
            db.enabled = true
        elseif command == "off" then
            db.enabled = false
        elseif command == "som" then
            db.sound = db.sound == false
        elseif command == "marca" then
            db.mark = db.mark == false
        elseif command == "placas" then
            if InCombatLockdown() then
                Qolly.Print("Radar: saia de combate para ligar as placas.")
                return
            end
            SetCVar("nameplateShowEnemies", "1")
            -- Distância máxima em que o client cria placas; o padrão é menor.
            pcall(SetCVar, "nameplateMaxDistance", "60")
        elseif command == "teste" then
            Alert("Fulano (31 Humano Guerreiro) |cffff5555PvP|r")
            return
        end
        Qolly.Print(("Radar %s, som %s, marca %s, placas de inimigos %s."):format(
            OnOff(db.enabled), OnOff(db.sound ~= false), OnOff(db.mark ~= false),
            OnOff(GetCVar("nameplateShowEnemies") == "1")))
    end,
    init = function(moduleDB)
        Radar.db = moduleDB
        if moduleDB.enabled == nil then
            moduleDB.enabled = true
        end
    end,
})
