# Install & compile (RiskGuard 1.20)

## 1. Open the MetaTrader data folder

In MT5: **File → Open Data Folder**.

You should see `MQL5` with `Experts`, `Include`, `Scripts`.

## 2. Copy files

| From this repository | Into your data folder |
|----------------------|------------------------|
| `MQL5/Experts/RiskGuard.mq5` | `MQL5/Experts/RiskGuard.mq5` |
| `MQL5/Include/RiskGuard/` (all files inside) | `MQL5/Include/RiskGuard/` |
| `MQL5/Scripts/RiskGuard_SelfTest.mq5` | `MQL5/Scripts/RiskGuard_SelfTest.mq5` |

Create `Include/RiskGuard` if it does not exist.

## 3. Compile

1. Open **MetaEditor** (F4 from MT5).
2. Open `Experts/RiskGuard.mq5`.
3. Press **Compile** (F7).
4. Errors tab: **0 errors**. A `RiskGuard.ex5` appears next to the source.
5. Also compile `Scripts/RiskGuard_SelfTest.mq5`.

If you see `cannot open include file`, the `Include/RiskGuard` folder is in the wrong place.

## 4. Attach

1. Navigator → **Expert Advisors** → drag **RiskGuard** onto **XAUUSD M1** (or your symbol).
2. **Common** tab: tick **Allow Algo Trading**.
3. **Inputs** tab: five groups, 27 settings, full-sentence labels.  
   If you are new, change lot / stop / target / commission. Dictionary: [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)  
   **Upgrading from 1.11 or earlier:** remove the EA from the chart, then attach it again. The Inputs list was rebuilt; old saved values would stick to the wrong lines.
4. OK. Toolbar **Algo Trading** must be **green**.

## 5. Confirm it is alive

Chart box: `RISKGUARD · XAUUSD`. Status line should contain **protecting**.

Experts log:

```text
RiskGuard| RiskGuard 1.20 started on XAUUSD
```

If the box says **CANNOT TRADE**, you are not protected. Typical causes:

- toolbar Algo Trading is off
- Allow Algo Trading was not ticked on the EA
- the account or this symbol cannot be traded
- terminal not connected

Open a tiny demo position **with no stop**. On the **next tick** a stop and a target should appear.

Optional: Navigator → **Scripts → RiskGuard_SelfTest** on XAUUSD **during liquid hours**. Experts tab: all PASS. If quotes are dead, live money tests are skipped — run it when gold is trading.

## 6. Permissions checklist

- [ ] Toolbar Algo Trading green
- [ ] EA “Allow Algo Trading” ticked
- [ ] Broker/account allows EAs
- [ ] Hedging account if you need several add-on trades on one symbol
- [ ] Demo first

## 7. Updating

Replace the `.mq5` / `.mqh` files, recompile, remove the EA from the chart, attach again.

1.20 rebuilt the Inputs list (70-odd knobs down to 27). After this upgrade, always **re-attach** so values do not shift onto the wrong line.

Day lock and today’s trade count survive a reload (stored in the terminal for this account).
