-- Craft: lucro de receitas com os preços do scan da AH.
local _, Qolly = ...
local Craft = Qolly.Craft
local AH = Qolly.AH

-- Sobe a cada scan gravado; o painel e os ícones da receita redesenham quando muda.
Craft.version = 0

function Craft.OnPricesChanged()
    Craft.version = Craft.version + 1
end

local aggregator

AH.AddListener({
    begin = function()
        aggregator = Craft.Prices.NewAggregator()
    end,
    row = function(_, itemID, count, buyout)
        aggregator.Add(itemID, buyout / count, count)
    end,
    finish = function()
        local count = aggregator.Commit()
        aggregator = nil
        Qolly.Print(("Craft: %d itens com preço."):format(count))
        Craft.OnPricesChanged()
    end,
})

local function CountPrices()
    local count = 0
    for _ in pairs(Craft.db.prices) do
        count = count + 1
    end
    return count
end

local function PrintStatus()
    local db = Craft.db
    if not db.scanTime then
        Qolly.Print("Nenhum scan da AH ainda. Abra a AH, aba Qolly, e clique em Scan da AH.")
        return
    end
    Qolly.Print(("%d itens com preço. Último scan há %s."):format(
        CountPrices(), Qolly.Ago(time() - db.scanTime)))
    local left = AH.CooldownLeft()
    if left > 0 then
        Qolly.Print("Próximo scan liberado em " .. Qolly.Ago(left) .. ".")
    end
end

-- Aceita link de item (shift+clique) ou o id.
local function PrintPrice(argument)
    local itemID = tonumber(argument:match("item:(%d+)") or argument)
    if not itemID then
        Qolly.Print("Uso: /qolly craft price <link do item ou id>")
        return
    end
    local unit, seen = Craft.Prices.Get(itemID)
    if unit then
        Qolly.Print(("%s: %s /un (visto há %s)"):format(argument, Qolly.Money(unit), Qolly.Ago(time() - seen)))
    else
        Qolly.Print(argument .. ": sem preço no scan.")
    end
end

local function Command(input)
    local command, argument = strtrim(input):match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "scan" then
        AH.Request()
    elseif command == "price" then
        PrintPrice(argument)
    elseif command == "status" then
        PrintStatus()
    else
        Qolly.Print("Craft: /qolly craft scan | price <item> | status")
    end
end

Qolly.RegisterModule("craft", {
    help = "scan | price <item> | status",
    command = Command,
    init = function(moduleDB)
        Craft.db = moduleDB
        moduleDB.prices = moduleDB.prices or {}
        -- O cooldown do scan agora mora no módulo ah (que inicia antes, pela ordem do .toc).
        if moduleDB.lastScanRequest then
            AH.db.lastScanRequest = math.max(AH.db.lastScanRequest or 0, moduleDB.lastScanRequest)
            moduleDB.lastScanRequest = nil
        end
    end,
})
