## Qolly: quality-of-life suite for WoW Forever

Qolly bundles small tools that remove busywork from leveling, gathering, crafting and trading on **WoW Forever**. Every feature is a separate module you can turn on or off in the settings (minimap button or `/qolly`), so you only keep what you use. The interface text is in Portuguese (Brazil).

### Auction House

A panel opens **beside** the Auction House window, with side tabs. It does not touch the AH's own tabs, so it also works with UI replacements such as ElvUI and EllesmereUI. Press *Scan* once and the panel fills three pages:

- **Upgrades**: gear on sale that is better than what you wear in that slot, with the price and how much better it is. You stop browsing slot by slot. (Needs QuestMaster.)
- **Sales**: what you sold, for how much, and what is still listed.
- **Opportunities**: items listed well below their usual price (to resell), items worth more disenchanted than their price, items cheaper than what a vendor pays for them, and essence arbitrage (lesser and greater essences converting at a profit). For example: a green listed for 20s that usually sells for 1g, or a ring that disenchants into 60s of dust while it costs 35s.

The analysis runs in small steps after the scan, so the game does not freeze.

### Leveling

- **Training**: a side tab on the spellbook lists what you can learn at your class trainer right now and in the next levels, with the cost, so you know whether a trip to town is worth it. Warlocks also get every demon tome, grouped by demon.
- **Dungeon quests**: a side tab on the DungeonJournal window lists the quests for the dungeon you are looking at, or for every dungeon at your level. It shows whether each quest is done, in your log, or blocked by an earlier quest. For long quest chains it tells you which step you are on and where its quest giver is. One click puts a waypoint on your map. (Needs DungeonJournal; without it the option stays greyed out.)
- **Buffs and XP bonus**: warns when a class buff is missing or about to expire (yours or one you can cast on the group), with a button to cast it. The experience bar shows your total XP bonus from food, campfire and rested, and how long each lasts.
- **Quest items**: lists items left in your bags from quests you already turned in, so you can sell or destroy them.

### Gathering and professions

- **Gathering**: known herb and ore locations on the minimap and the world map, with the current AH price of each, so you can pick the most profitable route.
- **Crafting**: profit for every recipe in your profession window, using material and product prices from your last AH scan. You see at a glance which crafts make money and which lose it.
- **Fishing**: one key casts and the same key reels in when the bobber splashes.

### Combat and awareness

- **Nameplates**: health, threat, cast bars and your debuffs on the default nameplates, without replacing them.
- **Aggro**: a traffic-light marker on enemy nameplates showing whether you are inside, near, or outside the mob's aggro range, so you can path around packs.
- **Radar**: an alert when an enemy player appears nearby.

### Gold

- **Income**: every copper that comes in and goes out (loot, quests, vendors, AH, repairs, training), per session and per day.
- **Junk**: sells grey items automatically when you open a vendor. Items you lock are never sold.

### Social

- **Snipe**: shows where a Battle.net friend is (zone and area), handy for meeting up.

### Optional addons

- **QuestMaster**: required for the Upgrades page.
- **DungeonJournal**: required for Dungeon quests.
- **GatherLite**: if installed, Gathering also uses its node database.

Without them, only the feature that depends on them stays off; everything else works.

### Commands

`/qolly` opens the settings and lists all commands. Examples: `/qolly treino` (training), `/qolly masmorras` (dungeon quests), `/qolly mercado` (opportunities), `/qolly buffs`.

Open source under GPL-3.0: [github.com/diegojrq/qolly](https://github.com/diegojrq/qolly). Credits for imported data are in CREDITS.md.

---

## Português

Qolly é uma suíte de melhorias para o **WoW Forever**. Cada parte liga e desliga sozinha nas configurações (botão no minimapa ou `/qolly`).

- **Casa de leilão**: painel ao lado da AH com Melhorias (equipamento à venda melhor que o seu), Vendas e Oportunidades (revenda abaixo do preço, desencanto com lucro, itens abaixo do preço do vendedor, essências).
- **Treino**: aba no grimório com o que aprender no instrutor agora e nos próximos níveis; tomos de demônio do bruxo.
- **Quests de masmorra**: aba no DungeonJournal com as quests da masmorra, o passo da cadeia e um clique que marca no mapa onde pegar.
- **Buffs**: avisa buff faltando ou acabando e mostra o bônus de XP somado na barra de experiência.
- **Coleta**, **Craft**, **Pesca**, **Placas**, **Aggro**, **Radar**, **Ganhos**, **Lixo**, **Itens de missão** e **Snipe**.
