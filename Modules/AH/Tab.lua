-- Páginas do Qolly na casa de leilão (melhorias de equipamento, vendas, oportunidades),
-- num painel ao lado da janela da AH com abas laterais, como o painel de treino do
-- grimório. Não mexe na fileira de abas da AH: interfaces que remontam a AH inteira
-- (EllesmereUI, ElvUI) quebravam a aba que ficava lá.
local _, Qolly = ...
local AH = Qolly.AH

local Tab = {}
Qolly.AHTab = Tab

local WIDTH = 760

local PAGES = {
    { key = "upgrades", label = "Melhorias", icon = "Interface/Icons/INV_Chest_Plate06",
        tip = "Equipamentos na AH que melhoram o seu.",
        embed = function(parent) return Qolly.Gear.List.Embed(parent) end },
    { key = "sales", label = "Vendas", icon = "Interface/Icons/INV_Misc_Coin_02",
        tip = "O que você vendeu e o que ainda está anunciado.",
        embed = function(parent) return Qolly.Sales.Embed(parent) end },
    { key = "market", label = "Oportunidades", icon = "Interface/Icons/INV_Enchant_EssenceEternalLarge",
        tip = "Revenda, desencanto, vendedor e essências com lucro.",
        embed = function(parent) return Qolly.Market.Embed(parent) end },
}

local panel, area
local tabs = {}
-- key -> frame da página, depois da primeira vez aberta.
local pages = {}

local function Host()
    return AuctionHouseFrame
end

local function Current()
    return (AH.db and AH.db.page) or "upgrades"
end

local function IsOpen()
    return panel ~= nil and panel:IsShown()
end

local function Layout()
    local host = Host()
    local open = IsOpen()
    local previous
    for _, page in ipairs(PAGES) do
        local tab = tabs[page.key]
        if tab then
            tab:ClearAllPoints()
            if previous then
                tab:SetPoint("TOP", previous, "BOTTOM", 0, -6)
            else
                tab:SetPoint("TOPLEFT", open and panel or host, "TOPRIGHT", open and 8 or 0, -40)
            end
            tab:SetActive(open and page.key == Current())
            previous = tab
        end
    end
end

local function ShowPage(key)
    AH.db.page = key
    for _, page in ipairs(PAGES) do
        if page.key == key then
            panel.pageTitle:SetText(page.label)
            -- Embed devolve o frame da página, já posto dentro da área (a página de
            -- vendas também abre fora da AH, então ela volta para cá a cada vez).
            local ok, frame = pcall(page.embed, area)
            if ok and frame then
                pages[page.key] = frame
                frame:Show()
            elseif not ok then
                Qolly.Print("ERRO no painel Qolly da AH: " .. tostring(frame))
            end
        elseif pages[page.key] and pages[page.key]:GetParent() == area then
            pages[page.key]:Hide()
        end
    end
    Layout()
end

local function CreatePanel()
    local host = Host()
    panel = Qolly.SidePanel(host, "QollyAHPanel", "AH", WIDTH, function()
        Tab.Close()
    end)
    panel:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 2, 0)

    panel.pageTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    panel.pageTitle:SetPoint("LEFT", panel.title, "RIGHT", 8, 0)

    -- Scan completo da AH, no alto, à esquerda do "x".
    local scan = AH.CreateButton(panel)
    scan:SetParent(panel)
    scan:ClearAllPoints()
    scan:SetSize(130, 22)
    scan:SetPoint("RIGHT", panel.close, "LEFT", -4, 0)

    area = CreateFrame("Frame", nil, panel.body)
    area:SetAllPoints(panel.body)
    local background = area:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.35)

    panel:SetScript("OnShow", function()
        ShowPage(Current())
    end)
end

local function Create()
    local host = Host()
    if not host or tabs[PAGES[1].key] then
        return
    end
    CreatePanel()
    for _, page in ipairs(PAGES) do
        tabs[page.key] = Qolly.SideTab(host, page.icon, page.label, page.tip, function()
            if IsOpen() and Current() == page.key then
                Tab.Close()
            else
                Tab.Select(page.key)
            end
        end)
    end
    if AH.db.panelOpen then
        panel:Show()
    end
    Layout()
end

function Tab.Close()
    AH.db.panelOpen = false
    if panel then
        panel:Hide()
    end
    Layout()
end

-- Abre o painel Qolly da AH, numa página se pedida.
function Tab.Select(key)
    if not AH.IsOpen() then
        Qolly.Print("Abra a casa de leilão para ver o painel Qolly.")
        return
    end
    Qolly.Safe("painel Qolly da AH", Create)
    if not panel then
        return
    end
    AH.db.page = key or Current()
    AH.db.panelOpen = true
    if panel:IsShown() then
        ShowPage(AH.db.page)
    else
        panel:Show()
    end
end

AH.AddListener({
    show = function()
        Qolly.Safe("painel Qolly da AH", Create)
    end,
})
