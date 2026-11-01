"""Set learning mode's disenchant log (#40) against Shatter's table.

Learning mode (`/shatter learn on`, hidden from Settings and the command list,
off by default) logs every disenchant whose loot window Shatter read in
ShatterDB.yieldLog. This reads the SavedVariables (written at /reload or
logout), groups the log by quality, armor or weapon, and item level, and sets
each material's observed chance and amount against the rules in
Data/DisenchantTables.lua. It lists:
  - each item level, with the materials seen and the table's prediction;
  - boundaries: where a material is seen against where the table has it;
  - flagged entries: no table rule, loot that isn't a material, a material
    the table doesn't predict for the item;
  - item levels with too few disenchants to judge.

    python Tools/yield_report.py                  # every account under _forever_
    python Tools/yield_report.py --saved <path/to/Shatter.lua> [--build 1.60.1.70685] [--min-samples 10]

Standard library only. tests/test_yield_report.py covers it.
"""

import argparse
import glob
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_WTF = r"C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account"

ARMOR, WEAPON = 4, 2
QUALITY_NAMES = {2: "Uncommon", 3: "Rare", 4: "Epic"}
CLASS_NAMES = {ARMOR: "armor", WEAPON: "weapon"}


# --- Reading SavedVariables -------------------------------------------------

class LuaReader:
    """Just enough Lua to read a SavedVariables file: assignments of
    strings, numbers, booleans, nil and tables to globals."""

    TOKEN = re.compile(r"""
        (?P<space>\s+|--[^\n]*)
      | (?P<string>"(?:[^"\\]|\\.)*")
      | (?P<number>-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)
      | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<punct>[{}\[\]=,;])
    """, re.VERBOSE | re.DOTALL)

    def __init__(self, text):
        self.tokens = []
        pos = 0
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                raise ValueError("unexpected %r at offset %d" % (text[pos:pos + 20], pos))
            pos = m.end()
            if m.lastgroup != "space":
                self.tokens.append((m.lastgroup, m.group()))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, value=None):
        tok = self.peek()
        if value is not None and tok[1] != value:
            raise ValueError("expected %r, got %r" % (value, tok[1]))
        self.i += 1
        return tok

    def globals(self):
        out = {}
        while self.peek()[0] is not None:
            kind, name = self.take()
            if kind != "name":
                raise ValueError("expected a global name, got %r" % name)
            self.take("=")
            out[name] = self.value()
        return out

    def value(self):
        kind, text = self.take()
        if kind == "string":
            return unescape(text[1:-1])
        if kind == "number":
            return float(text) if any(c in text for c in ".eE") else int(text)
        if kind == "name" and text in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[text]
        if text == "{":
            return self.table()
        raise ValueError("unexpected %r" % text)

    def table(self):
        result, n = {}, 0
        while self.peek()[1] != "}":
            kind, text = self.peek()
            if text == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
                result[key] = self.value()
            elif kind == "name" and self.tokens[self.i + 1][1] == "=":
                self.take()
                self.take("=")
                result[text] = self.value()
            else:
                n += 1
                result[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        if result and set(result) == set(range(1, len(result) + 1)):
            return [result[k] for k in range(1, len(result) + 1)]
        return result


ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unescape(s):
    def repl(m):
        e = m.group(1)
        return chr(int(e)) if e.isdigit() else ESCAPES.get(e, e)
    return re.sub(r"\\(\d{1,3}|.)", repl, s, flags=re.DOTALL)


def read_log(path):
    """The yieldLog entries in one Shatter.lua, or [] without a log."""
    with open(path, encoding="utf-8", errors="replace") as f:
        db = LuaReader(f.read()).globals().get("ShatterDB")
    log = db.get("yieldLog") if isinstance(db, dict) else None
    entries = log.get("entries") if isinstance(log, dict) else None
    if isinstance(entries, dict):    # an empty Lua table reads as {}
        entries = list(entries.values())
    return [e for e in entries or [] if isinstance(e, dict)]


# --- Shatter's own table ----------------------------------------------------

RULE_RE = re.compile(r"\{\s*(\d)\s*,\s*(ARMOR|WEAPON|nil)\s*,\s*(\d+)\s*,\s*(\d+|TOP)\s*,\s*(\d+)\s*,"
                     r"\s*([\d.]+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}")


def read_rules(path):
    """RULES from Data/DisenchantTables.lua, as tuples
    (quality, classID or None, minLevel, maxLevel, material, chance, minAmount, maxAmount)."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    top = int(re.search(r"local TOP = (\d+)", text).group(1))
    block = text[text.index("local RULES = {"):text.index("Tables.RULES = RULES")]
    classes = {"ARMOR": ARMOR, "WEAPON": WEAPON, "nil": None}
    rules = []
    for q, c, lo, hi, mat, chance, mn, mx in RULE_RE.findall(block):
        rules.append((int(q), classes[c], int(lo), top if hi == "TOP" else int(hi), int(mat),
                      float(chance), int(mn), int(mx)))
    if not rules:
        raise ValueError("no rules found in %s" % path)
    return rules


def read_material_names(path):
    """Material names from Constants.MATERIAL_ITEM_IDS' comments."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    start = text.index("Constants.MATERIAL_ITEM_IDS = {")
    block = text[start:text.index("}", start)]
    return {int(i): name.strip() for i, name in re.findall(r"\[(\d+)\]\s*=\s*true,\s*--\s*([^\n]+)", block)}


def predict(rules, quality, classID, level):
    """The table's materials for an item: {material: (chance, minAmount, maxAmount)}."""
    out = {}
    for q, c, lo, hi, mat, chance, mn, mx in rules:
        if q == quality and lo <= level <= hi and (c is None or c == classID):
            p, a, b = out.get(mat, (0.0, mn, mx))
            out[mat] = (p + chance, min(a, mn), max(b, mx))
    return out


# --- The report -------------------------------------------------------------

def group_label(quality, classID):
    return "%s %s" % (QUALITY_NAMES.get(quality, "quality %s" % quality), CLASS_NAMES.get(classID, "other"))


def material_name(names, itemID):
    return names.get(itemID, "item:%s" % itemID)


def loot_of(entry):
    loot = entry.get("loot")
    if isinstance(loot, list):    # ids 1..n read as a list
        loot = {i + 1: c for i, c in enumerate(loot)}
    return {int(k): v for k, v in (loot or {}).items() if isinstance(v, (int, float)) and v > 0}


def flags_of(entry):
    flags = []
    if entry.get("unmatched"):
        flags.append("no table rule")
    if entry.get("unknownLoot"):
        flags.append("not a material")
    if entry.get("surprise"):
        flags.append("a material the table doesn't predict")
    return flags


def report(entries, rules, names, min_samples=10, build=None):
    lines = []
    builds = {}
    for e in entries:
        builds[e.get("build", "?")] = builds.get(e.get("build", "?"), 0) + 1
    if build:
        entries = [e for e in entries if e.get("build") == build]
    lines.append("%d disenchants logged (%s)%s." % (
        len(entries), ", ".join("%s: %d" % (b, n) for b, n in sorted(builds.items())),
        "; build %s only" % build if build else ""))

    groups = {}
    for e in entries:
        if not isinstance(e.get("quality"), int) or not isinstance(e.get("itemLevel"), int):
            continue
        key = (e["quality"], e.get("classID") if e.get("classID") in CLASS_NAMES else None, e["itemLevel"])
        groups.setdefault(key, []).append(e)

    lines.append("")
    lines.append("== By item level (seen: chance, average amount, range; table: the same) ==")
    few = []
    seen_levels = {}    # (quality, classID, material) -> [levels seen]
    logged_levels = {}  # (quality, classID) -> [levels logged]
    for key in sorted(groups, key=lambda k: (k[0], k[1] or 0, k[2])):
        quality, classID, level = key
        group = groups[key]
        n = len(group)
        logged_levels.setdefault((quality, classID), []).append(level)
        if n < min_samples:
            few.append("%s %d (%d)" % (group_label(quality, classID), level, n))
        lines.append("%s %d: %d disenchant%s%s" % (group_label(quality, classID), level, n, "" if n == 1 else "s",
                                                  " (few samples)" if n < min_samples else ""))
        observed = {}
        for e in group:
            for mat, count in loot_of(e).items():
                o = observed.setdefault(mat, [0, 0, count, count])
                o[0] += 1
                o[1] += count
                o[2], o[3] = min(o[2], count), max(o[3], count)
        table = predict(rules, quality, classID, level)
        for mat in sorted(set(observed) | set(table), key=lambda m: (-(observed.get(m, [0])[0]), m)):
            o, t = observed.get(mat), table.get(mat)
            seen = ("seen %d%% x%.1f (%d-%d)" % (round(100.0 * o[0] / n), float(o[1]) / o[0], o[2], o[3])
                    if o else "never seen")
            pred = ("table %g%% x%.1f (%d-%d)" % (round(100 * t[0], 1), (t[1] + t[2]) / 2.0, t[1], t[2])
                    if t else "table none")
            note = ""
            if o and not t:
                note = "  <- not in the table"
            elif t and not o and n * t[0] >= 3:
                note = "  <- about %d expected, none seen" % round(n * t[0])
            elif o and t and n >= min_samples and 0 < t[0] < 1:
                se = math.sqrt(t[0] * (1 - t[0]) / n)
                if abs(float(o[0]) / n - t[0]) > 3 * se:
                    note = "  <- chance differs"
            lines.append("  %s: %s; %s%s" % (material_name(names, mat), seen, pred, note))
            if o:
                seen_levels.setdefault((quality, classID, mat), []).append(level)

    lines.append("")
    lines.append("== Boundaries (levels a material is seen at, against the table, within the levels logged) ==")
    boundary_lines = []
    for (quality, classID, mat) in sorted(seen_levels, key=lambda k: (k[0], k[1] or 0, k[2])):
        levels = seen_levels[(quality, classID, mat)]
        logged = logged_levels[(quality, classID)]
        table_levels = [lv for lv in logged if mat in predict(rules, quality, classID, lv)]
        # Ranges, not sets: a 5% shard is missing from most levels by chance.
        if table_levels and (min(levels), max(levels)) == (min(table_levels), max(table_levels)):
            continue
        table_text = "%d-%d" % (min(table_levels), max(table_levels)) if table_levels else "none"
        boundary_lines.append("%s, %s: seen at %d-%d, the table has it at %s (levels logged: %d-%d)" % (
            group_label(quality, classID), material_name(names, mat), min(levels), max(levels), table_text,
            min(logged), max(logged)))
    lines.extend(boundary_lines or ["None: every material is seen over the levels the table has it."])

    lines.append("")
    lines.append("== Flagged ==")
    flagged = [e for e in entries if flags_of(e)]
    for e in flagged:
        loot = ", ".join("%s x%d" % (material_name(names, m), c) for m, c in sorted(loot_of(e).items()))
        lines.append("item:%s (%s, item level %s, %s): %s - %s" % (
            e.get("itemID"), group_label(e.get("quality"), e.get("classID")), e.get("itemLevel"),
            e.get("build", "?"), loot, ", ".join(flags_of(e))))
    if not flagged:
        lines.append("None.")

    lines.append("")
    lines.append("== Too few to judge (under %d disenchants) ==" % min_samples)
    lines.append(", ".join(few) if few else "None.")
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--saved", action="append",
                        help="a Shatter.lua SavedVariables file (repeatable); default: every account under _forever_")
    parser.add_argument("--build", help="only this client build, e.g. 1.60.1.70685")
    parser.add_argument("--min-samples", type=int, default=10, help="fewer disenchants than this at a level: too few")
    parser.add_argument("--rules", default=os.path.join(REPO, "Data", "DisenchantTables.lua"))
    parser.add_argument("--constants", default=os.path.join(REPO, "Constants.lua"))
    args = parser.parse_args(argv)

    paths = args.saved or sorted(glob.glob(os.path.join(DEFAULT_WTF, "*", "SavedVariables", "Shatter.lua")))
    if not paths:
        print("No Shatter.lua under %s; pass --saved." % DEFAULT_WTF, file=sys.stderr)
        return 1
    entries = []
    for path in paths:
        try:
            entries.extend(read_log(path))
        except (OSError, ValueError) as err:
            print("Can't read %s: %s" % (path, err), file=sys.stderr)
            return 1
    if not entries:
        print("No learning-mode log in %s (/shatter learn on, then /reload)." % ", ".join(paths), file=sys.stderr)
        return 1
    rules = read_rules(args.rules)
    names = read_material_names(args.constants)
    for line in report(entries, rules, names, args.min_samples, args.build):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
