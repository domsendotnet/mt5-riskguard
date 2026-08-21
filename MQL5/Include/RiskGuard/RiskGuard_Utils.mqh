//+------------------------------------------------------------------+
//|                                            RiskGuard_Utils.mqh |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_UTILS_MQH
#define RISKGUARD_UTILS_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include "RiskGuard_Inputs.mqh"

CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

string g_lastStatusReason = "armed";
string g_lastAction       = "-";
bool   g_dayLocked        = false;
int    g_dayStamp         = 0;       // yyyymmdd of current risk day
double g_dayStartEquity   = 0.0;
int    g_dayClosedTrades  = 0;
datetime g_cooldownUntil  = 0;
datetime g_eaStartTime    = 0;

//+------------------------------------------------------------------+
void RG_Log(const int level, const string msg)
  {
   if(!InpLogToExperts)
      return;
   if(level > InpLogVerbosity)
      return;
   Print("RiskGuard| ", msg);
  }

//+------------------------------------------------------------------+
void RG_Notify(const string msg)
  {
   g_lastAction = msg;
   RG_Log(1, msg);
   if(InpAlertPopup)
      Alert("RiskGuard: ", msg);
   if(InpAlertPush)
      SendNotification("RiskGuard: " + msg);
   if(InpAlertSound)
      PlaySound(InpAlertSoundFile);
  }

//+------------------------------------------------------------------+
double RG_RiskBasis()
  {
   if(InpRiskBase == RG_RISK_BALANCE)
      return AccountInfoDouble(ACCOUNT_BALANCE);
   return AccountInfoDouble(ACCOUNT_EQUITY);
  }

//+------------------------------------------------------------------+
int RG_DayStampNow()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   int hour = dt.hour;
   // shift back if before reset hour
   datetime t = TimeTradeServer();
   if(hour < InpDayResetHourServer)
      t -= 86400;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
  }

//+------------------------------------------------------------------+
bool RG_SymbolAllowed(const string symbol)
  {
   string list = InpSymbolsWhitelist;
   StringReplace(list, " ", "");
   string parts[];
   int n = 0;
   if(StringLen(list) > 0)
      n = StringSplit(list, ',', parts);

   bool in_whitelist = false;
   for(int i = 0; i < n; i++)
     {
      if(parts[i] == symbol)
        {
         in_whitelist = true;
         break;
        }
     }

   if(InpChartSymbolOnly)
      return (symbol == _Symbol || in_whitelist);

   // All symbols mode
   if(n == 0)
      return true;
   return in_whitelist;
  }

//+------------------------------------------------------------------+
bool RG_MagicAllowed(const long magic)
  {
   if(InpMagicMode == RG_MAGIC_ALL)
      return true;
   if(InpMagicMode == RG_MAGIC_ZERO)
      return (magic == 0);
   return (magic == InpMagicFilter);
  }

//+------------------------------------------------------------------+
bool RG_PositionManaged(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   if(!RG_SymbolAllowed(g_pos.Symbol()))
      return false;
   if(!RG_MagicAllowed(g_pos.Magic()))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
bool RG_SelectManagedByIndex(const int index)
  {
   if(!g_pos.SelectByIndex(index))
      return false;
   if(!RG_SymbolAllowed(g_pos.Symbol()))
      return false;
   if(!RG_MagicAllowed(g_pos.Magic()))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
int RG_CountManaged(const string symbol_filter = "")
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(StringLen(symbol_filter) > 0 && g_pos.Symbol() != symbol_filter)
         continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
int RG_CountManagedDirection(const string symbol, const ENUM_POSITION_TYPE type)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(g_pos.PositionType() != type)
         continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
double RG_NormalizeVolume(const string symbol, double volume)
  {
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   volume = MathFloor(volume / step + 1e-12) * step;
   volume = NormalizeDouble(volume, 8);
   if(volume < vmin)
      return 0.0;
   if(volume > vmax)
      volume = vmax;
   return volume;
  }

//+------------------------------------------------------------------+
double RG_Point(const string symbol)
  {
   double p = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return (p > 0.0 ? p : _Point);
  }

//+------------------------------------------------------------------+
int RG_StopsLevelPoints(const string symbol)
  {
   return (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
  }

//+------------------------------------------------------------------+
int RG_FreezeLevelPoints(const string symbol)
  {
   return (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
  }

//+------------------------------------------------------------------+
double RG_ClampToStops(const string symbol, const ENUM_POSITION_TYPE ptype,
                       const double open_price, const double price_candidate, const bool is_sl)
  {
   double point = RG_Point(symbol);
   int stops = RG_StopsLevelPoints(symbol);
   double min_dist = stops * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double price = price_candidate;

   if(ptype == POSITION_TYPE_BUY)
     {
      if(is_sl)
        {
         double max_sl = bid - min_dist;
         if(price > max_sl)
            price = max_sl;
        }
      else
        {
         double min_tp = bid + min_dist;
         if(price < min_tp)
            price = min_tp;
        }
     }
   else
     {
      if(is_sl)
        {
         double min_sl = ask + min_dist;
         if(price < min_sl)
            price = min_sl;
        }
      else
        {
         double max_tp = ask - min_dist;
         if(price > max_tp)
            price = max_tp;
        }
     }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
// Money <-> price distance using OrderCalcProfit (production-accurate)
//+------------------------------------------------------------------+
bool RG_MoneyToDistance(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE order_type, const double open_price,
                        const double money, double &out_distance)
  {
   out_distance = 0.0;
   if(lots <= 0.0 || money <= 0.0)
      return false;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;

   // Initial estimate
   double money_per_tick = tick_value * lots;
   if(money_per_tick <= 0.0)
      return false;
   double dist = (money / money_per_tick) * tick_size;

   // Refine with OrderCalcProfit binary search on distance
   double lo = tick_size;
   double hi = dist * 4.0 + tick_size;
   if(hi < tick_size * 10)
      hi = tick_size * 10;

   for(int iter = 0; iter < 40; iter++)
     {
      double mid = (lo + hi) * 0.5;
      double close_price = open_price;
      if(order_type == ORDER_TYPE_BUY)
         close_price = open_price - mid; // SL side for buy => loss
      else
         close_price = open_price + mid;

      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
        {
         // fallback to tick formula
         out_distance = dist;
         return true;
        }
      double loss = -profit; // positive loss amount
      if(loss < money)
         lo = mid;
      else
         hi = mid;
     }
   out_distance = hi;
   return (out_distance > 0.0);
  }

//+------------------------------------------------------------------+
bool RG_DistanceToMoney(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE order_type, const double open_price,
                        const double distance, double &out_money)
  {
   out_money = 0.0;
   if(lots <= 0.0 || distance <= 0.0)
      return false;
   double close_price = (order_type == ORDER_TYPE_BUY) ? (open_price - distance)
                                                       : (open_price + distance);
   double profit = 0.0;
   if(!OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
     {
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
         return false;
      out_money = (distance / tick_size) * tick_value * lots;
      return true;
     }
   out_money = -profit;
   if(out_money < 0.0)
      out_money = 0.0;
   return true;
  }

//+------------------------------------------------------------------+
// Target floating profit (TP side) -> price distance
//+------------------------------------------------------------------+
bool RG_MoneyToProfitDistance(const string symbol, const double lots,
                              const ENUM_ORDER_TYPE order_type, const double open_price,
                              const double money, double &out_distance)
  {
   out_distance = 0.0;
   if(lots <= 0.0 || money <= 0.0)
      return false;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;

   double money_per_tick = tick_value * lots;
   if(money_per_tick <= 0.0)
      return false;
   double dist = (money / money_per_tick) * tick_size;

   double lo = tick_size;
   double hi = dist * 4.0 + tick_size;
   if(hi < tick_size * 10)
      hi = tick_size * 10;

   for(int iter = 0; iter < 40; iter++)
     {
      double mid = (lo + hi) * 0.5;
      double close_price = (order_type == ORDER_TYPE_BUY) ? (open_price + mid)
                                                          : (open_price - mid);
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
        {
         out_distance = dist;
         return true;
        }
      if(profit < money)
         lo = mid;
      else
         hi = mid;
     }
   out_distance = hi;
   return (out_distance > 0.0);
  }

//+------------------------------------------------------------------+
double RG_ScaledMoneyPer001(const double per001, const double lots)
  {
   return per001 * (lots / 0.01);
  }

//+------------------------------------------------------------------+
bool RG_IsHedgingAccount()
  {
   return (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

//+------------------------------------------------------------------+
double RG_PositionRiskMoney(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return 0.0;
   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   double open_price = g_pos.PriceOpen();
   double sl = g_pos.StopLoss();
   ENUM_ORDER_TYPE otype = (g_pos.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   if(sl <= 0.0)
     {
      // assume max allowed loss if naked
      return RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
     }
   double dist = MathAbs(open_price - sl);
   double money = 0.0;
   if(!RG_DistanceToMoney(symbol, lots, otype, open_price, dist, money))
      return RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
   return money;
  }

//+------------------------------------------------------------------+
double RG_TotalOpenRiskMoney(const string symbol_filter = "")
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(StringLen(symbol_filter) > 0 && g_pos.Symbol() != symbol_filter)
         continue;
      total += RG_PositionRiskMoney(g_pos.Ticket());
     }
   return total;
  }

//+------------------------------------------------------------------+
double RG_BasketNetProfit(const string symbol)
  {
   // Floating profit (+ optional swap). Commission is modeled in the exit TARGET
   // via InpCommissionPer001 so it is not double-counted here.
   double net = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      net += g_pos.Profit();
      if(InpBasketProfitIncludesSwap)
         net += g_pos.Swap();
     }
   return net;
  }

//+------------------------------------------------------------------+
double RG_BasketLots(const string symbol)
  {
   double lots = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      lots += g_pos.Volume();
     }
   return lots;
  }

//+------------------------------------------------------------------+
double RG_BasketExitTarget(const string symbol)
  {
   double lots = RG_BasketLots(symbol);
   double commission = InpCommissionPer001 * (lots / 0.01);
   return InpBasketMinProfit + commission + InpBasketExtraBuffer;
  }

//+------------------------------------------------------------------+
void RG_ConfigureTrade()
  {
   g_trade.SetExpertMagicNumber(0);
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);
   g_trade.SetAsyncMode(false);
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

#endif // RISKGUARD_UTILS_MQH
