-- Morrer desliga o rastreamento de ervas/minérios do minimapa. Ao reviver, um aviso
-- mostra um botão para religar cada um que estava ligado. O addon não pode lançar a
-- magia sozinho; um botão seguro clicado por você pode.
local _, Qolly = ...
local Gather = Qolly.Gather

local SPELLS = {
    { id = 2383, label = "Encontrar Ervas", kind = "herb" },
    { id = 2580, label = "Encontrar Minerais", kind = "ore" },
}

-- Tipo de nó -> rastreamento ligado agora. Lido pelo minimapa a cada atualização.
local trackingOn = {}
local readAt = 0
local ActiveTracking

-- Relê o estado a cada segundo: o evento de mudança do rastreamento nem sempre chega
-- (morte, troca de zona, ligar pelo menu de outro addon).
local READ_EVERY = 1

function Gather.TrackingOn(kind)
    local now = GetTime()
    if now - readAt >= READ_EVERY then
        readAt = now
        local current = ActiveTracking()
        for _, spell in ipairs(SPELLS) do
            trackingOn[spell.kind] = current[spell.id] or nil
        end
    end
    return trackingOn[kind] == true
end

local popup
local buttons = {}
-- spellID -> true: o que estava ligado antes de morrer.
local wasOn = {}
-- spellID -> true: você fechou o aviso; só volta a pedir depois de ligar e desligar.
local dismissed = {}
local waitingCombat = false

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

-- O WoW Forever às vezes não manda o id da magia no rastreamento: tenta o filtro da
-- entrada, depois o nome e o ícone da magia no idioma do client.
local function SpellOf(index, name, texture)
    if C_Minimap.GetTrackingFilter then
        local ok, filter = pcall(C_Minimap.GetTrackingFilter, index)
        local id = ok and type(filter) == "table" and Plain(filter.spellID)
        if id then
            return id
        end
    end
    for _, spell in ipairs(SPELLS) do
        if name and C_Spell.GetSpellName(spell.id) == name then
            return spell.id
        end
        if texture and C_Spell.GetSpellTexture(spell.id) == texture then
            return spell.id
        end
    end
end

local logged = false

-- Os rastreamentos ligados agora, por spellID. C_Minimap devolve tabela nos clients
-- novos e valores soltos nos antigos.
function ActiveTracking()
    local active = {}
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
        return active
    end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info, texture, isActive, _, _, spellID = C_Minimap.GetTrackingInfo(index)
        local name = info
        if type(info) == "table" then
            isActive, spellID, name, texture = info.active, info.spellID, info.name, info.texture
        end
        name, texture, isActive, spellID = Plain(name), Plain(texture), Plain(isActive), Plain(spellID)
        if type(name) ~= "string" then
            name = nil
        end
        -- Id que não é das nossas (outra versão da magia) também passa pelo nome/ícone.
        if not (spellID == SPELLS[1].id or spellID == SPELLS[2].id) then
            spellID = SpellOf(index, name, texture) or spellID
        end
        -- Uma vez por sessão no log, para conferir o que o client responde.
        if not logged and isActive then
            Qolly.Log(("Rastreamento ativo: %s, id %s, ícone %s"):format(tostring(name), tostring(spellID), tostring(texture)))
        end
        if isActive and spellID then
            active[spellID] = true
        end
    end
    logged = true
    return active
end

-- /qolly coleta rastreio: cada entrada do rastreamento como o jogo devolve.
function Gather.DebugTracking()
    local D = Qolly.Describe
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
        Qolly.Print("Rastreio: sem C_Minimap.GetNumTrackingTypes.")
        return
    end
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info, texture, active, kind, subType, spellID = C_Minimap.GetTrackingInfo(index)
        if type(info) == "table" then
            Qolly.Print(("#%d tabela: nome=%s ativo=%s id=%s tipo=%s ícone=%s"):format(index,
                D(info.name), D(info.active), D(info.spellID), D(info.type), D(info.texture)))
        else
            Qolly.Print(("#%d solto: nome=%s ativo=%s id=%s tipo=%s ícone=%s"):format(index,
                D(info), D(active), D(spellID), D(kind), D(texture)))
        end
    end
    for _, spell in ipairs(SPELLS) do
        Qolly.Print(("%s: %s, conhecida=%s, ligada pelo Qolly=%s"):format(spell.label,
            D(C_Spell.GetSpellName(spell.id)), D(IsPlayerSpell(spell.id)), D(Gather.TrackingOn(spell.kind))))
    end
end

local function Dead()
    return UnitIsDeadOrGhost("player")
end

local function Missing()
    local active = ActiveTracking()
    local missing = {}
    for _, spell in ipairs(SPELLS) do
        -- Desligado e você mostra esse tipo de nó (ou estava ligado antes de morrer).
        local wanted = wasOn[spell.id] or (Gather.Shown(spell.kind) and not dismissed[spell.id])
        if active[spell.id] then
            dismissed[spell.id] = nil
        elseif wanted and IsPlayerSpell(spell.id) then
            missing[#missing + 1] = spell
        end
    end
    return missing
end

local BUTTON_WIDTH = 140

local function CreatePopup()
    -- Fechar em combate esconderia botões seguros (bloqueado): só fora de combate.
    -- Fechado, não volta até você ligar e desligar de novo (ou morrer com ele ligado).
    popup = Qolly.Notice("QollyTrackingPopup", "rastreamento desligado", function()
        if not InCombatLockdown() then
            for _, spell in ipairs(SPELLS) do
                dismissed[spell.id] = true
            end
            wipe(wasOn)
            popup:Hide()
        end
    end)
    for index, spell in ipairs(SPELLS) do
        local button = CreateFrame("Button", nil, popup, "SecureActionButtonTemplate, UIPanelButtonTemplate")
        button:SetSize(BUTTON_WIDTH, 22)
        button:SetText(spell.label)
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", spell.id)
        button:RegisterForClicks("AnyUp", "AnyDown")
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell.id)
        if icon then
            button:SetText(("|T%s:14|t %s"):format(icon, spell.label))
        end
        buttons[index] = button
    end
    popup:Hide()
end

-- Mexer em frame seguro em combate é bloqueado: espera o combate acabar.
local function Refresh()
    if InCombatLockdown() then
        waitingCombat = true
        return
    end
    waitingCombat = false
    if not popup then
        CreatePopup()
    end
    local missing = Gather.db.trackingPopup ~= false and not Dead() and Missing() or {}
    if #missing == 0 then
        popup:Hide()
        return
    end
    local shown = {}
    for _, spell in ipairs(missing) do
        shown[spell.id] = true
    end
    local previous
    for index, spell in ipairs(SPELLS) do
        local button = buttons[index]
        button:ClearAllPoints()
        if shown[spell.id] then
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
            else
                -- Botão protegido só pode se prender a frame, não ao texto do título.
                button:SetPoint("LEFT", popup, "LEFT", popup:ContentLeft(), 0)
            end
            button:Show()
            previous = button
        else
            button:Hide()
        end
    end
    popup:Fit(#missing * (BUTTON_WIDTH + 6) - 6)
    popup:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MINIMAP_UPDATE_TRACKING")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not waitingCombat then
        return
    end
    local current = ActiveTracking()
    for _, spell in ipairs(SPELLS) do
        trackingOn[spell.kind] = current[spell.id] or nil
    end
    -- Vivo, o estado atual do rastreamento é o que se quer de volta depois de morrer.
    if not Dead() and event ~= "PLAYER_ALIVE" and event ~= "PLAYER_UNGHOST" then
        local active = ActiveTracking()
        for _, spell in ipairs(SPELLS) do
            if active[spell.id] then
                wasOn[spell.id] = true
            elseif not (popup and popup:IsShown()) then
                wasOn[spell.id] = nil
            end
        end
    end
    Qolly.Safe("rastreamento", Refresh)
end)

-- Ligar ou desligar Herborismo/Mineração na Coleta muda o que o aviso pede.
function Gather.RefreshTracking()
    Qolly.Safe("rastreamento", Refresh)
end
