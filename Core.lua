local ADDON_NAME, Qolly = ...

local PREFIX = "|cff66ccffQolly:|r "
local MAX_LOG_LINES = 1000

-- Marca das linhas de tooltip que são do Qolly, para não confundir com outros addons.
Qolly.TAG = "|cff66ccff||Qy|||r "  -- "||" é a barra literal no texto do jogo

Qolly.modules = {}
Qolly.moduleOrder = {}

-- O WoW só grava QollyDB em disco no /reload ou ao deslogar:
-- _forever_\WTF\Account\<CONTA>\SavedVariables\Qolly.lua
function Qolly.Log(message)
    if not QollyDB then
        return
    end
    QollyDB.log = QollyDB.log or {}
    table.insert(QollyDB.log, date("%Y-%m-%d %H:%M:%S") .. " " .. message)
    while #QollyDB.log > MAX_LOG_LINES do
        table.remove(QollyDB.log, 1)
    end
end

-- O empacotador troca @project-version@ pela tag; numa cópia direto do repositório fica "dev".
function Qolly.Version()
    local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "?"
    if version:find("^@") then return "dev" end
    return version
end

function Qolly.Print(message)
    print(PREFIX .. message)
    Qolly.Log(message)
end

-- Valores secretos do Midnight dão erro de Lua se forem comparados, concatenados
-- ou usados como chave.
function Qolly.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function Qolly.Describe(value)
    if Qolly.IsSecret(value) then
        return "<SECRETO>"
    end
    return tostring(value)
end

local function DescribeError(failure)
    return Qolly.Describe(failure) .. "\n" .. debugstack(2)
end

-- Roda fn protegido: um erro vai para o chat e para o log com a pilha, em vez de
-- interromper o handler que chamou.
function Qolly.Safe(label, fn, ...)
    local ok, failure = xpcall(fn, DescribeError, ...)
    if not ok then
        Qolly.Print("ERRO em " .. label .. ": " .. failure)
    end
    return ok
end

-- Cobre em ouro com os ícones de moeda; negativo ganha "-".
function Qolly.Money(copper)
    copper = math.floor(copper + 0.5)
    if copper == 0 then
        return "0"
    end
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    if GetMoneyString then
        return sign .. GetMoneyString(copper, true)
    end
    return ("%s%dg %ds %dc"):format(sign, copper / 10000, (copper / 100) % 100, copper % 100)
end

-- Duração curta em português: "agora", "12m", "3h", "2d".
function Qolly.Ago(seconds)
    if seconds < 60 then
        return "agora"
    elseif seconds < 3600 then
        return ("%dm"):format(seconds / 60)
    elseif seconds < 86400 then
        return ("%dh"):format(seconds / 3600)
    end
    return ("%dd"):format(seconds / 86400)
end

-- Um módulo é { help = "linha de ajuda", command = function(argument), init = function(db) }.
-- init roda depois que QollyDB carregou e recebe a tabela do módulo dentro dele.
-- O módulo responde a "/qolly <nome> ...".
function Qolly.RegisterModule(name, module)
    Qolly.modules[name] = module
    table.insert(Qolly.moduleOrder, name)
end

local function PrintHelp()
    Qolly.Print("Comandos:")
    for _, name in ipairs(Qolly.moduleOrder) do
        Qolly.Print(("   /qolly %s %s"):format(name, Qolly.modules[name].help))
    end
    Qolly.Print("   /qolly clearlog")
end

local function RunSlash(input)
    Qolly.Log("> /qolly " .. input)
    local command, argument = strtrim(input):match("^(%S*)%s*(.-)$")
    command = command:lower()

    local module = Qolly.modules[command]
    if module and module.command then
        module.command(argument)
    elseif command == "clearlog" then
        QollyDB.log = {}
        Qolly.Print("Log limpo.")
    else
        PrintHelp()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon ~= ADDON_NAME then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    QollyDB = QollyDB or {}
    Qolly.Log("--- addon carregado ---")

    for _, name in ipairs(Qolly.moduleOrder) do
        local module = Qolly.modules[name]
        if module.init then
            QollyDB[name] = QollyDB[name] or {}
            Qolly.Safe("init de " .. name, module.init, QollyDB[name])
        end
    end

    SLASH_QOLLY1 = "/qolly"
    SlashCmdList.QOLLY = function(input)
        Qolly.Safe("/qolly", RunSlash, input)
    end

    -- A versão vem do .toc: se o chat mostra uma velha, o jogo não releu os arquivos.
    local version = Qolly.Version()
    local names = table.concat(Qolly.moduleOrder, ", ")
    Qolly.Print(("v%s carregado (%s). Digite /qolly para os comandos."):format(version, names))
end)

-- Avisos no alto da tela -------------------------------------------------------------
-- Faixas finas empilhadas no topo, no centro: [|Qy| título] [conteúdo] [x].
-- Um aviso com botão seguro (lançar magia) não pode se mexer em combate: a pilha
-- espera o combate acabar para se reorganizar.

local NOTICE_TOP, NOTICE_GAP = -6, 4
local notices = {}
local noticesPending = false

local function LayoutNotices()
    if InCombatLockdown() then
        for _, frame in ipairs(notices) do
            if frame:IsProtected() then
                noticesPending = true
                return
            end
        end
    end
    noticesPending = false
    local y = NOTICE_TOP
    for _, frame in ipairs(notices) do
        if frame:IsShown() then
            frame:ClearAllPoints()
            frame:SetPoint("TOP", UIParent, "TOP", 0, y)
            y = y - frame:GetHeight() - NOTICE_GAP
        end
    end
end
Qolly.LayoutNotices = LayoutNotices

local noticeEvents = CreateFrame("Frame")
noticeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
noticeEvents:SetScript("OnEvent", function()
    if noticesPending then
        LayoutNotices()
    end
end)

-- Põe um frame que já existe na pilha do alto.
function Qolly.StackNotice(frame)
    notices[#notices + 1] = frame
    frame:HookScript("OnShow", LayoutNotices)
    frame:HookScript("OnHide", LayoutNotices)
    frame:HookScript("OnSizeChanged", LayoutNotices)
    LayoutNotices()
end

local NOTICE_BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

function Qolly.StyleNotice(frame)
    frame:SetBackdrop(NOTICE_BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.8)
    frame:SetBackdropBorderColor(1, 0.82, 0, 0.5)
end

-- Aviso novo com título. onClose: um "x" à direita que chama a função.
-- O conteúdo vai à direita de frame.title; frame:Fit(largura do conteúdo) ajusta.
function Qolly.Notice(name, title, onClose)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetHeight(32)
    frame:SetFrameStrata("HIGH")
    Qolly.StyleNotice(frame)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame, "LEFT", 10, 0)
    frame.title:SetText(Qolly.TAG .. title)
    local right = 10
    if onClose then
        local ok, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButtonNoScripts")
        if not ok then
            close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        end
        close:SetSize(22, 22)
        close:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        close:SetScript("OnClick", onClose)
        frame.close = close
        right = 30
    end
    -- Onde o conteúdo começa, medido da borda esquerda do aviso. Botões protegidos
    -- (lançar magia) não podem se prender ao texto do título, só ao aviso.
    function frame:ContentLeft()
        return 10 + self.title:GetStringWidth() + 10
    end
    function frame:Fit(contentWidth)
        self:SetWidth(10 + self.title:GetStringWidth() + 10 + contentWidth + right)
    end
    frame:Fit(0)
    frame:Hide()
    Qolly.StackNotice(frame)
    return frame
end

-- Abas laterais -------------------------------------------------------------------------
-- Botão quadrado com ícone, preso na borda direita de uma janela (grimório, AH, ...),
-- no lugar de uma aba na fileira de cima: não depende de como a janela foi montada,
-- então funciona com interfaces que trocam o visual todo (ElvUI, EllesmereUI).

local SIDE_BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
Qolly.SIDE_BACKDROP = SIDE_BACKDROP

-- tab:SetActive(bool) acende/apaga; tab:SetCount(n) mostra um número no canto.
function Qolly.SideTab(parent, icon, title, tip, onClick)
    local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tab:SetSize(40, 40)
    tab:SetBackdrop(SIDE_BACKDROP)
    tab:SetBackdropColor(0, 0, 0, 0.85)
    tab:SetBackdropBorderColor(1, 0.82, 0, 0.7)
    tab:SetFrameLevel(parent:GetFrameLevel() + 10)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetPoint("TOPLEFT", 5, -5)
    tab.icon:SetPoint("BOTTOMRIGHT", -5, 5)
    tab.icon:SetTexture(icon)
    tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tab.glow = tab:CreateTexture(nil, "OVERLAY")
    tab.glow:SetPoint("TOPLEFT", -6, 6)
    tab.glow:SetPoint("BOTTOMRIGHT", 6, -6)
    tab.glow:SetTexture("Interface/Buttons/CheckButtonHilight")
    tab.glow:SetBlendMode("ADD")
    tab.glow:Hide()
    tab:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
    tab.count = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    tab.count:SetPoint("BOTTOMRIGHT", -3, 3)
    tab:SetScript("OnClick", function(self)
        Qolly.Safe(title, onClick, self)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Qolly.TAG .. title)
        if tip then
            GameTooltip:AddLine(tip, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    function tab:SetActive(active)
        self.glow:SetShown(active and true or false)
    end
    function tab:SetCount(count)
        self.count:SetText((count and count > 0) and count or "")
    end
    return tab
end

-- Painel ao lado de uma janela: título, "x" e panel.body para o conteúdo.
function Qolly.SidePanel(parent, name, title, width, onClose)
    local panel = CreateFrame("Frame", name, parent, "BackdropTemplate")
    panel:SetWidth(width)
    panel:SetBackdrop(SIDE_BACKDROP)
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    panel:SetBackdropBorderColor(1, 0.82, 0, 0.6)
    panel:EnableMouse(true)
    panel:SetFrameLevel(parent:GetFrameLevel() + 5)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetText(Qolly.TAG .. title)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        if onClose then
            onClose()
        else
            panel:Hide()
        end
    end)
    panel.close = close
    panel.body = CreateFrame("Frame", nil, panel)
    panel.body:SetPoint("TOPLEFT", 8, -40)
    panel.body:SetPoint("BOTTOMRIGHT", -8, 8)
    panel:Hide()
    return panel
end
