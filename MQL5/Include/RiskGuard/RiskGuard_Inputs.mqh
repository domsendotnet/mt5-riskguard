//+------------------------------------------------------------------+
//|                                           RiskGuard_Inputs.mqh |
//|  Labels you see in MT5 Inputs. Keep order stable (saved values).|
//+------------------------------------------------------------------+
#ifndef RISKGUARD_INPUTS_MQH
#define RISKGUARD_INPUTS_MQH

enum ENUM_RG_MAGIC_MODE
  {
   RG_MAGIC_ALL = 0,       // All trades (manual and EA) — recommended
   RG_MAGIC_ZERO = 1,      // Only my manual trades
   RG_MAGIC_SPECIFIC = 2   // Only one EA (set the magic number below)
  };

enum ENUM_RG_RISK_BASE
  {
   RG_RISK_EQUITY = 0,     // Equity (includes open profit/loss) — recommended
   RG_RISK_BALANCE = 1     // Balance (ignores open profit/loss)
  };

enum ENUM_RG_OVERSIZE_ACTION
  {
   RG_OVERSIZE_REDUCE = 0, // Shrink the lot to a safe size
   RG_OVERSIZE_CLOSE = 1   // Close the whole trade right now
  };

enum ENUM_RG_SL_MODE
  {
   RG_SL_MONEY_PER_001 = 0, // From money per 0.01 lot (your currency) — recommended
   RG_SL_POINTS = 1         // Fixed distance in points
  };

enum ENUM_RG_TP_MODE
  {
   RG_TP_MONEY_PER_001 = 0, // From money per 0.01 lot (your currency) — recommended
   RG_TP_POINTS = 1,        // Fixed distance in points
   RG_TP_R_MULTIPLE = 2     // Multiple of the stop-loss distance
  };

enum ENUM_RG_ILLEGAL_ADD_ACTION
  {
   RG_ILLEGAL_CLOSE_ADD = 0, // Close only the extra trade that broke the rule
   RG_ILLEGAL_FLATTEN = 1    // Close every trade on this symbol
  };

//====================================================================
// 1. MASTER
//====================================================================
input group "═══ 1. Start here ═══"
input bool               InpEnableGuard           = true;           // Protection ON (recommended). OFF = panel only, no closes
input bool               InpChartSymbolOnly       = true;           // Watch only this chart's symbol (recommended)
input string             InpSymbolsWhitelist      = "";             // Extra symbols to watch (e.g. XAUUSD,EURUSD). Empty = none
input ENUM_RG_MAGIC_MODE InpMagicMode             = RG_MAGIC_ALL;   // Which trades to watch
input long               InpMagicFilter           = 0;              // Magic number — only if "which trades" is set to one EA
input int                InpTimerSeconds          = 1;              // Extra check every N seconds (1 is fine; ticks already check)
input int                InpModifyRetries         = 3;              // Times to retry a stop/target if the broker says no
input int                InpRetryPauseMs          = 150;            // Leave this. Not used — kept so your saved settings stay put
input int                InpMaxSlippagePoints     = 30;             // Max price slip when RiskGuard closes a trade (in points)

//====================================================================
// 2. ACCOUNT RISK
//====================================================================
input group "═══ 2. How much you can lose ═══"
input double                 InpMaxLot                 = 0.05;            // Biggest lot allowed on ONE trade (e.g. 0.05)
input double                 InpMaxLossPer001          = 5.0;             // Worst loss allowed per 0.01 lot, in your account money
input double                 InpMaxRiskPercentPerTrade = 1.0;             // One trade may not risk more than this % of the account
input double                 InpMaxTotalRiskPercent    = 2.0;             // All open trades together may not risk more than this %
input ENUM_RG_RISK_BASE      InpRiskBase               = RG_RISK_EQUITY;  // Those % are calculated from
input ENUM_RG_OVERSIZE_ACTION InpOnOversize            = RG_OVERSIZE_REDUCE; // If a trade is too big: shrink it, or close it
input int                    InpMaxOpenPositions      = 1;               // Max trades here when adding to losers is NOT allowed
input int                    InpHardMaxOpenPositions  = 3;               // Never more than this many trades here, even when adding is allowed

//====================================================================
// 3. STOP LOSS
//====================================================================
input group "═══ 3. Stop loss (where it hurts) ═══"
input bool           InpForceSL               = true;                 // Always put a stop loss on every trade
input ENUM_RG_SL_MODE InpSLMode               = RG_SL_MONEY_PER_001;  // How far to place the stop loss
input double         InpSL_MoneyPer001        = 3.0;                  // Normal stop: lose this much per 0.01 lot if hit (your money)
input int            InpSL_Points             = 300;                  // Stop distance in points — only if "how far" is Points
input bool           InpBlockWidenSL          = true;                 // If you drag the stop farther (more loss), snap it back
input bool           InpBlockRemoveSL         = true;                 // If you delete the stop, put it back. No naked trades
input int            InpNakedSLTimeoutSec     = 3;                    // If a stop still cannot be set after N seconds, close the trade
input bool           InpCloseIfSLModifyFails  = true;                 // Leave this. Trades with no stop are always closed after the timeout

//====================================================================
// 4. TAKE PROFIT
//====================================================================
input group "═══ 4. Take profit (bank the win) ═══"
input bool           InpForceTP               = true;                 // Always put a take profit on a single trade
input ENUM_RG_TP_MODE InpTPMode               = RG_TP_MONEY_PER_001;  // How far to place the take profit
input double         InpTP_MoneyPer001        = 4.0;                  // Take-profit: bank this much per 0.01 lot (your money)
input int            InpTP_Points             = 250;                  // Target in points — only if "how far" is Points
input double         InpTP_RMultiple          = 1.0;                  // Target as multiple of the stop (1.0 = same distance as SL)
input bool           InpDisableTPInBasket     = true;                 // With 2+ trades open, drop per-trade targets so they exit together

//====================================================================
// 5. AVERAGING
//====================================================================
input group "═══ 5. Adding to losers (only if risk is tiny) ═══"
input bool                     InpAveragingEnabled        = true;  // Allow extra trades on a loser ONLY when risk is already tiny
input double                   InpAveragingMaxLot         = 0.02;  // Extra trades allowed only if EVERY open trade is this lot or smaller
input double                   InpAveragingMaxRiskPercent = 0.50;  // Extra trades allowed only if open risk is this % of the account or less
input int                      InpAveragingMaxAdds        = 2;     // How many extras you may add (1 original + this many)
input bool                     InpAveragingSameDirection  = true;  // Extras must be the same direction (no buy+sell mix)
input ENUM_RG_ILLEGAL_ADD_ACTION InpOnIllegalAdd          = RG_ILLEGAL_CLOSE_ADD; // If an extra trade is not allowed, what to do
input double                   InpBasketMinProfit         = 0.01;  // Close all of them together at this tiny profit (your money)
input double                   InpCommissionPer001        = 0.04;  // Your broker commission per 0.01 lot (so "tiny profit" is after costs)
input double                   InpBasketExtraBuffer       = 0.00;  // Extra cushion on top of tiny profit + commission
input bool                     InpBasketProfitIncludesSwap = true; // Count overnight swap in the combined profit

//====================================================================
// 6. TIME GUARD
//====================================================================
input group "═══ 6. Dead-trade timer (single trade) ═══"
input bool   InpTimeGuardEnabled      = true;  // Close a single trade that is going nowhere
input int    InpMustBeGreenSeconds    = 120;   // If still not in profit after this many seconds, close it (after costs)
input int    InpMaxHoldSeconds        = 180;   // Never hold a single trade longer than this many seconds
input double InpTimeGuardExemptProfit = 0.50;  // If profit after costs is at least this, do not time-close
input bool   InpTimeGuardSkipBasket   = true;  // With 2+ trades open, ignore the timer — they exit together at tiny profit

//====================================================================
// 7. DAY PROTECTION
//====================================================================
input group "═══ 7. Stop the day ═══"
input bool   InpDayLockEnabled        = true;  // Stop trading if the day is already too ugly
input double InpMaxDayLossPercent     = 3.0;   // Lock the day if equity is down this % from this morning
input int    InpMaxDayTrades          = 40;    // Lock the day after this many closed trades (0 = no count limit)
input bool   InpDayLockFlatten        = true;  // When the day locks, close everything RiskGuard is watching
input int    InpCooldownAfterLossSec  = 120;   // After a loss, block NEW trades for this many seconds (revenge pause)
input int    InpDayResetHourServer    = 0;     // When the risk-day restarts (broker server hour; 0 = midnight)

//====================================================================
// 8. ALERTS
//====================================================================
input group "═══ 8. Alerts and log ═══"
input bool   InpAlertPopup      = true;       // Pop-up on the terminal when RiskGuard acts
input bool   InpAlertPush       = false;      // Also send that alert to the MT5 phone app
input bool   InpAlertSound      = true;       // Play a sound when RiskGuard acts
input string InpAlertSoundFile  = "alert.wav"; // Sound file name (in the terminal Sounds folder)
input bool   InpLogToExperts    = true;       // Write what happened into the Experts log
input int    InpLogVerbosity    = 1;          // Log detail: 0=errors only  1=actions (recommended)  2=everything

//====================================================================
// 9. PANEL
//====================================================================
input group "═══ 9. Chart panel look ═══"
input bool            InpShowPanel         = true;            // Show the status box on the chart
input ENUM_BASE_CORNER InpPanelCorner      = CORNER_LEFT_UPPER; // Which corner of the chart
input int             InpPanelX            = 12;              // Distance from that corner, left-right (pixels)
input int             InpPanelY            = 24;              // Distance from that corner, up-down (pixels)
input int             InpPanelFontSize     = 9;               // Text size
input string          InpPanelFont         = "Consolas";      // Font name
input color           InpPanelTextColor    = clrWhiteSmoke;   // Normal text color
input color           InpPanelAccentColor  = clrDodgerBlue;   // Header / OK color
input color           InpPanelWarnColor    = clrOrange;       // Warning color (revenge pause)
input color           InpPanelDangerColor  = clrTomato;       // Danger color (day locked / cannot trade)
input color           InpPanelBgColor      = C'18,22,28';     // Background color
input bool            InpPanelShowBackground = true;          // Draw a background behind the text

//====================================================================
// 10. PENDINGS (appended — do not insert inputs above this block)
//====================================================================
input group "═══ 10. Pending orders ═══"
input bool   InpManagePendings        = true;  // Delete pending orders that would break the rules, before they become trades

#endif // RISKGUARD_INPUTS_MQH
