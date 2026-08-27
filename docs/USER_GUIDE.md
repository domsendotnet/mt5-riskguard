# User guide (RiskGuard 1.28)

You click. RiskGuard watches. If the account is in a state your emotions would like and your math cannot afford, it **fixes it or kills it**. It keeps trying until the account is legal.

It does **not** find entries. It is not a strategy. It is a guardian.

---

## First 10 minutes

1. Install and compile ([INSTALL.md](INSTALL.md)).
2. Attach **RiskGuard** to XAUUSD, **M1**.
3. Common tab: tick **Allow Algo Trading**.
4. Inputs: six groups, 28 settings. Leave defaults unless you know better. Put **your** commission in group **3**. Group **6** is no-trade hours (Berlin clock, default `13:45-15:15,16:00-16:05`). After **1.24** re-attach (one Input removed). After **1.25** set both account-% boxes to **0** if they still say 1 / 2, or they will shrink the lot you typed. **1.27+** group 6 is at the end — old values stay put. From 1.22: copy this whole folder into `MQL5/Experts/` — do not split Include/Scripts.
5. Toolbar **Algo Trading** = green.
6. The chart box must say **protecting** (or **NO TRADE HOURS** if you are inside a slot), not **CANNOT TRADE**. Experts log must say `RiskGuard 1.28 started` and print Berlin vs server for your slots.
7. On demo, open a tiny trade **with no stop**. A stop and a target should appear on the **next tick**.
8. Optional: in MetaEditor open `Scripts/RiskGuard_SelfTest.mq5` (same folder as the EA) and run it during market hours. Experts tab should say all PASS.

If the box says **CANNOT TRADE**, you are **not** protected. Fix Algo Trading / permissions before you size up.

---

## What the chart box means

| You see | Meaning |
|---------|---------|
| **ONE TRADE** | One position. Individual stop + target. Dead-trade timer may cut it. |
| **SEVERAL TRADES** | Two or more. They exit together at a tiny combined profit (after costs). |
| **REVENGE PAUSE** | You just took a loss. New trades and new pendings are blocked for a couple of minutes. |
| **DAY LOCKED** | Daily loss or trade-count hit. No new risk. Everything watched is closed, and it keeps trying until they are gone. |
| **NO TRADE HOURS** | The clock is inside a slot you typed (Berlin time by default). Everything watched is closed until the slot ends. |
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
| Stop / Target per 0.01 | Your stop and your bank target, in account money per 0.01 lot. |
| Last action | The last thing RiskGuard did (plain language). |
| Closed trades today | Counted full closes only, not partials. |

---

## A normal 1-minute gold scalp

1. You buy 0.01 (or 0.02 if that is still inside your max lot).
2. RiskGuard puts a stop at about **5** of your money per 0.01 (whatever you set), and a target at about **4**.
3. Most of the time it goes green and the target (or you) banks it.
4. Sometimes it does not:
   - the stop is the breath
   - if it is still not in profit after **120 seconds** (after costs), it is closed
   - it will not live past **180 seconds** unless it is already a real winner (after-cost profit ≥ the exempt amount, default **0.50**) — then the take-profit owns it

That is “losers that run too long” without cutting everything in two seconds.

---

## Adding to a loser

Only when risk is **actually** small. On a ~2,000 account that means lots like **0.01 or 0.02**, not 0.05.

Set **How many extras** to `0` if you never want this.

If it is allowed:

- you may add 1–2 extras, same direction
- as soon as **all of them together** are a tiny bit green **after commission**, everything is closed

If it is not allowed (lot too big, add-on % if you set one, day locked, revenge pause, netting account, too many already):

- a market add is closed on this tick
- a pending add is deleted **before** it fills

---

## What happens if you mess up

| You do | RiskGuard does |
|--------|----------------|
| Open with no stop / no target | Puts them on, this tick |
| Delete the stop | Puts it back. Still missing after 3 seconds → closes |
| Drag the stop farther (more loss) | Pulls it back toward the worst-loss ceiling. If the broker cannot take that stop *yet* **and you are not already through that money**, it keeps the tightest legal stop and retries — it does not close for that |
| Price already through your stop (gap / no SL yet) | Market-closes. It will not plant a stop further away than the loss you already have |
| Open 0.09 when max lot is 0.08 | Shrinks to 0.08 this tick (does not wait for a stop). If shrinking fails, closes |
| Place a 0.10 pending | Deletes the pending |
| Add to a 0.05 loser | Extra is closed (and stays closed on the next ticks) |
| Revenge-click 10 seconds after a loss | New trade closed; new pending deleted |
| Blow 3% of this morning’s equity | Day locks. Open watched trades are closed, and it keeps trying until they are gone |
| Click during 13:45–15:15 Berlin (if you set that slot) | Trade is closed. Already-open trades are closed too. Pendings deleted. |
| Turn Algo Trading off | Box says **CANNOT TRADE**. It will not pretend. |

MetaTrader **cannot** block a market click before fill. Fastest legal reaction is **this tick**. Pendings are the only thing that can be prevented for real.

---

## Settings you should actually open

28 settings, 6 groups. Full dictionary: [SETTINGS_REFERENCE.md](SETTINGS_REFERENCE.md). The labels match the Inputs tab.

Most people only set:

1. Biggest lot on one trade
2. Stop per 0.01 (one number — that is the stop)
3. Take-profit per 0.01
4. How many extras (`0` = never add)
5. Add-on lot
6. **Your** commission per 0.01
7. Day-loss %
8. No-trade hours (Berlin clock + slots like `13:45-15:15,16:00-16:05`)

Stops, pending-order kills, “same direction only”, shrink-or-close, and day-lock flatten are **always on**. That is the guardian, not a menu.

---

## Demo checklist before live

- [ ] Self-test script: all PASS on this symbol during liquid hours
- [ ] Box says **protecting**, not **CANNOT TRADE**
- [ ] Naked tiny fill → stop and target appear this tick
- [ ] Fat lot (e.g. 0.09 vs max 0.08) → shrink this tick, even before a stop is on; full close if the broker refuses a partial
- [ ] Drag stop too far → pulled back toward the ceiling, or parked at the tightest legal stop (not closed for that)
- [ ] (Optional, volatile demo) fill with no stop into a move already past your stop money → market-closed, not a wider stop
- [ ] Fat pending → deleted
- [ ] Algo Trading off → **CANNOT TRADE**
- [ ] Two tiny 0.01 fills when adding is YES → they close together slightly green after costs
- [ ] Fat first trade, then an add → add dies and stays dead
- [ ] After a loss, a revenge fill during the pause is closed
- [ ] Tiny day-loss % on demo → day locks and everything watched is closed
- [ ] No-trade hours: set a slot that includes *now* (Berlin clock) → box says **NO TRADE HOURS**, open trades close, Experts log shows Berlin vs server mapping

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

**I set max lot to 0.08 and a 0.09 stayed open.**  
That was a bug in 1.22 and earlier: lot cap waited for a stop. **1.23+** shrinks (or closes) this tick. Confirm the Experts log version matches this guide.

**It closed me around 5 / 0.01 even though the stop on the chart looked wider.**  
That is 1.26. If the quote has already used your stop money (gap, or gold would not accept the 5-stop yet), RiskGuard market-closes. It will not wait for a wider parked stop to get hit.

**Two RiskGuards on the same symbol.**  
Don’t. One guardian per symbol.

**Server is 1 hour behind Berlin — do I type 12:45 or 13:45?**  
Leave the clock on **Europe/Berlin** and type **13:45-15:15** as you mean it in Berlin. Experts log rewrites the slot onto the server clock. If the gap is not ~60 minutes, pick **Broker server clock** and type the hours as the MT5 time shows them.
