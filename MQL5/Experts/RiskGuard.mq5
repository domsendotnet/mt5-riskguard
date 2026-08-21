//+------------------------------------------------------------------+
//|                                                    RiskGuard.mq5 |
//|           Production risk guardian for discretionary scalpers    |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property link      "https://github.com"
#property version   "1.00"
#property strict
#property description "RiskGuard — auto SL/TP, lot/risk caps, conditional averaging,"
#property description "basket BE+ exit, time guards, and day lock for MT5 scalpers."

#include <RiskGuard/RiskGuard_Panel.mqh>

//+------------------------------------------------------------------+
int OnInit()
  {
   g_eaStartTime = TimeTradeServer();
   g_dayStamp = 0;
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayClosedTrades = 0;
   g_dayLocked = false;
   g_cooldownUntil = 0;
   g_lastAction = "initialized";
   g_lastStatusReason = "armed";

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
   if(InpSL_MoneyPer001 > InpMaxLossPer001)
      Print("RiskGuard| WARNING: SL money per 0.01 > MaxLossPer001 — widen guard uses MaxLossPer001");
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

   RG_ConfigureTrade();

   if(!EventSetTimer(InpTimerSeconds))
     {
      Print("RiskGuard| EventSetTimer failed");
      return INIT_FAILED;
     }

   RG_UpdateDayState();
   RG_EnforceAll();
   RG_PanelUpdate();

   RG_Log(1, "RiskGuard started on " + _Symbol);
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
   // lightweight: basket exit is latency-sensitive for scalpers
   if(!InpEnableGuard)
     {
      RG_PanelUpdate();
      return;
     }
   if(InpChartSymbolOnly)
      RG_EnforceBasketExit(_Symbol);
   else
     {
      // still cheap: scan symbols with managed positions
      string symbols[];
      int ns = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!RG_SelectManagedByIndex(i))
            continue;
         string s = g_pos.Symbol();
         bool found = false;
         for(int k = 0; k < ns; k++)
            if(symbols[k] == s) { found = true; break; }
         if(!found)
           {
            ArrayResize(symbols, ns + 1);
            symbols[ns++] = s;
           }
        }
      for(int s = 0; s < ns; s++)
         RG_EnforceBasketExit(symbols[s]);
     }
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   RG_EnforceAll();
   RG_PanelUpdate();
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpEnableGuard)
      return;

   // New position deal
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      ulong deal = trans.deal;
      if(deal == 0)
         return;
      if(!HistoryDealSelect(deal))
         return;

      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      long deal_type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         return;

      string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
      long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
      if(!RG_SymbolAllowed(symbol))
         return;
      if(!RG_MagicAllowed(magic))
         return;

      if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
        {
         ulong pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         ulong pos_ticket = 0;

         if(pos_id > 0)
           {
            for(int i = PositionsTotal() - 1; i >= 0; i--)
              {
               if(!g_pos.SelectByIndex(i))
                  continue;
               if((ulong)g_pos.Identifier() == pos_id || g_pos.Ticket() == pos_id)
                 {
                  pos_ticket = g_pos.Ticket();
                  break;
                 }
              }
           }

         if(pos_ticket == 0)
           {
            datetime newest = 0;
            for(int i = PositionsTotal() - 1; i >= 0; i--)
              {
               if(!g_pos.SelectByIndex(i))
                  continue;
               if(g_pos.Symbol() != symbol || g_pos.Magic() != magic)
                  continue;
               datetime t = (datetime)PositionGetInteger(POSITION_TIME);
               if(t >= newest)
                 {
                  newest = t;
                  pos_ticket = g_pos.Ticket();
                 }
              }
           }

         if(pos_ticket > 0 && RG_PositionManaged(pos_ticket))
            RG_EnforceNewPosition(pos_ticket);
        }

      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
        {
         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT)
                         + HistoryDealGetDouble(deal, DEAL_SWAP)
                         + HistoryDealGetDouble(deal, DEAL_COMMISSION);
         RG_OnDealClosedLoss(profit);
         RG_UpdateDayState();
        }
     }

   // SL/TP changed externally — re-enforce widen/remove rules
   if(trans.type == TRADE_TRANSACTION_POSITION)
     {
      ulong ticket = trans.position;
      if(ticket > 0 && RG_PositionManaged(ticket))
        {
         RG_ApplyAutoSLTP(ticket);
         RG_EnforceSize(ticket);
        }
     }

   RG_PanelUpdate();
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      RG_PanelUpdate();
  }
//+------------------------------------------------------------------+
