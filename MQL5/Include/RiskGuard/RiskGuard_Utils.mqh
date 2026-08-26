//+------------------------------------------------------------------+
//|                                            RiskGuard_Utils.mqh |
//|  Filters, persistence, money math, trade helpers. Fail-closed. |
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

string   g_lastStatusReason   = "starting";
string   g_lastAction         = "-";
bool     g_dayLocked          = false;
int      g_dayStamp           = 0;
double   g_dayStartEquity     = 0.0;
int      g_dayClosedTrades    = 0;
datetime g_cooldownUntil      = 0;
datetime g_cooldownStarted    = 0;
datetime g_lockTime           = 0;
datetime g_eaStartTime        = 0;

bool     g_tradingOk          = true;
string   g_tradingBlockReason = "";

string   g_lastNotifyMsg      = "";
datetime g_lastNotifyTime     = 0;

#define RG_SEEN_DEALS 256
ulong    g_seenDeals[RG_SEEN_DEALS];
int      g_seenDealN          = 0;
int      g_seenDealNext       = 0;

#define RG_NOTIFY_DEBOUNCE_SEC 5

//+------------------------------------------------------------------+
int RG_DayStampNow()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   datetime t = TimeTradeServer();
   if(dt.hour < InpDayResetHourServer)
      t -= 86400;
   TimeToStruct(t, dt);
   return dt.year * 10000 + dt.mon * 100 + dt.day;
  }

//+------------------------------------------------------------------+
string RG_StateKey(const string suffix)
  {
   return "RG_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + suffix;
  }

//+------------------------------------------------------------------+
void RG_StateSave()
  {
   GlobalVariableSet(RG_StateKey("dayStamp"), (double)g_dayStamp);
   GlobalVariableSet(RG_StateKey("dayEquity"), g_dayStartEquity);
   GlobalVariableSet(RG_StateKey("dayTrades"), (double)g_dayClosedTrades);
   GlobalVariableSet(RG_StateKey("dayLocked"), g_dayLocked ? 1.0 : 0.0);
   GlobalVariableSet(RG_StateKey("cooldown"), (double)g_cooldownUntil);
   GlobalVariableSet(RG_StateKey("cooldownStart"), (double)g_cooldownStarted);
   GlobalVariableSet(RG_StateKey("lockTime"), (double)g_lockTime);
  }

//+------------------------------------------------------------------+
void RG_StateLoad()
  {
   string kStamp = RG_StateKey("dayStamp");
   if(!GlobalVariableCheck(kStamp))
      return;
   int stamp = (int)GlobalVariableGet(kStamp);
   if(stamp != RG_DayStampNow())
      return;
   g_dayStamp = stamp;
   g_dayStartEquity = GlobalVariableGet(RG_StateKey("dayEquity"));
   g_dayClosedTrades = (int)GlobalVariableGet(RG_StateKey("dayTrades"));
   g_dayLocked = (GlobalVariableGet(RG_StateKey("dayLocked")) > 0.5);
   g_cooldownUntil = (datetime)GlobalVariableGet(RG_StateKey("cooldown"));
   g_cooldownStarted = (datetime)GlobalVariableGet(RG_StateKey("cooldownStart"));
   g_lockTime = (datetime)GlobalVariableGet(RG_StateKey("lockTime"));
   if(g_cooldownUntil > 0 && TimeTradeServer() >= g_cooldownUntil)
     {
      g_cooldownUntil = 0;
      g_cooldownStarted = 0;
     }
   if(!g_dayLocked)
      g_lockTime = 0;
  }

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
   datetime now = TimeTradeServer();
   if(msg == g_lastNotifyMsg && g_lastNotifyTime > 0 &&
      (now - g_lastNotifyTime) < RG_NOTIFY_DEBOUNCE_SEC)
     {
      g_lastAction = msg;
      return;
     }
   g_lastNotifyMsg = msg;
   g_lastNotifyTime = now;
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
bool RG_TradingAllowed(string &reason)
  {
   reason = "";
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      reason = "terminal is not connected to the broker";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      reason = "toolbar Algo Trading button is OFF";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason = "this EA does not have Allow Algo Trading ticked";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      reason = "the broker has disabled trading on this account";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      reason = "this account does not allow Expert Advisors";
      return false;
     }
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
     {
      reason = "this symbol cannot be traded right now";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
void RG_RefreshTradingStatus()
  {
   g_tradingOk = RG_TradingAllowed(g_tradingBlockReason);
  }

//+------------------------------------------------------------------+
bool RG_EnsureSymbol(const string symbol)
  {
   if(StringLen(symbol) == 0)
      return false;
   if(symbol == _Symbol)
      return true;
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
     {
      if(!SymbolSelect(symbol, true))
        {
         RG_Log(0, "SymbolSelect failed for " + symbol);
         return false;
        }
     }
   return true;
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
bool RG_IsPendingType(const long type)
  {
   return (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT ||
           type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP ||
           type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT);
  }

//+------------------------------------------------------------------+
int RG_CountManagedPendings(const string symbol_filter = "")
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!RG_IsPendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(!RG_SymbolAllowed(symbol))
         continue;
      if(!RG_MagicAllowed(magic))
         continue;
      if(StringLen(symbol_filter) > 0 && symbol != symbol_filter)
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
double RG_TickSize(const string symbol)
  {
   double t = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(t > 0.0)
      return t;
   return RG_Point(symbol);
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
int RG_MinStopPoints(const string symbol)
  {
   int stops = RG_StopsLevelPoints(symbol);
   int freeze = RG_FreezeLevelPoints(symbol);
   return (int)MathMax(stops, freeze);
  }

//+------------------------------------------------------------------+
double RG_RoundToTick(const string symbol, double price)
  {
   double tick = RG_TickSize(symbol);
   if(tick <= 0.0)
      tick = RG_Point(symbol);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   price = MathRound(price / tick) * tick;
   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
// Round to tick, then if the price violates min distance from market,
// step tick by tick away from market until it is legal (or give up).
//+------------------------------------------------------------------+
double RG_ClampToStops(const string symbol, const ENUM_POSITION_TYPE ptype,
                       const double open_price, const double price_candidate, const bool is_sl)
  {
   double point = RG_Point(symbol);
   double tick = RG_TickSize(symbol);
   int min_pts = RG_MinStopPoints(symbol);
   double min_dist = min_pts * point;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double price = RG_RoundToTick(symbol, price_candidate);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   if(ptype == POSITION_TYPE_BUY)
     {
      if(is_sl)
        {
         double max_sl = RG_RoundToTick(symbol, bid - min_dist);
         if(price > max_sl)
            price = max_sl;
         // step away from market (down) if still too close after rounding
         for(int k = 0; k < 8 && price > bid - min_dist + 1e-12; k++)
            price = NormalizeDouble(price - tick, digits);
        }
      else
        {
         double min_tp = RG_RoundToTick(symbol, bid + min_dist);
         if(price < min_tp)
            price = min_tp;
         for(int k = 0; k < 8 && price < bid + min_dist - 1e-12; k++)
            price = NormalizeDouble(price + tick, digits);
        }
     }
   else
     {
      if(is_sl)
        {
         double min_sl = RG_RoundToTick(symbol, ask + min_dist);
         if(price < min_sl)
            price = min_sl;
         for(int k = 0; k < 8 && price < ask + min_dist - 1e-12; k++)
            price = NormalizeDouble(price + tick, digits);
        }
      else
        {
         double max_tp = RG_RoundToTick(symbol, ask - min_dist);
         if(price > max_tp)
            price = max_tp;
         for(int k = 0; k < 8 && price > ask - min_dist + 1e-12; k++)
            price = NormalizeDouble(price - tick, digits);
        }
     }

   return RG_RoundToTick(symbol, price);
  }

//+------------------------------------------------------------------+
double RG_ScaledMoneyPer001(const double per001, const double lots)
  {
   return per001 * (lots / 0.01);
  }

//+------------------------------------------------------------------+
double RG_CommissionForLots(const double lots)
  {
   if(lots <= 0.0)
      return 0.0;
   return InpCommissionPer001 * (lots / 0.01);
  }

//+------------------------------------------------------------------+
double RG_ExitTargetForLots(const double lots)
  {
   return InpBasketMinProfit + RG_CommissionForLots(lots) + InpBasketExtraBuffer;
  }

//+------------------------------------------------------------------+
// Money -> SL-side price distance. Fail-closed: no silent points guess.
//+------------------------------------------------------------------+
bool RG_MoneyToDistance(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE order_type, const double open_price,
                        const double money, double &out_distance)
  {
   out_distance = 0.0;
   if(lots <= 0.0 || money <= 0.0)
      return false;
   if(!RG_EnsureSymbol(symbol))
      return false;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;

   double money_per_tick = tick_value * lots;
   if(money_per_tick <= 0.0)
      return false;
   double dist_est = (money / money_per_tick) * tick_size;

   double lo = tick_size;
   double hi = dist_est * 4.0 + tick_size;
   if(hi < tick_size * 10.0)
      hi = tick_size * 10.0;

   bool any_ok = false;
   for(int iter = 0; iter < 40; iter++)
     {
      double mid = (lo + hi) * 0.5;
      double close_price = (order_type == ORDER_TYPE_BUY) ? (open_price - mid)
                                                          : (open_price + mid);
      if(close_price <= 0.0)
        {
         hi = mid;
         continue;
        }
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
         continue;
      any_ok = true;
      double loss = -profit;
      if(loss < money)
         lo = mid;
      else
         hi = mid;
     }
   if(!any_ok)
      return false;
   out_distance = hi;
   return (out_distance > 0.0);
  }

//+------------------------------------------------------------------+
// Distance -> money (measurement). Tick-value fallback is allowed here
// because we are reading an existing SL, not inventing one.
//+------------------------------------------------------------------+
bool RG_DistanceToMoney(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE order_type, const double open_price,
                        const double distance, double &out_money)
  {
   out_money = 0.0;
   if(lots <= 0.0 || distance <= 0.0)
      return false;
   if(!RG_EnsureSymbol(symbol))
      return false;

   double close_price = (order_type == ORDER_TYPE_BUY) ? (open_price - distance)
                                                       : (open_price + distance);
   double profit = 0.0;
   if(close_price > 0.0 &&
      OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
     {
      out_money = -profit;
      if(out_money < 0.0)
         out_money = 0.0;
      return true;
     }

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;
   out_money = (distance / tick_size) * tick_value * lots;
   return true;
  }

//+------------------------------------------------------------------+
bool RG_MoneyToProfitDistance(const string symbol, const double lots,
                              const ENUM_ORDER_TYPE order_type, const double open_price,
                              const double money, double &out_distance)
  {
   out_distance = 0.0;
   if(lots <= 0.0 || money <= 0.0)
      return false;
   if(!RG_EnsureSymbol(symbol))
      return false;

   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0.0 || tick_value <= 0.0)
      return false;

   double money_per_tick = tick_value * lots;
   if(money_per_tick <= 0.0)
      return false;
   double dist_est = (money / money_per_tick) * tick_size;

   double lo = tick_size;
   double hi = dist_est * 4.0 + tick_size;
   if(hi < tick_size * 10.0)
      hi = tick_size * 10.0;

   bool any_ok = false;
   for(int iter = 0; iter < 40; iter++)
     {
      double mid = (lo + hi) * 0.5;
      double close_price = (order_type == ORDER_TYPE_BUY) ? (open_price + mid)
                                                          : (open_price - mid);
      if(close_price <= 0.0)
        {
         hi = mid;
         continue;
        }
      double profit = 0.0;
      if(!OrderCalcProfit(order_type, symbol, lots, open_price, close_price, profit))
         continue;
      any_ok = true;
      if(profit < money)
         lo = mid;
      else
         hi = mid;
     }
   if(!any_ok)
      return false;
   out_distance = hi;
   return (out_distance > 0.0);
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
      return RG_ScaledMoneyPer001(InpMaxLossPer001, lots);

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
   return RG_ExitTargetForLots(RG_BasketLots(symbol));
  }

//+------------------------------------------------------------------+
double RG_PositionNetAfterCosts()
  {
   double net = g_pos.Profit() + g_pos.Swap();
   net -= RG_CommissionForLots(g_pos.Volume());
   return net;
  }

//+------------------------------------------------------------------+
void RG_PrepareTrade(const string symbol)
  {
   g_trade.SetDeviationInPoints(InpMaxSlippagePoints);
   g_trade.SetAsyncMode(false);
   if(!RG_EnsureSymbol(symbol))
     {
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
      return;
     }
   long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
void RG_ConfigureTrade()
  {
   g_trade.SetExpertMagicNumber(0);
   RG_PrepareTrade(_Symbol);
  }

//+------------------------------------------------------------------+
bool RG_DealAlreadySeen(const ulong deal)
  {
   if(deal == 0)
      return true;
   for(int i = 0; i < g_seenDealN; i++)
      if(g_seenDeals[i] == deal)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
void RG_MarkDealSeen(const ulong deal)
  {
   if(deal == 0 || RG_DealAlreadySeen(deal))
      return;
   g_seenDeals[g_seenDealNext] = deal;
   g_seenDealNext = (g_seenDealNext + 1) % RG_SEEN_DEALS;
   if(g_seenDealN < RG_SEEN_DEALS)
      g_seenDealN++;
  }

//+------------------------------------------------------------------+
void RG_CollectManagedSymbols(string &symbols[])
  {
   int ns = 0;
   ArrayResize(symbols, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      string s = g_pos.Symbol();
      bool found = false;
      for(int k = 0; k < ns; k++)
         if(symbols[k] == s)
           {
            found = true;
            break;
           }
      if(!found)
        {
         ArrayResize(symbols, ns + 1);
         symbols[ns++] = s;
        }
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!RG_IsPendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      string s = OrderGetString(ORDER_SYMBOL);
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(!RG_SymbolAllowed(s) || !RG_MagicAllowed(magic))
         continue;
      bool found = false;
      for(int k = 0; k < ns; k++)
         if(symbols[k] == s)
           {
            found = true;
            break;
           }
      if(!found)
        {
         ArrayResize(symbols, ns + 1);
         symbols[ns++] = s;
        }
     }
  }

#endif // RISKGUARD_UTILS_MQH
