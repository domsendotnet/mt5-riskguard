# Install & compile

## 1. Locate your MT5 data folder

In MetaTrader 5: **File → Open Data Folder**.

You should see an `MQL5` directory with `Experts`, `Include`, `Scripts`, etc.

## 2. Copy files

From this repository:

| Source | Destination |
|--------|-------------|
| `MQL5/Experts/RiskGuard.mq5` | `DataFolder/MQL5/Experts/RiskGuard.mq5` |
| `MQL5/Include/RiskGuard/*` | `DataFolder/MQL5/Include/RiskGuard/` |

Create the `Include/RiskGuard` folder if it does not exist.

> Tip: you can also clone this repo and symlink/copy the `MQL5` tree into the data folder.

## 3. Compile

1. Open **MetaEditor** (F4 from MT5).
2. Open `Experts/RiskGuard.mq5`.
3. Press **Compile** (F7).
4. Confirm `0` errors in the Errors tab. A `RiskGuard.ex5` appears next to the source.

If you see `cannot open include file`, the `Include/RiskGuard` path is wrong.

## 4. Attach to chart

1. In MT5 Navigator → **Expert Advisors** → drag **RiskGuard** onto your symbol chart.
2. In Common tab: enable **Allow Algo Trading**.
3. In Inputs: review groups (start with defaults, then tune money-per-0.01 to your broker).
4. Click OK. Toolbar **Algo Trading** button must be green/on.

## 5. Verify it is alive

You should see the on-chart panel (`RISKGUARD · SYMBOL`) and a log line in the **Experts** tab:

```text
RiskGuard| RiskGuard started on XAUUSD
```

Open a tiny demo position **without** SL/TP — within a second RiskGuard should assign SL/TP (and alert if configured).

## 6. Permissions checklist

- [ ] Algo Trading enabled (toolbar)
- [ ] EA “Allow Algo Trading” checked
- [ ] Autotrading not blocked by broker / account type
- [ ] Hedging account if you need multi-leg averaging
- [ ] Demo first — always

## 7. Updating

Replace `.mq5` / `.mqh` files with newer versions from git, recompile, remove EA from chart, re-attach (or right-click chart → Expert list → refresh properties).
