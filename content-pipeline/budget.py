"""Monthly spending cap for the content generator.

Every Claude call is priced from the token usage the API reports, and the running
total for the calendar month (UTC) is saved in packs/spend.json, which the GitHub
Action commits after each run. So the cap holds across all runs in a month, manual
or scheduled.

Before each call, the generator reserves that call's *worst-case* price (the full
prompt plus the maximum reply length, at the most expensive model it may use). A
call starts only if that worst case still fits under the cap, so the month's total
can't go over the limit, even if a call runs long.
"""
from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

# US dollars per million tokens: (input, output). From Anthropic's price list.
PRICES = {
    "claude-opus-5-5": (4.00, 20.00),
    "claude-opus-4-8": (5.00, 25.00),   # the fallback model if a request is declined
    "claude-opus-5": (5.00, 25.00),
}
WORST_PRICE = max(PRICES.values(), key=lambda p: p[1])


def month_key(now: dt.datetime | None = None) -> str:
    now = now or dt.datetime.now(dt.timezone.utc)
    return f"{now.year:04d}-{now.month:02d}"


def worst_case_cost(prompt: str, max_tokens: int) -> float:
    # Overestimate input: Cyrillic text can be close to 1 token per 2 characters.
    input_tokens = len(prompt) / 2 + 500
    price_in, price_out = WORST_PRICE
    return (input_tokens * price_in + max_tokens * price_out) / 1_000_000


def actual_cost(message) -> float:
    """Price of one API response from its reported usage."""
    usage = message.usage
    price_in, price_out = PRICES.get(getattr(message, "model", ""), WORST_PRICE)
    # If a fallback model took over, price everything at the higher rate (cautious).
    if any(getattr(it, "type", "") == "fallback_message" for it in (getattr(usage, "iterations", None) or [])):
        price_in, price_out = WORST_PRICE
    tokens_in = (usage.input_tokens or 0) \
        + 1.25 * (getattr(usage, "cache_creation_input_tokens", 0) or 0) \
        + 0.10 * (getattr(usage, "cache_read_input_tokens", 0) or 0)
    return (tokens_in * price_in + (usage.output_tokens or 0) * price_out) / 1_000_000


class Budget:
    def __init__(self, limit_usd: float, ledger: Path, month: str | None = None):
        self.limit = limit_usd
        self.ledger = ledger
        self.month = month or month_key()
        data = json.loads(ledger.read_text()) if ledger.exists() else {}
        self.data: dict[str, float] = {k: float(v) for k, v in data.items()}

    @property
    def spent(self) -> float:
        return self.data.get(self.month, 0.0)

    @property
    def remaining(self) -> float:
        return max(0.0, self.limit - self.spent)

    def can_afford(self, worst_case: float) -> bool:
        return self.spent + worst_case <= self.limit

    def record(self, cost: float) -> None:
        self.data[self.month] = round(self.spent + cost, 4)
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        self.ledger.write_text(json.dumps(dict(sorted(self.data.items())), indent=1) + "\n")
