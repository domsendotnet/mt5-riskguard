# Behavior specification (RiskGuard 1.22)

This is the **engineer’s spec** — exact runtime rules. If you are using the EA, start with [USER_GUIDE.md](USER_GUIDE.md) and [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md). Those use the same words as the Inputs dialog.

This document is the source of truth for what RiskGuard does at runtime. Version **1.20** is the same 1.10 guardian loop with a smaller policy surface: money-only stops/targets, always-on fail-closed mechanics, extras-count as the averaging switch (`0` = off), day lock on if a limit is > 0.

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
4. **Pendings** — delete illegal / extra / lock / cooldown.
5. **Day lock flatten** — close all managed positions **until they are actually gone** (retries every sweep). Leftovers still get SL/size.
6. **Position caps** — cooldown-new, lock-new (when not flattening), hedge rule, max positions.
7. **Each position:** auto SL/TP, then size/risk using the SL that **actually landed**.
8. Naked SL timeout close.
9. Time guard (single-leg).
10. Total open risk — close **largest money-risk first**.
11. Basket BE+ exit.

## Stop loss rules

- If SL missing → set to auto distance (preferred breath, money/0.01).
- If current SL distance implies loss > `MaxLossPer001` scale → snap SL as close as the broker allows.
- If broker min-distance / freeze / requote still leaves loss/0.01 above the hard max → **keep the tightest legal stop and retry next tick**. Do not close the trade for that.
- If still naked after timeout → close.
- Loss/0.01 over max is **not** fixed by reducing lot (risk per 0.01 is a distance). Snap when price allows.

## Take profit rules

- Single-leg: set TP from money-per-0.01 when TP is missing.
- Basket (2+ managed on symbol): clear per-leg TP so the combined tiny-profit exit owns the trade.

## Size / risk caps

Evaluated **after** SL exists, on the actual SL money:

- lot > MaxLot
- risk % of equity/balance > per-trade cap

Action: reduce to a legal lot, or close. **If reduce/partial close fails → full close.** Never leave an oversized position because the broker rejected a partial.

If risk cannot be measured at all → close.

## Averaging privilege

Allowed only if all gates pass:

- Extras > 0
- Hedging account
- Not day-locked / not in cooldown (for *new* risk)
- Every leg lot ≤ averaging max lot
- Open risk % on the symbol ≤ averaging max risk %
- Count ≤ `1 + extras`

When privilege is false, the cap is **1**. Hard cap is always `1 + extras`.

Illegal extra / hedge: close the **newest** violating position (retry that same ticket if the close fails; never skip to the older leg). Buy+sell mix is always rejected.

Cooldown does **not** flatten already-open legs. It rejects **new** positions (open time ≥ cooldown start) and deletes pendings. Day lock **does** flatten everything watched, then keeps trying until they are gone.

## Pending orders (prevent if possible)

A pending is deleted if:

- Day lock or cooldown is active
- Volume > MaxLot
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

## Time guard (single-leg)

Skipped when basket active (if configured). Floating result is `profit + swap − modeled commission` (same money language as the basket).

- Age ≥ max hold → close
- Age ≥ must-be-green AND net ≤ 0 → close
- Net ≥ exempt → skip

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

A **full** closed deal with negative profit+swap+commission starts a cooldown window. Partial closes are ignored. New managed entries and pendings during cooldown are removed. Positions that were already open stay.

## Fail-safe philosophy

- Prefer **deterministic enforcement** over discretion
- Every invariant is true on a timer/tick, not only on a fill event
- Prefer **reduce** when configured, else **close**
- Prefer **close** over leaving a naked, over-risked, or unmeasurable position
- If a protective trade fails, **retry** — do not log and forget
- If the EA cannot trade, say **CANNOT TRADE**, not “protecting”
- Log and alert every intervention (same message debounced for 5 seconds)

## Known broker / platform limits

- Stop level / freeze level can delay or reject modifies — retries then safety close
- Netting accounts merge volume — multi-leg basket averaging is hedging-only
- Some symbols have unstable tick value until a quote session is active — attach during liquid hours; money mode will not invent a points SL
- Partial close requires broker support; if it fails RiskGuard full-closes
- One RiskGuard per chart/symbol is the intended setup; two copies on the same symbol will both try to enforce

## Versioning

EA `#property version` tracks releases. Behaviour that changes risk outcomes must update this document in the same change. Policy-surface releases (1.20) must list every built-in constant in SETTINGS_REFERENCE (“Always on”) so removing a dialog knob is not silent.
