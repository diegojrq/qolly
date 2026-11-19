-- Ícone ✓/✗ ao lado do nome de cada receita na lista da esquerda.
-- As linhas são da Blizzard e recicladas pelo ScrollBox: nada nelas é alterado, só ganham
-- uma textura nossa. Linha nova chega pelo callback OnInitializedFrame do ScrollBox; um
-- scan novo repinta as linhas visíveis com ForEachFrame.
local _, Qolly = ...
local Craft = Qolly.Craft
local Recipe = Craft.Recipe

local RecipeRows = {}
Craft.RecipeRows = RecipeRows

local ICON_SIZE = 14
local ICONS = {
    profit = "Interface\\RaidFrame\\ReadyCheck-Ready",
    loss = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    -- Tem lucro, mas algum mat ficou sem preço: pode não ser lucro de verdade.
    unsure = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local scrollBox
-- linha -> textura. Chaves fracas: as linhas são da Blizzard.
local icons = setmetatable({}, { __mode = "k" })
-- recipeID -> { version, kind } para não recalcular a cada scroll.
local cache = {}

local function RecipeIDOf(elementData)
    local data = elementData
    if type(elementData) == "table" and elementData.GetData then
        data = elementData:GetData()
    end
    local info = type(data) == "table" and data.recipeInfo
    if type(info) == "table" and not Qolly.IsSecret(info.recipeID) then
        return info.recipeID
    end
end

-- "profit", "loss", "unsure" ou nil quando não dá para saber (sem preço de venda).
local function KindOf(recipeID)
    local cached = cache[recipeID]
    if cached and cached.version == Craft.version then
        return cached.kind
    end
    local kind
    local recipe = Craft.db.scanTime and Recipe.Read(recipeID)
    if recipe and recipe.outputItemID then
        local result = Recipe.Evaluate(recipe)
        if result.profit then
            if result.profit < 0 then
                kind = "loss"
            elseif result.missing > 0 then
                kind = "unsure"
            else
                kind = "profit"
            end
        end
    end
    cache[recipeID] = { version = Craft.version, kind = kind }
    return kind
end

local function Paint(row, elementData)
    local recipeID = RecipeIDOf(elementData or row:GetElementData())
    local kind = recipeID and KindOf(recipeID)
    local icon = icons[row]
    if not kind then
        if icon then
            icon:Hide()
        end
        return
    end
    if not icon then
        icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icons[row] = icon
    end
    icon:SetTexture(ICONS[kind])

    -- Logo depois do fim do texto do nome; sem o Label, no fim da linha.
    icon:ClearAllPoints()
    local label = row.Label
    if label and label.GetStringWidth then
        local width = label:GetStringWidth()
        local box = label:GetWidth()
        if box and box > 0 and box < width then
            width = box
        end
        icon:SetPoint("LEFT", label, "LEFT", width + 3, 0)
    else
        icon:SetPoint("RIGHT", row, "RIGHT", -40, 0)
    end
    icon:Show()
end

local function OnInitialized(_, row, elementData)
    Qolly.Safe("ícone da receita", Paint, row, elementData)
end

-- Repinta as linhas visíveis (depois de um scan novo).
function RecipeRows.Refresh()
    if not scrollBox or not scrollBox:IsVisible() then
        return
    end
    scrollBox:ForEachFrame(function(row, elementData)
        Qolly.Safe("ícone da receita", Paint, row, elementData)
    end)
end

function RecipeRows.Attach(page)
    local list = page.RecipeList
    local box = list and list.ScrollBox
    if not box or not box.RegisterCallback or not ScrollBoxListMixin then
        Qolly.Log("Craft: lista de receitas não encontrada, sem ícones.")
        return
    end
    scrollBox = box
    box:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, OnInitialized, RecipeRows)
    RecipeRows.Refresh()
end
