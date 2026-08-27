//+------------------------------------------------------------------+
//|                                                    RiskGuard.mq5 |
//|           Production risk guardian for discretionary scalpers    |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property link      "https://github.com/domsendotnet/mt5-riskguard"
#property version   "1.30"
#property strict
#property description "RiskGuard watches your trades: stop/target, lot caps, no revenge stacking,"
#property description "tiny-profit basket exit, dead-trade timer, day kill-switch, no-trade hours."

#include "Include/RiskGuard_Panel.mqh"

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
   g_noTradeWasActive = false;
   ArrayInitialize(g_seenDeals, 0);
   RG_StateLoad();

   if(InpMaxLot <= 0.0 || InpMaxLossPer001 <= 0.0)
     {
      Print("RiskGuard| Biggest lot and stop per 0.01 must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAveragingMaxAdds < 0)
     {
      Print("RiskGuard| Extra trades cannot be negative (use 0 to never add)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTP_MoneyPer001 <= 0.0)
     {
      Print("RiskGuard| Take-profit per 0.01 must be > 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(vmin > 0.0 && InpMaxLot + 1e-12 < vmin)
     {
      Print("RiskGuard| Biggest lot ", InpMaxLot, " is below broker min volume ", vmin,
            " — every fill would be closed");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpMustBeGreenSeconds > 0 && InpMaxHoldSeconds > 0 &&
      InpMustBeGreenSeconds > InpMaxHoldSeconds)
      Print("RiskGuard| WARNING: 'still not in profit' seconds is longer than max hold — max hold wins");

   if(InpAveragingMaxAdds > 0 && InpAveragingMaxLot > InpMaxLot + 1e-8)
      Print("RiskGuard| WARNING: add-on max lot is bigger than biggest lot — the biggest-lot cap already blocks that");

   if(InpAveragingStopFactor < 1.0)
     {
      Print("RiskGuard| Averaging stop factor must be 1 or more (1 = don't widen, 2 = twice as wide)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAveragingMaxAdds > 0 && InpAveragingStopFactor <= 1.0 + 1e-12)
      Print("RiskGuard| WARNING: averaging stop factor is 1 — extras still use the single-trade stop, so the first leg can get stopped out");

   if(InpBE_TriggerPercent < 0.0 || InpBE_TriggerPercent > 100.0)
     {
      Print("RiskGuard| Break-even % must be 0 (off) through 100 (e.g. 70, not 0.70)");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBE_LockPer001 < 0.0)
     {
      Print("RiskGuard| Break-even lock per 0.01 cannot be negative");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBE_TriggerPercent > 0.0 && InpBE_TriggerPercent < 10.0)
      Print("RiskGuard| WARNING: break-even % is ", DoubleToString(InpBE_TriggerPercent, 1),
            " — 70 means seventy percent of take-profit, not 0.70");

   string hours_err;
   if(!RG_NoTradeHoursValidate(hours_err))
     {
      Print("RiskGuard| No-trade hours: ", hours_err,
            " — use 13:45-15:15,16:00-16:05 (empty = off)");
      return INIT_PARAMETERS_INCORRECT;
     }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxRiskPercentPerTrade > 0.0 && eq > 0.0)
     {
      double lot_risk = RG_ScaledMoneyPer001(InpMaxLossPer001, InpMaxLot);
      double pct_money = eq * InpMaxRiskPercentPerTrade / 100.0;
      if(lot_risk > pct_money + 1e-6)
         Print("RiskGuard| WARNING: max lot at your stop risks about ",
               DoubleToString(lot_risk, 2), " but one-trade % only allows ",
               DoubleToString(pct_money, 2),
               " — the % will shrink lots (set that % to 0 if you want the lot you typed)");
     }

   RG_SelectWhitelistSymbols();
   RG_ConfigureTrade();
   RG_RefreshTradingStatus();
   if(!g_tradingOk)
      Print("RiskGuard| WARNING: cannot trade yet — ", g_tradingBlockReason,
            " (panel will show CANNOT TRADE until this is fixed)");

   if(!EventSetTimer(RG_TIMER_SECONDS))
     {
      Print("RiskGuard| EventSetTimer failed");
      return INIT_FAILED;
     }

   RG_Log(1, "RiskGuard 1.30 started on " + _Symbol);
   RG_LogNoTradeHoursMapping();
   if(RG_IsNoTradeHoursActive())
      Print("RiskGuard| WARNING: inside a no-trade slot right now — watched trades will be closed on the next tick");
   // Do not send trades from OnInit (brokers reject it). Timer/tick sweep takes over.
   RG_RefreshStatusReason();
   RG_PanelUpdate();
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
