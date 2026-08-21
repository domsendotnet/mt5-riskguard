# RiskGuard for MetaTrader 5

**RiskGuard** is a production-grade Expert Advisor that protects discretionary scalpers from the two account-killers that matter most: **oversized lots** and **losers that run too long** — while still leaving room to breathe inside a defined money risk.

It does **not** find entries. You trade. RiskGuard enforces the rules.

Designed for high win-rate **1-minute candle momentum** styles (e.g. XAUUSD): bank winners quickly, accept a fixed money loss per `0.01` lot, and only allow averaging-down when risk is genuinely low.

---

## What it does

| Protection | Behavior |
|------------|----------|
| **Auto SL / TP** | Every managed position gets a stop and take-profit derived from money-per-0.01 (or points / R) |
| **Lot & risk caps** | Hard max lot, max loss per 0.01, max % risk per trade and total — reduce or close on breach |
| **No hope mode** | Blocks SL removal and SL widening past max risk |
| **Conditional averaging** | Allows 1–N adds only when lot and open risk % are low (hedging accounts) |
| **Basket BE+ exit** | With 2+ legs, flattens the whole basket at tiny net profit + commission buffer |
| **Time guard** | Cuts dead single-leg trades that never go green / overstay |
| **Day lock** | Daily loss % and/or trade-count lock with optional flatten + post-loss cooldown |
| **On-chart panel** | Live status: risk, averaging privilege, basket target, mode, last action |

---

## Requirements

- MetaTrader 5 (build with MQL5 Standard Library: `Trade.mqh`, etc.)
- **Hedging** account for multi-leg averaging / basket exit (on **netting**, size/SL/TP/time/day guards still work; averaging privilege stays blocked)
- Algo Trading enabled; EA allowed to trade

---

## Install

1. Copy this repository’s `MQL5/Experts/RiskGuard.mq5` into your terminal data folder:
   - `File → Open Data Folder → MQL5/Experts/`
2. Copy `MQL5/Include/RiskGuard/` into:
   - `MQL5/Include/RiskGuard/`
3. In MetaEditor: open `RiskGuard.mq5` → **Compile** (F7).
4. Attach **RiskGuard** to your chart (e.g. XAUUSD M1).
5. Enable **Algo Trading**.

Full walkthrough: [docs/INSTALL.md](docs/INSTALL.md)

---

## Quick start (scalper defaults)

Settings are grouped and labeled in plain language. Sensible starting point for a ~€2000 account:

- Max lot `0.05` (set lower if you want)
- Max loss / 0.01 lot = `5.0` (hard ceiling)
- Auto SL money / 0.01 = `3.0` (breathing room)
- Auto TP money / 0.01 = `4.0` (quick bank)
- Averaging max lot `0.02`, max open risk `0.50%`, max adds `2`
- Basket min profit `0.01` + commission per 0.01 `0.04`
- Time: must be green by `90s`, max hold `180s`
- Day loss lock `3%`

Every relevant behavior is configurable — see [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md).

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | How to use RiskGuard day-to-day |
| [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md) | Every input explained |
| [docs/BEHAVIOR.md](docs/BEHAVIOR.md) | Exact enforcement rules & edge cases |
| [docs/INSTALL.md](docs/INSTALL.md) | Install, compile, permissions |

---

## Repository layout

```
MQL5/
  Experts/RiskGuard.mq5          # EA entry point
  Include/RiskGuard/
    RiskGuard_Inputs.mqh         # All inputs (grouped)
    RiskGuard_Utils.mqh          # Risk math, filters, trade helpers
    RiskGuard_Enforce.mqh        # Enforcement engine
    RiskGuard_Panel.mqh          # On-chart panel
docs/                            # Full documentation
LICENSE
README.md
```

---

## Disclaimer

Trading CFDs and FX involves substantial risk of loss. RiskGuard is a **risk enforcement tool**, not a trading system and not financial advice. Past discipline does not guarantee future results. You are solely responsible for settings, broker conditions, and trading decisions.

---

## License

MIT — see [LICENSE](LICENSE).
