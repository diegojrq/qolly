-- Lê uma receita da profissão e calcula o lucro de craftar e vender na AH.
local _, Qolly = ...
local Craft = Qolly.Craft
local Prices = Craft.Prices

local Recipe = {}
Craft.Recipe = Recipe

-- Comissão da AH sobre a venda (5%, a mesma que o CraftProfit mediu neste client).
Recipe.AH_CUT = 0.05

local function Plain(value)
    if Qolly.IsSecret(value) then
        return nil
    end
    return value
end

-- { outputItemID, made, reagents = { { qty, options = {itemID, ...} } } } ou nil.
-- options são as variantes de qualidade do mesmo slot; vale a mais barata.
function Recipe.Read(recipeID)
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or type(schematic) ~= "table" then
        return nil
    end

    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local reagents = {}
    for _, slot in ipairs(Plain(schematic.reagentSlotSchematics) or {}) do
        -- Só reagentes obrigatórios; slots opcionais e de acabamento não entram no custo.
        local isBasic
        if basic ~= nil then
            isBasic = Plain(slot.reagentType) == basic
        else
            isBasic = Plain(slot.required) ~= false
        end
        local qty = Plain(slot.quantityRequired)
        if isBasic and qty then
            local options = {}
            for _, reagent in ipairs(Plain(slot.reagents) or {}) do
                local itemID = Plain(reagent.itemID)
                if itemID then
                    options[#options + 1] = itemID
                end
            end
            if #options > 0 then
                reagents[#reagents + 1] = { qty = qty, options = options }
            end
        end
    end

    local low = Plain(schematic.quantityMin) or 1
    local high = Plain(schematic.quantityMax) or low
    return {
        outputItemID = Plain(schematic.outputItemID),
        made = (low + high) / 2,
        reagents = reagents,
    }
end

-- Opção mais barata com preço: itemID, preço por unidade, data. Sem preço: a primeira opção.
local function Cheapest(options)
    local bestID, bestUnit, bestTime
    for _, itemID in ipairs(options) do
        local unit, seen = Prices.Get(itemID)
        if unit and (not bestUnit or unit < bestUnit) then
            bestID, bestUnit, bestTime = itemID, unit, seen
        end
    end
    return bestID or options[1], bestUnit, bestTime
end

-- Custo dos mats, valor de venda líquido e lucro. Mats sem preço ficam em `missing`
-- e não entram no custo, então o lucro fica otimista.
function Recipe.Evaluate(recipe)
    local result = { lines = {}, missing = 0, cost = 0 }

    for _, reagent in ipairs(recipe.reagents) do
        local itemID, unit, seen = Cheapest(reagent.options)
        local line = { itemID = itemID, qty = reagent.qty, unit = unit, seen = seen }
        if unit then
            line.cost = unit * reagent.qty
            result.cost = result.cost + line.cost
        else
            result.missing = result.missing + 1
        end
        result.lines[#result.lines + 1] = line
    end

    local saleUnit, saleSeen = Prices.Get(recipe.outputItemID)
    result.saleUnit, result.saleSeen = saleUnit, saleSeen
    if saleUnit then
        result.revenue = saleUnit * recipe.made * (1 - Recipe.AH_CUT)
        -- Arredondado ao cobre: -0,3c não pode aparecer como "0" vermelho nem virar ✗.
        result.profit = math.floor(result.revenue - result.cost + 0.5)
    end
    return result
end
