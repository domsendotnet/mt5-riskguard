# Settings reference (RiskGuard 1.23)

These names are **exactly** what you see in MetaTrader:

**Right-click the chart → Expert list → Properties → Inputs.**

There are **27** settings in **5 groups**. Everything else is built in (stop always on, pendings always watched, extras always same-direction, and so on). You still choose the **policy**. RiskGuard chooses the **mechanics**.

**Upgrading from 1.11 or earlier:** remove the EA from the chart and attach it again. The Inputs list was rebuilt. Old saved values would land on the wrong lines.

---

## How to read the numbers

| Phrase | Meaning |
|--------|---------|
| **Your money** | EUR, USD, or whatever the account is in |
| **Per 0.01 lot** | The unit. 0.02 lot = twice that money |
| **Example** | Stop 3.0 per 0.01 on a 0.02 lot → about **6.0** of your money if the stop is hit |
| **0 = off** | For timers, day lock, extras, and revenge pause |

Defaults assume a roughly **2,000** account and **1-minute gold**.

---

## The numbers most people change

| What you see | Default | In one sentence |
|--------------|---------|-----------------|
| Biggest lot on ONE trade | `0.05` | Hard cap. Greedy size dies here. |
| Worst loss allowed per 0.01 lot | `5.0` | Ceiling. A stop cannot sit farther than this. |
| Normal stop: lose this much per 0.01 lot if hit | `3.0` | Breathing room. Must be ≤ the ceiling. |
| Take-profit: bank this much per 0.01 lot | `4.0` | Where a single scalp is taken off. |
| How many extras (0 = never add) | `2` | `0` turns adding off. |
| Add only if EVERY open trade is this lot or smaller | `0.02` | Bigger than this already in? No add. |
| Your broker commission per 0.01 lot | `0.04` | **Put your real cost here.** |

Leave the rest until you know you need it.

---

## 1. Start

| What you see | Default | Meaning |
|--------------|---------|---------|
| Protection ON. OFF = chart box only, no closes | `true` | Master switch. OFF still draws the box but **does not protect you**. |
| Which trades to watch | All trades (manual and EA) | **All** = everything on this symbol. **Only my manual trades** = ignore other EAs. **Only one EA** = type that EA’s magic number next. |
| Magic number — ignore unless "one EA" is selected above | `0` | Ignored unless you picked “one EA”. |
| Also watch these symbols. Empty = this chart only | empty | Optional extras. This chart is always watched. |

This chart’s symbol is always included. There is no “watch the whole account” switch — that was too easy to get wrong.

---

## 2. Your money

| What you see | Default | Meaning |
|--------------|---------|---------|
| Biggest lot on ONE trade | `0.05` | A bigger fill is shrunk, or closed if it cannot be shrunk. |
| Worst loss allowed per 0.01 lot (your money) | `5.0` | Hard ceiling. RiskGuard pulls the stop in to this. If the broker will not take that stop *yet* (gold min distance), it keeps the tightest legal stop and retries — it does not close the trade. |
| Normal stop: lose this much per 0.01 lot if hit | `3.0` | The usual breath. |
| Take-profit: bank this much per 0.01 lot | `4.0` | The usual bank. With 2+ trades open, per-trade targets are cleared so they exit together instead. |
| One trade may not risk more than this % of the account | `1.0` | Size vs account. Uses **equity** (open P/L counts). |
| All open trades together may not risk more than this % | `2.0` | If combined risk is too high, the **fattest** risk is closed first. |

Stops and targets are always in **money per 0.01 lot**. There is no points / R-multiple mode — convert to money once and you are done.

---

## 3. Adding to losers

`How many extras = 0` means never add. That **is** the on/off switch.

Adds are allowed only when **all** of this is true:

- extras > 0
- the account can hold several trades on one symbol (hedging)
- the day is not locked, and you are not in the revenge pause
- every open trade is ≤ the add-on lot
- open risk % is ≤ the add-on risk %
- you have not used up original + extras

Otherwise the extra is closed (a pending extra is deleted). Buy+sell mix is always rejected.

| What you see | Default | Meaning |
|--------------|---------|---------|
| How many extras (0 = never add). Original + this many. | `2` | Cap is always **1 + extras**. |
| Add only if EVERY open trade is this lot or smaller | `0.02` | |
| Add only if open risk is this % of the account or less | `0.50` | |
| Close all together at this tiny profit (your money, before commission) | `0.01` | Combined “just green”. |
| Your broker commission per 0.01 lot | `0.04` | Folded into the combined target so a fake BE does not print a loss. |

They close together when:

```text
combined profit ≥ tiny profit + commission per 0.01 × (lots / 0.01)
```

Example: two 0.01 lots, tiny profit 0.01, commission 0.04 → close at combined P/L ≥ **0.09**.

---

## 4. Cut losers / stop the day

Timers apply to a **single** trade. With 2+ trades, the timer is skipped — they exit together at tiny profit instead.

“In profit” for the timer means **after commission**.

| What you see | Default | Meaning |
|--------------|---------|---------|
| Close a single trade still not in profit after N seconds (0 = off) | `120` | Two 1-minute candles. |
| Never hold a single trade longer than N seconds (0 = off) | `180` | Three 1-minute candles. |
| Do not time-close if profit after costs is at least this | `0.50` | A real winner is left for the take-profit. |
| Lock the day if equity is down this % from this morning (0 = off) | `3.0` | Includes open losses. Then everything watched is closed, and it keeps trying until they are gone. |
| Lock the day after this many closed trades (0 = off) | `40` | Overtrading cap. |
| After a loss, block NEW trades for N seconds (0 = off) | `120` | Existing trades stay. New fills and pendings die. Partials do not start this. |
| Risk-day restarts at this broker-server hour (0 = midnight) | `0` | |

Set **both** day-loss % and trade-count to `0` if you do not want a day lock at all.

Reloading the EA does **not** reset the day lock.

---

## 5. Alerts and panel

| What you see | Default | Meaning |
|--------------|---------|---------|
| How to tell you when RiskGuard acts | Pop-up and sound | Silent / pop-up / pop-up+sound / pop-up+sound+phone. The Experts log always records actions. |
| Show the status box on the chart | `true` | |
| Chart corner for the box | Left upper | |
| Left-right / up-down offset (pixels) | `12` / `24` | Nudge it off your candles. |

Look (font, colors) is built in. It is not a settings job.

---

## Always on (not in the dialog)

This is the product. You do not turn these off:

- Stop on every trade; put it back if you delete it; snap it if you widen it past the ceiling
- Target on a single trade; with 2+ trades, combined tiny-profit exit owns the exit
- Illegal pending orders are deleted before they fill
- Extra trades must be the same direction
- Too-big lots: shrink, or close if shrinking fails
- Day lock closes everything watched (when a day limit is set)
- Equity is the % base (open P/L counts)
- Checks every tick, plus every 1 second if the market is quiet
- This chart’s symbol is always watched

That is not less power. It is the guardian refusing to be talked into “just this once”.

---

## Quick math (2,000 account)

| Lot | Stop 3.0 / 0.01 | Worst 5.0 / 0.01 |
|-----|-----------------|------------------|
| 0.01 | ~3 | ~5 |
| 0.02 | ~6 | ~10 |
| 0.05 | ~15 | ~25 |

0.01–0.02 is “tiny risk” → adding may be allowed. 0.05 is already max lot → adding is blocked.
