# Behavior specification (RiskGuard 1.32)

This is the **engineer’s spec** — exact runtime rules. If you are using the EA, start with [USER_GUIDE.md](USER_GUIDE.md) and [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md). Those use the same words as the Inputs dialog.

This document is the source of truth for what RiskGuard does at runtime.

**Current build: 1.32** (`#property version` in `RiskGuard.mq5`). The guardian loop is still the 1.10 tick/timer sweep. On top of that:

- **1.20** — policy Inputs; mechanics always on; extras `0` = never add; day lock on if a limit is `> 0`
- **1.21** — stop ceiling is a goal, not a reason to close if the broker will not take that stop this tick
- **1.22** — EA + `Include/` + `Scripts/` live in one folder (copy into `MQL5/Experts/`)
- **1.23** — lot cap runs **before** SL exists (shrink oversized volume this tick)
- **1.24** — one stop number (auto-stop = widen ceiling)
- **1.25** — account-% caps are optional (`0` = off) so they do not shrink a lot you already capped
- **1.26** — already-through-stop market-closes; full-close accounting no longer swallowed as a partial; close deviation follows spread; hedge keeps the oldest direction
- **1.27** — no-trade hours in a chosen clock (Berlin DST default), mapped onto server time; flatten-until-flat while a slot is live
- **1.28** — no-trade hours on by default (`13:45-15:15,16:00-16:05`); no trading from `OnInit`; unreadable hours fail-closed
- **1.29** — averaging widens every leg’s stop by `InpAveragingStopFactor` (default 2×) so the first scalp is not stopped at the single-trade 5
- **1.30** — optional single-trade break-even lock after a % of take-profit (off by default)
- **1.31** — optional basket rescue: old 3+ average, hole shrunk to 1/N of worst, flatten while still red
- **1.32** — rescue hole is keyed to the oldest ticket so a new average does not inherit a stale worst

## Event model

Every rule is a **continuous invariant**. If the account is in an illegal state, RiskGuard acts. If the action fails, it retries on the next tick. A missed deal event cannot leave an illegal position unenforced.

| Hook | Role |
|------|------|
| `OnTick` | Primary loop: full `RG_GuardianSweep` (caps, pendings, SL/TP, size, time, basket, day lock) |
| `OnTimer` | Same sweep — backup when there is no tick (session gap, thin market) |
| `OnTradeTransaction` | Fast path for closed-deal accounting (day count / cooldown); then the same sweep |
| `OnChartEvent` | Panel redraw |

Manual **market** orders cannot be hard-blocked pre-fill in portable MQL5. RiskGuard:

1. Deletes **illegal pending orders** before they fill (the only real prevent).
2. Enforces **on this tick** after a fill, not “sometime after a deal event”.

There is **no `Sleep()`** in event handlers. Modify/close retries happen immediately (a few attempts) and then on the next sweep.

## Trading-allowed honesty

Before any action, RiskGuard checks:

- terminal connected
- terminal Algo Trading
- EA “Allow Algo Trading”
- account trading allowed / EAs allowed
- symbol not `TRADE_MODE_DISABLED`

If any check fails: **no actions**, panel mode **CANNOT TRADE**, reason on the panel. It will never show “protecting” while it cannot protect you.

## Managed universe

A position or pending is managed when:

1. Guard is enabled
2. Symbol is this chart, or on the extra-symbols list
3. Magic passes magic-mode filter

## Risk math

Distances for money-based SL/TP are computed with `OrderCalcProfit` (binary search on price distance).

```text
scaled_money = money_per_001 × (lots / 0.01)
```

**Fail-closed:** if quotes/tick value are missing or `OrderCalcProfit` never succeeds, RiskGuard **does not guess a points SL**. The position is treated as naked; the naked-SL timeout closes it.

Prices are aligned to `SYMBOL_TRADE_TICK_SIZE`. Stop distance uses `max(stops_level, freeze_level)`. Filling mode is set **per symbol**.

Risk % uses `ACCOUNT_EQUITY` (open P/L counts).

Measuring an *existing* SL may fall back to tick-value if `OrderCalcProfit` fails on that one call. Inventing a new SL never uses that fallback.

## Guardian sweep order

1. Update day lock state (equity drawdown / trade count).
2. Harvest recent closed deals (day count + cooldown), with a seen-ticket ring so events are not double-counted.
3. Abort actions if guard off or trading not allowed.
4. **Pendings** — delete illegal / extra / lock / cooldown / no-trade hours.
5. **Day lock flatten** — close all managed positions **until they are actually gone** (retries every sweep). Leftovers still get lot/SL/size.
6. **No-trade hours flatten** — if the selected clock is inside a configured slot, same flatten-until-flat as day lock; pendings deleted. Leftovers still get lot/SL/size.
7. **Position caps** — cooldown-new, lock-new, hedge (same direction), max positions (`1` or `1 + extras`).
8. **Each position, in this order:**
   1. **Already-through-stop** — if floating loss or the quote is at/through the money stop, market-close (do not plant a stop behind the market)
   2. **Lot cap** (no stop needed) — shrink to MaxLot or close
   3. Auto SL/TP
   4. % risk vs equity (needs the SL that actually landed)
   5. Break-even lock (single trade only, if the % trigger is set)
9. Naked SL timeout close (still no stop after 3 seconds).
10. Time guard (single-leg only; skipped while 2+ trades are open).
11. Total open risk — close **largest money-risk first**.
12. Combined tiny-profit exit (2+ legs) and basket rescue (if armed).

## Stop loss rules

- If the trade is **already at/through** `InpMaxLossPer001` (floating P/L, or Bid/Ask vs the money-stop price) → **market-close**. Do not plant a stop behind the market.
- If SL missing → set to the **current** stop money per 0.01. One trade: `InpMaxLossPer001`. Two or more on the symbol while adding is on: that times `InpAveragingStopFactor` (default 2). That is also the farthest the stop may sit in that state.
- When a second trade opens, existing legs that still have the single-trade stop are **pushed out** to the basket width. New legs get that width from the start. Take-profits are still cleared.
- Back to one trade: stop money is the normal `InpMaxLossPer001` again. A leftover already past that 5 is closed (hard money-stop).
- If current SL implies more loss than that → snap as close as the broker allows.
- If broker min-distance / freeze / requote still leaves it wider, **and you are not yet through the 5** → **keep the tightest legal stop and retry next tick**. Do not close the trade for that.
- If still naked after timeout → close.
- Extra width is **not** fixed by reducing lot (loss per 0.01 is a distance). Snap when price allows. Close when price has *used* that distance.

## Break-even lock (optional, single trade)

Off unless `InpBE_TriggerPercent > 0`.

When **exactly one** managed trade is open on the symbol, and floating `profit + swap` ≥ that percent of `InpTP_MoneyPer001` scaled to the lot:

- Compute a profit-side stop whose OrderCalcProfit ≈ `InpBE_LockPer001 + InpCommissionPer001` per 0.01 (so a hit is still green after costs)
- Move SL there if it is **better** than the stop already on (never pull a lock backwards)
- 2+ trades: skipped (averaging stop owns the basket)
- Missing quotes / money math: skip this tick, retry. Do not guess a points BE.
- A profit-side lock is **not** treated as a too-wide loss stop. Auto-SL will not snap it back to the 5. A later 2+ basket may still push it out to the averaging width.
- The dead-trade timer still applies. If the trade later sits on the tiny lock (below the 0.50 exempt), max-hold can close it. That is the 180s scalp cap, not a BE bug.

## Take profit rules

- Single-leg: set TP from money-per-0.01 when TP is missing.
- Basket (2+ managed on symbol): clear per-leg TP so the combined tiny-profit exit owns the trade.

## Size / risk caps

**Lot cap is first and does not wait for a stop.** If volume > MaxLot → shrink to MaxLot, or close if shrinking fails.

Then, **after** SL exists, on the actual SL money:

- if one-trade % is `> 0` and risk % of equity > that cap → shrink or close
- if combined % is `> 0` and total open risk > that cap → close largest first

Action: reduce to a legal lot, or close. **If reduce/partial close fails → full close.** Never leave an oversized position because the broker rejected a partial.

If risk cannot be measured at all → close.

## Averaging privilege

Allowed only if all gates pass:

- Extras > 0
- Hedging account
- Not day-locked / not in cooldown / not in no-trade hours (for *new* risk)
- Every leg lot ≤ averaging max lot
- If add-on % is `> 0`, open risk % on the symbol ≤ that
- Count ≤ `1 + extras`

When privilege is false, the cap is **1**. Hard cap is always `1 + extras`.

Illegal extra: close the **newest** violating position (retry that same ticket if the close fails; never skip to the older leg). Buy+sell mix is always rejected: the **oldest** leg’s direction is kept, opposite tickets are closed newest-first. Opposite-direction pendings are deleted before they fill.

Cooldown does **not** flatten already-open legs. It rejects **new** positions (open time ≥ cooldown start) and deletes pendings. Day lock **does** flatten everything watched, then keeps trying until they are gone.

## Pending orders (prevent if possible)

A pending is deleted if:

- Day lock, cooldown, or no-trade hours is active
- Volume > MaxLot
- Opposite direction to an already-open managed leg on that symbol
- Worst-case money risk at MaxLossPer001 exceeds the per-trade % cap
- No free position slot (`positions >= allowed cap`)
- Positions already exist and averaging privilege is false, or pending lot > averaging max lot
- Too many pendings for remaining slots (newest extras deleted)

## Basket BE+ exit

When managed count on a symbol ≥ 2:

```text
net    = Σ(profit [+ swap])
target = MinProfit + CommissionPer001 × (Σlots / 0.01)
if net ≥ target → close all managed legs on symbol
```

Commission is **not** double-counted in `net`; it is modeled in `target` via the configured commission input.

## Basket rescue (optional, 2+ trades)

Off unless `InpBasketRescueMinAgeSec > 0`. Does **not** replace tiny-green exit or single-trade BE.

While averaging is on, for each symbol:

1. While 2+ managed legs are open, remember the **worst** combined `profit+swap` (persisted per login+symbol), keyed to the **oldest ticket**. If that first-leg ticket changes, the hole starts over. Forget it when the symbol is flat. Orphans are purged if the EA starts with no managed positions.
2. Fire only if **all** of:
   - extras > 0
   - open managed count ≥ `InpBasketRescueMinTrades` (must be ≥ 2)
   - age of the **oldest** leg ≥ `InpBasketRescueMinAgeSec`
   - worst net ≤ −`InpBasketRescueMinHole`
   - `giveback N` ≥ 2 (1 is rejected at init — that would close at the bottom of the hole)
   - current net ≥ `worst / N` (e.g. worst −30, N=6 → close at ≥ −5, including scratch/green)

Then flatten the symbol (retry until gone). Time guard still skips 2+ legs; this is the basket’s early-out. Single-trade BE never runs at the same time (count ≠ 1).

## Time guard (single-leg)

Always skipped while 2+ managed trades are open on the symbol (combined exit owns those). Floating result is `profit + swap − modeled commission` (same money language as the basket).

- Net ≥ exempt → skip **both** timers (a real winner is left for the take-profit; “never hold” is not a hard cap once you are that green)
- Age ≥ max hold → close
- Age ≥ must-be-green AND net ≤ 0 → close

Defaults aimed at 1-minute XAU momentum: must-be-green **120s** (2 candles), max hold **180s** (3 candles).

## Day protection

Risk day key = server date shifted by `DayResetHour`.

On new day: clear lock, reset day-start equity and closed-trade counter.

Lock when:

- Equity drawdown from day-start equity ≥ max day loss %, or
- Closed trade count ≥ max day trades

On lock: flatten all managed positions **retried until flat**; new fills closed while locked; pendings deleted.

Day stamp, day-start equity, closed-trade count, lock flag, lock time, cooldown start and cooldown until are persisted in terminal **global variables** (per account login) so reloading the EA mid-session does not reset the day lock.

## Cooldown

A **full** closed deal with negative profit+swap+commission starts a cooldown window. Partial closes are ignored. A close event whose position ticket is still in the list is **not** marked seen for 2 seconds, so a full close is not eaten as a partial. New managed entries and pendings during cooldown are removed. Positions that were already open stay.

## No-trade hours

Slots are wall-clock ranges in the **selected timezone**, not in raw server hours.

Clock conversion uses `TimeGMT()` plus a DST-aware offset:

| Clock | Winter | Summer |
|-------|--------|--------|
| Europe/Berlin | UTC+1 (CET) | UTC+2 (CEST) — EU DST, last Sunday of March 01:00 UTC → last Sunday of October 01:00 UTC |
| Europe/London | UTC+0 | UTC+1 (BST) — same EU DST |
| America/New York | UTC−5 (EST) | UTC−4 (EDT) — US DST, 2nd Sunday of March 07:00 UTC → 1st Sunday of November 06:00 UTC |
| UTC | 0 | 0 |
| Server | `TimeTradeServer() − TimeGMT()` (broker’s own DST, if any) | same |
| This PC | `TimeLocal() − TimeGMT()` (Windows DST) | same |

A slot `13:45-15:15` is **inclusive of both minutes**: 13:45:00 through 15:15:59 in that clock. Overnight wrap (`22:00-02:00`) is `now ≥ start OR now ≤ end`.

Empty string = feature off. Default in 1.28 is `13:45-15:15,16:00-16:05`. A non-empty string that does not parse → **init fails**. If hours are set but become unreadable at runtime → treat as **active** (block), not off.

Closes are **not** sent from `OnInit` (brokers reject that). First tick or 1-second timer flattens.

While a slot is active (checked every tick / timer):

- flatten every managed position until gone
- delete managed pendings
- refuse averaging / new pendings
- new market fills are closed on this tick

This is **not** “new only”. A trade opened at 13:40 is still closed at 13:45. That is the point of a news blackout.

On start, Experts prints now in the chosen clock, server, and UTC, the server-minus-clock gap, and each slot rewritten onto the server clock.

No persistence: when the clock leaves the slot, trading is allowed again.

## Fail-safe philosophy

- Prefer **deterministic enforcement** over discretion
- Every invariant is true on a timer/tick, not only on a fill event
- Oversized **lot**: shrink, or close if shrinking fails
- Oversized **stop vs 5/0.01**: pull it in; if the broker refuses this tick **and you are not yet through the 5**, keep the tightest legal stop and retry — do not close for that
- Already **through** the 5 (P/L or quote) → market-close; never plant a stop behind the market
- Prefer **close** over leaving a **naked** position (no stop after 3 seconds)
- If a protective trade fails, **retry** — do not log and forget
- If the EA cannot trade, say **CANNOT TRADE**, not “protecting”
- Log and alert every intervention (same message debounced for 5 seconds)

## Known broker / platform limits

- Stop level / freeze level can delay or reject a tighter stop — retry next tick; do not close the scalp for that
- Netting accounts merge volume — multi-leg basket averaging is hedging-only
- Some symbols have unstable tick value until a quote session is active — attach during liquid hours; money mode will not invent a points SL
- Partial close requires broker support; if it fails RiskGuard full-closes
- One RiskGuard per chart/symbol is the intended setup; two copies on the same symbol will both try to enforce
- Close/modify deviation is `max(30 points, 3× current spread)` per symbol so a 3-digit gold spike is not rejected for a 3-cent slippage cap
- Harvest of closed deals looks back 180 seconds. A disconnect longer than that can miss day-trade counts and a revenge pause (day-lock *equity* still uses live equity)

## Versioning

EA `#property version` is **1.32**. Any behaviour or layout change must update **all** of these in the same change, and set their version headers to the same number:

- `RiskGuard.mq5` `#property version` and the Experts start log line
- `Scripts/RiskGuard_SelfTest.mq5` version + banner
- `README.md`
- `docs/USER_GUIDE.md`
- `docs/SETTINGS_REFERENCE.md`
- `docs/BEHAVIOR.md` (this file)
- `docs/INSTALL.md` (title + start log example)
- `docs/CHANGELOG.md` (new section at the top)

Policy-surface changes must list every built-in constant in SETTINGS_REFERENCE (“Always on”).
