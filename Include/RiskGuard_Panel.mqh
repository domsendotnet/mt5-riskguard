//+------------------------------------------------------------------+
//|                                            RiskGuard_Panel.mqh |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_PANEL_MQH
#define RISKGUARD_PANEL_MQH

#include "RiskGuard_Enforce.mqh"

#define RG_PANEL_PREFIX "RG_UI_"

//+------------------------------------------------------------------+
void RG_PanelDelete()
  {
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, RG_PANEL_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
void RG_PanelSetLabel(const string id, const int line, const string text, const color clr)
  {
   string name = RG_PANEL_PREFIX + id;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX + 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + 10 + line * (RG_PANEL_FONT_SIZE + 6));
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, RG_PANEL_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, RG_PANEL_FONT_SIZE);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void RG_PanelSetBackground(const int lines)
  {
   string name = RG_PANEL_PREFIX + "BG";
   int width = 430;
   int height = 20 + lines * (RG_PANEL_FONT_SIZE + 6) + 10;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, RG_PANEL_BG_COLOR);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, RG_PANEL_ACCENT_COLOR);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
  }

//+------------------------------------------------------------------+
string RG_FmtMoney(const double v)
  {
   return StringFormat("%s %.2f", AccountInfoString(ACCOUNT_CURRENCY), v);
  }

//+------------------------------------------------------------------+
void RG_PanelUpdate()
  {
   if(!InpShowPanel)
     {
      RG_PanelDelete();
      return;
     }

   RG_RefreshTradingStatus();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double day_pnl = equity - g_dayStartEquity;
   double basis = RG_RiskBasis();
   double open_risk = RG_TotalOpenRiskMoney(_Symbol);
   double risk_pct = (basis > 0.0) ? (100.0 * open_risk / basis) : 0.0;
   int open_n = RG_CountManaged(_Symbol);
   int cap = RG_AllowedMaxPositions(_Symbol);
   int shown_cap = cap;
   if(g_dayLocked || RG_IsCooldownActive() || RG_IsNoTradeHoursActive())
      shown_cap = open_n; // cannot add
   int pend_n = RG_CountManagedPendings(_Symbol);
   double basket_net = RG_BasketNetProfit(_Symbol);
   double basket_tgt = RG_BasketExitTarget(_Symbol);

   string avg_reason;
   bool avg = RG_AveragingPrivilegeOK(_Symbol, avg_reason, false);

   color status_clr = RG_PANEL_ACCENT_COLOR;
   if(!g_tradingOk)
      status_clr = RG_PANEL_DANGER_COLOR;
   else if(g_dayLocked)
      status_clr = RG_PANEL_DANGER_COLOR;
   else if(RG_IsNoTradeHoursActive())
      status_clr = RG_PANEL_DANGER_COLOR;
   else if(RG_IsCooldownActive())
      status_clr = RG_PANEL_WARN_COLOR;
   else if(!InpEnableGuard)
      status_clr = RG_PANEL_WARN_COLOR;

   string mode;
   if(!InpEnableGuard)
      mode = "OFF";
   else if(!g_tradingOk)
      mode = "CANNOT TRADE";
   else if(g_dayLocked)
      mode = "DAY LOCKED";
   else if(RG_IsNoTradeHoursActive())
      mode = "NO TRADE HOURS";
   else if(RG_IsCooldownActive())
      mode = "REVENGE PAUSE";
   else if(open_n >= 2)
      mode = "SEVERAL TRADES";
   else
      mode = "ONE TRADE";

   string hours_line = RG_PolicyNoTradeHoursOn() ? RG_NoTradeHoursPanelLine() : "";
   string rescue_line = RG_RescuePanelLine(_Symbol);
   int lines = 11 + ((StringLen(hours_line) > 0) ? 1 : 0) +
               ((StringLen(rescue_line) > 0) ? 1 : 0);
   int line = 0;
   RG_PanelSetBackground(lines);
   RG_PanelSetLabel("h", line++, "RISKGUARD  ·  " + _Symbol, status_clr);
   RG_PanelSetLabel("e", line++, StringFormat("Account %s   Today P/L %+.2f",
                    RG_FmtMoney(equity), day_pnl), RG_PANEL_TEXT_COLOR);
   if(InpMaxRiskPercentPerTrade > 0.0)
      RG_PanelSetLabel("r", line++, StringFormat("At risk %s (%.2f%%)   Max one trade %.2f%%",
                       RG_FmtMoney(open_risk), risk_pct, InpMaxRiskPercentPerTrade), RG_PANEL_TEXT_COLOR);
   else
      RG_PanelSetLabel("r", line++, StringFormat("At risk %s (%.2f%%)   Max lot %.2f",
                       RG_FmtMoney(open_risk), risk_pct, InpMaxLot), RG_PANEL_TEXT_COLOR);
   RG_PanelSetLabel("p", line++, StringFormat("Open trades %d / %d   Pending orders %d   Never more than %d",
                    open_n, shown_cap, pend_n, RG_PolicyHardMaxPositions()), RG_PANEL_TEXT_COLOR);
   RG_PanelSetLabel("a", line++, avg ? "Adding to losers: YES"
                                     : ("Adding to losers: NO — " + avg_reason),
                    avg ? RG_PANEL_ACCENT_COLOR : RG_PANEL_WARN_COLOR);

   string acct = RG_IsHedgingAccount() ? "can hold several trades" : "one net trade per symbol";
   if(open_n >= 2)
      RG_PanelSetLabel("b", line++, StringFormat("Combined P/L %+.2f  (close all at %.2f)  stop %.2f/0.01 (%.0f×)  [%s]",
                       basket_net, basket_tgt, RG_StopMoneyPer001(_Symbol), RG_AveragingStopFactor(), acct),
                       (basket_net >= basket_tgt ? RG_PANEL_ACCENT_COLOR : RG_PANEL_TEXT_COLOR));
   else
      {
       string be = "";
       if(RG_PolicyBreakEvenOn())
          be = StringFormat("   BE after %.0f%% of target (+%.2f/0.01)",
                            InpBE_TriggerPercent, InpBE_LockPer001);
       RG_PanelSetLabel("b", line++, StringFormat("Stop %.2f / 0.01   Target %.2f / 0.01%s  [%s]",
                        InpMaxLossPer001, InpTP_MoneyPer001, be, acct), RG_PANEL_TEXT_COLOR);
      }

   if(StringLen(hours_line) > 0)
      RG_PanelSetLabel("h2", line++, hours_line,
                       RG_IsNoTradeHoursActive() ? RG_PANEL_DANGER_COLOR : RG_PANEL_TEXT_COLOR);
   else
      ObjectDelete(0, RG_PANEL_PREFIX + "h2");

   if(StringLen(rescue_line) > 0)
      RG_PanelSetLabel("rs", line++, rescue_line, RG_PANEL_WARN_COLOR);
   else
      ObjectDelete(0, RG_PANEL_PREFIX + "rs");

   RG_PanelSetLabel("m", line++, mode + "  ·  " + g_lastStatusReason, status_clr);
   RG_PanelSetLabel("l", line++, "Last action: " + g_lastAction, RG_PANEL_TEXT_COLOR);
   RG_PanelSetLabel("t", line++, StringFormat("Closed trades today %d   Rechecks every tick + every %ds",
                    g_dayClosedTrades, RG_TIMER_SECONDS), RG_PANEL_TEXT_COLOR);

   ChartRedraw(0);
  }

#endif // RISKGUARD_PANEL_MQH
