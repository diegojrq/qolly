-- Mercado: oportunidades de lucro achadas no scan completo da AH.
--   Revenda: anúncios bem abaixo do preço normal do item (histórico de dias de scan).
--   Desencantar: verde/azul mais barato que o valor esperado do pó/essência/fragmento.
--   Vendedor: item na AH por menos do que o NPC paga por ele.
--   Essências: 3 menores valem 1 maior (e vice-versa); clicar com o botão direito na
--   essência converte, qualquer um pode.
-- Os valores de desencantar seguem a tabela clássica (nível do item -> material e
-- chance). Desencantar exige Encantamento, e o nível do encantamento limita o item.
local _, Qolly = ...
local AH = Qolly.AH

local Market = {}
Qolly.Market = Market

local db

local AH_CUT = 0.95          -- a AH fica com 5% da venda
local HISTORY_DAYS = 7       -- dias de mediana guardados por item
local MIN_DAYS = 2           -- dias anteriores necessários para confiar no "preço normal"
local FLIP_BELOW = 0.65      -- anúncio a até 65% do preço normal entra na revenda
local SAMPLE = 10            -- unidades mais baratas que entram na mediana do scan
local MIN_PROFIT = { flip = 5000, disenchant = 1000, vendor = 100, essence = 1000 }

-- Desencantar ---------------------------------------------------------------------------

local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = {
    lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134,
    gmystic = 11135, lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203,
}
local SHARD = {
    sglimmer = 10978, lglimmer = 11084, sglow = 11138, lglow = 11139, sradiant = 11177,
    lradiant = 11178, sbrilliant = 14343, lbrilliant = 14344, nexus = 20725,
}

-- { nível máximo, { {material, chance, quantidade média}, ... } } por tipo. A arma
-- inverte as chances de pó e essência da armadura.
local function Green(dust, dustQty, essence, essQty, shard, shardChance, weapon)
    local dustChance = weapon and 0.20 or 0.75
    local essChance = weapon and 0.75 or 0.20
    if not shard then
        dustChance, essChance = weapon and 0.20 or 0.80, weapon and 0.80 or 0.20
    elseif shardChance > 0.05 then
        dustChance, essChance = weapon and 0.15 or 0.75, weapon and 0.75 or 0.15
    end
    local list = { { dust, dustChance, dustQty }, { essence, essChance, essQty } }
    if shard then
        list[#list + 1] = { shard, shardChance, 1 }
    end
    return list
end

local GREEN_BANDS = {
    { 15, DUST.strange, 1.5, ESS.lmagic, 1.5 },
    { 20, DUST.strange, 2.5, ESS.gmagic, 1.5, SHARD.sglimmer, 0.05 },
    { 25, DUST.strange, 5, ESS.lastral, 1.5, SHARD.sglimmer, 0.10 },
    { 30, DUST.soul, 1.5, ESS.gastral, 1.5, SHARD.lglimmer, 0.05 },
    { 35, DUST.soul, 3.5, ESS.lmystic, 1.5, SHARD.sglow, 0.05 },
    { 40, DUST.vision, 1.5, ESS.gmystic, 1.5, SHARD.lglow, 0.05 },
    { 45, DUST.vision, 3.5, ESS.lnether, 1.5, SHARD.sradiant, 0.05 },
    { 50, DUST.dream, 1.5, ESS.gnether, 1.5, SHARD.lradiant, 0.05 },
    { 55, DUST.dream, 3.5, ESS.leternal, 1.5, SHARD.sbrilliant, 0.05 },
    { 60, DUST.illusion, 1.5, ESS.geternal, 1.5, SHARD.lbrilliant, 0.05 },
    { 65, DUST.illusion, 3.5, ESS.geternal, 2.5, SHARD.lbrilliant, 0.05 },
}

local BLUE_BANDS = {
    { 25, SHARD.sglimmer }, { 30, SHARD.lglimmer }, { 35, SHARD.sglow }, { 40, SHARD.lglow },
    { 45, SHARD.sradiant }, { 50, SHARD.lradiant }, { 55, SHARD.sbrilliant }, { 65, SHARD.lbrilliant },
}

local EPIC_BANDS = {
    { 45, SHARD.sradiant, 3 }, { 50, SHARD.lradiant, 3 }, { 55, SHARD.sbrilliant, 3 },
    { 60, SHARD.nexus, 1 }, { 65, SHARD.nexus, 1.5 },
}

local WEAPON, ARMOR = 2, 4
local NOT_DISENCHANTABLE = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- Lista { {material, chance, quantidade}, ... } ou nil.
local function Yields(quality, level, classID)
    if quality == 2 then
        if level < 5 then
            return nil
        end
        for _, band in ipairs(GREEN_BANDS) do
            if level <= band[1] then
                return Green(band[2], band[3], band[4], band[5], band[6], band[7] or 0, classID == WEAPON)
            end
        end
    elseif quality == 3 then
        for _, band in ipairs(BLUE_BANDS) do
            if level <= band[1] then
                return { { band[2], 1, 1 } }
            end
        end
    elseif quality == 4 and level >= 40 then
        for _, band in ipairs(EPIC_BANDS) do
            if level <= band[1] then
                return { { band[2], 1, band[3] } }
            end
        end
    end
end

-- Essências: { menor, maior }
local ESSENCE_PAIRS = {
    { ESS.lmagic, ESS.gmagic }, { ESS.lastral, ESS.gastral }, { ESS.lmystic, ESS.gmystic },
    { ESS.lnether, ESS.gnether }, { ESS.leternal, ESS.geternal },
}

-- Preços --------------------------------------------------------------------------------

local function Today()
    return tonumber(date("%Y%m%d"))
end

-- Mediana das SAMPLE unidades mais baratas. listings ordenados por preço.
local function Median(listings)
    local picked = {}
    for _, listing in ipairs(listings) do
        for _ = 1, math.min(listing[2], SAMPLE - #picked) do
            picked[#picked + 1] = listing[1]
        end
        if #picked >= SAMPLE then
            break
        end
    end
    return picked[math.ceil(#picked / 2)]
end

-- Preço normal: mediana das medianas dos dias anteriores a hoje.
local function Normal(itemID)
    local entry = db.history[itemID]
    if not entry then
        return nil, 0
    end
    local days = {}
    for index, value in ipairs(entry.m) do
        if not (index == #entry.m and entry.d == Today()) then
            days[#days + 1] = value
        end
    end
    if #days < MIN_DAYS then
        return nil, #days
    end
    table.sort(days)
    return days[math.ceil(#days / 2)], #days
end

local function Remember(itemID, median)
    local entry = db.history[itemID]
    local today = Today()
    if not entry then
        db.history[itemID] = { d = today, m = { median } }
        return
    end
    if entry.d == today then
        entry.m[#entry.m] = median
    else
        entry.d = today
        entry.m[#entry.m + 1] = median
        while #entry.m > HISTORY_DAYS do
            table.remove(entry.m, 1)
        end
    end
end

-- Análise -------------------------------------------------------------------------------

local byItem         -- itemID -> { {unit, qty}, ... } do scan em andamento
local snapshot       -- o último scan desta sessão, para refazer a análise
local medians = {}   -- itemID -> mediana do último scan

-- Preço de venda de um material: o do scan, ou o normal.
local function SellPrice(itemID)
    return medians[itemID] or Normal(itemID)
end

-- Soma dos anúncios abaixo de `limit`: quantidade, custo, lucro vendendo a `value`.
local function Below(listings, limit, value)
    local qty, cost, profit, best = 0, 0, 0, nil
    for _, listing in ipairs(listings) do
        local unit, count = listing[1], listing[2]
        if unit > limit then
            break
        end
        qty = qty + count
        cost = cost + unit * count
        profit = profit + (value - unit) * count
        best = best or unit
    end
    return qty, cost, profit, best
end

-- A análise roda em partes (CHUNK itens por frame), como a leitura do scan: um scan tem
-- dezenas de milhares de itens e fazer tudo de uma vez trava o jogo.
local CHUNK = 400

local results = {}   -- itemID -> oportunidades deste item (revenda, vendedor, desencantar)
local missing = {}   -- itemID -> true: arma/armadura esperando informação do jogo
local dirty = {}     -- itemID -> true: a informação chegou, refazer este item
local job = 0        -- muda a cada análise nova; uma parte com número velho para

-- Oportunidades de um item só (sem as essências, que olham pares de itens).
local function AnalyzeItem(itemID, listings)
    local found = {}
    -- Revenda
    local normal, days = Normal(itemID)
    if normal and listings[1][1] <= normal * FLIP_BELOW then
        local qty, cost, profit, best = Below(listings, normal * FLIP_BELOW, normal * AH_CUT)
        if profit >= MIN_PROFIT.flip then
            found[#found + 1] = {
                kind = "flip", item = itemID, qty = qty, cost = cost, profit = profit,
                best = best, value = normal, days = days,
            }
        end
    end

    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
    local _, _, quality, level, _, _, _, _, _, _, vendor = C_Item.GetItemInfo(itemID)
    -- Pede ao jogo uma vez só por item: o retorno chega pelo evento e refaz só ele.
    if quality == nil and (classID == WEAPON or classID == ARMOR) then
        if missing[itemID] == nil then
            missing[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    else
        missing[itemID] = nil
    end

    -- Vendedor
    if vendor and vendor > 0 and listings[1][1] < vendor then
        local qty, cost, profit, best = Below(listings, vendor - 1, vendor)
        if profit >= MIN_PROFIT.vendor then
            found[#found + 1] = {
                kind = "vendor", item = itemID, qty = qty, cost = cost, profit = profit,
                best = best, value = vendor,
            }
        end
    end

    -- Desencantar
    if quality and level and (classID == WEAPON or classID == ARMOR) and not NOT_DISENCHANTABLE[equipLoc] then
        local yields = Yields(quality, level, classID)
        if yields then
            local value, known = 0, true
            for _, yield in ipairs(yields) do
                local price = SellPrice(yield[1])
                if price then
                    value = value + yield[2] * yield[3] * price
                elseif yield[2] >= 0.5 then
                    known = false
                end
            end
            value = value * AH_CUT
            if known and value > 0 and listings[1][1] < value then
                local qty, cost, profit, best = Below(listings, value - 1, value)
                if profit >= MIN_PROFIT.disenchant then
                    found[#found + 1] = {
                        kind = "disenchant", item = itemID, qty = qty, cost = cost, profit = profit,
                        best = best, value = value, yields = yields,
                    }
                end
            end
        end
    end
    results[itemID] = #found > 0 and found or nil
end

local function Essences(found)
    for _, pair in ipairs(ESSENCE_PAIRS) do
        local lesser, greater = pair[1], pair[2]
        local lesserSell, greaterSell = SellPrice(lesser), SellPrice(greater)
        if greaterSell and snapshot[lesser] then
            -- 3 menores compradas viram 1 maior
            local limit = greaterSell * AH_CUT / 3
            local qty, cost, profit, best = Below(snapshot[lesser], limit, limit)
            qty = qty - qty % 3
            if qty >= 3 and profit >= MIN_PROFIT.essence then
                found[#found + 1] = {
                    kind = "essence", item = lesser, into = greater, ratio = 3, qty = qty, cost = cost,
                    profit = profit, best = best, value = greaterSell,
                }
            end
        end
        if lesserSell and snapshot[greater] then
            -- 1 maior comprada vira 3 menores
            local limit = lesserSell * AH_CUT * 3
            local qty, cost, profit, best = Below(snapshot[greater], limit, limit)
            if qty >= 1 and profit >= MIN_PROFIT.essence then
                found[#found + 1] = {
                    kind = "essence", item = greater, into = lesser, ratio = 1 / 3, qty = qty, cost = cost,
                    profit = profit, best = best, value = lesserSell,
                }
            end
        end
    end
end

-- Junta os resultados por item com as essências e ordena: barato, roda a qualquer hora.
local function Rebuild()
    if not snapshot then
        return
    end
    local found = {}
    for _, list in pairs(results) do
        for _, entry in ipairs(list) do
            found[#found + 1] = entry
        end
    end
    Essences(found)
    table.sort(found, function(a, b)
        return a.profit > b.profit
    end)
    db.found = found
    db.analyzedAt = time()
    Market.Refresh()
end

-- Percorre `keys` em partes chamando each(itemID); no fim chama done().
local function InChunks(keys, each, done)
    local myJob = job
    local index = 0
    local function Step()
        if myJob ~= job then
            return
        end
        local last = math.min(index + CHUNK, #keys)
        for i = index + 1, last do
            each(keys[i])
        end
        index = last
        if index < #keys then
            C_Timer.After(0, Step)
        else
            done()
        end
    end
    Step()
end

-- Scan novo: ordena e tira a mediana de cada item (o desencanto precisa dos preços dos
-- materiais), depois analisa item por item.
local function AnalyzeAll(onDone)
    job = job + 1
    results, missing, dirty = {}, {}, {}
    local keys = {}
    for itemID in pairs(snapshot) do
        keys[#keys + 1] = itemID
    end
    InChunks(keys, function(itemID)
        local listings = snapshot[itemID]
        table.sort(listings, function(a, b)
            return a[1] < b[1]
        end)
        local median = Median(listings)
        medians[itemID] = median
        Remember(itemID, median)
    end, function()
        InChunks(keys, function(itemID)
            AnalyzeItem(itemID, snapshot[itemID])
        end, function()
            Rebuild()
            if onDone then
                onDone()
            end
        end)
    end)
end

AH.AddListener({
    begin = function()
        byItem = {}
    end,
    row = function(_, itemID, count, buyout)
        local list = byItem[itemID]
        if not list then
            list = {}
            byItem[itemID] = list
        end
        list[#list + 1] = { buyout / count, count }
    end,
    finish = function()
        if not byItem then
            return
        end
        medians = {}
        snapshot, byItem = byItem, nil
        AnalyzeAll(function()
            local count = #db.found
            if count > 0 then
                Qolly.Print(("Mercado: %d oportunidades. Veja no painel Qolly da AH > Oportunidades."):format(count))
            end
        end)
    end,
})

-- Informação de item chegou. Se é um item que esperávamos, refaz só ele; com a página
-- aberta, redesenha (nomes que ainda eram "item 16203"). Outros addons pedem milhares
-- de itens (a página de melhorias, por exemplo): o resto é ignorado.
local infoTimer
local infoEvents = CreateFrame("Frame")
infoEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
infoEvents:SetScript("OnEvent", function(_, _, itemID)
    local wanted = itemID and missing[itemID]
    if wanted then
        missing[itemID] = false
        dirty[itemID] = true
    end
    if infoTimer or not (wanted or Market.IsOpen()) then
        return
    end
    infoTimer = C_Timer.NewTimer(1, function()
        infoTimer = nil
        if next(dirty) and snapshot then
            local list = dirty
            dirty = {}
            for id in pairs(list) do
                if snapshot[id] then
                    Qolly.Safe("mercado", AnalyzeItem, id, snapshot[id])
                end
            end
            Qolly.Safe("mercado", Rebuild)
        elseif Market.IsOpen() then
            Qolly.Safe("mercado", Market.Refresh)
        end
    end)
end)

-- Página ---------------------------------------------------------------------------------

local KINDS = {
    { key = "all", label = "Tudo" },
    { key = "flip", label = "Revenda", tag = "|cff66ccffrevenda|r" },
    { key = "disenchant", label = "Desencantar", tag = "|cffcc88ffdesencantar|r" },
    { key = "vendor", label = "Vendedor", tag = "|cffffcc66vendedor|r" },
    { key = "essence", label = "Essências", tag = "|cff88ff88essência|r" },
}
local TAGS = {}
for _, kind in ipairs(KINDS) do
    TAGS[kind.key] = kind.tag
end

local ROW_HEIGHT = 24
local frame, rows, filter = nil, {}, "all"

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return "item " .. itemID
    end
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and (color.hex .. name .. "|r") or name, name
end

local function Plan(entry)
    if entry.kind == "flip" then
        return ("compre %d até %s, revenda a ~%s"):format(entry.qty, Qolly.Money(entry.best), Qolly.Money(entry.value))
    elseif entry.kind == "vendor" then
        return ("compre %d, o NPC paga %s cada"):format(entry.qty, Qolly.Money(entry.value))
    elseif entry.kind == "disenchant" then
        return ("compre %d a partir de %s, vale ~%s desencantado"):format(entry.qty, Qolly.Money(entry.best), Qolly.Money(entry.value))
    end
    local into = select(2, ItemName(entry.into)) or ("item " .. entry.into)
    if entry.ratio == 3 then
        return ("compre %d, junte de 3 em 3 em %s"):format(entry.qty, into)
    end
    return ("compre %d, quebre cada uma em 3 %s"):format(entry.qty, into)
end

local function ShowTip(row)
    local entry = row.entry
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(entry.item)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Qolly.TAG .. Plan(entry), 0.4, 0.8, 1, true)
    GameTooltip:AddDoubleLine("Custo", Qolly.Money(entry.cost), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Lucro esperado", Qolly.Money(entry.profit), 1, 1, 1, 0.4, 1, 0.4)
    if entry.kind == "flip" then
        GameTooltip:AddLine(("Preço normal: mediana de %d dias de scan. Não garante que vende rápido."):format(entry.days), 0.7, 0.7, 0.7, true)
    elseif entry.kind == "disenchant" then
        GameTooltip:AddLine("Rende em média (já sem os 5% da AH):", 0.8, 0.8, 0.8)
        for _, yield in ipairs(entry.yields) do
            local price = SellPrice(yield[1])
            GameTooltip:AddDoubleLine(("%d%%  %.1fx %s"):format(yield[2] * 100, yield[3], select(2, ItemName(yield[1])) or "?"),
                price and Qolly.Money(price) or "sem preço", 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddLine("Precisa de Encantamento no nível do item. É sorte: a média vale para muitos itens.", 0.7, 0.7, 0.7, true)
    elseif entry.kind == "essence" then
        GameTooltip:AddLine("Botão direito na essência converte, sem precisar de Encantamento.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(Qolly.TAG .. "clique: buscar na AH", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Row(index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Button", nil, frame.content)
    row:SetHeight(ROW_HEIGHT)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.profit:SetPoint("RIGHT", -6, 0)
    row.profit:SetWidth(110)
    row.profit:SetJustifyH("RIGHT")
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tag:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.tag:SetWidth(80)
    row.tag:SetJustifyH("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.tag, "RIGHT", 4, 0)
    row.name:SetWidth(220)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.plan = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.plan:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.plan:SetPoint("RIGHT", row.profit, "LEFT", -6, 0)
    row.plan:SetJustifyH("LEFT")
    row.plan:SetWordWrap(false)
    row:SetScript("OnEnter", ShowTip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        local _, plain = ItemName(self.entry.item)
        if plain then
            AH.Browse(plain)
        end
    end)
    rows[index] = row
    return row
end

function Market.Refresh()
    if not frame or not frame:IsVisible() then
        return
    end
    local found = db.found or {}
    local shown, total = 0, 0
    local width = frame.scroll:GetWidth()
    for _, entry in ipairs(found) do
        if filter == "all" or entry.kind == filter then
            shown = shown + 1
            total = total + entry.profit
            local row = Row(shown)
            row.entry = entry
            row.icon:SetTexture(C_Item.GetItemIconByID(entry.item) or 134400)
            row.tag:SetText(TAGS[entry.kind])
            row.name:SetText((ItemName(entry.item)))
            row.plan:SetText(Plan(entry))
            row.profit:SetText("|cff66ff66+" .. Qolly.Money(entry.profit) .. "|r")
            row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -(shown - 1) * ROW_HEIGHT)
            row:SetWidth(width)
            row:Show()
        end
    end
    for index = shown + 1, #rows do
        rows[index]:Hide()
    end
    frame.content:SetSize(width, math.max(1, shown * ROW_HEIGHT))
    local days = 0
    for _, entry in pairs(db.history) do
        days = math.max(days, #entry.m)
    end
    if not db.analyzedAt then
        frame.status:SetText("Faça um scan da AH (botão à esquerda) para achar oportunidades.")
    else
        frame.status:SetText(("%d oportunidades, lucro somado %s  ·  análise há %s  ·  histórico de %d dia(s)%s"):format(
            shown, Qolly.Money(total), Qolly.Ago(time() - db.analyzedAt), days,
            days <= MIN_DAYS and " (a revenda precisa de 3 dias de scan)" or ""))
    end
    for _, button in ipairs(frame.filters) do
        if button.key == filter then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
end

local function CreatePage(parent)
    frame = CreateFrame("Frame", "QollyMarketPage", parent)
    frame.filters = {}
    local previous
    for _, kind in ipairs(KINDS) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(96, 22)
        button:SetText(kind.label)
        button.key = kind.key
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
        end
        button:SetScript("OnClick", function()
            filter = kind.key
            Market.Refresh()
        end)
        frame.filters[#frame.filters + 1] = button
        previous = button
    end
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -34)
    frame.status:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.status:SetJustifyH("LEFT")
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -52)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 6)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(1, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame:SetScript("OnShow", Market.Refresh)
end

function Market.IsOpen()
    return frame ~= nil and frame:IsVisible()
end

function Market.Embed(parent)
    if not frame then
        CreatePage(parent)
    end
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetAllPoints(parent)
    C_Timer.After(0, Market.Refresh)
    return frame
end

Qolly.RegisterModule("mercado", {
    help = "(as 5 melhores oportunidades do último scan da AH)",
    command = function()
        local found = db.found or {}
        if #found == 0 then
            Qolly.Print("Nenhuma oportunidade. Faça um scan da AH.")
            return
        end
        for index = 1, math.min(5, #found) do
            local entry = found[index]
            Qolly.Print(("%s %s: %s  |cff66ff66+%s|r"):format(TAGS[entry.kind], select(1, ItemName(entry.item)), Plan(entry), Qolly.Money(entry.profit)))
        end
    end,
    init = function(saved)
        db = saved
        db.history = db.history or {}
        db.found = db.found or {}
    end,
})
