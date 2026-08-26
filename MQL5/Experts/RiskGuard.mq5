//+------------------------------------------------------------------+
//|                                                    RiskGuard.mq5 |
//|           Production risk guardian for discretionary scalpers    |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property link      "https://github.com/domsendotnet/mt5-riskguard"
#property version   "1.11"
#property strict
#property description "RiskGuard watches your trades: stop/target, lot caps, no revenge stacking,"
#property description "tiny-profit basket exit, dead-trade timer, and a day kill-switch."

#include <RiskGuard/RiskGuard_Panel.mqh>

//+------------------------------------------------------------------+
void RG_SelectWhitelistSymbols()
  {
   string list = InpSymbolsWhitelist;
   StringReplace(list, " ", "");
   if(StringLen(list) == 0)
      return;
   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
     {
      if(StringLen(parts[i]) == 0)
         continue;
      if(!SymbolSelect(parts[i], true))
         Print("RiskGuard| WARNING: could not select symbol ", parts[i]);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_eaStartTime = TimeTradeServer();
   g_dayStamp = 0;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayClosedTrades = 0;
   g_dayLocked = false;
   g_cooldownUntil = 0;
   g_cooldownStarted = 0;
   g_lockTime = 0;
   g_seenDealN = 0;
   g_seenDealNext = 0;
   g_lastAction = "initialized";
   g_lastStatusReason = "starting";
   g_lastNotifyMsg = "";
   g_lastNotifyTime = 0;
   ArrayInitialize(g_seenDeals, 0);
   RG_StateLoad();

   if(InpTimerSeconds < 1)
     {
      Print("RiskGuard| InpTimerSeconds must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxLot <= 0.0 || InpMaxLossPer001 <= 0.0)
     {
      Print("RiskGuard| MaxLot and MaxLossPer001 must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAveragingMaxAdds < 0)
     {
      Print("RiskGuard| AveragingMaxAdds must be >= 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpHardMaxOpenPositions < 1)
     {
      Print("RiskGuard| HardMaxOpenPositions must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxOpenPositions < 1)
     {
      Print("RiskGuard| MaxOpenPositions must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
     }

   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(vmin > 0.0 && InpMaxLot + 1e-12 < vmin)
     {
      Print("RiskGuard| MaxLot ", InpMaxLot, " < broker min volume ", vmin,
            " — every fill would be closed");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpSLMode == RG_SL_MONEY_PER_001 && InpSL_MoneyPer001 > InpMaxLossPer001)
      Print("RiskGuard| WARNING: SL money per 0.01 > MaxLossPer001 — hard max wins, SL will be snapped");

   if(InpTimeGuardEnabled && InpMustBeGreenSeconds > 0 && InpMaxHoldSeconds > 0 &&
      InpMustBeGreenSeconds > InpMaxHoldSeconds)
      Print("RiskGuard| WARNING: must-be-green seconds > max hold — max hold will fire first");

   RG_SelectWhitelistSymbols();
   RG_ConfigureTrade();
   RG_RefreshTradingStatus();
   if(!g_tradingOk)
      Print("RiskGuard| WARNING: cannot trade yet — ", g_tradingBlockReason,
            " (panel will show CANNOT TRADE until this is fixed)");

   if(!EventSetTimer(InpTimerSeconds))
     {
      Print("RiskGuard| EventSetTimer failed");
      return INIT_FAILED;
     }

   RG_GuardianSweep();
   RG_PanelUpdate();

   RG_Log(1, "RiskGuard 1.11 started on " + _Symbol);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   RG_PanelDelete();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   RG_GuardianSweep();
   RG_PanelUpdate();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   RG_GuardianSweep();
   RG_PanelUpdate();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
      RG_ProcessClosedDeal(trans.deal);

   if(InpEnableGuard)
      RG_GuardianSweep();
   RG_PanelUpdate();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      RG_PanelUpdate();
  }
//+------------------------------------------------------------------+
