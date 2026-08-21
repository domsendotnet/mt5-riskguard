# Behavior specification

This document is the source of truth for what RiskGuard does at runtime.

## Event model

| Hook | Role |
|------|------|
| `OnTradeTransaction` | Instant reaction to new deals and position changes (SL/TP edits) |
| `OnTick` | Low-latency basket BE+ check |
| `OnTimer` | Full enforcement sweep (size, SL/TP, naked SL, time, total risk, day, panel) |

Manual market orders **cannot** be hard-blocked pre-fill in portable MQL5. RiskGuard enforces **immediately after fill** and continuously afterward.

## Managed universe

A position is managed when:

1. Guard is enabled
2. Symbol passes chart/whitelist filter
3. Magic passes magic-mode filter

## Risk math

Distances for money-based SL/TP are computed with `OrderCalcProfit` (binary search on price distance), with tick-value fallback if calculation fails.

```text
scaled_money = money_per_001 × (lots / 0.01)
```

Risk % uses `ACCOUNT_EQUITY` or `ACCOUNT_BALANCE` per `InpRiskBase`.

## New position pipeline

For each new managed inbound deal:

1. **Day lock / cooldown** → close immediately if active  
2. **Position count / averaging / hedge rules** → close add or flatten  
3. **Size / risk caps** → reduce or close  
4. **Auto SL/TP** → modify with retries; optional safety close if SL cannot be set  
5. **Total open risk** → close newest until under cap  

## Stop loss rules

- If Force SL and SL missing → set to auto distance (preferred breath).
- If Block widen and current SL distance implies loss > `MaxLossPer001` scale → snap SL to max-risk distance.
- If still naked after timeout → close.
- Broker `STOPS_LEVEL` / freeze constraints are applied via clamp-to-market.

## Take profit rules

- Single-leg: Force TP sets TP from money / points / R.
- Basket (2+ managed on symbol) + `Disable TP in basket`: clear per-leg TP so basket exit owns the trade.

## Averaging privilege

Allowed only if all gates pass (see Settings). Requires **hedging** account.

Illegal add actions:

- `Close add` — close the newest violating position  
- `Flatten` — close all managed positions on that symbol  

Same-direction option rejects buy+sell mixes on the symbol.

## Basket BE+ exit

When managed count on a symbol ≥ 2:

```text
net    = Σ(profit [+ swap])
target = MinProfit + CommissionPer001 × (Σlots / 0.01) + ExtraBuffer
if net ≥ target → close all managed legs on symbol
```

Commission is **not** double-counted in `net`; it is modeled in `target` via your configured commission input.

## Time guard (single-leg)

Skipped when basket active (if configured). Else:

- Age ≥ max hold → close  
- Age ≥ must-be-green AND floating profit ≤ 0 → close  
- Floating profit ≥ exempt → skip  

## Day protection

Risk day key = server date shifted by `DayResetHour`.

On new day: clear lock, reset day-start equity and closed-trade counter.

Lock when:

- Equity drawdown from day-start equity ≥ max day loss %, or  
- Closed trade count ≥ max day trades  

On lock: optional flatten of all managed positions; new fills closed while locked.

Day stamp, day-start equity, closed-trade count, lock flag, and cooldown timestamp are persisted in terminal **global variables** (per account login) so reloading the EA mid-session does not reset the day lock.

## Cooldown

A closed deal with negative profit+swap+commission starts a cooldown window. New managed entries during cooldown are closed.

## Fail-safe philosophy

- Prefer **deterministic enforcement** over discretion  
- Prefer **reduce** when configured, else **close**  
- Prefer **close** over leaving a naked or over-risked position  
- Log and alert every intervention  

## Known broker / platform limits

- Stop level / freeze level can delay or reject modifies — retries then safety close  
- Netting accounts merge volume — multi-leg basket averaging is hedging-only  
- Some symbols have unstable tick value until a quote session is active — attach during liquid hours  
- Partial close requires broker support for close-by volume  

## Versioning

EA `#property version` tracks releases. Behavior changes that affect risk outcomes must update this document in the same commit.
