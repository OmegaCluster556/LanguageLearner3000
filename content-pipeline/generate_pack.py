#!/usr/bin/env python3
"""Writes a brand-new monthly content pack for LanguageLearner3000 with Claude.

For every language (Russian, Ukrainian) and level (A1-C2) it:
  1. asks Claude for new words, sentences, gap-fill questions and stories around
     this month's theme, avoiding everything used in earlier months;
  2. asks Claude again, as a native-speaker editor, to proofread and fix it;
  3. runs automatic checks (validate_pack.py) and drops anything malformed.

Spending is capped (default $5 per calendar month for everything, see budget.py).
All levels of both languages are written first; proofreading passes then use
whatever budget is left. If the cap is reached, the remaining levels are filled
in by the next run (the Action also runs on the 1st of each month).

Output: packs/<ru|uk>/<YYYY-MM>.json, which the app downloads on its own.

Usage:
    export ANTHROPIC_API_KEY=...
    python generate_pack.py                  # next month (from the 15th) or this month
    python generate_pack.py --month 2026-12  # a specific month
    python generate_pack.py --budget 2       # a different monthly cap in dollars
    python generate_pack.py --dry-run        # print one prompt and the cost cap, no API calls
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

import anthropic

from budget import Budget, actual_cost, worst_case_cost
from validate_pack import LEVELS, clean_level

MAX_TOKENS = 20000  # longest reply allowed per call; also sets each call's worst-case cost

MODEL = "claude-opus-5-5"
ROOT = Path(__file__).resolve().parent.parent
PACKS_DIR = ROOT / "packs"
BUNDLED = ROOT / "LanguageLearner3000" / "Resources"

LANGUAGES = {
    "ru": {"name": "Russian", "bundled": "russian.json",
           "rules": "Use standard modern Russian. Write ё where it belongs."},
    "uk": {"name": "Ukrainian", "bundled": "ukrainian.json",
           "rules": ("Use standard modern Ukrainian (current orthography, e.g. проєкт). "
                     "Avoid Russianisms and surzhyk, and never use the letters ы, э, ъ, ё. "
                     "Use the apostrophe ' in words like п'ять, м'ясо.")},
}

LEVEL_GUIDE = {
    "A1": "absolute beginner: very common words, present tense, sentences of 3-6 words, stories of 50-70 words",
    "A2": "elementary: everyday topics, past and future, sentences up to 8 words, stories of 70-100 words",
    "B1": "intermediate: opinions, plans, experiences, subordinate clauses, stories of 100-130 words",
    "B2": "upper-intermediate: abstract topics, argument, conditionals, participles, stories of 120-160 words",
    "C1": "advanced: nuanced, formal and idiomatic language, complex syntax, stories of 140-180 words",
    "C2": "proficient: literary, rare and stylistically marked vocabulary, idioms, stories of 150-200 words",
}

# One theme per month, so each month feels different. Cycles every two years.
THEMES = [
    "food, cooking and markets", "travel and transport", "family and relationships", "work and careers",
    "health and the body", "nature, seasons and weather", "city life and housing", "shopping and money",
    "sport and hobbies", "music, film and the arts", "school, university and learning", "technology and the internet",
    "holidays and traditions", "history and famous people", "science and discoveries", "the environment",
    "emotions and personality", "media and news", "law, rights and society", "literature and folklore",
    "animals and the countryside", "architecture and design", "humour, idioms and everyday expressions",
    "space, the future and imagination",
]

COUNTS = {"vocab": 25, "sentences": 10, "gaps": 10, "readings": 2}

ITEM_SCHEMA = {
    "type": "object",
    "properties": {
        "vocab": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "w": {"type": "string"}, "m": {"type": "string"},
                "f": {"type": "array", "items": {"type": "string"}},
                "e": {"type": "string"}, "et": {"type": "string"},
            },
            "required": ["w", "m", "f", "e", "et"], "additionalProperties": False}},
        "sentences": {"type": "array", "items": {
            "type": "object",
            "properties": {"s": {"type": "string"}, "t": {"type": "string"}},
            "required": ["s", "t"], "additionalProperties": False}},
        "gaps": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "s": {"type": "string"}, "a": {"type": "string"},
                "o": {"type": "array", "items": {"type": "string"}}, "t": {"type": "string"},
            },
            "required": ["s", "a", "o", "t"], "additionalProperties": False}},
        "readings": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "title": {"type": "string"}, "text": {"type": "string"}, "translation": {"type": "string"},
                "glossary": {"type": "array", "items": {
                    "type": "object",
                    "properties": {"form": {"type": "string"}, "meaning": {"type": "string"}},
                    "required": ["form", "meaning"], "additionalProperties": False}},
                "questions": {"type": "array", "items": {
                    "type": "object",
                    "properties": {
                        "q": {"type": "string"},
                        "o": {"type": "array", "items": {"type": "string"}},
                        "a": {"type": "integer"},
                    },
                    "required": ["q", "o", "a"], "additionalProperties": False}},
            },
            "required": ["title", "text", "translation", "glossary", "questions"], "additionalProperties": False}},
    },
    "required": ["vocab", "sentences", "gaps", "readings"],
    "additionalProperties": False,
}

FORMAT_RULES = """Field meanings:
- vocab: w = dictionary form, m = short English meaning, f = other forms of the word that appear in
  this month's sentences/stories (empty list if none), e = example sentence, et = its English translation.
- sentences: s = a natural sentence, t = English translation. Words separated by single spaces.
- gaps: s = sentence containing exactly one "___", a = the one correct word for the gap,
  o = 2 or 3 wrong options (typically other forms of the same word, or near-synonyms that are
  grammatically or idiomatically wrong here). Exactly one option may be correct. t = English
  translation of the full sentence. Practise grammar typical for the level (cases, aspect, verbs
  of motion, agreement, prepositions, conjunctions).
- readings: an original short story, dialogue-free prose or article on the theme. translation =
  faithful English translation. glossary = every word form in the text a learner at this level may
  not know, as it appears in the text (lower case), with its English meaning in context; include
  multi-word expressions by glossing each word with a hint to the whole expression, in the
  form "<meaning of the word> (<whole expression> = <its English meaning>)".
  questions = 3 comprehension questions in English, each with 3 English options, a = index (0-2)
  of the correct option. Questions must be answerable only from the text.
All English text must be in English only (no Cyrillic). All target-language text must be in the
target language only."""


def default_month(today: dt.date | None = None) -> str:
    """From the 15th on, prepare next month; before that, finish the current month."""
    today = today or dt.datetime.now(dt.timezone.utc).date()
    year, month = today.year, today.month
    if today.day >= 15:
        year, month = (year + 1, 1) if month == 12 else (year, month + 1)
    return f"{year:04d}-{month:02d}"


def theme_for(month: str) -> str:
    year, mon = map(int, month.split("-"))
    return THEMES[(year * 12 + mon) % len(THEMES)]


def existing_content(lang: str) -> dict[str, dict[str, list[str]]]:
    """Headwords and story titles already used (bundled course + earlier packs)."""
    used = {lvl: {"words": [], "titles": []} for lvl in LEVELS}
    files = [BUNDLED / LANGUAGES[lang]["bundled"], *sorted((PACKS_DIR / lang).glob("*.json"))]
    for path in files:
        if not path.exists():
            continue
        pack = json.loads(path.read_text(encoding="utf-8"))
        for lvl, content in pack.get("levels", {}).items():
            if lvl in used:
                used[lvl]["words"] += [v["w"] for v in content.get("vocab", [])]
                used[lvl]["titles"] += [r["title"] for r in content.get("readings", [])]
    return used


def generation_prompt(lang: str, level: str, month: str, used: dict[str, list[str]]) -> str:
    info = LANGUAGES[lang]
    avoid_words = ", ".join(used["words"][-600:]) or "(none yet)"
    avoid_titles = "; ".join(used["titles"][-60:]) or "(none yet)"
    return f"""Create fresh {info['name']} learning material for an English-speaking learner.

Level: {level} ({LEVEL_GUIDE[level]}).
Theme for {month}: {theme_for(month)}. Stay mostly on the theme, but include useful general words too.

Produce exactly: {COUNTS['vocab']} vocab items, {COUNTS['sentences']} sentences, {COUNTS['gaps']} gaps,
{COUNTS['readings']} readings.

Language rules: {info['rules']}
Do not use stress marks. Keep sentences for A1-B1 to at most 10 words.

Do NOT reuse these headwords (already taught): {avoid_words}
Do NOT reuse these story titles: {avoid_titles}

{FORMAT_RULES}

Before answering, double-check every item for grammar, spelling, natural word choice, correct
English translations, and that each gap has only one correct answer."""


def review_prompt(lang: str, level: str, draft: dict) -> str:
    info = LANGUAGES[lang]
    return f"""You are a native {info['name']} speaker and an experienced language teacher.
Proofread this {level} learning material and return a corrected version in the same structure.

Fix: grammar, spelling, case endings, aspect, unnatural or calqued phrasing, words that do not
match level {level}, wrong or loose English translations, glossary entries that do not match the
form in the text, gaps where more than one option is correct, and comprehension questions whose
answer is not supported by the text. {info['rules']}
Keep everything that is already correct unchanged. Keep the same number of items.

{FORMAT_RULES}

Material to review:
{json.dumps(draft, ensure_ascii=False, indent=1)}"""


class CallFailed(RuntimeError):
    pass


def ask_claude(client: anthropic.Anthropic, prompt: str, budget: Budget) -> dict:
    """One Claude call. Its cost is added to the monthly ledger even if it fails."""
    # Streaming avoids HTTP timeouts on long outputs. If a safety classifier declines
    # (rare for this content), the server retries on the fallback model; budget.py
    # prices calls at that model's higher rate.
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=MAX_TOKENS,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks=[{"model": "claude-opus-4-8"}],
        output_config={
            "effort": "medium",
            "format": {"type": "json_schema", "schema": ITEM_SCHEMA},
        },
        messages=[{"role": "user", "content": prompt}],
    ) as stream:
        message = stream.get_final_message()
    cost = actual_cost(message)
    budget.record(cost)
    print(f"      cost ${cost:.3f} (month so far ${budget.spent:.2f} of ${budget.limit:.2f})")
    if message.stop_reason == "refusal":
        raise CallFailed(f"request declined: {message.stop_details}")
    if message.stop_reason == "max_tokens":
        raise CallFailed("reply was too long and got cut off")
    text = next(b.text for b in message.content if b.type == "text")
    return json.loads(text)


def try_call(client, prompt: str, budget: Budget, label: str) -> dict | None:
    """Runs a call only if its worst-case cost still fits in the monthly budget."""
    worst = worst_case_cost(prompt, MAX_TOKENS)
    if not budget.can_afford(worst):
        print(f"[{label}] skipped: ${budget.remaining:.2f} left this month, "
              f"a call may cost up to ${worst:.2f}")
        return None
    print(f"[{label}] asking Claude…")
    try:
        return ask_claude(client, prompt, budget)
    except (CallFailed, json.JSONDecodeError, StopIteration) as exc:
        print(f"[{label}] failed: {exc}", file=sys.stderr)
    except anthropic.APIStatusError as exc:
        print(f"[{label}] API error {exc.status_code}: {exc.message}", file=sys.stderr)
    except anthropic.APIConnectionError as exc:
        print(f"[{label}] connection error: {exc}", file=sys.stderr)
    return None


def load_pack(path: Path, month: str) -> dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"version": month, "theme": theme_for(month), "levels": {}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--month", default=default_month(), help="YYYY-MM")
    parser.add_argument("--languages", default="ru,uk", help="comma-separated: ru,uk")
    parser.add_argument("--levels", default=",".join(LEVELS), help="comma-separated, e.g. A1,A2")
    parser.add_argument("--budget", type=float, default=float(os.environ.get("MONTHLY_BUDGET_USD", "5")),
                        help="max dollars to spend per calendar month, all runs together (default 5)")
    parser.add_argument("--no-review", action="store_true", help="skip proofreading passes")
    parser.add_argument("--force", action="store_true", help="rewrite levels that already exist")
    parser.add_argument("--dry-run", action="store_true", help="print one prompt and the budget, no API calls")
    args = parser.parse_args()

    langs = [l for l in args.languages.split(",") if l in LANGUAGES]
    levels = [l for l in args.levels.split(",") if l in LEVELS]
    budget = Budget(args.budget, PACKS_DIR / "spend.json")
    print(f"Target month: {args.month}. Budget: ${budget.spent:.2f} spent of ${budget.limit:.2f} "
          f"in {budget.month}.")

    packs = {lang: load_pack(PACKS_DIR / lang / f"{args.month}.json", args.month) for lang in langs}
    used = {lang: existing_content(lang) for lang in langs}
    # Interleave languages so both get the same levels if the budget runs out.
    todo = [(lang, lvl) for lvl in levels for lang in langs
            if args.force or lvl not in packs[lang]["levels"]]
    if not todo:
        print("This month's packs are already complete.")
        return 0

    if args.dry_run:
        lang, lvl = todo[0]
        prompt = generation_prompt(lang, lvl, args.month, used[lang][lvl])
        print(prompt)
        print(f"\n{len(todo)} level(s) to write. Worst case per call: "
              f"${worst_case_cost(prompt, MAX_TOKENS):.2f}")
        return 0

    client = anthropic.Anthropic()
    drafts: dict[tuple[str, str], dict] = {}

    # Pass 1: write every level.
    for lang, lvl in todo:
        prompt = generation_prompt(lang, lvl, args.month, used[lang][lvl])
        result = try_call(client, prompt, budget, f"{lang} {lvl} write")
        if result is not None:
            drafts[(lang, lvl)] = result

    # Pass 2: proofread with whatever budget is left.
    if not args.no_review:
        for (lang, lvl), draft in list(drafts.items()):
            reviewed = try_call(client, review_prompt(lang, lvl, draft), budget, f"{lang} {lvl} proofread")
            if reviewed is not None:
                drafts[(lang, lvl)] = reviewed

    # Check, clean and save.
    for (lang, lvl), draft in drafts.items():
        for i, reading in enumerate(draft.get("readings", []), start=1):
            reading["id"] = f"{lang}-{lvl.lower()}-{args.month}-{i}"
        problems: list[str] = []
        existing = {w.lower().replace("ё", "е") for w in used[lang][lvl]["words"]}
        content = clean_level(draft, lang, existing, problems)
        packs[lang]["levels"][lvl] = content
        print(f"[{lang} {lvl}] {len(content['vocab'])} words, {len(content['sentences'])} sentences, "
              f"{len(content['gaps'])} gaps, {len(content['readings'])} stories"
              + (f" ({len(problems)} item(s) dropped)" if problems else ""))
        for p in problems:
            print(f"    - {p}")

    for lang in langs:
        pack = packs[lang]
        if not pack["levels"]:
            continue
        pack["levels"] = {lvl: pack["levels"][lvl] for lvl in LEVELS if lvl in pack["levels"]}
        out_path = PACKS_DIR / lang / f"{args.month}.json"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(pack, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"Wrote {out_path} ({len(pack['levels'])} of 6 levels)")

    missing = [f"{lang} {lvl}" for lang in langs for lvl in levels if lvl not in packs[lang]["levels"]]
    print(f"Spent this month: ${budget.spent:.2f} of ${budget.limit:.2f}.")
    if missing:
        print("Not written yet (next run will continue): " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
