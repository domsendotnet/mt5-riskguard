# Settings reference

All inputs appear in the EA properties dialog, grouped. Units in **account currency** mean EUR, USD, etc. — whatever your account is denominated in.

---

## Master

| Input | Default | Meaning |
|-------|---------|---------|
| Enable RiskGuard enforcement | `true` | Master switch. `false` = panel only, no actions |
| Manage chart symbol only | `true` | Manage `_Symbol` (+ whitelist). `false` = all symbols (or whitelist only) |
| Extra symbols (comma-separated) | empty | Additional symbols to manage |
| Which magics to manage | All | All / magic 0 only / one specific magic |
| Magic number (when specific) | `0` | Filter when mode = specific |
| Background check interval (seconds) | `1` | `OnTimer` cadence for full enforcement |
| Retries for SL/TP modify | `3` | Modify attempts before fail path |
| Pause between modify retries (ms) | `150` | Delay between retries |
| Max slippage for closes (points) | `30` | Deviation for close / partial close |

---

## Account Risk

| Input | Default | Meaning |
|-------|---------|---------|
| Absolute max lot per position | `0.05` | Hard volume ceiling per position |
| Hard max loss per 0.01 lot | `5.0` | Ceiling used for widen-block & risk math (account ccy) |
| Max risk % per trade | `1.0` | Max risk of this position vs equity/balance |
| Max combined open risk % | `2.0` | Across all managed positions; trims newest first |
| Risk % calculated from | Equity | Equity or Balance |
| Action when lot/risk too high | Reduce | Reduce to safe lot, or close fully |
| Max positions when averaging blocked | `1` | Soft cap without averaging privilege |
| Absolute hard cap (even with averaging) | `3` | Never exceed this many managed positions on a symbol |

---

## Stop Loss

| Input | Default | Meaning |
|-------|---------|---------|
| Always ensure a stop loss exists | `true` | Auto-set SL if missing |
| How auto SL distance is computed | Money / 0.01 | Money-per-0.01 or fixed points |
| Auto SL: loss per 0.01 lot | `3.0` | Breathing SL in account ccy (money mode) |
| Auto SL: points | `300` | Used when SL mode = points |
| Prevent SL from being widened past max risk | `true` | Snaps SL back to max-loss distance |
| Prevent naked positions (no SL) | `true` | Forces SL; timeout close if unsettable |
| Close if still without SL after N seconds | `3` | Safety close |
| Close if SL cannot be set after retries | `true` | Fail-closed |

---

## Take Profit (single trade)

| Input | Default | Meaning |
|-------|---------|---------|
| Always ensure a take profit exists | `true` | Auto-set TP if missing (single-leg) |
| How auto TP distance is computed | Money / 0.01 | Money / points / R-multiple |
| Auto TP: profit per 0.01 lot | `4.0` | Quick bank target (money mode) |
| Auto TP: points | `250` | Points mode |
| Auto TP: R-multiple of SL | `1.0` | R mode |
| Clear individual TP when basket (2+) is active | `true` | Basket BE+ owns the exit |

---

## Averaging (add to losers)

| Input | Default | Meaning |
|-------|---------|---------|
| Allow averaging only when risk is low | `true` | Master privilege switch |
| Privilege: only if each leg lot ≤ | `0.02` | Lot gate |
| Privilege: only if open risk % ≤ | `0.50` | Risk% gate on symbol |
| Max extra adds (entry + N) | `2` | Max legs = 1 + N (also limited by hard cap) |
| Only allow adds in the same direction | `true` | Blocks hedges |
| Action when add not allowed | Close add | Close illegal add, or flatten symbol |
| Close basket when net ≥ (account ccy) | `0.01` | Minimum collective profit |
| Commission cost per 0.01 lot | `0.04` | Added into basket exit target |
| Extra buffer | `0.00` | Extra cushion on target |
| Include swap in basket net profit | `true` | Net = profit + swap (commission modeled in target) |

**Basket exit target**

```text
target = MinProfit + CommissionPer001 × (basket_lots / 0.01) + ExtraBuffer
```

When `basket_net ≥ target` → flatten all managed legs on that symbol.

---

## Time Guard (single trade)

| Input | Default | Meaning |
|-------|---------|---------|
| Enable time-based exit | `true` | Momentum-fail cuts |
| Close if still ≤ 0 after N seconds | `90` | Must-be-green timer |
| Absolute max hold (seconds) | `180` | Hard lifetime |
| Skip time cut if floating profit ≥ | `0.50` | Exempt winners you’re managing |
| Do not time-cut legs while basket active | `true` | Basket mode uses BE+ instead |

---

## Day Protection

| Input | Default | Meaning |
|-------|---------|---------|
| Enable daily loss / trade locks | `true` | Day kill-switch |
| Lock when day loss reaches % of equity | `3.0` | Vs equity at day start |
| Lock after this many closed trades | `40` | `0` = off |
| Flatten all managed positions on day lock | `true` | Close everything managed |
| Block new risk for N seconds after a loss | `120` | Cooldown |
| Day boundary hour (server time) | `0` | Risk-day reset hour |

---

## Alerts & Logs

| Input | Default | Meaning |
|-------|---------|---------|
| Terminal alert popups | `true` | `Alert()` |
| Push notifications to phone | `false` | MT5 push |
| Play sound on intervention | `true` | Sound |
| Sound file name | `alert.wav` | Terminal sounds folder |
| Write detailed logs to Experts tab | `true` | `Print` |
| Verbosity 0/1/2 | `1` | errors / actions / verbose |

---

## On-Chart Panel

| Input | Default | Meaning |
|-------|---------|---------|
| Show RiskGuard status panel | `true` | Labels + optional background |
| Panel corner / X / Y | Left upper, 12, 24 | Placement |
| Font / size / colors | Consolas 9 + theme | Optics |
| Draw panel background | `true` | Rectangle label |

---

## Tuning tips

- **Think in money per 0.01**, then scale: `0.02` lot at `3.0` per 0.01 ⇒ about `6.0` account currency to SL.
- Set commission to your real round-turn (or per-side) cost so basket exits don’t flake out at “false BE”.
- If stops level on gold is large, money-based SL is clamped to broker minimum distance — watch Experts log if modifies fail.
