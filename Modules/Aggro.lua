-- Semáforo de aggro: uma bolinha em cima da placa de cada mob hostil.
--   verde    longe do raio de aggro
--   amarelo  perto: mais alguns passos e ele vem
--   vermelho dentro do raio (ou quase)
-- Raio: por volta de 20 jardas no mesmo nível, 1 jarda a mais por nível que o mob tem
-- acima de você (a menos por nível abaixo), entre 5 e 45. Mob caveira: 45.
-- Distância: o jogo só diz se um item alcança a unidade, então ela vem em faixas
-- (5, 10, 15, 20, 25, 30, 35, 40, 45 jardas). Os itens de cada faixa são os que
-- funcionam com mobs hostis neste client.
local _, Qolly = ...

local Aggro = {}
Qolly.Aggro = Aggro

local db

local BASE_RADIUS = 20
local MIN_RADIUS, MAX_RADIUS = 5, 45
-- Até esta folga além do raio a bolinha fica amarela.
local MARGIN = 10
local TICK = 0.2

-- Faixa (jardas) -> itens que alcançam um mob hostil a essa distância.
local BANDS = {
    { 5, { 8149, 15826 } },
    { 10, { 9606, 9618 } },
    { 15, { 4559 } },
    { 20, { 1191, 10645 } },
    { 25, { 13289 } },
    { 30, { 835, 1404 } },
    { 35, { 1399, 1258 } },
    { 40, { 4945, 8348 } },
    { 45, { 221316 } },
}

local COLORS = {
    green = { 0.2, 0.9, 0.2 },
    yellow = { 1, 0.85, 0.1 },
    red = { 1, 0.15, 0.15 },
    unknown = { 0.6, 0.6, 0.6 },
}

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function InRange(itemID, unit)
    local ok, result = pcall(C_Item.IsItemInRange, itemID, unit)
    if not ok then
        return nil
    end
    return Plain(result)
end

-- Menor faixa que alcança o mob e a anterior: a distância está entre as duas.
-- nil, nil quando nenhum item responde (mob longe demais ou dado indisponível).
local function Distance(unit)
    local below, any = 0, false
    for _, band in ipairs(BANDS) do
        local yards, items = band[1], band[2]
        local answered, inside = false, false
        for _, itemID in ipairs(items) do
            local result = InRange(itemID, unit)
            if result ~= nil then
                answered = true
                inside = result == true
                break
            end
        end
        if answered then
            any = true
            if inside then
                return below, yards
            end
            below = yards
        end
    end
    if not any then
        return nil
    end
    return below, nil
end

local function Radius(unit)
    local mine = Plain(UnitLevel("player"))
    local theirs = Plain(UnitLevel(unit))
    if not mine or not theirs then
        return BASE_RADIUS
    end
    if theirs < 0 then
        return MAX_RADIUS
    end
    return math.max(MIN_RADIUS, math.min(MAX_RADIUS, BASE_RADIUS + theirs - mine))
end

-- Só mob que ataca sozinho: vermelho (hostil), vivo, fora de combate e que não é jogador.
local function Watch(unit)
    if Plain(UnitIsPlayer(unit)) ~= false then
        return false
    end
    if Plain(UnitCanAttack("player", unit)) ~= true or Plain(UnitIsDead(unit)) ~= false then
        return false
    end
    local reaction = Plain(UnitReaction(unit, "player"))
    if not reaction or reaction > 2 then
        return false
    end
    return Plain(UnitAffectingCombat(unit)) ~= true
end

local function Light(unit)
    local low, high = Distance(unit)
    if not low then
        return "unknown"
    end
    local radius = Radius(unit)
    if high and high <= radius then
        return "red"
    end
    if low < radius + MARGIN and (high or low < radius) then
        return "yellow"
    end
    return "green"
end

-- Placa -> bolinha. As placas são reaproveitadas: a bolinha some quando a unidade sai.
local dots = {}
local units = {} -- unidade da placa -> true

local function Dot(plate)
    local dot = dots[plate]
    if not dot then
        -- Num frame próprio acima da placa, para nada (ícone de elite, textos) cobrir.
        local holder = CreateFrame("Frame", nil, plate)
        holder:SetSize(26, 26)
        holder:SetFrameLevel(plate:GetFrameLevel() + 20)
        dot = holder:CreateTexture(nil, "OVERLAY")
        dot:SetAllPoints()
        dot:SetTexture("Interface/COMMON/Indicator-Gray")
        dot.holder = holder
        hooksecurefunc(dot, "Show", function() holder:Show() end)
        hooksecurefunc(dot, "Hide", function() holder:Hide() end)
        dots[plate] = dot
    end
    -- À direita da barra de vida visível (à esquerda fica o ícone de elite); a placa
    -- em si é mais larga que a barra.
    local unitFrame = plate.UnitFrame
    local bar = unitFrame and (unitFrame.healthBar or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar))
    local anchor = (bar and bar:IsVisible()) and bar or plate
    -- O nível do mob fica logo à direita da barra: a bolinha vai depois dele.
    local level = unitFrame and (unitFrame.LevelFrame or unitFrame.levelFrame or unitFrame.Level)
    local gap = 56
    if level and level.IsVisible and level:IsVisible() then
        anchor, gap = level, 14
    end
    dot.holder:ClearAllPoints()
    dot.holder:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
    return dot
end

local function PlateOf(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        return nil
    end
    return plate
end

local function Hide(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and dots[plate] then
        dots[plate]:Hide()
    end
end

local function Update(unit)
    local plate = PlateOf(unit)
    if not plate then
        return
    end
    if not db.enabled or not Watch(unit) then
        if dots[plate] then
            dots[plate]:Hide()
        end
        return
    end
    local dot = Dot(plate)
    local color = COLORS[Light(unit)]
    dot:SetVertexColor(color[1], color[2], color[3])
    dot:Show()
end

local function UpdateAll()
    for unit in pairs(units) do
        Qolly.Safe("aggro", Update, unit)
    end
end

-- Os itens precisam estar no cache para o teste de alcance responder.
local function LoadItems()
    for _, band in ipairs(BANDS) do
        for _, itemID in ipairs(band[2]) do
            if C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, itemID)
            end
        end
    end
end

local clock = CreateFrame("Frame")
local elapsed = 0
clock:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < TICK then
        return
    end
    elapsed = 0
    if db and db.enabled then
        UpdateAll()
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        LoadItems()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        units[unit] = true
        if db then
            Qolly.Safe("aggro", Update, unit)
        end
    else
        units[unit] = nil
        Hide(unit)
    end
end)

function Aggro.SetEnabled(on)
    db.enabled = on and true or false
    UpdateAll()
end

function Aggro.IsEnabled()
    return db.enabled == true
end

Qolly.RegisterModule("aggro", {
    help = "(liga/desliga o semáforo de aggro em cima da placa dos mobs)",
    command = function()
        Aggro.SetEnabled(not db.enabled)
        Qolly.Print("Semáforo de aggro " .. (db.enabled and "ligado." or "desligado."))
    end,
    init = function(moduleDB)
        db = moduleDB
        if db.enabled == nil then
            db.enabled = true
        end
    end,
})
