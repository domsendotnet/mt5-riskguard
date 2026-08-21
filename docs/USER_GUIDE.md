# User guide

## Mental model

You open trades manually (or with another tool). RiskGuard watches every managed fill and asks:

1. Is size / risk inside limits?
2. Does it have a proper SL (and TP if configured)?
3. Is this an illegal average / revenge stack?
4. Is a basket collectively green enough to flatten?
5. Has this single scalp failed on time?
6. Has the day already blown the budget?

If the answer is bad, it **acts** (modify / reduce / close). It does not ask politely.

## Recommended workflow (1m XAU momentum)

1. Attach RiskGuard to XAUUSD M1 before the session.
2. Set **Max loss per 0.01** to your hard ceiling (e.g. 5 account currency).
3. Set **Auto SL money per 0.01** to your normal breath (e.g. 3).
4. Set **Auto TP money per 0.01** to where you usually bank (e.g. 4).
5. Keep **Max open positions = 1** when averaging is not privileged.
6. Trade your setups. Do not remove SL. Do not widen SL past max risk — RiskGuard will snap or close.
7. If risk is low (tiny lots vs equity), you may add 1–2 times; RiskGuard will flatten the basket at BE + costs automatically.
8. If you take a loss, expect cooldown. If you hit day loss %, expect lock.

## Single-leg vs basket mode

| Situation | Mode | Exits |
|-----------|------|-------|
| 1 managed position | `SCALP` | Individual SL + TP; time guard may cut |
| 2+ managed positions (hedging) | `BASKET` | Individual TPs cleared (optional); **basket BE+** flattens all |

## Averaging privilege (important)

Averaging is a **privilege**, not a right. It is allowed only when **all** are true:

- Averaging enabled in inputs
- Account is **hedging**
- Not day-locked / not in cooldown
- Every leg lot ≤ `Averaging max lot`
- Open risk % on the symbol ≤ `Averaging max risk %`
- Position count ≤ `1 + max adds` and ≤ hard max

Otherwise the new add is closed (or the whole basket flattened — your setting).

## Panel legend

- **ARMED** — enforcing, ready
- **BASKET** — multi-leg; watching net vs target
- **COOLDOWN** — new risk rejected for N seconds after a loss
- **LOCKED** — day protection active
- **Averaging ALLOWED / BLOCKED** — privilege state + reason

## Alerts

On intervention RiskGuard can popup-alert, push-notify, and play a sound. Tune under **Alerts & Logs**. All actions also go to the Experts log when logging is enabled.

## What RiskGuard will not do

- Place entries or “find momentum” for you
- Martingale when risk is high
- Let winners run for swing targets (unless you set TP that way)
- Bypass broker stop levels / freeze levels / trade disabled states

## Demo checklist before live

- [ ] Force SL/TP on a naked demo fill
- [ ] Open oversized lot → reduce or close fires
- [ ] Widen SL past max → snap back
- [ ] Low-risk double fill → basket closes at tiny green
- [ ] High-risk second fill → add killed
- [ ] Day loss lock on a small demo % setting
