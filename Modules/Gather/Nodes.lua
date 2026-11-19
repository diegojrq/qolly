-- Coleta: nós de erva e minério para o minimapa. Duas fontes:
--   * o banco importado do GatherLite (Data.lua), convertido para jardas no login;
--   * o que você coleta, gravado em QollyDB.coleta.nodes (pega nó que o banco não tem).
-- O tooltip de cada nó diz o nível de perícia pedido e quanto o saque vale na AH.
--
-- Posição em coordenadas de mundo (jardas), por continente: o mesmo nó tem a mesma
-- posição em qualquer mapa de zona que o cubra. Vetor do C_Map: x cresce para o norte,
-- y cresce para o oeste.
local _, Qolly = ...

local Gather = {}
Qolly.Gather = Gather

-- Dois registros a menos que isso viram o mesmo nó (o nó renasce perto, não no mesmo
-- ponto, e você coleta a alguns passos dele).
local SAME_NODE = 12
-- Saque que chega até esse tempo depois da coleta é do nó.
local LOOT_WINDOW_SECONDS = 3

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Magia de coleta -> tipo do nó, pelo nome localizado (cobre todos os ranks), e a
-- linha de perícia da profissão.
local KINDS = {
    herb = { spell = 2366, skillLine = 182 }, -- Herborismo
    ore = { spell = 2575, skillLine = 186 },  -- Mineração
}
local kindBySpellName

local function Plain(value)
    if value == nil or Qolly.IsSecret(value) then
        return nil
    end
    return value
end

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return (GetSpellInfo(spellID))
end

local function KindOf(spellID)
    if not kindBySpellName then
        kindBySpellName = {}
        for kind, entry in pairs(KINDS) do
            local name = SpellName(entry.spell)
            if name then
                kindBySpellName[name] = kind
            end
        end
    end
    local name = Plain(SpellName(spellID))
    return name and kindBySpellName[name]
end

-- Nome do nó -> entrada do banco (níveis, item), para os nós que você grava.
local infoByName = {}
for _, info in pairs(Qolly.GatherData or {}) do
    infoByName[info.name] = info
end

-- Cantos de cada mapa de zona em jardas: { continente, norte do topo, oeste da
-- esquerda, altura, largura }, ou false se o mapa não tem coordenadas de mundo.
local mapFrames = {}

function Gather.MapFrame(mapID)
    local known = mapFrames[mapID]
    if known ~= nil then
        return known
    end
    local frame = false
    local continent, topLeft = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
    local _, bottomRight = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 1))
    if continent and topLeft and bottomRight then
        local top, left = topLeft:GetXY()
        local bottom, right = bottomRight:GetXY()
        frame = { continent, top, left, bottom - top, right - left }
    end
    mapFrames[mapID] = frame
    return frame
end

-- Onde o jogador está: continente e posição em jardas, ou nil (instância, posição
-- secreta ou mapa sem coordenadas).
function Gather.PlayerPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    local frame = Gather.MapFrame(mapID)
    if not (frame and Plain(x) and Plain(y)) then
        return nil
    end
    return frame[1], frame[2] + frame[4] * y, frame[3] + frame[5] * x
end

-- Banco convertido: continente -> lista de { north, west, kind, info }. Montado uma
-- vez, no login (os mapas já respondem); a fonte é solta depois para liberar memória.
local predefined = {}

local function LoadPredefined()
    for _, info in pairs(Qolly.GatherData or {}) do
        for mapID, coords in pairs(info.maps) do
            local frame = Gather.MapFrame(mapID)
            if frame then
                local list = predefined[frame[1]] or {}
                predefined[frame[1]] = list
                for i = 1, #coords, 2 do
                    list[#list + 1] = {
                        north = frame[2] + frame[4] * coords[i + 1],
                        west = frame[3] + frame[5] * coords[i],
                        kind = info.kind,
                        info = info,
                    }
                end
            end
        end
        info.maps = nil
    end
end

-- Tipo de nó ("herb", "ore") que o jogador não escondeu no filtro do mapa.
function Gather.Shown(kind)
    return not Gather.db.hide[kind]
end

-- As listas de nós de um continente: a do banco e a gravada por você.
function Gather.Lists(continent)
    local lists = {}
    if Gather.db.useData ~= false and predefined[continent] then
        lists[#lists + 1] = predefined[continent]
    end
    if Gather.db.nodes[continent] then
        lists[#lists + 1] = Gather.db.nodes[continent]
    end
    return lists
end

local function Near(list, kind, north, west)
    for _, node in ipairs(list or {}) do
        if node.kind == kind then
            local dn, dw = node.north - north, node.west - west
            if dn * dn + dw * dw <= SAME_NODE * SAME_NODE then
                return node
            end
        end
    end
end

local function Record(kind, name)
    local continent, north, west = Gather.PlayerPosition()
    if not continent then
        return
    end
    -- Nó que o banco já tem não ganha ícone repetido.
    if Near(predefined[continent], kind, north, west) then
        return
    end
    local nodes = Gather.db.nodes[continent] or {}
    Gather.db.nodes[continent] = nodes
    local node = Near(nodes, kind, north, west)
    if node then
        node.count = node.count + 1
        node.name = name or node.name
        return
    end
    nodes[#nodes + 1] = { north = north, west = west, kind = kind, name = name, count = 1 }
end

-- Saque de coleta: aprende os itens de cada nó pelo nome (cobre nó novo do Forever que
-- o banco não sabe o item).
local lastGather

local function LearnLoot()
    if not (lastGather and GetTime() - lastGather.time <= LOOT_WINDOW_SECONDS and lastGather.name) then
        return
    end
    local name = lastGather.name
    lastGather = nil
    local yields = Gather.db.yields[name] or {}
    -- Contagem para a chance de drop: coletas do nó e em quantas cada item veio.
    local stats = Gather.db.stats[name] or { n = 0, items = {} }
    local seen = {}
    for slot = 1, GetNumLootItems() do
        local link = Plain(GetLootSlotLink(slot))
        local itemID = link and GetItemInfoInstant(link)
        if itemID then
            yields[itemID] = true
            seen[itemID] = true
        end
    end
    if not next(seen) then
        return
    end
    stats.n = stats.n + 1
    for itemID in pairs(seen) do
        stats.items[itemID] = (stats.items[itemID] or 0) + 1
    end
    Gather.db.yields[name] = yields
    Gather.db.stats[name] = stats
end

-- Chance de um item vir de um nó, pelo seu próprio saque: vezes, coletas.
function Gather.DropRate(name, itemID)
    local stats = name and Gather.db.stats[name]
    if not (stats and stats.n > 0) then
        return nil
    end
    return stats.items[itemID] or 0, stats.n
end

-- Perícia atual do personagem na profissão do tipo do nó, ou nil se não tem.
function Gather.Skill(kind)
    local wanted = KINDS[kind] and KINDS[kind].skillLine
    for _, index in ipairs({ GetProfessions() }) do
        if index then
            local _, _, level, _, _, _, skillLine = GetProfessionInfo(index)
            if skillLine == wanted then
                return level
            end
        end
    end
end

-- O que o tooltip mostra de um nó: nome, níveis de perícia, o item principal (a erva ou
-- o minério) e o loot adicional (sementes, pedras, gemas).
function Gather.Info(node)
    local name = node.info and node.info.name or node.name
    local info = node.info or (name and infoByName[name])
    local stats = name and Gather.db.stats[name]
    local main = info and info.item ~= 0 and info.item or nil
    -- Nó sem item no banco: o principal é o que mais veio no seu saque.
    if not main and stats then
        local best = 0
        for itemID, times in pairs(stats.items) do
            if times > best then
                main, best = itemID, times
            end
        end
    end
    if not main then
        main = next(name and Gather.db.yields[name] or {})
    end
    local extras = {}
    for itemID in pairs(name and Gather.db.yields[name] or {}) do
        if itemID ~= main then
            extras[#extras + 1] = itemID
        end
    end
    table.sort(extras)
    return name, info and info.levels, main, extras
end

-- O alvo da magia (nome do nó) só vem no SENT; o registro espera o SUCCEEDED para não
-- gravar coleta interrompida.
local pending = {}

local events = CreateFrame("Frame")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, _, a, b, c)
    if event == "PLAYER_LOGIN" then
        Qolly.Safe("banco de coleta", LoadPredefined)
    elseif event == "LOOT_OPENED" then
        Qolly.Safe("saque de coleta", LearnLoot)
    elseif event == "UNIT_SPELLCAST_SENT" then
        local target, castGUID, spellID = a, b, c
        castGUID = Plain(castGUID)
        local kind = Plain(spellID) and KindOf(spellID)
        if castGUID and kind then
            local name = Plain(target)
            pending[castGUID] = { kind = kind, name = name ~= "" and name or nil }
        end
    else
        local castGUID = Plain(a)
        local cast = castGUID and pending[castGUID]
        if cast then
            pending[castGUID] = nil
            lastGather = { name = cast.name, time = GetTime() }
            Qolly.Safe("coleta", Record, cast.kind, cast.name)
        end
    end
end)

local function Count(lists)
    local herb, ore = 0, 0
    for _, nodes in pairs(lists) do
        for _, node in ipairs(nodes) do
            if node.kind == "herb" then
                herb = herb + 1
            else
                ore = ore + 1
            end
        end
    end
    return herb, ore
end

local function OnOff(value)
    return value and "|cff33dd33ligado|r" or "|cffff5555desligado|r"
end

Qolly.RegisterModule("coleta", {
    help = "on | off | mapa (liga/desliga no mapa-múndi) | banco (liga/desliga o banco do GatherLite) | limpar (apaga os nós que você gravou) | rastreio (mostra o que o jogo diz do rastreamento)",
    command = function(input)
        local command = strtrim(input):lower()
        local db = Gather.db
        if command == "on" then
            db.enabled = true
        elseif command == "off" then
            db.enabled = false
        elseif command == "mapa" then
            db.worldMap = db.worldMap == false
            if Gather.RefreshWorldMap then
                Gather.RefreshWorldMap()
            end
        elseif command == "banco" then
            db.useData = db.useData == false
        elseif command == "rastreio" then
            Gather.DebugTracking()
            return
        elseif command == "limpar" then
            db.nodes = {}
        end
        local herb, ore = Count(predefined)
        local myHerb, myOre = Count(db.nodes)
        Qolly.Print(("Coleta no minimapa %s, no mapa-múndi %s. Banco %s: %d ervas, %d minérios. Gravados por você: %d ervas, %d minérios."):format(
            OnOff(db.enabled), OnOff(db.worldMap ~= false), OnOff(db.useData ~= false), herb, ore, myHerb, myOre))
    end,
    init = function(moduleDB)
        Gather.db = moduleDB
        moduleDB.nodes = moduleDB.nodes or {}
        moduleDB.yields = moduleDB.yields or {}
        moduleDB.hide = moduleDB.hide or {}
        moduleDB.stats = moduleDB.stats or {}
        if moduleDB.enabled == nil then
            moduleDB.enabled = true
        end
    end,
})
