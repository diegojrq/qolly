-- Buffs de classe de longa duração: fora de combate, um aviso mostra um ícone para cada
-- buff da sua classe que está faltando (ou acabando). Clicar no ícone lança o buff em
-- você. Só entram os buffs que você conhece; o mesmo buff lançado por outro jogador
-- (ou a versão de grupo, como Dom da Natureza) também conta.
-- Os buffs são reconhecidos pelo nome, então qualquer patente da magia serve.
local _, Qolly = ...

local Buffs = {}
Qolly.Buffs = Buffs

local db
-- Grupo -> true: você fechou o aviso com ele. Só nesta sessão.
local dismissed = {}

-- Faltando menos que isso (segundos), o buff já aparece no aviso.
local EXPIRING = 60
-- Releitura periódica: o fim de um buff nem sempre gera evento a tempo.
local TICK = 5
local MAIN_HAND = 16

-- Cada grupo pede um buff. cast: magias que o botão pode lançar, em ordem de
-- preferência (você conhecer uma delas liga o grupo). also: outras que também valem,
-- sem serem lançadas. pick: o botão lança a última do grupo que esteve ativa em
-- você. weapon: vale também um encantamento temporário na arma.
local CLASSES = {
    MAGE = {
        { key = "intelecto", label = "Intelecto Arcano", cast = { 1459 }, also = { 23028 } },
        { key = "armadura", label = "Armadura", pick = true, cast = { 30482, 6117, 7302, 168 } },
    },
    PRIEST = {
        { key = "vigor", label = "Palavra de Poder: Fortitude", cast = { 1243, 21562 } },
        { key = "fogo", label = "Fogo Interior", cast = { 588 } },
    },
    DRUID = {
        { key = "marca", label = "Marca do Selvagem", cast = { 1126 }, also = { 21849 } },
        { key = "espinhos", label = "Espinhos", cast = { 467 } },
    },
    PALADIN = {
        { key = "bencao", label = "Bênção", pick = true, cast = { 19740, 19742, 20217, 1038, 19977, 20911 },
          also = { 25782, 25894, 25898, 25895, 25890, 25899 } },
        { key = "aura", label = "Aura", pick = true, cast = { 465, 7294, 19746, 19876, 19888, 19891, 32223, 317920 } },
    },
    WARLOCK = {
        { key = "armadura", label = "Armadura demoníaca", pick = true, cast = { 28176, 706, 687 } },
        -- Talento; só existe com o demônio invocado.
        { key = "vinculo", label = "Vínculo Anímico", pet = true, cast = { 19028 } },
    },
    HUNTER = {
        -- Chita e Bando valem enquanto ativos, mas o botão nunca os lança.
        { key = "aspecto", label = "Aspecto", pick = true, cast = { 61846, 13165, 13163, 20043 }, also = { 5118, 13159 } },
    },
    SHAMAN = {
        { key = "escudo", label = "Escudo", pick = true, cast = { 192106, 324, 52127, 24398, 974 } },
        { key = "arma", label = "Arma encantada", weapon = true, pick = true, cast = { 318038, 33757, 8024, 8232, 8017, 8033 } },
    },
    ROGUE = {
        -- 2842 é a habilidade Venenos dos clients antigos (veneno é item, aplicado à mão).
        { key = "veneno", label = "Veneno na arma", weapon = true, cast = { 315584, 2823, 8679 }, also = {}, known = { 2842 } },
    },
    EVOKER = {
        { key = "bronze", label = "Bênção do Bronze", cast = { 364342 } },
    },
}

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function Known(spellID)
    local ok, known = pcall(IsPlayerSpell, spellID)
    if ok and Plain(known) then
        return true
    end
    ok, known = pcall(IsSpellKnown, spellID)
    return ok and Plain(known) == true
end

local function NameOf(spellID)
    local name = C_Spell.GetSpellName(spellID)
    return Plain(name)
end

-- Buffs em você agora: nome -> segundos restantes (math.huge quando não acaba), e a
-- lista com os detalhes de cada um.
local function ActiveAuras()
    local active, list = {}, {}
    for index = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then
            break
        end
        local name = Plain(aura.name)
        if name then
            local expires = Plain(aura.expirationTime)
            local left = (expires and expires > 0) and (expires - GetTime()) or math.huge
            active[name] = math.max(active[name] or 0, left)
            list[#list + 1] = { name = name, left = left, icon = Plain(aura.icon), spellID = Plain(aura.spellId), data = aura }
        end
    end
    return active, list
end

-- Segundos restantes do encantamento temporário da mão principal, ou nil.
local function WeaponLeft()
    if not GetInventoryItemID("player", MAIN_HAND) then
        return nil, false
    end
    local has, expiresMs = GetWeaponEnchantInfo()
    if Plain(has) then
        return (Plain(expiresMs) or 0) / 1000, true
    end
    return nil, true
end

-- A magia que o botão do grupo lança: a última que você usou dele, ou a primeira conhecida.
local function SpellToCast(group)
    local first
    for _, id in ipairs(group.cast) do
        if Known(id) then
            local name = NameOf(id)
            if name and name == db.last[group.key] then
                return id, name
            end
            first = first or id
        end
    end
    return first, first and NameOf(first)
end

local function Relevant(group)
    if group.pet and not (UnitExists("pet") and not UnitIsDead("pet")) then
        return false
    end
    if SpellToCast(group) then
        return true
    end
    for _, id in ipairs(group.known or {}) do
        if Known(id) then
            return true
        end
    end
    return false
end

-- Quanto falta do buff do grupo: 0 se não está ativo, nil se o grupo não se aplica agora.
local function TimeLeft(group, active)
    local best = 0
    local function Check(ids, remember)
        for _, id in ipairs(ids or {}) do
            local name = NameOf(id)
            local left = name and active[name]
            if left then
                if left > best then
                    best = left
                end
                if remember then
                    db.last[group.key] = name
                end
            end
        end
    end
    Check(group.cast, group.pick)
    Check(group.also, false)
    if group.weapon then
        local left, armed = WeaponLeft()
        if not armed then
            return nil
        end
        if left and left > best then
            best = left
        end
    end
    return best
end

-- Bônus de XP ------------------------------------------------------------------------
-- O texto do buff diz quanto de experiência ele dá ("Aumenta em 3% o ganho de
-- experiência"). O Qolly lê a frase que fala de experiência e pega a porcentagem dela.

-- spellID -> porcentagem de XP (0 quando o buff não fala de XP).
local xpCache = {}

local function DescriptionOf(aura)
    local id = aura.auraInstanceID
    if C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID and id then
        local ok, info = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", id)
        if ok and type(info) == "table" and info.lines then
            local parts = {}
            for index = 2, #info.lines do
                local text = Plain(info.lines[index].leftText)
                if text then
                    parts[#parts + 1] = text
                end
            end
            if #parts > 0 then
                return table.concat(parts, " ")
            end
        end
    end
    local spellID = Plain(aura.spellId)
    return spellID and Plain(C_Spell.GetSpellDescription(spellID))
end

-- A porcentagem da frase que fala de experiência ("3.5%" e "3,5%" também valem).
-- "Experiência", "XP" e "EXP" contam ("ganho de XP aumentado em 5 %" também).
local function TalksXP(sentence)
    local lower = " " .. sentence:lower() .. " "
    return lower:find("xperi") or lower:find("[^%a]e?xp[^%a]")
end

local function XPPercent(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for sentence in (text .. ". "):gmatch("(.-)[%.;\n]%s") do
        if TalksXP(sentence) then
            local number = sentence:match("(%d+[%.,]?%d*)%s*%%")
            if number then
                return tonumber((number:gsub(",", "."))) or 0
            end
        end
    end
    return 0
end

-- Releitura periódica do texto de cada buff: ele pode chegar incompleto na primeira vez,
-- e alguns mudam a porcentagem sem trocar de magia.
local RECHECK = 10
local xpChecked = {}

local function MaxLevel()
    local level = Plain(UnitLevel("player")) or 0
    local max = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    return level >= max or (IsXPUserDisabled and IsXPUserDisabled())
end

-- Comida com bônus de XP -------------------------------------------------------------
-- É o "Bem Alimentado" que também dá XP. O Qolly aprende qual comida você comeu
-- (o item da bolsa cuja magia você acabou de usar) e o botão do aviso come dela.

local FOOD = { key = "comida", label = "Comida com bônus de XP", food = true }
local WELL_FED = { 19705, 19706, 24799, 46899 }
local FOOD_ICON = "Interface/Icons/INV_Misc_Food_14"
local LEARN_WINDOW = 60

local function IsWellFed(name)
    for _, id in ipairs(WELL_FED) do
        if NameOf(id) == name then
            return true
        end
    end
    local lower = name:lower()
    return lower:find("aliment") ~= nil or lower:find("well fed") ~= nil
end

-- Item da bolsa que acabou de ser usado (comida em andamento) e quando.
local eaten, eatenAt

local function ItemOfSpell(spellID)
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local _, itemSpell = C_Item.GetItemSpell(itemID)
                if itemSpell == spellID then
                    return itemID
                end
            end
        end
    end
end

local function OnSpellCast(spellID)
    spellID = Plain(spellID)
    local itemID = spellID and ItemOfSpell(spellID)
    if itemID then
        eaten, eatenAt = itemID, GetTime()
    end
end

-- Quanto falta do Bem Alimentado (0 se não tem). Aprende a comida quando o buff
-- aparece logo depois de comer.
local function FoodLeft(auras)
    local best = 0
    for _, aura in ipairs(auras) do
        if aura.name and IsWellFed(aura.name) then
            best = math.max(best, aura.left)
            if eaten and GetTime() - eatenAt < LEARN_WINDOW then
                db.food = eaten
                eaten = nil
            end
        end
    end
    return best
end

-- A comida aprendida, se ainda tem na bolsa.
local function FoodItem()
    local itemID = db.food
    if itemID and (C_Item.GetItemCount(itemID) or 0) > 0 then
        return itemID
    end
end

-- O Bem Alimentado não diz no próprio texto que dá XP: quem diz é a comida ("...ganhará
-- 5% a mais de experiência"). Lê o tooltip da comida que você comeu.
local function ItemXP(itemID)
    if not itemID or not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
        return 0
    end
    local ok, info = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not ok or type(info) ~= "table" or not info.lines then
        return 0
    end
    local parts = {}
    for _, line in ipairs(info.lines) do
        local text = Plain(line.leftText)
        if text then
            parts[#parts + 1] = text
        end
    end
    return XPPercent(table.concat(parts, ". "))
end

local function FoodXP()
    db.foodXP = db.foodXP or {}
    local itemID = eaten or db.food
    if not itemID then
        return 0
    end
    local percent = ItemXP(itemID)
    if percent > 0 then
        db.foodXP[itemID] = percent
    end
    return db.foodXP[itemID] or 0
end

-- Buffs que dão XP agora: { name, percent, left, icon, spellID }, e a soma.
local function XPBonuses(auras)
    local list, total = {}, 0
    local now = GetTime()
    for _, aura in ipairs(auras) do
        local spellID = aura.spellID
        -- Por instância do buff e relido de tempos em tempos: alguns crescem sem trocar
        -- de magia (o Descansado da fogueira vai de 1% a 3% enquanto você fica perto).
        local key = (aura.data and aura.data.auraInstanceID) or spellID
        local percent = key and xpCache[key]
        if percent and now - (xpChecked[key] or 0) > RECHECK then
            percent = nil
        end
        if not percent then
            local text = DescriptionOf(aura.data)
            if text and text ~= "" then
                percent = XPPercent(text)
                if key then
                    xpCache[key] = percent
                    xpChecked[key] = now
                end
            end
        end
        if (not percent or percent == 0) and IsWellFed(aura.name) then
            percent = FoodXP()
        end
        if percent and percent > 0 then
            list[#list + 1] = { name = aura.name, percent = percent, left = aura.left, icon = aura.icon, spellID = spellID }
            total = total + percent
        end
    end
    return list, total
end


-- Grupos da sua classe com o buff faltando ou acabando.
local function Missing(active, auras)
    local list = {}
    local function Consider(group, left)
        if left and left >= EXPIRING then
            dismissed[group.key] = nil
        elseif left and not dismissed[group.key] then
            list[#list + 1] = group
        end
    end
    for _, group in ipairs(CLASSES[select(2, UnitClass("player"))] or {}) do
        if Relevant(group) then
            Consider(group, TimeLeft(group, active))
        end
    end
    if db.foodAlert ~= false and not MaxLevel() then
        Consider(FOOD, FoodLeft(auras))
    end
    return list
end

local function Blocked()
    return UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
        or (UnitInVehicle and UnitInVehicle("player")) or IsResting() and db.skipResting
end

-- Texto do bônus de XP ---------------------------------------------------------------
-- "XP +8%  ·  descanso 45%" no canto direito da barra de experiência. O mouse em cima
-- mostra de onde vem cada parte.

local xpFrame
local xpBonuses, xpTotal = {}, 0

local function Duration(seconds)
    if seconds == math.huge then
        return ""
    end
    if seconds >= 3600 then
        local minutes = math.floor(seconds / 60 + 0.5)
        local hours, rest = math.floor(minutes / 60), minutes % 60
        return rest > 0 and ("%dh%02d"):format(hours, rest) or ("%dh"):format(hours)
    end
    return ("%d min"):format(math.max(1, seconds / 60))
end

local function RestedPercent()
    local rested = Plain(GetXPExhaustion()) or 0
    local max = Plain(UnitXPMax("player")) or 0
    if max <= 0 then
        return 0
    end
    return rested / max * 100
end

-- Barraca de acampamento: ela enche o descanso de uma vez e põe o "Descanso Melhorado"
-- (1h sem poder ganhar de outra barraca). O jogo não diz quanto deu, então o Qolly mede:
-- o descanso logo antes do bloqueio aparecer contra o maior valor nos segundos seguintes.
local TENT_LOCK = 1229451
local TENT_WINDOW = 20
local lastRested, tent = nil, nil

local function TentLock()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then
        return nil
    end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, TENT_LOCK)
    if not ok or type(aura) ~= "table" then
        return nil
    end
    local expires = Plain(aura.expirationTime)
    return (expires and expires > 0) and (expires - GetTime()) or math.huge, Plain(aura.auraInstanceID)
end

local function WatchTent(rested)
    local left, instance = TentLock()
    if left then
        if not tent or tent.instance ~= instance then
            tent = { instance = instance, base = lastRested or rested, seen = GetTime() }
        end
        if GetTime() - tent.seen <= TENT_WINDOW then
            local gain = rested - tent.base
            if gain > 0.5 then
                db.tentGain = math.floor(gain + 0.5)
            end
        end
    else
        tent = nil
    end
    lastRested = rested
    return left
end

local function ShowXPTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Qolly.TAG .. "bônus de experiência")
    for _, bonus in ipairs(xpBonuses) do
        local icon = bonus.icon and ("|T%s:14|t "):format(bonus.icon) or ""
        GameTooltip:AddDoubleLine(icon .. bonus.name, ("+%s%%  %s"):format(bonus.percent, Duration(bonus.left)), 1, 1, 1, 0.4, 1, 0.4)
    end
    if #xpBonuses == 0 then
        GameTooltip:AddLine("Nenhum buff de XP ativo.", 0.8, 0.8, 0.8)
    end
    local rested = RestedPercent()
    if rested > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Descanso acumulado", ("%d%% do nível"):format(rested), 1, 1, 1, 0.5, 0.7, 1)
        GameTooltip:AddLine("Enquanto durar, abates dão XP em dobro.", 0.8, 0.8, 0.8, true)
    end
    local lock = TentLock()
    if lock or db.tentGain then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Barraca de acampamento",
            db.tentGain and ("+%d%% do nível em descanso"):format(db.tentGain) or "ganho não medido",
            1, 1, 1, 0.5, 0.7, 1)
        if lock then
            GameTooltip:AddLine("Outra barraca só dá descanso em " .. Duration(lock) .. ".", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Barraca liberada: sentar numa dá descanso de novo.", 0.4, 1, 0.4, true)
        end
    end
    GameTooltip:Show()
end

local function XPAnchor()
    return _G.MainStatusTrackingBarContainer or _G.StatusTrackingBarManager or _G.MainMenuExpBar
end

local function CreateXPFrame()
    xpFrame = CreateFrame("Frame", "QollyXPBonus", UIParent)
    xpFrame:SetFrameStrata("HIGH")
    xpFrame:SetHeight(16)
    xpFrame.text = xpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpFrame.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    xpFrame.text:SetPoint("RIGHT", xpFrame, "RIGHT", 0, 0)
    xpFrame:EnableMouse(true)
    xpFrame:SetScript("OnEnter", ShowXPTip)
    xpFrame:SetScript("OnLeave", GameTooltip_Hide)
    local anchor = XPAnchor()
    if anchor then
        xpFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -4, 1)
    else
        xpFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 2)
    end
end

local function UpdateXP(auras)
    if not xpFrame then
        CreateXPFrame()
    end
    if db.xpText == false or MaxLevel() then
        xpFrame:Hide()
        return
    end
    xpBonuses, xpTotal = XPBonuses(auras)
    local rested = RestedPercent()
    WatchTent(rested)
    local parts = {}
    if xpTotal > 0 then
        parts[#parts + 1] = ("|cff66ff66XP +%s%%|r"):format(xpTotal)
    end
    if rested > 0 then
        parts[#parts + 1] = ("|cff88aaffdescanso %d%%|r"):format(rested)
    end
    if #parts == 0 then
        xpFrame:Hide()
        return
    end
    xpFrame.text:SetText(table.concat(parts, "  ·  "))
    xpFrame:SetWidth(xpFrame.text:GetStringWidth() + 4)
    xpFrame:Show()
end

-- Aviso ---------------------------------------------------------------------------

local SIZE = 24
local SPACING = 4
local popup
local buttons = {}
local waitingCombat = false

local function ShowTip(button)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if button.itemID then
        GameTooltip:SetItemByID(button.itemID)
        GameTooltip:AddLine(Qolly.TAG .. "clique para comer", 0.4, 0.8, 1)
    elseif button.spellID then
        GameTooltip:SetSpellByID(button.spellID)
        GameTooltip:AddLine(Qolly.TAG .. "clique para lançar em você", 0.4, 0.8, 1)
    elseif button.group.food then
        GameTooltip:AddLine(button.group.label)
        GameTooltip:AddLine(Qolly.TAG .. "coma uma comida que dá bônus de XP. Depois da primeira vez, o Qolly lembra qual foi e este botão come dela.", 0.4, 0.8, 1, true)
    else
        GameTooltip:AddLine(button.group.label)
        GameTooltip:AddLine(Qolly.TAG .. "aplique pela bolsa", 0.4, 0.8, 1)
    end
    GameTooltip:Show()
end

local function Button(index)
    local button = buttons[index]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, popup, "SecureActionButtonTemplate")
    button:SetSize(SIZE, SIZE)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", ShowTip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    buttons[index] = button
    return button
end

local function CreatePopup()
    -- Fechado, cada buff só volta a ser pedido depois de ativo e acabar de novo.
    popup = Qolly.Notice("QollyBuffsPopup", "buffs faltando", function()
        if InCombatLockdown() then
            return
        end
        for _, button in ipairs(buttons) do
            if button:IsShown() then
                dismissed[button.group.key] = true
            end
        end
        popup:Hide()
    end)
end

-- Mexer em botão seguro em combate é bloqueado: espera o combate acabar.
local function Refresh()
    if InCombatLockdown() then
        waitingCombat = true
        return
    end
    waitingCombat = false
    if not popup then
        CreatePopup()
    end
    local active, auras = ActiveAuras()
    Qolly.Safe("bônus de XP", UpdateXP, auras)
    local missing = (db.enabled ~= false and not Blocked()) and Missing(active, auras) or {}
    for index, group in ipairs(missing) do
        local button = Button(index)
        local spellID, name
        local itemID = group.food and FoodItem()
        if not group.food then
            spellID, name = SpellToCast(group)
        end
        button.group, button.spellID, button.itemID = group, spellID, itemID
        if itemID then
            button:SetAttribute("type", "item")
            button:SetAttribute("item", "item:" .. itemID)
            button.icon:SetTexture(C_Item.GetItemIconByID(itemID))
        elseif group.food then
            button:SetAttribute("type", nil)
            button.icon:SetTexture(FOOD_ICON)
        elseif spellID then
            button:SetAttribute("type", "spell")
            button:SetAttribute("spell", name)
            button:SetAttribute("unit", "player")
            button.icon:SetTexture(C_Spell.GetSpellTexture(spellID))
        else
            button:SetAttribute("type", nil)
            button.icon:SetTexture("Interface/Icons/Trade_BrewPoison")
        end
        button:ClearAllPoints()
        -- Botão protegido só pode se prender a frame, não ao texto do título.
        button:SetPoint("LEFT", popup, "LEFT", popup:ContentLeft() + (index - 1) * (SIZE + SPACING), 0)
        button:Show()
    end
    for index = #missing + 1, #buttons do
        buttons[index]:Hide()
    end
    if #missing == 0 then
        popup:Hide()
        return
    end
    popup:Fit(#missing * (SIZE + SPACING) - SPACING)
    popup:Show()
end

-- Roda a cada 5 s: um erro aqui vai inteiro para o log, mas só aparece no chat uma vez.
local failed = false
local function Schedule()
    local ok, failure = xpcall(Refresh, debugstack and function(message)
        return tostring(message) .. "\n" .. debugstack(2)
    end or tostring)
    if not ok and not failed then
        failed = true
        Qolly.Print("ERRO em buffs (só aviso uma vez): " .. tostring(failure):match("^[^\n]*"))
        Qolly.Log(tostring(failure))
    end
end

-- Vários UNIT_AURA chegam juntos: um refresh só, um instante depois.
local pending = false
local function Soon()
    if pending then
        return
    end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        Schedule()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_UPDATE_RESTING")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_PET", "player")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("UPDATE_EXHAUSTION")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if not db then
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        Qolly.Safe("comida", OnSpellCast, spellID)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        Schedule()
    elseif not InCombatLockdown() then
        Soon()
    end
end)

C_Timer.NewTicker(TICK, function()
    if db and not InCombatLockdown() then
        Schedule()
    end
end)

function Buffs.IsEnabled()
    return db.enabled ~= false
end

function Buffs.SetEnabled(on)
    db.enabled = on and true or false
    Schedule()
end

-- Opções ligadas por padrão: foodAlert (comida de XP no aviso), xpText (texto na barra).
function Buffs.GetOption(key)
    return db[key] ~= false
end

function Buffs.SetOption(key, on)
    db[key] = on and true or false
    Schedule()
end

function Buffs.SkipsResting()
    return db.skipResting == true
end

function Buffs.SetSkipResting(on)
    db.skipResting = on and true or false
    Schedule()
end

Qolly.RegisterModule("buffs", {
    help = "(liga/desliga o aviso de buffs de classe faltando; 'xp' mostra o texto de cada buff)",
    command = function(argument)
        if argument == "xp" then
            local _, auras = ActiveAuras()
            for _, aura in ipairs(auras) do
                local text = DescriptionOf(aura.data) or "?"
                Qolly.Print(("%s (%s): XP %s%% | %s"):format(aura.name, tostring(aura.spellID), XPPercent(text), text))
            end
            return
        end
        wipe(dismissed)
        Buffs.SetEnabled(not Buffs.IsEnabled())
        Qolly.Print("Aviso de buffs " .. (Buffs.IsEnabled() and "ligado." or "desligado."))
    end,
    init = function(moduleDB)
        db = moduleDB
        db.last = db.last or {}
    end,
})
