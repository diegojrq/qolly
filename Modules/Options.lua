-- Configurações do Qolly: botão no minimapa (arrastável pela borda) e uma janela com as
-- opções dos módulos. Carrega depois dos módulos: lê os bancos deles.
local _, Qolly = ...

local Options = {}
Qolly.Options = Options

local ICON = "Interface\\Icons\\INV_Misc_Gear_01"

local db, panel, button

local function Version()
    return Qolly.Version()
end

-- Opções agrupadas por módulo. Cada uma: rótulo, leitura, escrita e dica opcional.
local function Sections()
    local Gather, Radar = Qolly.Gather, Qolly.Radar
    local function RefreshMap()
        if Gather.RefreshWorldMap then
            Gather.RefreshWorldMap()
        end
        if Gather.RefreshTracking then
            Gather.RefreshTracking()
        end
    end
    return {
        {
            title = "Coleta",
            icon = "Interface/Icons/INV_Misc_Flower_02",
            description = "Ervas e minérios no minimapa e no mapa-múndi. Passe o mouse num nó para ver quanto ele vale na AH e a perícia que ele pede.",
            {
                label = "Herborismo",
                tip = "Ervas no minimapa e no mapa-múndi.",
                get = function() return Gather.Shown("herb") end,
                set = function(on) Gather.db.hide.herb = not on; RefreshMap() end,
            },
            {
                label = "Mineração",
                tip = "Veios e depósitos no minimapa e no mapa-múndi.",
                get = function() return Gather.Shown("ore") end,
                set = function(on) Gather.db.hide.ore = not on; RefreshMap() end,
            },
            {
                label = "Mostrar no minimapa",
                get = function() return Gather.db.enabled end,
                set = function(on) Gather.db.enabled = on end,
            },
            {
                label = "Ícone ao lado do nó com o rastreamento ligado",
                tip = "No minimapa, com Encontrar Ervas/Minerais ligado, o ícone vai para a esquerda com uma seta apontando o nó: o pontinho amarelo do jogo na ponta da seta é o nó que existe agora.",
                get = function() return Gather.db.rings ~= false end,
                set = function(on) Gather.db.rings = on end,
            },
            {
                label = "Mostrar no mapa-múndi",
                get = function() return Gather.db.worldMap ~= false end,
                set = function(on) Gather.db.worldMap = on; RefreshMap() end,
            },
            {
                label = "Avisar quando o rastreamento está desligado",
                tip = "Encontrar Ervas / Encontrar Minerais desligado (ou desligado ao morrer): um aviso com botão para ligar. Fechar o aviso cala até você ligar de novo.",
                get = function() return Gather.db.trackingPopup ~= false end,
                set = function(on) Gather.db.trackingPopup = on; RefreshMap() end,
            },
            {
                label = "Usar o banco de nós do GatherLite",
                tip = "Desligado, só aparecem os nós que você coletou.",
                get = function() return Gather.db.useData ~= false end,
                set = function(on) Gather.db.useData = on; RefreshMap() end,
            },
        },
        {
            title = "Radar de inimigos",
            icon = "Interface/Icons/Spell_Holy_MindVision",
            description = "Avisa quando um jogador da facção inimiga aparece por perto, mesmo antes da placa de nome dele aparecer.",
            actions = {
                { label = "Testar o aviso", run = function() Qolly.modules.radar.command("teste") end },
            },
            {
                label = "Avisar quando aparece inimigo",
                get = function() return Radar.db.enabled end,
                set = function(on) Radar.db.enabled = on end,
            },
            {
                label = "Som do aviso",
                get = function() return Radar.db.sound ~= false end,
                set = function(on) Radar.db.sound = on end,
            },
            {
                label = "Marca em cima da placa do inimigo",
                tip = "Só você vê a marca.",
                get = function() return Radar.db.mark ~= false end,
                set = function(on) Radar.db.mark = on end,
            },
        },
        {
            title = "Placas",
            icon = "Interface/Icons/Ability_Hunter_SniperShot",
            description = "Complementos para a placa de nome padrão dos mobs que você pode atacar. Precisa das placas de inimigos ligadas (tecla V).",
            { kind = "preview", create = function(parent) return Qolly.Plates.Preview(parent) end },
            {
                label = "Vida na barra",
                tip = "À esquerda, dentro da barra.",
                get = function() return Qolly.Plates.Get("health") end,
                set = function(on) Qolly.Plates.Set("health", on) end,
            },
            {
                label = "Mostrar também a vida em número",
                tip = "Ex.: 1.2k (72%).",
                get = function() return Qolly.Plates.Get("healthAmount") end,
                set = function(on) Qolly.Plates.Set("healthAmount", on) end,
            },
            {
                label = "Cor da barra pela ameaça",
                tip = "Em combate. Sem ser tanque: vermelho o mob está em você, laranja quase, amarelo você está para puxar. Tanque: verde seguro, laranja perdendo, vermelho em outro.",
                get = function() return Qolly.Plates.Get("threat") end,
                set = function(on) Qolly.Plates.Set("threat", on) end,
            },
            {
                label = "Porcentagem de ameaça",
                tip = "Em combate, à direita da barra: quanto da ameaça do mob é sua (100% = ele vem em você).",
                get = function() return Qolly.Plates.Get("threatPercent") end,
                set = function(on) Qolly.Plates.Set("threatPercent", on) end,
            },
            {
                label = "Substituir os textos da placa padrão",
                tip = "Esconde os números que o jogo põe na barra de vida, para não ficarem dois. O nome do mob continua.",
                get = function() return Qolly.Plates.Get("override") end,
                set = function(on) Qolly.Plates.Set("override", on) end,
            },
            {
                label = "Cast com tempo e alvo",
                tip = "Tempo restante na barra de cast, em quem o mob está lançando (vermelho se for você) e moldura amarela quando dá para interromper.",
                get = function() return Qolly.Plates.Get("cast") end,
                set = function(on) Qolly.Plates.Set("cast", on) end,
            },
            {
                label = "Debuffs com tempo e tamanho ajustável",
                tip = "Os debuffs que a placa padrão mostra ganham os segundos restantes no ícone e o tamanho escolhido abaixo.",
                get = function() return Qolly.Plates.Get("debuffs") end,
                set = function(on) Qolly.Plates.Set("debuffs", on) end,
            },
            {
                kind = "slider", label = "Texto da vida e da ameaça", min = 8, max = 20, step = 1,
                get = function() return Qolly.Plates.GetValue("textSize") end,
                set = function(v) Qolly.Plates.SetValue("textSize", v) end,
            },
            {
                kind = "slider", label = "Texto do cast", min = 8, max = 18, step = 1,
                get = function() return Qolly.Plates.GetValue("castTextSize") end,
                set = function(v) Qolly.Plates.SetValue("castTextSize", v) end,
            },
            {
                kind = "slider", label = "Tamanho dos debuffs", min = 0.6, max = 1.6, step = 0.05,
                format = function(v) return ("%d%%"):format(v * 100 + 0.5) end,
                tip = "100% = tamanho do jogo.",
                get = function() return Qolly.Plates.GetValue("debuffScale") end,
                set = function(v) Qolly.Plates.SetValue("debuffScale", v) end,
            },
            {
                kind = "slider", label = "Número no debuff", min = 6, max = 16, step = 1,
                get = function() return Qolly.Plates.GetValue("debuffFont") end,
                set = function(v) Qolly.Plates.SetValue("debuffFont", v) end,
            },
            {
                label = "Semáforo de aggro nos mobs",
                tip = "Bolinha em cima da placa do mob hostil: verde longe, amarelo perto do raio de aggro, vermelho dentro. Precisa das placas de inimigos ligadas (tecla V).",
                get = function() return Qolly.Aggro.IsEnabled() end,
                set = function(on) Qolly.Aggro.SetEnabled(on) end,
            },
        },
        {
            title = "Equipamento",
            icon = "Interface/Icons/INV_Chest_Chain_05",
            description = "Gear Score na ficha do personagem, melhorias à venda na AH (aba Qolly) e quanto cada item melhora o seu equipamento.",
            {
                label = "Melhoria em % no tooltip do item",
                tip = "Compara com o que está equipado no slot, pelos pesos de atributo do QuestMaster para o seu papel, e mostra quanto o GS muda.",
                get = function() return Qolly.Gear.db.tooltip ~= false end,
                set = function(on) Qolly.Gear.db.tooltip = on end,
            },
        },
        {
            title = "Pesca",
            icon = "Interface/Icons/Trade_Fishing",
            description = "Uma tecla lança a linha e a mesma tecla puxa o peixe. Só age com a vara de pesca equipada; em combate a tecla volta ao normal.",
            {
                label = "Modo pesca: uma tecla lança e puxa",
                tip = "Ligado, a tecla abaixo lança a linha; com a boia na água, a mesma tecla puxa. Aperte quando a boia mexer. Em combate a tecla volta ao normal. Também: /qolly pesca.",
                get = function() return Qolly.Fishing.IsEnabled() end,
                set = function(on) Qolly.Fishing.SetEnabled(on) end,
            },
            {
                kind = "key",
                label = "Tecla da pesca",
                tip = "Clique e aperte a tecla (ou botão do mouse) que quer usar. Esc cancela. Ela só muda de função com o modo pesca ligado.",
            },
            {
                label = "Som da boia em destaque",
                tip = "Com a linha na água, música, ambiente e falas ficam mudos e os efeitos no máximo: o barulho da boia mexendo se destaca. Volta tudo ao tirar a linha.",
                get = function() return QollyDB.pesca.sound ~= false end,
                set = function(on) QollyDB.pesca.sound = on end,
            },
            {
                label = "Saque automático no modo pesca",
                get = function() return QollyDB.pesca.autoLoot ~= false end,
                set = function(on) QollyDB.pesca.autoLoot = on end,
            },
        },
        {
            title = "Ganhos",
            icon = "Interface/Icons/INV_Misc_Coin_02",
            description = "Todo ouro que entra e sai, por origem: missões, saque, lixo, vendedor, AH, correio, reparos... E, na outra aba, cada venda da AH por item e categoria.",
            embed = function(parent) return Qolly.Income.Embed(parent) end,
        },
        {
            title = "Itens de missão",
            icon = "Interface/Icons/INV_Misc_Note_02",
            description = "Itens de missão na bolsa que não servem mais: missão concluída, abandonada ou nenhuma missão conhecida. Confira e apague; nada sai da bolsa sem você confirmar.",
            embed = function(parent) return Qolly.QuestItems.Embed(parent) end,
        },
        {
            title = "Geral",
            icon = "Interface/Icons/INV_Misc_Gear_01",
            description = "Preço da AH nos itens, vender lixo no vendedor e o botão do Qolly no minimapa: clique abre esta janela, Shift+clique abre as vendas, botão do meio liga a pesca e botão direito liga a coleta.",
            {
                label = "Preço da AH no tooltip do item",
                tip = "Mediana das 10 unidades mais baratas no último Scan da AH, e há quanto tempo foi visto.",
                get = function() return Qolly.Craft.db.tooltipPrice ~= false end,
                set = function(on) Qolly.Craft.db.tooltipPrice = on end,
            },
            {
                label = "Botão no minimapa",
                tip = "Desligado, abra esta janela com /qolly config.",
                get = function() return not db.hideButton end,
                set = function(on) db.hideButton = not on; Options.UpdateButton() end,
            },
            {
                label = "Vender lixo ao abrir um vendedor",
                tip = "Vende os itens cinza sozinho e diz quanto rendeu. Segure Shift ao abrir o vendedor para pular. Os mais caros ficam por último, na recompra.",
                get = function() return Qolly.Junk.IsEnabled() end,
                set = function(on) Qolly.Junk.SetEnabled(on) end,
            },
            {
                label = "Avisar buffs de classe faltando",
                tip = "Fora de combate, mostra um ícone para cada buff longo da sua classe que está faltando ou acabando (Intelecto Arcano, Marca do Selvagem, aspectos, escudos...). Clique no ícone para lançar.",
                get = function() return Qolly.Buffs.IsEnabled() end,
                set = function(on) Qolly.Buffs.SetEnabled(on) end,
            },
            {
                label = "Não avisar buffs em cidade/estalagem",
                tip = "Descansando, o aviso de buffs fica escondido.",
                get = function() return Qolly.Buffs.SkipsResting() end,
                set = function(on) Qolly.Buffs.SetSkipResting(on) end,
            },
            {
                label = "Avisar comida com bônus de XP",
                tip = "Entra no aviso de buffs quando falta o Bem Alimentado que dá XP. Coma uma vez e o botão passa a comer a mesma comida. Some no nível máximo.",
                get = function() return Qolly.Buffs.GetOption("foodAlert") end,
                set = function(on) Qolly.Buffs.SetOption("foodAlert", on) end,
            },
            {
                label = "Bônus de XP na barra de experiência",
                tip = "Soma os buffs que dão XP (comida, saco de dormir...) e o descanso acumulado. Passe o mouse para ver cada um.",
                get = function() return Qolly.Buffs.GetOption("xpText") end,
                set = function(on) Qolly.Buffs.SetOption("xpText", on) end,
            },
        },
        {
            title = "Quests de masmorra",
            icon = "Interface/Icons/INV_Misc_Book_09",
            description = "Aba lateral no mapa-múndi com as quests das masmorras do seu nível: onde pegar, em que passo da cadeia você está e um botão que marca o próximo passo no mapa. Usa os dados do addon DungeonJournal.",
            {
                label = "Ligar quests de masmorra",
                tip = "Precisa do DungeonJournal instalado e ativo.",
                disabled = function() return Qolly.DungeonQuests.Unavailable() end,
                get = function() return Qolly.DungeonQuests.IsEnabled() end,
                set = function(on) Qolly.DungeonQuests.SetEnabled(on) end,
            },
        },
    }
end

-- Uma opção: caixa, rótulo e a explicação logo abaixo, em cinza. Clicar no texto
-- também marca.
local function CheckBox(parent, option, width)
    local holder = CreateFrame("Button", nil, parent)
    local check = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, -6)
    label:SetWidth(width - 34)
    label:SetJustifyH("LEFT")
    label:SetText(option.label)
    local height = 28
    if option.tip then
        local tip = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
        tip:SetWidth(width - 34)
        tip:SetJustifyH("LEFT")
        tip:SetText(option.tip)
        height = 6 + label:GetStringHeight() + 3 + tip:GetStringHeight() + 8
    end
    holder:SetSize(width, math.max(28, height))
    check:SetScript("OnClick", function(self)
        Qolly.Safe("configuração", option.set, self:GetChecked() and true or false)
    end)
    holder:SetScript("OnClick", function()
        check:Click()
    end)
    -- option.disabled(): devolve o motivo quando a opção não pode ser ligada (falta
    -- outro addon, por exemplo); a caixa fica cinza e o motivo aparece no rótulo.
    function holder:Refresh()
        local reason = option.disabled and option.disabled()
        if reason then
            check:SetChecked(false)
            check:Disable()
            holder:Disable()
            label:SetText(option.label .. "  |cffff6666(" .. reason .. ")|r")
        else
            check:Enable()
            holder:Enable()
            label:SetText(option.label)
            check:SetChecked(option.get() and true or false)
        end
    end
    return holder
end

-- Valor numérico: rótulo, o valor atual à direita e uma barra para arrastar.
local function Slider(parent, option, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 44)
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", 4, -2)
    label:SetText(option.label)
    local value = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("LEFT", label, "RIGHT", 8, 0)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(math.min(260, width - 20), 16)
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -6)
    slider:SetMinMaxValues(option.min, option.max)
    slider:SetValueStep(option.step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)
    slider:EnableMouseWheel(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0.25, 0.25, 0.25, 1)
    slider:SetThumbTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
    local low = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    low:SetPoint("RIGHT", slider, "LEFT", -4, 0)
    local high = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    high:SetPoint("LEFT", slider, "RIGHT", 4, 0)
    local format = option.format or function(v) return tostring(v) end
    low:SetText(format(option.min))
    high:SetText(format(option.max))
    if option.tip then
        local tip = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("LEFT", high, "RIGHT", 12, 0)
        tip:SetPoint("RIGHT", holder, "RIGHT", -4, 0)
        tip:SetJustifyH("LEFT")
        tip:SetText(option.tip)
    end

    local loading = false
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / option.step + 0.5) * option.step
        value:SetText(format(v))
        if not loading then
            Qolly.Safe("configuração", option.set, v)
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * option.step)
    end)
    function holder:Refresh()
        loading = true
        local v = option.get()
        slider:SetValue(v)
        value:SetText(format(v))
        loading = false
    end
    return holder
end

-- Escolha de tecla: clique, depois aperte a tecla ou um botão extra do mouse.
local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function WithModifiers(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

local function KeyButton(parent, option)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(290, 24)
    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", holder, "LEFT", 4, 0)
    label:SetText(option.label .. ":")
    local button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetPoint("LEFT", label, "RIGHT", 8, 0)
    button:RegisterForClicks("AnyUp")

    function holder:Refresh()
        button.waiting = false
        button:EnableKeyboard(false)
        button:SetText(Qolly.Fishing.KeyText())
    end
    local function Finish(key)
        Qolly.Safe("tecla da pesca", Qolly.Fishing.SetKey, key)
        holder:Refresh()
    end
    button:SetScript("OnClick", function(self, mouse)
        if self.waiting then
            if MOUSE_KEYS[mouse] then
                Finish(WithModifiers(MOUSE_KEYS[mouse]))
            end
            return
        end
        if mouse == "RightButton" then
            Finish(nil)
            return
        end
        self.waiting = true
        self:SetText("aperte a tecla...")
        self:EnableKeyboard(true)
    end)
    button:SetScript("OnKeyDown", function(self, key)
        if MODIFIER_KEYS[key] then
            return
        end
        if key == "ESCAPE" then
            holder:Refresh()
            return
        end
        Finish(WithModifiers(key))
    end)
    button:SetScript("OnHide", function()
        holder:Refresh()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Qolly.TAG .. option.label)
        GameTooltip:AddLine(option.tip, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Botão direito: tirar a tecla", 0, 1, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return holder
end

-- Janela ----------------------------------------------------------------------------
-- Retrato e título no alto, seções numa coluna à esquerda (ícone + nome) e, à direita,
-- a seção escolhida: título, descrição e as opções com a explicação de cada uma.

local WIDTH, HEIGHT = 840, 520
local NAV_WIDTH = 180
local NAV_ROW = 40
local CONTENT_WIDTH = WIDTH - NAV_WIDTH - 26

local pages, navButtons = {}, {}
local sections

-- Moldura do jogo quando existe; senão uma janela simples.
local function Frame(kind, name, parent, template)
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok then
        return frame
    end
    return CreateFrame(kind, name, parent)
end

local function Page(section)
    local page = CreateFrame("Frame", nil, panel.content)
    page:SetAllPoints()
    page:Hide()
    local width = CONTENT_WIDTH - 40

    local icon = page:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -14)
    icon:SetTexture(section.icon)
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText(section.title)
    local description = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
    description:SetWidth(width)
    description:SetJustifyH("LEFT")
    description:SetText(section.description or "")
    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)
    line:SetWidth(width)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    -- Seção que mostra uma tela de outro módulo (as vendas) em vez de opções.
    page.widgets = {}
    if section.embed then
        page.holder = CreateFrame("Frame", nil, page)
        page.holder:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -8, -6)
        page.holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 6)
        return page
    end

    -- Prévia fixa no alto: as opções rolam embaixo dela e ela continua à vista.
    local top = line
    for _, option in ipairs(section) do
        if option.kind == "preview" then
            local preview = option.create(page)
            preview.Refresh = preview.Refresh or function() end
            preview:SetPoint("TOP", line, "BOTTOM", 0, -8)
            preview:SetPoint("LEFT", line, "LEFT", 0, 0)
            preview:SetPoint("RIGHT", line, "RIGHT", 0, 0)
            page.widgets[#page.widgets + 1] = preview
            top = preview
        end
    end

    -- Opções numa área com rolagem, caso a seção cresça.
    local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOP", top, "BOTTOM", 0, -8)
    scroll:SetPoint("LEFT", line, "LEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 8)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(width - 20, 1)
    scroll:SetScrollChild(list)

    local y = 0
    for _, option in ipairs(section) do
        local widget
        if option.kind == "preview" then
            -- Já está fixa no alto.
        elseif option.kind == "key" then
            widget = KeyButton(list, option)
        elseif option.kind == "slider" then
            widget = Slider(list, option, width - 24)
        else
            widget = CheckBox(list, option, width - 24)
        end
        if widget then
            widget:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
            page.widgets[#page.widgets + 1] = widget
            y = y + widget:GetHeight() + 6
        end
    end
    local previous
    for _, action in ipairs(section.actions or {}) do
        local actionButton = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
        actionButton:SetSize(170, 24)
        if previous then
            actionButton:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            actionButton:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -(y + 6))
        end
        actionButton:SetText(action.label)
        actionButton:SetScript("OnClick", function()
            Qolly.Safe(action.label, action.run)
        end)
        previous = actionButton
    end
    if previous then
        y = y + 36
    end
    list:SetHeight(math.max(1, y))
    return page
end

local function Select(index)
    db.section = index
    for i, navButton in ipairs(navButtons) do
        navButton.selected:SetShown(i == index)
    end
    if not pages[index] then
        pages[index] = Page(sections[index])
    end
    for i, page in pairs(pages) do
        page:SetShown(i == index)
    end
    for _, widget in ipairs(pages[index].widgets) do
        widget:Refresh()
    end
    -- A tela embutida pode ter ido para outro lugar (a aba da AH): volta para cá.
    if sections[index].embed then
        Qolly.Safe(sections[index].title, sections[index].embed, pages[index].holder)
    end
end

local function NavButton(index, section)
    local navButton = CreateFrame("Button", nil, panel.nav)
    navButton:SetSize(NAV_WIDTH - 12, NAV_ROW - 4)
    navButton:SetPoint("TOPLEFT", panel.nav, "TOPLEFT", 6, -6 - (index - 1) * NAV_ROW)
    navButton.selected = navButton:CreateTexture(nil, "BACKGROUND")
    navButton.selected:SetAllPoints()
    navButton.selected:SetColorTexture(1, 0.82, 0, 0.18)
    navButton.selected:Hide()
    navButton:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    local icon = navButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", navButton, "LEFT", 4, 0)
    icon:SetTexture(section.icon)
    local label = navButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetText(section.title)
    navButton:SetScript("OnClick", function()
        Select(index)
    end)
    navButtons[index] = navButton
end

local function CreatePanel()
    panel = Frame("Frame", "QollyOptions", UIParent, "PortraitFrameTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    -- Esc fecha.
    tinsert(UISpecialFrames, "QollyOptions")

    if panel.SetTitle then
        panel:SetTitle("Qolly")
    end
    if panel.SetPortraitToAsset then
        pcall(panel.SetPortraitToAsset, panel, ICON)
    end
    if not panel.CloseButton then
        local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
        local background = panel:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.05, 0.05, 0.05, 0.92)
    end

    panel.nav = Frame("Frame", nil, panel, "InsetFrameTemplate")
    panel.nav:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -66)
    panel.nav:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 28)
    panel.nav:SetWidth(NAV_WIDTH)

    panel.content = Frame("Frame", nil, panel, "InsetFrameTemplate")
    panel.content:SetPoint("TOPLEFT", panel, "TOPLEFT", NAV_WIDTH + 16, -30)
    panel.content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 28)

    local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 9)
    footer:SetText(("Qolly v%s  ·  /qolly para os comandos  ·  GPL-3"):format(Version()))

    sections = Sections()
    for index, section in ipairs(sections) do
        NavButton(index, section)
    end

    -- Mudanças feitas por comando ou pelo filtro do mapa aparecem ao reabrir.
    panel:SetScript("OnShow", function()
        local index = db.section
        Select(sections[index] and index or 1)
    end)
    panel:Hide()
end

-- Abre o painel na seção pelo título; já aberto nela, fecha.
function Options.Open(title)
    if not panel then
        CreatePanel()
    end
    local index
    for i, section in ipairs(sections) do
        if section.title == title then
            index = i
        end
    end
    if panel:IsShown() and db.section == index then
        panel:Hide()
        return
    end
    db.section = index or db.section
    if panel:IsShown() then
        Select(db.section)
    else
        panel:Show()
    end
end

function Options.Toggle()
    if not panel then
        CreatePanel()
    end
    panel:SetShown(not panel:IsShown())
end

-- Botão do minimapa ----------------------------------------------------------

-- Posição na borda pelo ângulo; minimapa quadrado leva o botão para a borda do quadrado.
local function PlaceButton()
    local angle = math.rad(db.angle or 200)
    local x, y = math.cos(angle), math.sin(angle)
    local radius = Minimap:GetWidth() / 2 + 5
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        local scale = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * scale, y * scale
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceButton()
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(Qolly.TAG .. "Qolly v" .. Version())
    GameTooltip:AddDoubleLine("Clique", "Configurações", 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Shift+clique", "Vendas da AH", 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Botão do meio", "Modo pesca liga/desliga", 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Botão direito", "Coleta no minimapa liga/desliga", 0, 1, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Arrastar", "Mover o botão", 0, 1, 0, 1, 1, 1)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "QollyMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(20, 20)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "MiddleButton" then
            Qolly.Safe("pesca", Qolly.Fishing.SetEnabled, not Qolly.Fishing.IsEnabled())
        elseif mouse == "LeftButton" and IsShiftKeyDown() then
            Qolly.Safe("vendas da AH", Qolly.Sales.Toggle)
        elseif mouse == "RightButton" then
            local Gather = Qolly.Gather
            Gather.db.enabled = not Gather.db.enabled
            Qolly.Print("Coleta no minimapa " .. (Gather.db.enabled and "ligada." or "desligada."))
        else
            Qolly.Safe("configurações", Options.Toggle)
        end
    end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", ButtonTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    PlaceButton()
end

function Options.UpdateButton()
    if not button then
        CreateButton()
    end
    button:SetShown(not db.hideButton)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    Qolly.Safe("botão do minimapa", Options.UpdateButton)
end)

Qolly.RegisterModule("config", {
    help = "(abre as configurações)",
    command = function()
        Options.Toggle()
    end,
    init = function(moduleDB)
        db = moduleDB
    end,
})
