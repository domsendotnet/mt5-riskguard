# User guide (RiskGuard 1.11)

You click. RiskGuard watches. If the account is in a state your emotions would like and your math cannot afford, it **fixes it or kills it**. It keeps trying until the account is legal.

It does **not** find entries. It is not a strategy. It is a guardian.

---

## First 10 minutes

1. Install and compile ([INSTALL.md](INSTALL.md)).
2. Attach **RiskGuard** to XAUUSD, **M1**.
3. Common tab: tick **Allow Algo Trading**.
4. Inputs: read group **1. Start here**. Leave defaults unless you know better. Put your real commission in group **5**.
5. Toolbar **Algo Trading** = green.
6. The chart box must say **protecting**, not **CANNOT TRADE**.
7. On demo, open a tiny trade **with no stop**. A stop and a target should appear on the **next tick**.
8. Optional: run **Scripts → RiskGuard_SelfTest** during market hours. Experts tab should say all PASS.

If the box says **CANNOT TRADE**, you are **not** protected. Fix Algo Trading / permissions before you size up.

---

## What the chart box means

| You see | Meaning |
|---------|---------|
| **ONE TRADE** | One position. Individual stop + target. Dead-trade timer may cut it. |
| **SEVERAL TRADES** | Two or more. They exit together at a tiny combined profit (after costs). |
| **REVENGE PAUSE** | You just took a loss. New trades and new pendings are blocked for a couple of minutes. |
| **DAY LOCKED** | Daily loss or trade-count hit. No new risk. Open trades are closed if that setting is on. |
| **CANNOT TRADE** | Rules are on, but the terminal cannot send orders. **You are naked.** |
| **OFF** | You turned protection off. Panel only. |

Other lines:

| Line | Meaning |
|------|---------|
| Account / Today P/L | Equity, and how today is doing vs this morning. |
| At risk | How much you would lose if every watched stop was hit, and that as a % of the account. |
| Open trades a / b | How many you have vs how many you may have right now. |
| Pending orders | Stop/limit orders RiskGuard is allowed to delete. |
| Adding to losers: YES / NO | Whether an extra trade would be allowed **right now**, and why not. |
| Stop / Target / Worst per 0.01 | Your breathing stop, your bank target, and the hard ceiling. |
| Last action | The last thing RiskGuard did (plain language). |
| Closed trades today | Counted full closes only, not partials. |

---

## A normal 1-minute gold scalp

1. You buy 0.01 (or 0.02 if that is still inside your max lot).
2. RiskGuard puts a stop at about **3** of your money per 0.01, and a target at about **4**.
3. Most of the time it goes green and the target (or you) banks it.
4. Sometimes it does not:
   - the stop is the breath
   - if it is still not in profit after **120 seconds** (after costs), it is closed
   - it will not live past **180 seconds**

That is “losers that run too long” without cutting everything in two seconds.

---

## Adding to a loser

Only when risk is **actually** small. On a ~2,000 account that means lots like **0.01 or 0.02**, not 0.05.

If it is allowed:

- you may add 1–2 extras, same direction
- as soon as **all of them together** are a tiny bit green **after commission**, everything is closed

If it is not allowed (lot too big, risk % too high, day locked, revenge pause, netting account, too many already):

- a market add is closed on this tick
- a pending add is deleted **before** it fills

---

## What happens if you mess up

| You do | RiskGuard does |
|--------|----------------|
| Open with no stop / no target | Puts them on, this tick |
| Delete the stop | Puts it back. Still missing after 3 seconds → closes |
| Drag the stop farther (more loss) | Snaps it back to the worst-loss ceiling. If the broker cannot place that, closes |
| Open 0.10 when max lot is 0.05 | Shrinks or closes. If shrinking fails, closes |
| Place a 0.10 pending | Deletes the pending |
| Add to a 0.05 loser | Extra is closed (and stays closed on the next ticks) |
| Revenge-click 10 seconds after a loss | New trade closed; new pending deleted |
| Blow 3% of this morning’s equity | Day locks. Open watched trades are closed, and it keeps trying until they are gone |
| Turn Algo Trading off | Box says **CANNOT TRADE**. It will not pretend. |

MetaTrader **cannot** block a market click before fill. Fastest legal reaction is **this tick**. Pendings are the only thing that can be prevented for real.

---

## Settings you should actually open

Full dictionary: [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md). The labels there match the Inputs tab.

Most people only set:

1. Biggest lot on one trade
2. Worst loss per 0.01
3. Normal stop per 0.01
4. Take-profit per 0.01
5. Add-on lot / add-on risk %
6. **Your** commission per 0.01
7. Day-loss %

Leave the rest.

---

## Demo checklist before live

- [ ] Self-test script: all PASS on this symbol during liquid hours
- [ ] Box says **protecting**, not **CANNOT TRADE**
- [ ] Naked tiny fill → stop and target appear this tick
- [ ] Fat lot → shrink or full close (including if the broker refuses a partial)
- [ ] Drag stop too far → snap or close
- [ ] Fat pending → deleted
- [ ] Algo Trading off → **CANNOT TRADE**
- [ ] Two tiny 0.01 fills when adding is YES → they close together slightly green after costs
- [ ] Fat first trade, then an add → add dies and stays dead
- [ ] After a loss, a revenge fill during the pause is closed
- [ ] Tiny day-loss % on demo → day locks and everything watched is closed

---

## What it will not do

- Find the trade for you
- Martingale when risk is high
- Let a winner run for a swing target (unless you set the take-profit that way)
- Bypass broker stop/freeze levels
- Protect you while **CANNOT TRADE** is on the box

---

## FAQ

**The box says CANNOT TRADE.**  
Toolbar Algo Trading is off, or this EA does not have Allow Algo Trading, or the account/symbol cannot trade. Fix that first.

**It did not close my extra trade.**  
Wait one tick. If it still sits, check Experts log. If the broker rejected the close, RiskGuard retries every tick — it will not log once and give up.

**I reloaded the EA and the day lock vanished.**  
It should not. Day lock is stored in the terminal for this account. If the risk-day hour rolled, that is a new day.

**I use another EA on this chart.**  
By default RiskGuard watches **all** magics. Set “Which trades to watch” if you only want manual trades, or only one magic.

**Netting account.**  
Stops, size, timer, day lock still work. Several separate add-on trades do not exist on netting, so adding stays blocked.

**Two RiskGuards on the same symbol.**  
Don’t. One guardian per symbol.
