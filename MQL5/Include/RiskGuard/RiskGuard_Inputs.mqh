//+------------------------------------------------------------------+
//|                                           RiskGuard_Inputs.mqh |
//|  Policy only. Implementation details are built-in constants.   |
//|  1.20 breaks old Input order — remove EA from chart, re-attach. |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_INPUTS_MQH
#define RISKGUARD_INPUTS_MQH

enum ENUM_RG_MAGIC_MODE
  {
   RG_MAGIC_ALL = 0,       // All trades (manual and EA) — recommended
   RG_MAGIC_ZERO = 1,      // Only my manual trades
   RG_MAGIC_SPECIFIC = 2   // Only one EA (set the magic number below)
  };

enum ENUM_RG_ALERTS
  {
   RG_ALERT_OFF = 0,           // Silent (Experts log only)
   RG_ALERT_POPUP = 1,         // Pop-up
   RG_ALERT_POPUP_SOUND = 2,   // Pop-up and sound — recommended
   RG_ALERT_PHONE = 3          // Pop-up, sound, and phone
  };

//====================================================================
// 1. START
//====================================================================
input group "═══ 1. Start ═══"
input bool               InpEnableGuard      = true;           // Protection ON. OFF = chart box only, no closes
input ENUM_RG_MAGIC_MODE InpMagicMode        = RG_MAGIC_ALL;   // Which trades to watch
input long               InpMagicFilter      = 0;              // Magic number — ignore unless "one EA" is selected above
input string             InpSymbolsWhitelist = "";             // Also watch these symbols (e.g. XAUUSD,EURUSD). Empty = this chart only

//====================================================================
// 2. YOUR MONEY
//====================================================================
input group "═══ 2. Your money ═══"
input double InpMaxLot                 = 0.05;  // Biggest lot on ONE trade
input double InpMaxLossPer001          = 5.0;   // Worst loss allowed per 0.01 lot (your money)
input double InpSL_MoneyPer001         = 3.0;   // Normal stop: lose this much per 0.01 lot if hit
input double InpTP_MoneyPer001         = 4.0;   // Take-profit: bank this much per 0.01 lot
input double InpMaxRiskPercentPerTrade = 1.0;   // One trade may not risk more than this % of the account
input double InpMaxTotalRiskPercent    = 2.0;   // All open trades together may not risk more than this %

//====================================================================
// 3. ADDING TO LOSERS
//====================================================================
input group "═══ 3. Adding to losers ═══"
input int    InpAveragingMaxAdds        = 2;     // How many extras (0 = never add). Original + this many.
input double InpAveragingMaxLot         = 0.02;  // Add only if EVERY open trade is this lot or smaller
input double InpAveragingMaxRiskPercent = 0.50;  // Add only if open risk is this % of the account or less
input double InpBasketMinProfit         = 0.01;  // Close all together at this tiny profit (your money, before commission)
input double InpCommissionPer001        = 0.04;  // Your broker commission per 0.01 lot (so "tiny profit" is after costs)

//====================================================================
// 4. TIME AND DAY
//====================================================================
input group "═══ 4. Cut losers / stop the day ═══"
input int    InpMustBeGreenSeconds     = 120;  // Close a single trade still not in profit after N seconds (0 = off)
input int    InpMaxHoldSeconds         = 180;  // Never hold a single trade longer than N seconds (0 = off)
input double InpTimeGuardExemptProfit  = 0.50; // Do not time-close if profit after costs is at least this
input double InpMaxDayLossPercent      = 3.0;  // Lock the day if equity is down this % from this morning (0 = off)
input int    InpMaxDayTrades           = 40;   // Lock the day after this many closed trades (0 = off)
input int    InpCooldownAfterLossSec   = 120;  // After a loss, block NEW trades for N seconds (0 = off)
input int    InpDayResetHourServer     = 0;    // Risk-day restarts at this broker-server hour (0 = midnight)

//====================================================================
// 5. ALERTS AND PANEL
//====================================================================
input group "═══ 5. Alerts and panel ═══"
input ENUM_RG_ALERTS   InpAlerts      = RG_ALERT_POPUP_SOUND; // How to tell you when RiskGuard acts
input bool             InpShowPanel   = true;                 // Show the status box on the chart
input ENUM_BASE_CORNER InpPanelCorner = CORNER_LEFT_UPPER;    // Chart corner for the box
input int              InpPanelX      = 12;                   // Left-right offset from that corner (pixels)
input int              InpPanelY      = 24;                   // Up-down offset from that corner (pixels)

//====================================================================
// Built-in policy — always on. Not in the dialog.
//====================================================================
#define RG_TIMER_SECONDS            1
#define RG_MODIFY_RETRIES           3
#define RG_MAX_SLIPPAGE_POINTS      30
#define RG_NAKED_SL_TIMEOUT_SEC     3
#define RG_ALERT_SOUND_FILE         "alert.wav"
#define RG_LOG_VERBOSITY            1

#define RG_PANEL_FONT               "Consolas"
#define RG_PANEL_FONT_SIZE          9
#define RG_PANEL_TEXT_COLOR         clrWhiteSmoke
#define RG_PANEL_ACCENT_COLOR       clrDodgerBlue
#define RG_PANEL_WARN_COLOR         clrOrange
#define RG_PANEL_DANGER_COLOR       clrTomato
#define RG_PANEL_BG_COLOR           C'18,22,28'

//+------------------------------------------------------------------+
bool RG_PolicyAveragingOn()
  {
   return (InpAveragingMaxAdds > 0);
  }

//+------------------------------------------------------------------+
int RG_PolicyHardMaxPositions()
  {
   int adds = InpAveragingMaxAdds;
   if(adds < 0)
      adds = 0;
   return (1 + adds);
  }

//+------------------------------------------------------------------+
bool RG_PolicyTimeOn()
  {
   return (InpMustBeGreenSeconds > 0 || InpMaxHoldSeconds > 0);
  }

//+------------------------------------------------------------------+
bool RG_PolicyDayOn()
  {
   return (InpMaxDayLossPercent > 0.0 || InpMaxDayTrades > 0);
  }

#endif // RISKGUARD_INPUTS_MQH
