-- Painel de lucro dentro da tela da receita (ProfessionsFrame.CraftingPage.SchematicForm).
local _, Qolly = ...
local Craft = Qolly.Craft
local Recipe = Craft.Recipe

local RecipeUI = {}
Craft.RecipeUI = RecipeUI

-- Posição do painel em relação ao canto inferior esquerdo da tela da receita.
local OFFSET_X, OFFSET_Y = 20, 16
local POLL_SECONDS = 0.25
-- Um preço visto há mais que isso aparece marcado como velho no tooltip.
local STALE_SECONDS = 24 * 3600

local GREEN, RED, GRAY = "|cff33dd33", "|cffff5555", "|cff999999"

local panel
local shownRecipeID, shownVersion
local current -- { recipe, result } da receita na tela, para o tooltip

local function ItemName(itemID)
    local name = C_Item.GetItemNameByID(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        return "item " .. itemID
    end
    return name
end

local function SelectedRecipeID(form)
    local ok, info = pcall(form.GetRecipeInfo, form)
    if ok and type(info) == "table" and not Qolly.IsSecret(info.recipeID) then
        return info.recipeID
    end
end

local function Render(recipeID)
    current = nil
    local recipe = recipeID and Recipe.Read(recipeID)
    if not recipe then
        panel:Hide()
        return
    end
    panel:Show()

    if not Craft.db.scanTime then
        panel.profit:SetText(GRAY .. "Sem preços da AH|r")
        panel.sale:SetText("Abra a AH: aba Qolly, Scan da AH")
        panel.cost:SetText("")
        panel.note:SetText("")
        return
    end

    local result = Recipe.Evaluate(recipe)
    current = { recipe = recipe, result = result }

    if not recipe.outputItemID then
        panel.profit:SetText(GRAY .. "Não gera item vendável|r")
        panel.sale:SetText("")
    elseif not result.profit then
        panel.profit:SetText(GRAY .. "Sem preço de venda na AH|r")
        panel.sale:SetText("")
    else
        local color = result.profit >= 0 and GREEN or RED
        local sign = result.profit >= 0 and "+" or ""
        panel.profit:SetText(("Lucro: %s%s%s|r"):format(color, sign, Qolly.Money(result.profit)))
        local made = recipe.made ~= 1 and (" (x%g)"):format(recipe.made) or ""
        panel.sale:SetText(("Venda: %s%s, -5%% AH"):format(Qolly.Money(result.saleUnit * recipe.made), made))
    end
    panel.cost:SetText("Mats: " .. Qolly.Money(result.cost))

    if result.missing > 0 then
        panel.note:SetText(("%s%d mat(s) sem preço, fora do custo|r"):format(RED, result.missing))
    else
        panel.note:SetText(("%sScan de há %s|r"):format(GRAY, Qolly.Ago(time() - Craft.db.scanTime)))
    end
end

local function SeenNote(seen)
    if seen and time() - seen > STALE_SECONDS then
        return GRAY .. " (de há " .. Qolly.Ago(time() - seen) .. ")|r"
    end
    return ""
end

local function ShowTooltip(self)
    if not current then
        return
    end
    local recipe, result = current.recipe, current.result
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(Qolly.TAG .. "custo da receita")
    for _, line in ipairs(result.lines) do
        local label = ("%dx %s"):format(line.qty, ItemName(line.itemID))
        if line.cost then
            GameTooltip:AddDoubleLine(label .. SeenNote(line.seen), Qolly.Money(line.cost), 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine(label, "sem preço", 1, 1, 1, 1, 0.33, 0.33)
        end
    end
    GameTooltip:AddDoubleLine("Total dos mats", Qolly.Money(result.cost))
    if result.saleUnit then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(ItemName(recipe.outputItemID) .. SeenNote(result.saleSeen),
            Qolly.Money(result.saleUnit) .. " /un", 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Líquido (-5% AH)", Qolly.Money(result.revenue), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Preço = mediana das 10 unidades mais baratas no último scan.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function CreatePanel(form)
    panel = CreateFrame("Frame", nil, form)
    panel:SetSize(230, 64)
    panel:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", OFFSET_X, OFFSET_Y)
    panel:SetFrameLevel(form:GetFrameLevel() + 10)

    local function Line(font, anchor, gap)
        local text = panel:CreateFontString(nil, "OVERLAY", font)
        text:SetJustifyH("LEFT")
        if anchor then
            text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        else
            text:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        end
        return text
    end
    panel.profit = Line("GameFontNormalLarge")
    panel.sale = Line("GameFontHighlightSmall", panel.profit, 3)
    panel.cost = Line("GameFontHighlightSmall", panel.sale, 1)
    panel.note = Line("GameFontDisableSmall", panel.cost, 1)

    -- Hover mostra o detalhe; clique passa para o que estiver embaixo.
    panel:EnableMouse(true)
    if panel.SetMouseClickEnabled then
        panel:SetMouseClickEnabled(false)
    end
    panel:SetScript("OnEnter", ShowTooltip)
    panel:SetScript("OnLeave", GameTooltip_Hide)

    -- O painel é filho da tela da receita, então só consulta enquanto ela está visível.
    local elapsed = POLL_SECONDS
    local watcher = CreateFrame("Frame", nil, form)
    watcher:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < POLL_SECONDS then
            return
        end
        elapsed = 0
        local recipeID = SelectedRecipeID(form)
        if Craft.version ~= shownVersion then
            Qolly.Safe("ícones das receitas", Craft.RecipeRows.Refresh)
        end
        if recipeID ~= shownRecipeID or Craft.version ~= shownVersion then
            shownRecipeID, shownVersion = recipeID, Craft.version
            Qolly.Safe("painel da receita", Render, recipeID)
        end
    end)
end

-- Blizzard_Professions carrega só quando a janela abre pela primeira vez.
function RecipeUI.TryAttach()
    if panel then
        return true
    end
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if not form then
        return false
    end
    CreatePanel(form)
    Qolly.Log("Craft: painel preso na tela da receita.")
    Qolly.Safe("ícones das receitas", Craft.RecipeRows.Attach, page)
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self)
    if Qolly.Safe("painel da receita", RecipeUI.TryAttach) and panel then
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
