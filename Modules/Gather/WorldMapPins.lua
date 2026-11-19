-- Nós de coleta no mapa-múndi, pelo sistema de pinos do próprio mapa (data provider).
-- Só em mapa de zona: um continente inteiro teria dezenas de milhares de pinos.
local _, Qolly = ...
local Gather = Qolly.Gather

local TEMPLATE = "QollyGatherPinTemplate"

-- Mixin do pino; o template em WorldMapPins.xml usa este nome global.
QollyGatherPinMixin = CreateFromMixins(MapCanvasPinMixin)

function QollyGatherPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    -- Cresce menos que o mapa no zoom, para não virar um borrão de ícones.
    self:SetScalingLimits(1, 1.0, 1.4)
end

function QollyGatherPinMixin:OnAcquired(node, x, y)
    self.node = node
    self.Icon:SetTexture(Gather.NodeIcon(node))
    self:SetPosition(x, y)
end

function QollyGatherPinMixin:OnMouseEnter()
    Qolly.Safe("tooltip de coleta", Gather.ShowNodeTooltip, self, self.node)
end

function QollyGatherPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

local function Fill(map)
    if Gather.db.worldMap == false then
        return
    end
    local mapID = map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not (info and info.mapType and info.mapType >= Enum.UIMapType.Zone) then
        return
    end
    local frame = Gather.MapFrame(mapID)
    if not frame then
        return
    end
    local continent, top, left, height, width = frame[1], frame[2], frame[3], frame[4], frame[5]
    for _, nodes in ipairs(Gather.Lists(continent)) do
        for _, node in ipairs(nodes) do
            local x, y = (node.west - left) / width, (node.north - top) / height
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 and Gather.Shown(node.kind) then
                map:AcquirePin(TEMPLATE, node, x, y)
            end
        end
    end
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    Qolly.Safe("coleta no mapa", Fill, self:GetMap())
end

function Gather.RefreshWorldMap()
    if Provider:GetMap() then
        Provider:RefreshAllData()
    end
end

-- Opções no filtro do próprio mapa (a lupa no canto): o que mostrar, nos dois mapas.
local OPTIONS = {
    { label = "Ervas", get = function() return Gather.Shown("herb") end,
      set = function() Gather.db.hide.herb = not Gather.db.hide.herb end },
    { label = "Minérios", get = function() return Gather.Shown("ore") end,
      set = function() Gather.db.hide.ore = not Gather.db.hide.ore end },
    { label = "No mapa-múndi", get = function() return Gather.db.worldMap ~= false end,
      set = function() Gather.db.worldMap = Gather.db.worldMap == false end },
    { label = "No minimapa", get = function() return Gather.db.enabled end,
      set = function() Gather.db.enabled = not Gather.db.enabled end },
}

local function IsChecked(option)
    return option.get()
end

local function Toggle(option)
    option.set()
    Gather.RefreshWorldMap()
end

-- ModifyMenu também passa pelo último menu já montado: cada menu ganha as opções uma vez.
local menuDone = setmetatable({}, { __mode = "k" })

local function AddOptions(_, root)
    if menuDone[root] then
        return
    end
    menuDone[root] = true
    root:CreateDivider()
    root:CreateTitle("Qolly: coleta")
    for _, option in ipairs(OPTIONS) do
        root:CreateCheckbox(option.label, IsChecked, Toggle, option)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if WorldMapFrame and WorldMapFrame.AddDataProvider then
        WorldMapFrame:AddDataProvider(Provider)
    else
        Qolly.Log("Coleta: mapa-múndi sem AddDataProvider, sem pinos no mapa.")
    end
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", AddOptions)
    else
        Qolly.Log("Coleta: sem Menu.ModifyMenu, opções só pelo /qolly coleta.")
    end
end)
