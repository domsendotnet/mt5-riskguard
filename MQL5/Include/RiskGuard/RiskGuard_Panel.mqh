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
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + 10 + line * (InpPanelFontSize + 6));
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, InpPanelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
void RG_PanelSetBackground(const int lines)
  {
   string name = RG_PANEL_PREFIX + "BG";
   int width = 430;
   int height = 20 + lines * (InpPanelFontSize + 6) + 10;
   if(!InpPanelShowBackground)
     {
      ObjectDelete(0, name);
      return;
     }
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpPanelCorner);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, InpPanelBgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpPanelAccentColor);
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
   double open_risk = RG_TotalOpenRiskMoney(InpChartSymbolOnly ? _Symbol : "");
   double risk_pct = (basis > 0.0) ? (100.0 * open_risk / basis) : 0.0;
   int open_n = RG_CountManaged(InpChartSymbolOnly ? _Symbol : "");
   int cap = RG_AllowedMaxPositions(_Symbol);
   int shown_cap = cap;
   if(g_dayLocked || RG_IsCooldownActive())
      shown_cap = open_n; // cannot add
   int pend_n = RG_CountManagedPendings(InpChartSymbolOnly ? _Symbol : "");
   double basket_net = RG_BasketNetProfit(_Symbol);
   double basket_tgt = RG_BasketExitTarget(_Symbol);

   string avg_reason;
   bool avg = RG_AveragingPrivilegeOK(_Symbol, avg_reason, false);

   color status_clr = InpPanelAccentColor;
   if(!g_tradingOk)
      status_clr = InpPanelDangerColor;
   else if(g_dayLocked)
      status_clr = InpPanelDangerColor;
   else if(RG_IsCooldownActive())
      status_clr = InpPanelWarnColor;
   else if(!InpEnableGuard)
      status_clr = InpPanelWarnColor;

   string mode;
   if(!InpEnableGuard)
      mode = "OFF";
   else if(!g_tradingOk)
      mode = "CANNOT TRADE";
   else if(g_dayLocked)
      mode = "DAY LOCKED";
   else if(RG_IsCooldownActive())
      mode = "REVENGE PAUSE";
   else if(open_n >= 2)
      mode = "SEVERAL TRADES";
   else
      mode = "ONE TRADE";

   int line = 0;
   RG_PanelSetBackground(11);
   RG_PanelSetLabel("h", line++, "RISKGUARD  ·  " + _Symbol, status_clr);
   RG_PanelSetLabel("e", line++, StringFormat("Account %s   Today P/L %+.2f",
                    RG_FmtMoney(equity), day_pnl), InpPanelTextColor);
   RG_PanelSetLabel("r", line++, StringFormat("At risk %s (%.2f%%)   Max one trade %.2f%%",
                    RG_FmtMoney(open_risk), risk_pct, InpMaxRiskPercentPerTrade), InpPanelTextColor);
   RG_PanelSetLabel("p", line++, StringFormat("Open trades %d / %d   Pending orders %d   Never more than %d",
                    open_n, shown_cap, pend_n, InpHardMaxOpenPositions), InpPanelTextColor);
   RG_PanelSetLabel("a", line++, avg ? "Adding to losers: YES"
                                     : ("Adding to losers: NO — " + avg_reason),
                    avg ? InpPanelAccentColor : InpPanelWarnColor);

   string acct = RG_IsHedgingAccount() ? "can hold several trades" : "one net trade per symbol";
   if(open_n >= 2)
      RG_PanelSetLabel("b", line++, StringFormat("Combined P/L %+.2f  (close all at %.2f)  [%s]",
                       basket_net, basket_tgt, acct),
                       (basket_net >= basket_tgt ? InpPanelAccentColor : InpPanelTextColor));
   else
      RG_PanelSetLabel("b", line++, StringFormat("Stop %.2f / 0.01   Target %.2f / 0.01   Worst %.2f / 0.01  [%s]",
                       InpSL_MoneyPer001, InpTP_MoneyPer001, InpMaxLossPer001, acct), InpPanelTextColor);

   RG_PanelSetLabel("m", line++, mode + "  ·  " + g_lastStatusReason, status_clr);
   RG_PanelSetLabel("l", line++, "Last action: " + g_lastAction, InpPanelTextColor);
   RG_PanelSetLabel("t", line++, StringFormat("Closed trades today %d   Rechecks every tick + every %ds",
                    g_dayClosedTrades, InpTimerSeconds), InpPanelTextColor);

   ChartRedraw(0);
  }

#endif // RISKGUARD_PANEL_MQH
