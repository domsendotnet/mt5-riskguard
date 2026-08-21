# Changelog

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
