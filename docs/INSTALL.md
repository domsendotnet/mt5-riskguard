# Install & compile (RiskGuard 1.30)

Everything you need sits in **one folder**: the EA, `Include/`, `Scripts/`, and `docs/`. Do not split them into MT5’s global Include/Scripts trees.

## 1. Open the MetaTrader data folder

In MT5: **File → Open Data Folder**.

You should see `MQL5` with `Experts`, `Include`, `Scripts`.

## 2. Copy this whole folder

Copy the folder that contains `RiskGuard.mq5` (this repository) into:

```text
DataFolder/MQL5/Experts/
```

You should end up with something like:

```text
MQL5/Experts/mt5-riskguard/RiskGuard.mq5
MQL5/Experts/mt5-riskguard/Include/...
MQL5/Experts/mt5-riskguard/Scripts/RiskGuard_SelfTest.mq5
MQL5/Experts/mt5-riskguard/docs/...
```

The folder name can be anything. **Keep `RiskGuard.mq5`, `Include/`, and `Scripts/` together.**

## 3. Compile

1. Open **MetaEditor** (F4 from MT5).
2. Open `Experts/<your-folder>/RiskGuard.mq5`.
3. Press **Compile** (F7).
4. Errors tab: **0 errors**. A `RiskGuard.ex5` appears next to the `.mq5`.
5. Optional: open `Scripts/RiskGuard_SelfTest.mq5` in that same folder and compile it too.

If you see `cannot open include file`, `Include/` is not sitting next to `RiskGuard.mq5`.

## 4. Attach

1. Navigator → **Expert Advisors** → your folder → drag **RiskGuard** onto **XAUUSD M1**.
2. **Common** tab: tick **Allow Algo Trading**.
3. **Inputs** tab: six groups, 31 settings. Dictionary: [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md)  
   **Upgrading from 1.23 or earlier:** remove the EA from the chart, then attach it again (1.24 removed one Input; 1.20 rebuilt the list).
4. OK. Toolbar **Algo Trading** must be **green**.

## 5. Confirm it is alive

Chart box: `RISKGUARD · XAUUSD`. Status line should contain **protecting**.

Experts log:

```text
RiskGuard| RiskGuard 1.30 started on XAUUSD
```

If the box says **CANNOT TRADE**, you are not protected. Typical causes:

- toolbar Algo Trading is off
- Allow Algo Trading was not ticked on the EA
- the account or this symbol cannot be traded
- terminal not connected

Open a tiny demo position **with no stop**. On the **next tick** a stop and a target should appear.

Optional self-test: in MetaEditor open `Scripts/RiskGuard_SelfTest.mq5` (same folder tree) and run it on XAUUSD **during liquid hours**. Experts tab: all PASS.

## 6. Permissions checklist

- [ ] Toolbar Algo Trading green
- [ ] EA “Allow Algo Trading” ticked
- [ ] Broker/account allows EAs
- [ ] Hedging account if you need several add-on trades on one symbol
- [ ] Demo first

## 7. Updating

Replace the **whole folder** (EA + `Include/` + `Scripts/` together), recompile, remove the EA from the chart, attach again.

- **From 1.29:** 1.30 **appends** break-even % and lock. Old values stay. Recompile and reload. Experts log must say `RiskGuard 1.30 started`. Feature is **off** until you set the % (try `70`).
- **From 1.28:** 1.29 **appends** the averaging stop-widen factor. Old values stay. Recompile and reload.
- **From 1.27:** 1.28 does not change Input order. Recompile and reload. Confirm the no-trade hours box is not empty if you saved 1.27 with it blank.
- **From 1.26:** 1.27 **appended** group 6 (no-trade hours). Old values stay. Recompile and reload. Then set hours (1.28 default is `13:45-15:15,16:00-16:05` on a fresh attach).
- **From 1.25:** 1.26 does not change the Input list. Recompile and reload the EA.
- **From 1.23 or earlier:** 1.24 dropped the extra stop Input. Re-attach or values land on the wrong lines.
- **From 1.11 or earlier:** Inputs were also rebuilt in 1.20. Re-attach.
- **From the old split layout** (`MQL5/Experts/RiskGuard.mq5` + `MQL5/Include/RiskGuard/`): delete those copies. From 1.22 the whole repo folder goes into `MQL5/Experts/` and stays together.

Day lock and today’s trade count survive a reload (stored in the terminal for this account).
