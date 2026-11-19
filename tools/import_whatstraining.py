"""Gera Modules/Training/Data.lua a partir dos dados do What's Training.

O What's Training (Sveng, licença MIT) traz, para cada classe do WoW Forever, as magias
do instrutor por nível (custo, magia anterior exigida, talento exigido, facção, perícia)
e os tomos de demônio do bruxo. Este script lê os arquivos da pasta Classes/Camelot e
escreve só as tabelas de dados no formato do Qolly.

Uso: python tools/import_whatstraining.py "<pasta do WhatsTraining>"
"""
import re
import sys
from pathlib import Path

CLASSES = ["Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"]
OUT = Path(__file__).resolve().parent.parent / "Modules" / "Training" / "Data.lua"

LEVEL = re.compile(r"^\s*\[(\d+)\]\s*=\s*\{", re.M)
ENTRY = re.compile(r"\{\s*(?:id|itemId)\s*=[^{}]*(?:\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}[^{}]*)*\}")
LOCAL_LIST = re.compile(r"^local (\w+) = \{([\d,\s]+)\}", re.M)
NUMBERS = re.compile(r"\d+")


def field(text, name):
    match = re.search(r"\b" + name + r"\s*=\s*(\d+)", text)
    return int(match.group(1)) if match else None


def string_field(text, name):
    match = re.search(r"\b" + name + r'\s*=\s*"([^"]*)"', text)
    return match.group(1) if match else None


def block(text, start):
    """Texto entre a chave que abre em `start` e a que fecha."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ValueError("chave sem par")


def table_after(text, name):
    index = text.find(name)
    if index < 0:
        return None
    return block(text, text.index("{", index))


def by_level(table):
    """{nível: [entrada, ...]} de uma tabela "[n] = { {...}, {...} }"."""
    result = []
    inner = table[1:-1]
    for match in LEVEL.finditer(inner):
        level = int(match.group(1))
        body = block(inner, match.end() - 1)
        for entry in ENTRY.findall(body):
            result.append((level, entry))
    return result


def spell_line(level, entry):
    parts = [f"{level}", f"{field(entry, 'id')}", f"{field(entry, 'cost') or 0}"]
    extra = []
    required = re.search(r"requiredIds\s*=\s*\{([^}]*)\}", entry)
    if required:
        extra.append("req = { " + ", ".join(NUMBERS.findall(required.group(1))) + " }")
    talent = field(entry, "requiredTalentId")
    if talent:
        extra.append(f"talent = {talent}")
    faction = string_field(entry, "faction")
    if faction:
        extra.append(f'faction = "{faction}"')
    skill = re.search(r"skill\s*=\s*(\d+),\s*level\s*=\s*(\d+)", entry)
    if skill:
        extra.append(f"skill = {{ {skill.group(1)}, {skill.group(2)} }}")
    return "{ " + ", ".join(parts + extra) + " }"


def overrides(text):
    table = table_after(text, "class.overriddenGroups")
    if not table:
        return []
    lists = {name: NUMBERS.findall(ids) for name, ids in LOCAL_LIST.findall(text)}
    groups = []
    inner = table[1:-1]
    inner = re.sub(r"--[^\n]*", "", inner)
    for literal in re.findall(r"\{([\d,\s]+)\}", inner):
        groups.append(NUMBERS.findall(literal))
    for name in re.findall(r"^\s*(\w+),?\s*$", re.sub(r"\{[^}]*\},?", "", inner), re.M):
        groups.append(lists[name])
    return groups


def main(folder):
    base = Path(folder) / "Classes" / "Camelot"
    out = [
        "-- Gerado por tools/import_whatstraining.py a partir do What's Training.",
        "-- Dados: Copyright (c) 2019 Sveng, licença MIT (veja CREDITS.md).",
        "-- Não edite à mão: rode o script de novo.",
        "-- spells: { nível, magia, custo em cobre, req = magias exigidas, talent = talento exigido,",
        "--           faction = facção, skill = { perícia, valor } }",
        "-- overrides: grupos de graus em ordem; saber um grau maior conta os menores como sabidos.",
        "-- tomes: { nível, item, custo, demônio, magia que ensina }",
        "local _, Qolly = ...",
        "",
        "Qolly.TrainingData = {",
    ]
    for name in CLASSES:
        text = (base / f"{name}.lua").read_text(encoding="utf-8")
        token = re.search(r'forClass\("(\w+)"\)', text).group(1)
        out.append(f"    {token} = {{")
        out.append("        spells = {")
        for level, entry in by_level(table_after(text, "class.spellsByLevel")):
            out.append("            " + spell_line(level, entry) + ",")
        out.append("        },")
        groups = overrides(text)
        if groups:
            out.append("        overrides = {")
            for group in groups:
                out.append("            { " + ", ".join(group) + " },")
            out.append("        },")
        out.append("    },")
    out.append("}")
    out.append("")

    tomes_text = (base / "WarlockTomes.lua").read_text(encoding="utf-8")
    taught = dict(re.findall(r"\[(\d+)\]\s*=\s*(\d+)", table_after(tomes_text, "tomeTaughtSpells")))
    out.append("Qolly.TrainingData.TOMES = {")
    for level, entry in by_level(table_after(tomes_text, "class.tomesByLevel")):
        item = str(field(entry, "itemId"))
        family = string_field(entry, "family")
        out.append(f'    {{ {level}, {item}, {field(entry, "cost") or 0}, "{family}", {taught.get(item, "nil")} }},')
    out.append("}")
    out.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"ok: {OUT}")


if __name__ == "__main__":
    main(sys.argv[1])
