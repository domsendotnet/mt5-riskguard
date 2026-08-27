# Changelog

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
