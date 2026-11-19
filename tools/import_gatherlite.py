"""Gera Modules/Gather/Data.lua a partir do banco de nós do GatherLite.

O GatherLite (Wuild e colaboradores, GPL-3.0-or-later) traz as posições dos nós de
erva e minério do WoW Forever. Este script lê três arquivos dele e escreve um arquivo
de dados do Qolly com só o que o minimapa usa: tipo, nome em português e coordenadas.

Uso: python tools/import_gatherlite.py "<pasta do GatherLite>"
"""
import re
import sys
from pathlib import Path

KINDS = {"herb", "ore"}

INSERT = re.compile(r'InsertObject\("(\w+)",\s*\{([^}]*)\},\s*"(\w+)",\s*"[^"]*",\s*\{([^}]*)\}')

# Item principal que cada nó dá, para o preço da AH no tooltip. Conhecimento do jogo,
# não vem do GatherLite. Nó fora daqui o Qolly aprende pelo saque quando você coleta.
ITEMS = {
    "peacebloom": 2447, "silverleaf": 765, "earthroot": 2449, "mageroyal": 785,
    "briarthorn": 2450, "stranglekelp": 3820, "bruiseweed": 2453, "wild_steelbloom": 3355,
    "grave_moss": 3369, "kingsblood": 3356, "liferoot": 3357, "fadeleaf": 3818,
    "goldthorn": 3821, "khadgars_whisker": 3358, "wintersbite": 3819, "firebloom": 4625,
    "purple_lotus": 8831, "arthas_tears": 8836, "sungrass": 8838, "blindweed": 8839,
    "ghost_mushroom": 8845, "gromsblood": 8846, "golden_sansam": 13464, "dreamfoil": 13463,
    "mountain_silversage": 13465, "plaguebloom": 13466, "icecap": 13467, "black_lotus": 13468,
    "copper_vein": 2770, "tin_vein": 2771, "silver_vein": 2775, "iron_deposit": 2772,
    "gold_vein": 2776, "mithril_deposit": 3858, "truesilver_deposit": 7911,
    "dark_iron_deposit": 11370, "small_thorium_vein": 10620, "rich_thorium_vein": 10620,
    "incendicite_mineral_vein": 3340, "lesser_bloodstone_deposit": 4278,
    "indurium_mineral_vein": 5833,
}
LOCALE = re.compile(r'L\[["\']node\.(\w+)["\']\]\s*=\s*"([^"]*)"')
OBJECT = re.compile(r"^    \[(\d+)\] = \{\s*$")
MAP = re.compile(r"^        \[(\d+)\] = \{\s*$")
NUMBER = re.compile(r"-?\d+(?:\.\d+)?")


def read(path):
    return Path(path).read_text(encoding="utf-8")


def objects(root):
    """objectID -> (tipo, slug do nome, níveis de perícia) para erva e minério."""
    found = {}
    for kind, ids, slug, levels in INSERT.findall(read(root / "scripts" / "nodes.lua")):
        if kind in KINDS:
            for objectID in NUMBER.findall(ids):
                found[int(objectID)] = (kind, slug, NUMBER.findall(levels))
    return found


def names(root):
    """slug -> nome em português, com inglês onde falta tradução."""
    result = dict(LOCALE.findall(read(root / "scripts" / "locales" / "enUS.lua")))
    result.update(LOCALE.findall(read(root / "scripts" / "locales" / "ptBR.lua")))
    return result


def points(root):
    """objectID -> mapID -> [x1, y1, x2, y2, ...] (0 a 1 no mapa da zona)."""
    result, objectID, mapID = {}, None, None
    for line in read(root / "plugins" / "database" / "data" / "forever.lua").splitlines():
        if match := OBJECT.match(line):
            objectID, mapID = int(match.group(1)), None
        elif match := MAP.match(line):
            mapID = int(match.group(1))
            result.setdefault(objectID, {})[mapID] = []
        elif mapID is not None and line.strip() not in ("},", "}"):
            result[objectID][mapID].extend(NUMBER.findall(line))
        elif line.startswith("        }"):
            mapID = None
    return result


def main():
    root = Path(sys.argv[1])
    kinds, localized, coordinates = objects(root), names(root), points(root)
    out = [
        "-- Gerado por tools/import_gatherlite.py. Não edite à mão.",
        "-- Posições de nós do GatherLite (https://github.com/Wuild/GatherLite),",
        "-- GPL-3.0-or-later, de Wuild e colaboradores.",
        "-- objectID = { kind, name, levels (perícia: laranja, amarelo, verde, cinza),",
        "--   item (0 = desconhecido), maps = { [uiMapID] = { x1, y1, x2, y2, ... } } }",
        "local _, Qolly = ...",
        "Qolly.GatherData = {",
    ]
    total = 0
    for objectID in sorted(coordinates):
        if objectID not in kinds:
            continue
        kind, slug, levels = kinds[objectID]
        name = localized.get(slug, slug.replace("_", " ").title()).replace('"', '\\"')
        out.append(f'    [{objectID}] = {{ kind = "{kind}", name = "{name}", '
                   f'levels = {{ {", ".join(levels)} }}, item = {ITEMS.get(slug, 0)}, maps = {{')
        for mapID in sorted(coordinates[objectID]):
            values = coordinates[objectID][mapID]
            total += len(values) // 2
            out.append(f"        [{mapID}] = {{ {', '.join(values)} }},")
        out.append("    } },")
    out.append("}")
    target = Path(__file__).resolve().parent.parent / "Modules" / "Gather" / "Data.lua"
    target.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{target}: {total} nós")


if __name__ == "__main__":
    main()
