# RiskGuard for MetaTrader 5

**Version 1.11**

You trade. RiskGuard enforces the rules.

It is a guardian for discretionary **1-minute gold (XAUUSD)** scalpers who win on **win rate**, not on letting winners run — and who historically blow up from **lots that are too big** and **losers that are left to hope**.

It does **not** find entries.

---

## What it does

| Protection | In practice |
|------------|-------------|
| **Stop + target on every fill** | Placed from money per 0.01 lot (your account currency). This tick, not “in a few seconds”. |
| **Lot and risk caps** | Max lot, max loss per 0.01, max % per trade and for all trades together. Shrink or close. If shrinking fails, close. |
| **No hoping** | You cannot delete the stop or drag it past the worst-loss ceiling. |
| **Adding to losers** | Only when risk is already tiny (small lots, low %). Otherwise the extra is closed. |
| **Combined tiny-profit exit** | Two or more trades close together when they are just green **after commission**. |
| **Dead-trade timer** | A single scalp that is still not in profit after ~2 minutes (after costs) is cut. Hard max ~3 minutes. |
| **Day kill-switch** | Daily loss % and/or too many trades. Closes everything it is watching and keeps trying until they are gone. |
| **Revenge pause** | After a full losing close, new fills and new pendings are blocked for a couple of minutes. |
| **Pending killer** | Illegal pending orders are deleted **before** they become trades. (A market click cannot be blocked before fill.) |
| **Honest panel** | **protecting** only if it can actually send orders. Otherwise **CANNOT TRADE** — it will not pretend. |

Every rule is checked **every tick** (and again on a 1-second timer). A missed fill event cannot leave an illegal trade sitting there.

---

## Requirements

- MetaTrader 5
- **Algo Trading** on, EA allowed to trade
- **Hedging** account if you want several add-on trades on one symbol (on **netting**, size / stop / timer / day lock still work; adding stays blocked)

---

## Install

1. Copy `MQL5/Experts/RiskGuard.mq5` into your data folder `MQL5/Experts/`.
2. Copy `MQL5/Include/RiskGuard/` into `MQL5/Include/RiskGuard/`.
3. Copy `MQL5/Scripts/RiskGuard_SelfTest.mq5` into `MQL5/Scripts/` (recommended).
4. MetaEditor: open `RiskGuard.mq5` → **Compile** (F7). Zero errors.
5. Attach **RiskGuard** to XAUUSD M1. Tick **Allow Algo Trading**. Toolbar Algo Trading = green.
6. The chart box must say **protecting**, not **CANNOT TRADE**.

Step-by-step: [docs/INSTALL.md](docs/INSTALL.md)

---

## Quick start (~2,000 account)

Open **Inputs**. Groups are numbered and written in plain language. Most people only change:

| Setting (as shown in Inputs) | Start with |
|------------------------------|------------|
| Biggest lot allowed on ONE trade | `0.05` |
| Worst loss allowed per 0.01 lot | `5.0` |
| Normal stop: lose this much per 0.01 lot if hit | `3.0` |
| Take-profit: bank this much per 0.01 lot | `4.0` |
| Extra trades … every open trade is this lot or smaller | `0.02` |
| Extra trades … open risk is this % … or less | `0.50` |
| Your broker commission per 0.01 lot | **your** cost (example `0.04`) |
| Lock the day if equity is down this % from this morning | `3.0` |
| If still not in profit after this many seconds | `120` |
| Never hold a single trade longer than | `180` |

Full dictionary of every Input, with the **same labels as the dialog**: [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md)

---

## Documentation

| Doc | Who it is for |
|-----|----------------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | First-time use, panel words, “if I do X, it does Y”, demo checklist |
| [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md) | Every Input, same wording as MT5 |
| [docs/BEHAVIOR.md](docs/BEHAVIOR.md) | Exact runtime rules (the spec) |
| [docs/INSTALL.md](docs/INSTALL.md) | Copy, compile, permissions, self-test |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | What changed in 1.11 / 1.10 / 1.01 / 1.00 |

---

## Repository

```
MQL5/
  Experts/RiskGuard.mq5          # attach this
  Include/RiskGuard/             # required includes
  Scripts/RiskGuard_SelfTest.mq5 # run on XAUUSD during market hours
docs/
LICENSE
README.md
```

---

## Disclaimer

Trading CFDs and FX involves substantial risk of loss. RiskGuard is a **risk enforcement tool**, not a trading system and not financial advice. You are solely responsible for settings, broker conditions, and trading decisions.

## License

MIT — see [LICENSE](LICENSE).
