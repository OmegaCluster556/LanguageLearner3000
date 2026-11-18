#!/usr/bin/env python3
"""Checks and cleans a LanguageLearner3000 content pack.

Bad items are dropped (not the whole pack), so one mistake from the generator
never breaks the app. Run on its own to check a file:

    python validate_pack.py ../packs/ru/2026-12.json
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]

CYRILLIC = re.compile(r"[А-Яа-яЁёІіЇїЄєҐґ]")
# Letters that exist in only one of the two languages.
RUSSIAN_ONLY = re.compile(r"[ЫыЭэЪъЁё]")
UKRAINIAN_ONLY = re.compile(r"[ІіЇїЄєҐґ]")


def _norm(word: str) -> str:
    return word.lower().replace("ё", "е").replace("’", "'").strip(" .,!?;:«»\"")


def _target_ok(text: str, lang: str) -> bool:
    if not isinstance(text, str) or not text.strip() or not CYRILLIC.search(text):
        return False
    wrong = RUSSIAN_ONLY if lang == "uk" else UKRAINIAN_ONLY
    return not wrong.search(text)


def _english_ok(text: str) -> bool:
    """English text; short Cyrillic hints like "despite (несмотря на)" are allowed."""
    if not isinstance(text, str):
        return False
    outside_brackets = re.sub(r"\([^)]*\)", "", text)
    return bool(re.search(r"[A-Za-z]", outside_brackets)) and not CYRILLIC.search(outside_brackets)


def clean_level(content: dict, lang: str, existing_words: set[str] | None = None,
                problems: list[str] | None = None) -> dict:
    """Returns a cleaned copy of one level's content."""
    existing_words = existing_words or set()
    problems = problems if problems is not None else []
    out = {"vocab": [], "sentences": [], "gaps": [], "readings": []}

    seen = set(existing_words)
    for v in content.get("vocab", []):
        w = v.get("w", "")
        if not _target_ok(w, lang) or not _english_ok(v.get("m", "")):
            problems.append(f"vocab dropped (bad text): {w!r}")
            continue
        if _norm(w) in seen:
            problems.append(f"vocab dropped (repeat): {w!r}")
            continue
        seen.add(_norm(w))
        item = {"w": w.strip(), "m": v["m"].strip()}
        forms = [f.strip() for f in v.get("f") or [] if _target_ok(f, lang) and _norm(f) != _norm(w)]
        if forms:
            item["f"] = sorted(set(forms), key=forms.index)
        if _target_ok(v.get("e", ""), lang) and _english_ok(v.get("et", "")):
            item["e"], item["et"] = v["e"].strip(), v["et"].strip()
        out["vocab"].append(item)

    seen_sent = set()
    for s in content.get("sentences", []):
        text = s.get("s", "")
        if not _target_ok(text, lang) or not _english_ok(s.get("t", "")) or "___" in text:
            problems.append(f"sentence dropped: {text!r}")
            continue
        if len(text.split()) > 12 or text in seen_sent:
            problems.append(f"sentence dropped (too long/repeat): {text!r}")
            continue
        seen_sent.add(text)
        out["sentences"].append({"s": text.strip(), "t": s["t"].strip()})

    for g in content.get("gaps", []):
        s, a = g.get("s", ""), g.get("a", "")
        options = [o.strip() for o in g.get("o") or [] if _target_ok(o, lang)]
        options = [o for o in dict.fromkeys(options) if _norm(o) != _norm(a)]
        if (s.count("___") != 1 or not _target_ok(s.replace("___", ""), lang) or not _target_ok(a, lang)
                or not 2 <= len(options) <= 3 or not _english_ok(g.get("t", ""))):
            problems.append(f"gap dropped: {s!r}")
            continue
        out["gaps"].append({"s": s.strip(), "a": a.strip(), "o": options, "t": g["t"].strip()})

    for r in content.get("readings", []):
        text = r.get("text", "")
        if not _target_ok(text, lang) or not _english_ok(r.get("translation", "")) or not r.get("title"):
            problems.append(f"reading dropped: {r.get('title')!r}")
            continue
        questions = []
        for q in r.get("questions", []):
            opts = q.get("o") or []
            if (_english_ok(q.get("q", "")) and 2 <= len(opts) <= 4 and all(_english_ok(o) for o in opts)
                    and isinstance(q.get("a"), int) and 0 <= q["a"] < len(opts) and len(set(opts)) == len(opts)):
                questions.append({"q": q["q"], "o": opts, "a": q["a"]})
            else:
                problems.append(f"question dropped in {r.get('title')!r}")
        if len(questions) < 2:
            problems.append(f"reading dropped (too few questions): {r.get('title')!r}")
            continue
        glossary = r.get("glossary") or {}
        if isinstance(glossary, list):  # generator format: [{"form", "meaning"}]
            glossary = {g.get("form", ""): g.get("meaning", "") for g in glossary}
        glossary = {k.strip().lower(): v.strip() for k, v in glossary.items()
                    if _target_ok(k, lang) and _english_ok(v)}
        out["readings"].append({
            "id": r.get("id") or f"{lang}-{abs(hash(text)) % 10**8}",
            "title": r["title"].strip(), "text": text.strip(),
            "translation": r["translation"].strip(), "glossary": glossary, "questions": questions,
        })
    return out


def clean_pack(pack: dict, lang: str, existing: dict[str, set[str]] | None = None) -> tuple[dict, list[str]]:
    existing = existing or {}
    problems: list[str] = []
    levels = {}
    for level in LEVELS:
        if level in pack.get("levels", {}):
            level_problems: list[str] = []
            levels[level] = clean_level(pack["levels"][level], lang, existing.get(level), level_problems)
            problems += [f"{level}: {p}" for p in level_problems]
    return {"version": pack.get("version"), "levels": levels}, problems


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    failed = False
    for path in map(Path, sys.argv[1:]):
        if not path.is_file() or path.name == "spend.json":
            continue
        lang = "uk" if ("/uk/" in str(path) or "ukrainian" in path.name) else "ru"
        pack = json.loads(path.read_text(encoding="utf-8"))
        cleaned, problems = clean_pack(pack, lang)
        print(f"{path}: {len(problems)} problem(s)")
        for p in problems:
            print("  -", p)
        for level, c in cleaned["levels"].items():
            print(f"  {level}: {len(c['vocab'])} vocab, {len(c['sentences'])} sentences, "
                  f"{len(c['gaps'])} gaps, {len(c['readings'])} readings")
        failed |= bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
