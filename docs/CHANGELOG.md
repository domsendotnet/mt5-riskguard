# Changelog

Current build: **1.30**. Every doc in `docs/` plus `README.md` is written for that version.

## 1.30 — 2026-08-27

Optional break-even lock on a **single** trade, so a winner does not walk back to red.

- Two Inputs appended (old saved values do not shift): **move stop to break-even after this % of take-profit** (`0` = off — try `70`) and **lock this much per 0.01 past break-even** (default `0.10`, plus commission so a hit is still green after costs).
- Only when **one** trade is open. A 2+ basket is left to the averaging stop — BE would stop the first leg out.
- Does not pull a stop backwards if it is already better than the lock.
- Auto-SL will **not** snap a profit-side lock back to the 5-loss stop (that distance is not a “too-wide loss”).
- Default is **off**. Set 70 yourself if you want it.

## 1.29 — 2026-08-27

Averaging was keeping the single-scalp stop, so the first leg got stopped out before extras could help.

- New Input **When 2+ trades: stop this many times as wide** (default `2`, appended — old saved values do not shift). `1` = don’t widen, `3` = three times.
- With 2+ managed trades on a symbol, **every** leg (old and new) is moved to `stop × factor`. Take-profits still come off so they exit together at the tiny combined target.
- Hard money-stop uses the same wider budget, so it does not flatten the basket at the original 5.
- Back to one trade: stop is the normal 5 again (if you are already past 5, that leftover is closed).

## 1.28 — 2026-08-27

Ship pass. No new knobs.

- No-trade hours default is now `13:45-15:15,16:00-16:05` (Berlin clock). Empty still means off. If you already saved 1.27 with an empty box, type the slots yourself — saved Inputs win over a new default.
- Do not send closes from `OnInit` (brokers often reject that). First tick / 1s timer does the work. If you attach *inside* a slot, Experts warns and the next tick flattens.
- Hours that are set but cannot be parsed at runtime **block** (fail-closed), not silently off.
- Tabs/newlines in the hours box are ignored. Server-offset log no longer always says “Berlin”.

## 1.27 — 2026-08-27

No-trade hours. You type the clock you live by; RiskGuard maps it onto the broker server (including DST).

- New group **6. No-trade hours** (two Inputs, **appended** — older saved values do not shift)
- Clock: Europe/Berlin (CET/CEST) default, or server / UTC / this PC / London / New York
- Slots: `13:45-15:15,16:00-16:05` (comma-separated, as many as you need, empty = off). End minute is included (`16:00-16:05` covers 16:05:00–16:05:59). Overnight wrap is allowed (`22:00-02:00`)
- While a slot is live: **every watched trade is closed** (already-open and new fills), pendings are deleted, and it keeps trying until the clock is out of the slot
- Experts log on start prints Berlin vs server vs UTC and each slot on the server clock so you can see the 1-hour gap
- Chart box: **NO TRADE HOURS** plus a line `now 14:03 = server 13:03`

## 1.26 — 2026-08-27

Audit fixes. These were holes, not style.

- **Already past the stop → close.** If floating loss (or the quote) is already at your stop money, RiskGuard market-closes. It will not plant a stop *behind* the market. That is how a 5-per-0.01 ceiling could become an 8–10 loss on a fill that did not have a stop yet. 1.21 still applies *before* you have used the 5: keep the tightest legal stop and retry.
- **Revenge pause could miss a loss.** A full close arriving on `DEAL_ADD` while the ticket was still in the position list was marked seen as a “partial” and never counted. Cooldown now waits ~2s for the list to settle; real partials still do not start the pause.
- **Closes used a 30-point deviation.** On 3-digit gold that is 3 cents — spike closes got rejected. Deviation is now `max(30, 3× spread)` per symbol (capped).
- **Buy+sell mix** now closes the *other direction* (oldest leg keeps its side), not “newest extra” which could kill a same-direction add and leave the hedge. Opposite-direction *pendings* are deleted before they fill.
- Partial-close “OK” with a stale volume cache no longer escalates to a full close if the broker already filled the cut.

## 1.25 — 2026-08-27

% of account no longer silently fights the lot you typed.

- One-trade % and combined % default to **0 = off**. Size is max lot × stop unless you opt into %.
- Add-on % default **0 = off**. Adding is extras + add-on lot unless you opt into %.
- Experts warning if max lot at your stop already exceeds the one-trade % (set % to 0 if you want the lot).
- Input order unchanged; if you already saved 1% / 2% / 0.50%, set them to **0** yourself.

## 1.24 — 2026-08-27

One stop number. “Normal” 3 vs “worst” 5 was two names for the same idea.

- Removed the extra “normal stop per 0.01” Input
- **Stop: lose this much per 0.01 lot if hit** is both the auto-stop and the widen ceiling (default `5.0`)
- **Re-attach the EA** — Inputs shifted by one line after this removal

## 1.23 — 2026-08-27

Max lot is enforced immediately, even if the stop is not on yet.

- A 0.09 fill with max lot 0.08 was kept because size checks waited for SL; we still put SL/TP on it and skipped the cap.
- Lot cap now runs first: shrink to max, or close if shrinking fails. Retries every tick.

## 1.22 — 2026-08-27

Install as one folder. No more copying Include/Scripts into MT5’s global trees.

- `RiskGuard.mq5` lives at the repo root
- `Include/` and `Scripts/` sit next to it (quoted includes)
- Copy the whole folder into `MQL5/Experts/` and compile

## 1.21 — 2026-08-27

Keep “worst loss per 0.01” as a real ceiling, not a reason to kill the scalp.

- If the broker will not accept a tighter stop *this tick* (min distance, freeze, requote), park at the tightest legal stop and retry. Do **not** close.
- Same when a gold min-stop is briefly wider than 5 per 0.01 at entry: wait until price allows, then pull the stop in.
- Alert only when the stop was actually pulled closer.

## 1.20 — 2026-08-26

Simpler Inputs without taking away policy. **Re-attach the EA** — the Input list was rebuilt (old saved values would land on the wrong lines).

- 70-odd knobs / 10 groups → **27 settings / 5 groups**
- Stops and targets are money-per-0.01 only (no points / R-multiple modes)
- Adding on/off is `How many extras` (`0` = never)
- Position cap is always `1 + extras`
- Day lock / dead-trade timer: `0` means off (no extra enable switches)
- Alerts are one dropdown (silent / pop-up / pop-up+sound / phone)
- Always on, not in the dialog: force stop+target, no hoping, pending killer, same-direction extras, shrink-or-close, day-lock flatten, equity %, this chart always watched
- Panel look (font/colors) is built in; you still place the box
- Docs rewritten against the 1.20 dialog

## 1.11 — 2026-08-26

Settings and documentation so a first-time user can use the EA without knowing MQL5. **Protection behavior is unchanged from 1.10.**

- Every Input label is a plain-language sentence (same order — saved settings do not shift)
- Input groups numbered 1–10 (“Start here”, “How much you can lose”, …)
- Dropdown choices rewritten in the same voice
- Chart panel uses the same words (ONE TRADE / SEVERAL TRADES / REVENGE PAUSE / DAY LOCKED / CANNOT TRADE)
- Last-action messages in the same voice
- USER_GUIDE, SETTINGS_REFERENCE, README, INSTALL rewritten against the live 1.11 dialog
- Two unused Inputs kept on purpose so older saved settings files do not scramble

## 1.10 — 2026-08-24

Guardian hardening. Every rule is a continuous invariant (tick + timer), not a one-shot deal handler.

- Full `RG_GuardianSweep` on every tick and timer; deal events are a hint, not the only chance
- No `Sleep()` in event handlers — failed closes/modifies retry next sweep
- Panel **DEAD** when algo trading / account / symbol cannot trade (never show ARMED while helpless)
- Fail-closed money math: no silent points SL when `OrderCalcProfit` fails
- SL/TP aligned to tick size; freeze+stops used as min distance; filling mode per symbol
- Size/risk checked **after** the SL that actually landed
- Loss/0.01 over max → snap SL or close (not a lot-reduce)
- Partial-close failure → full close
- Day lock flatten retried until flat; cooldown/lock only reject **new** risk
- `MaxOpenPositions` when averaging is blocked now actually allows that many
- Total-risk trim closes **largest** money risk first (not newest)
- Pending-order killer (oversized, extra, lock, cooldown, averaging-blocked)
- Time guard uses profit+swap−commission; default must-be-green **120s**
- Closed-deal harvest with `HistorySelect` retry + seen-ticket ring; ignore partials
- `RiskGuard_SelfTest.mq5` live math PASS/FAIL script
- Alert debounce (5s) to stop snap-spam

## 1.01 — 2026-08-21

- Persist day lock / day PnL baseline / trade count / cooldown via terminal global variables
- Ignore partial closes for day-trade counting and loss cooldown
- Link `#property` to GitHub repo; version bump

## 1.00 — 2026-08-21

- Initial production release of RiskGuard for MT5
- Money-based auto SL/TP with OrderCalcProfit distance solver
- Lot / per-trade % / total risk caps with reduce-or-close
- SL widen/remove protection and naked-SL timeout
- Conditional averaging privilege (hedging) + basket BE+ exit
- Single-leg time guard, day loss/trade lock, post-loss cooldown
- On-chart status panel and full documentation set
