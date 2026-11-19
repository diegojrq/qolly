-- Snipe: rastreia a zona de um amigo de Battle.net.
local _, Qolly = ...

local db

-- Devolve a conta do amigo cuja BattleTag bate com a informada, ou nil.
local function FindFriend(battleTag)
    local wanted = battleTag:lower()
    for index = 1, BNGetNumFriends() do
        local account = C_BattleNet.GetFriendAccountInfo(index)
        if account and account.battleTag and account.battleTag:lower() == wanted then
            return index, account
        end
    end
end

local function PrintFields(fields)
    local keys = {}
    for key in pairs(fields) do
        keys[#keys + 1] = tostring(key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        Qolly.Print("   " .. key .. " = " .. Qolly.Describe(fields[key]))
    end
end

local function DebugBuild()
    local version, build, _, interface = GetBuildInfo()
    Qolly.Print(("Client %s (%s), Interface = %s"):format(version, build, tostring(interface)))
end

local function DebugFriendList()
    Qolly.Print("Nenhum alvo definido. Amigos online no WoW:")
    local found = false
    for index = 1, BNGetNumFriends() do
        local account = C_BattleNet.GetFriendAccountInfo(index)
        local game = account and account.gameAccountInfo
        if game and game.clientProgram == BNET_CLIENT_WOW then
            found = true
            Qolly.Print(("   %s: zona = %s"):format(
                Qolly.Describe(account.battleTag), Qolly.Describe(game.areaName)))
        end
    end
    if not found then
        Qolly.Print("   nenhum")
    end
    Qolly.Print("Use /snipe add Nome#1234 para definir o alvo.")
end

local function DebugTarget(battleTag)
    local index, account = FindFriend(battleTag)
    if not index then
        Qolly.Print(battleTag .. " não está na sua lista de amigos de Battle.net.")
        return
    end

    Qolly.Print("Conta de " .. battleTag .. ":")
    PrintFields(account)

    for gameIndex = 1, C_BattleNet.GetFriendNumGameAccounts(index) do
        local game = C_BattleNet.GetFriendGameAccountInfo(index, gameIndex)
        if game then
            Qolly.Print("Game account " .. gameIndex .. ":")
            PrintFields(game)
        end
    end
end

-- Mostra se o nome dos jogadores nas nameplates visíveis pode ser lido.
local function DebugNameplates()
    local plates = C_NamePlate.GetNamePlates()
    Qolly.Print("Nameplates visíveis: " .. #plates)
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken
        if unit and UnitIsPlayer(unit) then
            Qolly.Print(("   jogador: nome = %s, inimigo = %s"):format(
                Qolly.Describe(UnitName(unit)), Qolly.Describe(UnitIsEnemy("player", unit))))
        end
    end
end

local function RunDebug()
    DebugBuild()
    if db.target then
        DebugTarget(db.target)
    else
        DebugFriendList()
    end
    DebugNameplates()
end

local function Command(input)
    local command, argument = strtrim(input):match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "add" and argument:find("#", 1, true) then
        db.target = argument
        Qolly.Print("Alvo: " .. argument)
    elseif command == "remove" then
        db.target = nil
        Qolly.Print("Alvo removido.")
    elseif command == "debug" then
        RunDebug()
    else
        Qolly.Print("Snipe: /snipe add Nome#1234 | remove | debug")
    end
end

Qolly.RegisterModule("snipe", {
    help = "add Nome#1234 | remove | debug  (atalho: /snipe)",
    command = Command,
    init = function(moduleDB)
        db = moduleDB
        SLASH_QOLLYSNIPE1 = "/snipe"
        SlashCmdList.QOLLYSNIPE = function(input)
            Qolly.Log("> /snipe " .. input)
            Qolly.Safe("/snipe", Command, input)
        end
    end,
})
