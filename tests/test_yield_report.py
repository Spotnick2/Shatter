"""Tests for Tools/yield_report.py (#40), on a fixture SavedVariables and table.

Run by tests/run.ps1 and CI: python tests/test_yield_report.py
"""

import contextlib
import io
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..")
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(REPO, "Tools"))
import yield_report as yr  # noqa: E402

RULES = """local TOP = 1000
local RULES = {
    { 2, ARMOR, 16, 20, 10940, 0.75, 2, 3 }, { 2, ARMOR, 21, 25, 10940, 0.75, 4, 6 },
    { 2, ARMOR, 26, 30, 11083, 0.75, 1, 2 },
    { 2, ARMOR, 16, 25, 10978, 0.05, 1, 1 },
    { 3, nil, 1, TOP, 10978, 1.00, 1, 1 },
}
Tables.RULES = RULES
"""
CONSTANTS = """Constants.MATERIAL_ITEM_IDS = {
    [10940] = true, -- Strange Dust
    [11083] = true, -- Soul Dust
    [10978] = true, -- Small Glimmering Shard
}
"""

B1, B2 = "1.60.1.70532", "1.60.1.70685"


def entry(level, loot, quality=2, classID=4, build=B1, **flags):
    lines = ['{', '["itemID"] = 2589,', '["itemLevel"] = %d,' % level, '["quality"] = %d,' % quality,
             '["classID"] = %d,' % classID, '["subclassID"] = 2,', '["equipLoc"] = "INVTYPE_CHEST",',
             '["mode"] = "SOLO",', '["build"] = "%s",' % build, '["time"] = 1790000000,', '["loot"] = {']
    lines += ['[%d] = %d,' % (i, c) for i, c in loot.items()]
    lines.append('},')
    lines += ['["%s"] = true,' % k for k in flags]
    lines.append('}, -- [n]')
    return "\n".join(lines)


ENTRIES = (
    [entry(20, {10940: 2}) for _ in range(10)]
    + [entry(20, {10940: 3}, build=B2) for _ in range(2)]
    + [entry(20, {10940: 2, 2589: 1}, unknownLoot=1)]                 # not a material
    + [entry(21, {10978: 1}) for _ in range(12)]                       # dust never seen
    + [entry(24, {10940: 5, 11083: 1}, surprise=1)]                    # soul dust below 26
    + [entry(26, {11083: 2})]
    + [entry(30, {10978: 1}, quality=4, unmatched=1)]                  # no rule
)
SAVED = """
ShatterDB = {
["settings"] = {
["skin"] = "forever",
["window"] = {
["x"] = -12.5,
},
["ignoredItems"] = {
},
},
["debugLog"] = {
{
["message"] = "a \\"quoted\\" path C:\\\\x\\nnext",
["level"] = "trace",
}, -- [1]
},
["yieldLog"] = {
["enabled"] = true,
["entries"] = {
%s
},
},
}
ShatterCharDB = nil
""" % "\n".join(ENTRIES)

failures = []


def check(cond, name):
    if not cond:
        failures.append(name)
        print("  FAIL: " + name)


def write(directory, name, text):
    path = os.path.join(directory, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


with tempfile.TemporaryDirectory() as tmp:
    saved = write(tmp, "Shatter.lua", SAVED)
    rules_path = write(tmp, "DisenchantTables.lua", RULES)
    constants_path = write(tmp, "Constants.lua", CONSTANTS)

    # 1. The reader: client-written Lua, with escapes, comments, empty tables.
    g = yr.LuaReader(SAVED).globals()
    db = g["ShatterDB"]
    check(db["debugLog"][0]["message"] == 'a "quoted" path C:\\x\nnext', "string escapes")
    check(db["settings"]["window"]["x"] == -12.5, "a negative float")
    check(db["settings"]["ignoredItems"] == {}, "an empty table")
    check(g["ShatterCharDB"] is None, "nil")
    check(isinstance(db["yieldLog"]["entries"], list) and len(db["yieldLog"]["entries"]) == len(ENTRIES),
          "the entries, as a list")
    log = yr.read_log(saved)
    check(len(log) == len(ENTRIES) and log[0]["loot"] == {10940: 2}, "read_log: the entries and their loot")
    empty = write(tmp, "Empty.lua", 'ShatterDB = {\n["yieldLog"] = {\n["enabled"] = false,\n["entries"] = {\n},\n},\n}\n')
    check(yr.read_log(empty) == [], "an empty log")
    check(yr.read_log(write(tmp, "None.lua", "ShatterDB = {\n}\n")) == [], "no log")

    # 2. The table and the names.
    rules = yr.read_rules(rules_path)
    check(len(rules) == 5 and rules[-1] == (3, None, 1, 1000, 10978, 1.0, 1, 1), "rules, TOP and nil class read")
    names = yr.read_material_names(constants_path)
    check(names == {10940: "Strange Dust", 11083: "Soul Dust", 10978: "Small Glimmering Shard"}, "material names")
    check(yr.predict(rules, 2, 4, 20) == {10940: (0.75, 2, 3), 10978: (0.05, 1, 1)}, "predict a level")

    # 2b. The real table reads whole: as many rules as the file has tuples.
    real = os.path.join(REPO, "Data", "DisenchantTables.lua")
    with open(real, encoding="utf-8") as f:
        text = f.read()
    block = text[text.index("local RULES = {"):text.index("Tables.RULES = RULES")]
    tuples = len(re.findall(r"\{ \d,", block))
    check(len(yr.read_rules(real)) == tuples and tuples > 50, "the real RULES: every rule (%d)" % tuples)
    check(len(yr.read_material_names(os.path.join(REPO, "Constants.lua"))) >= 20, "the real material names")

    # 3. The report.
    out = "\n".join(yr.report(log, rules, names, min_samples=10))
    def has(s, name):
        check(s in out, name + ": " + s)
    has("%d disenchants logged (%s: %d, %s: 2)." % (len(ENTRIES), B1, len(ENTRIES) - 2, B2), "the header")
    has("Uncommon armor 20: 13 disenchants\n", "a level's count")
    has("  Strange Dust: seen 100% x2.2 (2-3); table 75% x2.5 (2-3)", "seen against the table")
    has("  Small Glimmering Shard: never seen; table 5% x1.0 (1-1)", "predicted, not seen, too rare to note")
    has("  item:2589: seen 8% x1.0 (1-1); table none  <- not in the table", "a non-material")
    has("  Strange Dust: never seen; table 75% x5.0 (4-6)  <- about 9 expected, none seen", "a material missing")
    has("  Small Glimmering Shard: seen 100% x1.0 (1-1); table 5% x1.0 (1-1)  <- chance differs", "a chance that differs")
    has("Uncommon armor 24: 1 disenchant (few samples)", "few samples marked")
    has("Uncommon armor, Soul Dust: seen at 24-26, the table has it at 26-26 (levels logged: 20-26)", "a boundary")
    boundaries = out.split("== Boundaries")[1].split("== Flagged")[0]
    check("Uncommon armor, Strange Dust" not in boundaries, "no boundary where seen and table ranges match")
    has("item:2589 (Epic armor, item level 30, %s): Small Glimmering Shard x1 - no table rule" % B1, "unmatched flagged")
    has("item:2589 (Uncommon armor, item level 20, %s): item:2589 x1, Strange Dust x2 - not a material" % B1,
        "unknown loot flagged")
    has("item:2589 (Uncommon armor, item level 24, %s): Strange Dust x5, Soul Dust x1 - a material the table doesn't predict"
        % B1, "surprise flagged")
    has("Uncommon armor 24 (1), Uncommon armor 26 (1), Epic armor 30 (1)", "too few to judge")

    # 3b. One build only.
    only = "\n".join(yr.report(log, rules, names, build=B2))
    check("2 disenchants logged" in only and "Uncommon armor 20: 2 disenchants" in only
          and "Strange Dust: seen 100% x3.0 (3-3)" in only, "--build keeps that build's entries")

    # 4. The command line.
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = yr.main(["--saved", saved, "--rules", rules_path, "--constants", constants_path])
    check(code == 0 and "Uncommon armor 20: 13 disenchants" in buf.getvalue(), "main prints the report")
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        code = yr.main(["--saved", empty, "--rules", rules_path, "--constants", constants_path])
    check(code == 1 and "No learning-mode log" in err.getvalue(), "main: no log, exit 1 and why")
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        code = yr.main(["--saved", rules_path, "--rules", rules_path, "--constants", constants_path])
    check(code == 1 and "Can't read" in err.getvalue(), "main: a file that isn't SavedVariables, exit 1 and why")

if failures:
    print("test_yield_report: %d FAILED" % len(failures))
    sys.exit(1)
print("test_yield_report: passed")
