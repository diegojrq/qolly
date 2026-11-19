-- Preços da AH guardados entre sessões: db.prices[itemID] = { unit, quantidade, time() }.
local _, Qolly = ...

local Craft = {}
Qolly.Craft = Craft

local Prices = {}
Craft.Prices = Prices

-- Quantas das unidades mais baratas entram na mediana. Um anúncio isolado muito abaixo
-- do mercado quase não mexe no preço, como mexeria um simples mínimo.
Prices.SAMPLE_UNITS = 10

-- Mediana das SAMPLE_UNITS unidades mais baratas. listings = { {unit, qty}, ... }.
local function Summarize(listings)
    table.sort(listings, function(a, b) return a[1] < b[1] end)
    local picked, total = {}, 0
    for _, listing in ipairs(listings) do
        total = total + listing[2]
        if #picked < Prices.SAMPLE_UNITS then
            for _ = 1, math.min(listing[2], Prices.SAMPLE_UNITS - #picked) do
                picked[#picked + 1] = listing[1]
            end
        end
    end
    return picked[math.ceil(#picked / 2)], total
end

-- Junta anúncios (itemID, preço por unidade, quantidade) e no fim grava um preço por item.
function Prices.NewAggregator()
    local byItem = {}
    local aggregator = { listings = 0 }

    function aggregator.Add(itemID, unit, qty)
        local list = byItem[itemID]
        if not list then
            list = {}
            byItem[itemID] = list
        end
        list[#list + 1] = { unit, qty }
        aggregator.listings = aggregator.listings + 1
    end

    -- Grava no db os itens vistos agora. Itens fora da AH no momento mantêm o preço
    -- antigo com a data dele, para um mat esgotado ainda ter alguma referência.
    function aggregator.Commit()
        local now, count = time(), 0
        for itemID, list in pairs(byItem) do
            local unit, total = Summarize(list)
            Craft.db.prices[itemID] = { unit, total, now }
            count = count + 1
        end
        Craft.db.scanTime = now
        return count
    end

    return aggregator
end

-- Preço por unidade e a data em que foi visto, ou nil.
function Prices.Get(itemID)
    local row = itemID and Craft.db.prices[itemID]
    if row then
        return row[1], row[3]
    end
end

-- Linha de preço da AH no tooltip de qualquer item que apareceu no último scan.
local function OnItem(tooltip, data)
    if not Craft.db or Craft.db.tooltipPrice == false then
        return
    end
    if tooltip:IsForbidden() then
        return
    end
    local itemID = data and data.id
    if type(itemID) ~= "number" or Qolly.IsSecret(itemID) then
        return
    end
    local unit, seen = Prices.Get(itemID)
    if not unit then
        return
    end
    local ago = seen and Qolly.Ago(time() - seen)
    local age = ago and ("  |cff999999%s|r"):format(ago == "agora" and ago or ("há " .. ago)) or ""
    tooltip:AddDoubleLine(Qolly.TAG .. "AH", Qolly.Money(unit) .. age, 1, 0.82, 0, 1, 1, 1)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        -- Sem aviso no chat: um erro aqui repetiria a cada tooltip.
        pcall(OnItem, tooltip, data)
    end)
end
