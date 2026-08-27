# RiskGuard for MetaTrader 5

**Version 1.31**

You trade. RiskGuard enforces the rules.

It is a guardian for discretionary **1-minute gold (XAUUSD)** scalpers who win on **win rate**, not on letting winners run — and who historically blow up from **lots that are too big** and **losers that are left to hope**.

It does **not** find entries.

---

## What it does

| Protection | In practice |
|------------|-------------|
| **Stop + target on every fill** | Placed from money per 0.01 lot (your account currency). This tick, not “in a few seconds”. Optional: after ~70% of the target, stop moves to break-even + a tiny lock (single trade only). |
| **Lot and risk caps** | Max lot is cut **this tick** (does not wait for a stop): shrink, or close if shrinking fails. Then % of equity vs the stop that actually landed. |
| **No hoping** | You cannot delete the stop. Dragging it past the worst-loss ceiling is pulled back when the broker allows — the trade is not closed just because gold will not take a 5-stop this second. If the quote is **already through** that 5, it market-closes instead of planting a wider stop. |
| **Adding to losers** | Only when risk is already tiny (small lots, low %). Stops on every leg go **wider** (default 2×) so the first trade is not stopped out. Optional **rescue**: if a 3-leg average is old enough and the hole has shrunk to ~1/6 of the worst, flatten — do not wait for tiny green. Otherwise the extra is closed. |
| **Combined tiny-profit exit** | Two or more trades close together when they are just green **after commission**. |
| **Dead-trade timer** | A single scalp that is still not in profit after ~2 minutes (after costs) is cut. Hard max ~3 minutes unless it is already a real winner (exempt). |
| **Day kill-switch** | Daily loss % and/or too many trades. Closes everything it is watching and keeps trying until they are gone. |
| **No-trade hours** | You type hours in Berlin (or another clock). DST is handled. During those slots everything watched is closed. |
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

Copy **this whole folder** (the one with `RiskGuard.mq5`, `Include/`, and `Scripts/`) into your data folder:

```text
File → Open Data Folder → MQL5/Experts/
```

Then in MetaEditor open `RiskGuard.mq5` → **Compile** (F7). Attach it to XAUUSD M1. Algo Trading green. Chart box must say **protecting**, not **CANNOT TRADE**.

Do not split `Include/` or `Scripts/` into MT5’s global folders. They have to stay next to the `.mq5`.

Step-by-step: [docs/INSTALL.md](docs/INSTALL.md)

---

## Quick start (~2,000 account)

Open **Inputs**. Six groups, 35 settings, plain language. Most people only change:

| Setting (as shown in Inputs) | Start with |
|------------------------------|------------|
| Biggest lot on ONE trade | `0.05` |
| Stop: lose this much per 0.01 lot if hit | `5.0` |
| Take-profit: bank this much per 0.01 lot | `4.0` |
| How many extras (0 = never add) | `2` |
| Add only if EVERY open trade is this lot or smaller | `0.02` |
| When 2+ trades: stop this many times as wide | `2` |
| Move stop to break-even after this % of take-profit | `0` (off). Try `70` |
| Rescue: oldest trade at least this many seconds | `0` (off). Try `600` |
| Your broker commission per 0.01 lot | **your** cost (example `0.04`) |
| Lock the day if equity is down this % from this morning | `3.0` |
| Clock for no-trade hours | Europe/Berlin |
| Close EVERYTHING in these hours | `13:45-15:15,16:00-16:05` (empty = off) |

Stops, pending kills, and “no hoping” are always on. Full dictionary: [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md)

Upgrading: from **1.11** re-attach (Inputs rebuilt in 1.20). From the **old split MQL5 folders**, copy this whole repo into `MQL5/Experts/` and delete the old split copies (1.22).

---

## Documentation

| Doc | Who it is for |
|-----|----------------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | First-time use, panel words, “if I do X, it does Y”, demo checklist |
| [docs/SETTINGS_REFERENCE.md](docs/SETTINGS_REFERENCE.md) | Every Input, same wording as MT5 |
| [docs/BEHAVIOR.md](docs/BEHAVIOR.md) | Exact runtime rules (the spec) |
| [docs/INSTALL.md](docs/INSTALL.md) | Copy, compile, permissions, self-test |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | What changed in 1.31 / 1.30 / 1.29 / … |

---

## Repository

```
RiskGuard.mq5                    # attach this
Include/                         # required .mqh files (must stay next to the EA)
Scripts/RiskGuard_SelfTest.mq5   # compile/run from this folder
docs/
LICENSE
README.md
```

---

## Disclaimer

Trading CFDs and FX involves substantial risk of loss. RiskGuard is a **risk enforcement tool**, not a trading system and not financial advice. You are solely responsible for settings, broker conditions, and trading decisions.

## License

MIT — see [LICENSE](LICENSE).
