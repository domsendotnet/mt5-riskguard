# Settings reference (RiskGuard 1.11)

These names are **exactly** what you see in MetaTrader:

**Right-click the chart → Expert list → Properties → Inputs.**

You do not need to know MQL5. Read the left-hand label. If you are unsure, leave the default.

---

## How to read the numbers

| Phrase | Meaning |
|--------|---------|
| **Your account money** | EUR, USD, or whatever the account is denominated in |
| **Per 0.01 lot** | The unit. A 0.02 lot trade is twice that money. A 0.05 lot trade is five times. |
| **Example** | Stop 3.0 per 0.01, on a 0.02 lot → you are risking about **6.0** of your money if the stop is hit |

Defaults assume a roughly **2,000** account and **1-minute gold (XAUUSD)** scalping. That is a starting point, not a promise.

---

## The only numbers most people change

Leave everything else. Change these to match *your* broker and *your* pain limit.

| What you see in Inputs | Default | In one sentence |
|------------------------|---------|-----------------|
| Biggest lot allowed on ONE trade | `0.05` | Hard cap. Greedy size dies here. |
| Worst loss allowed per 0.01 lot | `5.0` | Ceiling. RiskGuard will not let a stop sit farther than this. |
| Normal stop: lose this much per 0.01 lot if hit | `3.0` | Breathing room — typical stop, tighter than the ceiling. |
| Take-profit: bank this much per 0.01 lot | `4.0` | Where a single scalp is taken off. |
| Extra trades allowed only if EVERY open trade is this lot or smaller | `0.02` | Bigger than this → no adding to losers. |
| Extra trades allowed only if open risk is this % of the account or less | `0.50` | Risk already high → no adding. |
| Your broker commission per 0.01 lot | `0.04` | Put **your** round-turn cost here or “tiny combined profit” will be a fake win. |
| Lock the day if equity is down this % from this morning | `3.0` | Day kill-switch. |

Then click OK. Toolbar **Algo Trading** must be green.

---

## 1. Start here

| What you see | Default | Meaning |
|--------------|---------|---------|
| Protection ON (recommended). OFF = panel only, no closes | `true` | Master switch. OFF still draws the panel but **does not protect you**. |
| Watch only this chart's symbol (recommended) | `true` | Ignore other symbols. Turn off only if you really want one RiskGuard to watch several markets. |
| Extra symbols to watch (e.g. XAUUSD,EURUSD). Empty = none | empty | Add-on list. Usually leave empty. |
| Which trades to watch | All trades (manual and EA) | **All trades** = everything on this symbol. **Only my manual trades** = ignore other EAs. **Only one EA** = type that EA’s magic number in the next box. |
| Magic number — only if "which trades" is set to one EA | `0` | Ignore unless you chose “only one EA”. |
| Extra check every N seconds (1 is fine; ticks already check) | `1` | Backup when the market is quiet. Do not set this high — protection should not nap. |
| Times to retry a stop/target if the broker says no | `3` | Broker rejected the stop? Try again. Then try again on the next tick. |
| Leave this. Not used — kept so your saved settings stay put | `150` | **Do not change.** It does nothing. Removing it would scramble saved Inputs. |
| Max price slip when RiskGuard closes a trade (in points) | `30` | How far price may move while a protective close is sent. |

---

## 2. How much you can lose

| What you see | Default | Meaning |
|--------------|---------|---------|
| Biggest lot allowed on ONE trade | `0.05` | A 0.10 lot fill is too big. RiskGuard shrinks it or closes it. |
| Worst loss allowed per 0.01 lot, in your account money | `5.0` | Hard ceiling. Dragging the stop farther than this is blocked. |
| One trade may not risk more than this % of the account | `1.0` | Size vs account. On 2,000 that is 20 of your money. |
| All open trades together may not risk more than this % | `2.0` | If the combined risk is too high, the **fattest** risk is closed first. |
| Those % are calculated from | Equity | **Equity** includes open profit/loss (recommended). **Balance** ignores floating P/L. |
| If a trade is too big: shrink it, or close it | Shrink | Shrink = cut volume. Close = kill the whole thing. If shrinking is refused by the broker, it closes anyway. |
| Max trades here when adding to losers is NOT allowed | `1` | Normal scalp: one trade. This number is real — `2` would allow two even without adding-privilege. |
| Never more than this many trades here, even when adding is allowed | `3` | Absolute ceiling (original + extras). |

---

## 3. Stop loss (where it hurts)

| What you see | Default | Meaning |
|--------------|---------|---------|
| Always put a stop loss on every trade | `true` | You click. A stop appears. |
| How far to place the stop loss | From money per 0.01 lot | **Money** is how you think. Points is only if you really think in points. |
| Normal stop: lose this much per 0.01 lot if hit | `3.0` | The usual breath. Must be **less than or equal to** the worst-loss ceiling. |
| Stop distance in points — only if "how far" is Points | `300` | Ignored in money mode. |
| If you drag the stop farther (more loss), snap it back | `true` | No hoping. The stop cannot run away. |
| If you delete the stop, put it back. No naked trades | `true` | A trade with no stop is a bomb. |
| If a stop still cannot be set after N seconds, close the trade | `3` | Broker won’t take the stop? The trade is closed. |
| Leave this. Trades with no stop are always closed after the timeout | `true` | **Do not change.** Kept so saved Inputs stay put. |

If the broker’s minimum stop distance would push the loss **past** your worst-loss ceiling, the trade is closed. Better a close than a stop that is a lie.

---

## 4. Take profit (bank the win)

| What you see | Default | Meaning |
|--------------|---------|---------|
| Always put a take profit on a single trade | `true` | Scalps bank. They do not “see where it goes”. |
| How far to place the take profit | From money per 0.01 lot | Same idea as the stop: think in money. |
| Take-profit: bank this much per 0.01 lot | `4.0` | Typical bank for a 1-minute gold scalp. |
| Target in points — only if "how far" is Points | `250` | Ignored in money mode. |
| Target as multiple of the stop (1.0 = same distance as SL) | `1.0` | Only if you picked “R-multiple”. |
| With 2+ trades open, drop per-trade targets so they exit together | `true` | Several trades = one combined tiny-profit exit, not three separate targets fighting each other. |

---

## 5. Adding to losers (only if risk is tiny)

Adding is a **privilege**, not a right. All of the following must be true or the extra trade is closed (and a pending extra is deleted):

- this switch is ON
- the account can hold several trades on one symbol (hedging). Netting accounts cannot.
- the day is not locked, and you are not in the revenge pause
- every open trade is ≤ the add-on lot
- open risk % is ≤ the add-on risk %
- you have not used up the extra-trade count (and never more than the hard max)

| What you see | Default | Meaning |
|--------------|---------|---------|
| Allow extra trades on a loser ONLY when risk is already tiny | `true` | Master switch for add-ons. |
| Extra trades allowed only if EVERY open trade is this lot or smaller | `0.02` | A 0.05 lot already in? No add-on. |
| Extra trades allowed only if open risk is this % of the account or less | `0.50` | Risk already spicy? No add-on. |
| How many extras you may add (1 original + this many) | `2` | Original + 2 extras = 3 trades, and still limited by “never more than”. |
| Extras must be the same direction (no buy+sell mix) | `true` | Blocks accidental hedges. |
| If an extra trade is not allowed, what to do | Close only the extra | **Close only the extra** = kill the new one. **Close every trade on this symbol** = flatten all. |
| Close all of them together at this tiny profit (your money) | `0.01` | Combined “just green”. |
| Your broker commission per 0.01 lot (so "tiny profit" is after costs) | `0.04` | **Put your real cost here.** |
| Extra cushion on top of tiny profit + commission | `0.00` | Optional extra. |
| Count overnight swap in the combined profit | `true` | Usually leave on. |

**When they all close together**

```text
close when combined profit ≥ tiny profit + (commission per 0.01 × lots/0.01) + extra cushion
```

Example: two 0.01 lots, tiny profit 0.01, commission 0.04 → they close when combined P/L ≥ **0.09**.

---

## 6. Dead-trade timer (single trade)

For **one** trade only. If several trades are open, this timer is skipped (they exit together at tiny profit instead).

“In profit” here means **after your commission**, not a fake +0.01 that is still a loser after costs.

| What you see | Default | Meaning |
|--------------|---------|---------|
| Close a single trade that is going nowhere | `true` | Momentum died? Get out. |
| If still not in profit after this many seconds, close it (after costs) | `120` | Two 1-minute candles. |
| Never hold a single trade longer than this many seconds | `180` | Three 1-minute candles. Hard stop on time. |
| If profit after costs is at least this, do not time-close | `0.50` | A real winner is left for the take-profit. |
| With 2+ trades open, ignore the timer — they exit together at tiny profit | `true` | Leave on. |

---

## 7. Stop the day

| What you see | Default | Meaning |
|--------------|---------|---------|
| Stop trading if the day is already too ugly | `true` | Day kill-switch. |
| Lock the day if equity is down this % from this morning | `3.0` | Uses live equity, including open losses. A big open loser can lock the day. That is on purpose. |
| Lock the day after this many closed trades (0 = no count limit) | `40` | Overtrading cap. `0` turns the count off. |
| When the day locks, close everything RiskGuard is watching | `true` | Keeps trying until they are actually gone. |
| After a loss, block NEW trades for this many seconds (revenge pause) | `120` | Existing trades stay. New fills and new pendings die. Partial closes do not start this pause. |
| When the risk-day restarts (broker server hour; 0 = midnight) | `0` | `0` = midnight server time. Use `22` if you want the day to roll at 22:00 server. |

Reloading the EA does **not** reset the day lock. It is remembered for this account until the risk-day rolls.

---

## 8. Alerts and log

| What you see | Default | Meaning |
|--------------|---------|---------|
| Pop-up on the terminal when RiskGuard acts | `true` | You will see why it closed or changed something. |
| Also send that alert to the MT5 phone app | `false` | Needs MetaQuotes ID set up in the terminal. |
| Play a sound when RiskGuard acts | `true` | |
| Sound file name (in the terminal Sounds folder) | `alert.wav` | |
| Write what happened into the Experts log | `true` | Always useful on demo. |
| Log detail: 0=errors only  1=actions (recommended)  2=everything | `1` | `1` is the sweet spot. |

The same message will not spam you every tick (it waits 5 seconds).

---

## 9. Chart panel look

Looks only. Does not change protection.

| What you see | Default | Meaning |
|--------------|---------|---------|
| Show the status box on the chart | `true` | |
| Which corner of the chart | Left upper | |
| Distance from that corner, left-right / up-down (pixels) | `12` / `24` | |
| Text size / font / colors / background | Consolas 9 + theme | Change if you cannot read it. |

---

## 10. Pending orders

| What you see | Default | Meaning |
|--------------|---------|---------|
| Delete pending orders that would break the rules, before they become trades | `true` | MetaTrader **cannot** block a market click before fill. It **can** delete a pending. This is that. Oversized, extra, day-locked, or revenge-pause pendings are removed. |

---

## Two inputs you should not touch

These exist only so older saved settings files do not shift and silently change your lot size:

1. **Leave this. Not used — kept so your saved settings stay put** (the old retry pause)
2. **Leave this. Trades with no stop are always closed after the timeout**

---

## Quick math (2,000 account)

| Lot | Stop 3.0 / 0.01 | Worst 5.0 / 0.01 |
|-----|-----------------|------------------|
| 0.01 | ~3 of your money | ~5 |
| 0.02 | ~6 | ~10 |
| 0.05 | ~15 | ~25 |

0.01–0.02 on this account is “tiny risk” → adding may be allowed. 0.05 is already the max lot → adding is blocked.
