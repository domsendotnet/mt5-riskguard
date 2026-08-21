//+------------------------------------------------------------------+
//|                                           RiskGuard_Inputs.mqh |
//|                     All user-facing settings (self-explaining) |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_INPUTS_MQH
#define RISKGUARD_INPUTS_MQH

enum ENUM_RG_MAGIC_MODE
  {
   RG_MAGIC_ALL = 0,       // Manage all magics
   RG_MAGIC_ZERO = 1,      // Manage manual trades only (magic 0)
   RG_MAGIC_SPECIFIC = 2   // Manage one magic number only
  };

enum ENUM_RG_RISK_BASE
  {
   RG_RISK_EQUITY = 0,     // Equity
   RG_RISK_BALANCE = 1     // Balance
  };

enum ENUM_RG_OVERSIZE_ACTION
  {
   RG_OVERSIZE_REDUCE = 0, // Reduce volume to max allowed
   RG_OVERSIZE_CLOSE = 1   // Close position fully
  };

enum ENUM_RG_SL_MODE
  {
   RG_SL_MONEY_PER_001 = 0, // Distance from money risk per 0.01 lot
   RG_SL_POINTS = 1         // Fixed distance in points
  };

enum ENUM_RG_TP_MODE
  {
   RG_TP_MONEY_PER_001 = 0, // Money profit per 0.01 lot
   RG_TP_POINTS = 1,        // Fixed points
   RG_TP_R_MULTIPLE = 2     // Multiple of SL distance
  };

enum ENUM_RG_ILLEGAL_ADD_ACTION
  {
   RG_ILLEGAL_CLOSE_ADD = 0, // Close only the illegal new add
   RG_ILLEGAL_FLATTEN = 1    // Flatten entire symbol basket
  };

//====================================================================
// MASTER
//====================================================================
input group "═══ Master ═══"
input bool               InpEnableGuard           = true;           // Enable RiskGuard enforcement
input bool               InpChartSymbolOnly       = true;           // Manage chart symbol only (recommended)
input string             InpSymbolsWhitelist      = "";             // Extra symbols (comma-separated), empty=none
input ENUM_RG_MAGIC_MODE InpMagicMode             = RG_MAGIC_ALL;   // Which magics to manage
input long               InpMagicFilter           = 0;              // Magic number (when mode = specific)
input int                InpTimerSeconds          = 1;              // Background check interval (seconds)
input int                InpModifyRetries         = 3;              // Retries for SL/TP modify
input int                InpRetryPauseMs          = 150;            // Pause between modify retries (ms)
input int                InpMaxSlippagePoints     = 30;             // Max slippage for closes (points)

//====================================================================
// ACCOUNT RISK
//====================================================================
input group "═══ Account Risk ═══"
input double                 InpMaxLot                 = 0.05;            // Absolute max lot per position
input double                 InpMaxLossPer001          = 5.0;             // Hard max loss per 0.01 lot (account currency)
input double                 InpMaxRiskPercentPerTrade = 1.0;             // Max risk % of equity/balance per trade
input double                 InpMaxTotalRiskPercent    = 2.0;             // Max combined open risk % (all managed)
input ENUM_RG_RISK_BASE      InpRiskBase               = RG_RISK_EQUITY;  // Risk % calculated from
input ENUM_RG_OVERSIZE_ACTION InpOnOversize            = RG_OVERSIZE_REDUCE; // Action when lot/risk too high
input int                    InpMaxOpenPositions      = 1;               // Max positions when averaging blocked
input int                    InpHardMaxOpenPositions  = 3;               // Absolute hard cap (even with averaging)

//====================================================================
// STOP LOSS
//====================================================================
input group "═══ Stop Loss ═══"
input bool           InpForceSL               = true;                 // Always ensure a stop loss exists
input ENUM_RG_SL_MODE InpSLMode               = RG_SL_MONEY_PER_001;  // How auto SL distance is computed
input double         InpSL_MoneyPer001        = 3.0;                  // Auto SL: loss per 0.01 lot (money mode)
input int            InpSL_Points             = 300;                  // Auto SL: points (points mode)
input bool           InpBlockWidenSL          = true;                 // Prevent SL from being widened past max risk
input bool           InpBlockRemoveSL         = true;                 // Prevent naked positions (no SL)
input int            InpNakedSLTimeoutSec     = 3;                    // Close if still without SL after N seconds
input bool           InpCloseIfSLModifyFails  = true;                 // Close if SL cannot be set after retries

//====================================================================
// TAKE PROFIT (single-leg)
//====================================================================
input group "═══ Take Profit (single trade) ═══"
input bool           InpForceTP               = true;                 // Always ensure a take profit exists
input ENUM_RG_TP_MODE InpTPMode               = RG_TP_MONEY_PER_001;  // How auto TP distance is computed
input double         InpTP_MoneyPer001        = 4.0;                  // Auto TP: profit per 0.01 lot (money mode)
input int            InpTP_Points             = 250;                  // Auto TP: points (points mode)
input double         InpTP_RMultiple          = 1.0;                  // Auto TP: R-multiple of SL (R mode)
input bool           InpDisableTPInBasket     = true;                 // Clear individual TP when basket (2+) active

//====================================================================
// AVERAGING (add to losers) — privilege when risk is low
//====================================================================
input group "═══ Averaging (add to losers) ═══"
input bool                     InpAveragingEnabled        = true;  // Allow averaging only when risk is low
input double                   InpAveragingMaxLot         = 0.02;  // Privilege: only if each leg lot ≤ this
input double                   InpAveragingMaxRiskPercent = 0.50;  // Privilege: only if open risk % ≤ this
input int                      InpAveragingMaxAdds        = 2;     // Max extra adds (entry + N)
input bool                     InpAveragingSameDirection  = true;  // Only allow adds in the same direction
input ENUM_RG_ILLEGAL_ADD_ACTION InpOnIllegalAdd          = RG_ILLEGAL_CLOSE_ADD; // Action when add not allowed
input double                   InpBasketMinProfit         = 0.01;  // Close basket when net ≥ this (account ccy)
input double                   InpCommissionPer001        = 0.04;  // Commission cost per 0.01 lot (account ccy)
input double                   InpBasketExtraBuffer       = 0.00;  // Extra buffer on top of min + commission
input bool                     InpBasketProfitIncludesSwap = true; // Include swap in basket net profit

//====================================================================
// TIME GUARD (single trade momentum fail)
//====================================================================
input group "═══ Time Guard (single trade) ═══"
input bool   InpTimeGuardEnabled      = true;  // Enable time-based exit for single trades
input int    InpMustBeGreenSeconds    = 90;    // Close if still ≤ 0 after N seconds
input int    InpMaxHoldSeconds        = 180;   // Absolute max hold for a single trade
input double InpTimeGuardExemptProfit = 0.50;  // Skip time cut if floating profit ≥ this
input bool   InpTimeGuardSkipBasket   = true;  // Do not time-cut legs while basket (2+) active

//====================================================================
// DAY PROTECTION
//====================================================================
input group "═══ Day Protection ═══"
input bool   InpDayLockEnabled        = true;  // Enable daily loss / trade locks
input double InpMaxDayLossPercent     = 3.0;   // Lock when day loss reaches this % of equity
input int    InpMaxDayTrades          = 40;    // Lock after this many closed trades (0=off)
input bool   InpDayLockFlatten        = true;  // Flatten all managed positions on day lock
input int    InpCooldownAfterLossSec  = 120;   // Block new risk for N seconds after a loss
input int    InpDayResetHourServer    = 0;     // Day boundary hour (server time, 0=midnight)

//====================================================================
// ALERTS & LOGS
//====================================================================
input group "═══ Alerts & Logs ═══"
input bool   InpAlertPopup      = true;       // Terminal alert popups
input bool   InpAlertPush       = false;      // Push notifications to phone
input bool   InpAlertSound      = true;       // Play sound on intervention
input string InpAlertSoundFile  = "alert.wav"; // Sound file name
input bool   InpLogToExperts    = true;       // Write detailed logs to Experts tab
input int    InpLogVerbosity    = 1;          // 0=errors 1=actions 2=verbose

//====================================================================
// PANEL (optics)
//====================================================================
input group "═══ On-Chart Panel ═══"
input bool            InpShowPanel         = true;            // Show RiskGuard status panel
input ENUM_BASE_CORNER InpPanelCorner      = CORNER_LEFT_UPPER; // Panel corner
input int             InpPanelX            = 12;              // Panel X offset (pixels)
input int             InpPanelY            = 24;              // Panel Y offset (pixels)
input int             InpPanelFontSize     = 9;               // Panel font size
input string          InpPanelFont         = "Consolas";      // Panel font
input color           InpPanelTextColor    = clrWhiteSmoke;   // Normal text color
input color           InpPanelAccentColor  = clrDodgerBlue;   // Accent / header color
input color           InpPanelWarnColor    = clrOrange;       // Warning color
input color           InpPanelDangerColor  = clrTomato;       // Danger / locked color
input color           InpPanelBgColor      = C'18,22,28';     // Background rectangle color
input bool            InpPanelShowBackground = true;          // Draw panel background

#endif // RISKGUARD_INPUTS_MQH
