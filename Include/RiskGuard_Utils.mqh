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
bool     g_noTradeWasActive   = false;

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
   if(level > RG_LOG_VERBOSITY)
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
   if(InpAlerts != RG_ALERT_OFF)
      Alert("RiskGuard: ", msg);
   if(InpAlerts == RG_ALERT_PHONE)
      SendNotification("RiskGuard: " + msg);
   if(InpAlerts == RG_ALERT_POPUP_SOUND || InpAlerts == RG_ALERT_PHONE)
      PlaySound(RG_ALERT_SOUND_FILE);
  }

//+------------------------------------------------------------------+
double RG_RiskBasis()
  {
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

   return (symbol == _Symbol || in_whitelist);
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
double RG_AveragingStopFactor()
  {
   double f = InpAveragingStopFactor;
   if(f < 1.0)
      f = 1.0;
   return f;
  }

//+------------------------------------------------------------------+
// One trade: InpMaxLossPer001. Two or more on the same symbol while
// adding is on: that times the widen factor, so the first leg is not
// stopped out at the single-scalp distance.
//+------------------------------------------------------------------+
double RG_StopMoneyPer001(const string symbol)
  {
   double base = InpMaxLossPer001;
   if(base <= 0.0)
      return 0.0;
   if(!RG_PolicyAveragingOn())
      return base;
   double f = RG_AveragingStopFactor();
   if(f <= 1.0 + 1e-12)
      return base;
   if(RG_CountManaged(symbol) < 2)
      return base;
   return base * f;
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
   return InpBasketMinProfit + RG_CommissionForLots(lots);
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
      return RG_ScaledMoneyPer001(RG_StopMoneyPer001(symbol), lots);

   if(g_pos.PositionType() == POSITION_TYPE_BUY && sl >= open_price - 1e-12)
      return 0.0; // already a break-even / profit stop
   if(g_pos.PositionType() == POSITION_TYPE_SELL && sl > 0.0 && sl <= open_price + 1e-12)
      return 0.0;

   double dist = MathAbs(open_price - sl);
   double money = 0.0;
   if(!RG_DistanceToMoney(symbol, lots, otype, open_price, dist, money))
      return RG_ScaledMoneyPer001(RG_StopMoneyPer001(symbol), lots);
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
// Floor is RG_MAX_SLIPPAGE_POINTS. On a fast gold print, 30 points of
// a 3-digit XAUUSD is 3 cents and closes get rejected — use 3× spread.
//+------------------------------------------------------------------+
int RG_DeviationPoints(const string symbol)
  {
   int dev = RG_MAX_SLIPPAGE_POINTS;
   int spread = (int)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > 0)
     {
      int by_spread = spread * 3;
      if(by_spread > dev)
         dev = by_spread;
     }
   if(dev > 5000)
      dev = 5000;
   return dev;
  }

//+------------------------------------------------------------------+
void RG_PrepareTrade(const string symbol)
  {
   int dev = RG_MAX_SLIPPAGE_POINTS;
   if(StringLen(symbol) > 0)
      dev = RG_DeviationPoints(symbol);
   g_trade.SetDeviationInPoints(dev);
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

//====================================================================
// No-trade hours — clocks, DST, slot parse. Fail-closed on bad input.
//====================================================================
#define RG_MAX_NOTRADE_SLOTS 12
const int RG_SAKAMOTO_T[12] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};

//+------------------------------------------------------------------+
int RG_DaysInMonth(const int year, const int month)
  {
   if(month == 2)
     {
      bool leap = ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0));
      return (leap ? 29 : 28);
     }
   if(month == 4 || month == 6 || month == 9 || month == 11)
      return 30;
   return 31;
  }

//+------------------------------------------------------------------+
// Sakamoto. 0 = Sunday. Civil date, timezone-free.
//+------------------------------------------------------------------+
int RG_DayOfWeekYMD(int year, int month, const int day)
  {
   if(month < 3)
      year--;
   return (year + year / 4 - year / 100 + year / 400 + RG_SAKAMOTO_T[month - 1] + day) % 7;
  }

//+------------------------------------------------------------------+
int RG_LastSundayDay(const int year, const int month)
  {
   int dim = RG_DaysInMonth(year, month);
   int dow = RG_DayOfWeekYMD(year, month, dim); // 0=Sun
   return (dim - dow);
  }

//+------------------------------------------------------------------+
int RG_NthSundayDay(const int year, const int month, const int n)
  {
   int dow1 = RG_DayOfWeekYMD(year, month, 1);
   int first_sun = (dow1 == 0) ? 1 : (8 - dow1);
   return first_sun + (n - 1) * 7;
  }

//+------------------------------------------------------------------+
// EU DST: last Sunday of March 01:00 UTC → last Sunday of October 01:00 UTC.
// gmt is a TimeGMT()-style datetime (TimeToStruct shows UTC wall).
//+------------------------------------------------------------------+
bool RG_EuSummerGmt(const datetime gmt)
  {
   MqlDateTime g;
   TimeToStruct(gmt, g);
   int start_day = RG_LastSundayDay(g.year, 3);
   int end_day = RG_LastSundayDay(g.year, 10);
   if(g.mon < 3 || g.mon > 10)
      return false;
   if(g.mon > 3 && g.mon < 10)
      return true;
   if(g.mon == 3)
     {
      if(g.day > start_day)
         return true;
      if(g.day < start_day)
         return false;
      return (g.hour >= 1);
     }
   if(g.day < end_day)
      return true;
   if(g.day > end_day)
      return false;
   return (g.hour < 1);
  }

//+------------------------------------------------------------------+
// US DST (2007+): 2nd Sunday of March 07:00 UTC → 1st Sunday of November 06:00 UTC.
//+------------------------------------------------------------------+
bool RG_UsSummerGmt(const datetime gmt)
  {
   MqlDateTime g;
   TimeToStruct(gmt, g);
   int start_day = RG_NthSundayDay(g.year, 3, 2);
   int end_day = RG_NthSundayDay(g.year, 11, 1);
   if(g.mon < 3 || g.mon > 11)
      return false;
   if(g.mon > 3 && g.mon < 11)
      return true;
   if(g.mon == 3)
     {
      if(g.day > start_day)
         return true;
      if(g.day < start_day)
         return false;
      return (g.hour >= 7);
     }
   if(g.day < end_day)
      return true;
   if(g.day > end_day)
      return false;
   return (g.hour < 6);
  }

//+------------------------------------------------------------------+
int RG_ClockGmtOffsetSec(const ENUM_RG_CLOCK clock, const datetime gmt)
  {
   if(clock == RG_CLOCK_UTC)
      return 0;
   if(clock == RG_CLOCK_SERVER)
      return (int)(TimeTradeServer() - TimeGMT());
   if(clock == RG_CLOCK_LOCAL)
      return (int)(TimeLocal() - TimeGMT());
   if(clock == RG_CLOCK_BERLIN)
      return (RG_EuSummerGmt(gmt) ? 7200 : 3600);
   if(clock == RG_CLOCK_LONDON)
      return (RG_EuSummerGmt(gmt) ? 3600 : 0);
   if(clock == RG_CLOCK_NEWYORK)
      return (RG_UsSummerGmt(gmt) ? -14400 : -18000);
   return 0;
  }

//+------------------------------------------------------------------+
datetime RG_NowInClock(const ENUM_RG_CLOCK clock)
  {
   if(clock == RG_CLOCK_SERVER)
      return TimeTradeServer();
   if(clock == RG_CLOCK_LOCAL)
      return TimeLocal();
   if(clock == RG_CLOCK_UTC)
      return TimeGMT();
   datetime gmt = TimeGMT();
   return (gmt + RG_ClockGmtOffsetSec(clock, gmt));
  }

//+------------------------------------------------------------------+
string RG_ClockName(const ENUM_RG_CLOCK clock)
  {
   if(clock == RG_CLOCK_BERLIN)
      return "Europe/Berlin";
   if(clock == RG_CLOCK_SERVER)
      return "server";
   if(clock == RG_CLOCK_UTC)
      return "UTC";
   if(clock == RG_CLOCK_LOCAL)
      return "this PC";
   if(clock == RG_CLOCK_LONDON)
      return "Europe/London";
   if(clock == RG_CLOCK_NEWYORK)
      return "America/New York";
   return "clock";
  }

//+------------------------------------------------------------------+
string RG_FmtHm(const int minutes_from_midnight)
  {
   int m = minutes_from_midnight % 1440;
   if(m < 0)
      m += 1440;
   return StringFormat("%02d:%02d", m / 60, m % 60);
  }

//+------------------------------------------------------------------+
int RG_NowMinutesInClock(const ENUM_RG_CLOCK clock)
  {
   MqlDateTime dt;
   TimeToStruct(RG_NowInClock(clock), dt);
   return (dt.hour * 60 + dt.min);
  }

//+------------------------------------------------------------------+
// Server wall minus selected clock wall, in seconds. Negative = server behind.
//+------------------------------------------------------------------+
int RG_ServerMinusClockSec(const ENUM_RG_CLOCK clock)
  {
   return (int)(TimeTradeServer() - RG_NowInClock(clock));
  }

//+------------------------------------------------------------------+
string RG_TrimCopy(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

//+------------------------------------------------------------------+
bool RG_ParseHhMm(const string raw, int &out_min, string &err)
  {
   out_min = 0;
   err = "";
   string s = RG_TrimCopy(raw);
   int colon = StringFind(s, ":");
   if(colon <= 0 || colon >= StringLen(s) - 1)
     {
      err = "'" + s + "' is not HH:MM";
      return false;
     }
   int h = (int)StringToInteger(StringSubstr(s, 0, colon));
   int mi = (int)StringToInteger(StringSubstr(s, colon + 1));
   if(h < 0 || h > 23 || mi < 0 || mi > 59)
     {
      err = "'" + s + "' hour/minute out of range";
      return false;
     }
   // reject junk like 13:45foo
   string rebuilt = StringFormat("%d:%02d", h, mi);
   string rebuilt2 = StringFormat("%02d:%02d", h, mi);
   if(s != rebuilt && s != rebuilt2)
     {
      err = "'" + s + "' is not HH:MM";
      return false;
     }
   out_min = h * 60 + mi;
   return true;
  }

//+------------------------------------------------------------------+
bool RG_MinutesInSlot(const int now_min, const int start_min, const int end_min)
  {
   if(start_min <= end_min)
      return (now_min >= start_min && now_min <= end_min);
   return (now_min >= start_min || now_min <= end_min);
  }

//+------------------------------------------------------------------+
bool RG_ParseNoTradeSlots(const string raw, int &starts[], int &ends[], int &n, string &err)
  {
   n = 0;
   err = "";
   ArrayResize(starts, 0);
   ArrayResize(ends, 0);
   string s = raw;
   StringReplace(s, " ", "");
   StringReplace(s, "\t", "");
   StringReplace(s, "\r", "");
   StringReplace(s, "\n", "");
   StringReplace(s, "–", "-");
   StringReplace(s, "—", "-");
   StringReplace(s, ";", ",");
   if(StringLen(s) == 0)
      return true;

   string parts[];
   int np = StringSplit(s, ',', parts);
   if(np <= 0)
     {
      err = "could not read no-trade hours";
      return false;
     }
   if(np > RG_MAX_NOTRADE_SLOTS)
     {
      err = StringFormat("too many no-trade slots (max %d)", RG_MAX_NOTRADE_SLOTS);
      return false;
     }

   for(int i = 0; i < np; i++)
     {
      if(StringLen(parts[i]) == 0)
         continue;
      int dash = StringFind(parts[i], "-");
      if(dash <= 0 || dash >= StringLen(parts[i]) - 1)
        {
         err = "each slot must look like 13:45-15:15 (got " + parts[i] + ")";
         return false;
        }
      int a = 0;
      int b = 0;
      string e1, e2;
      if(!RG_ParseHhMm(StringSubstr(parts[i], 0, dash), a, e1))
        {
         err = e1;
         return false;
        }
      if(!RG_ParseHhMm(StringSubstr(parts[i], dash + 1), b, e2))
        {
         err = e2;
         return false;
        }
      ArrayResize(starts, n + 1);
      ArrayResize(ends, n + 1);
      starts[n] = a;
      ends[n] = b;
      n++;
     }
   if(n == 0)
     {
      err = "no-trade hours is not empty but no slots were read";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
bool RG_NoTradeHoursValidate(string &err)
  {
   err = "";
   if(!RG_PolicyNoTradeHoursOn())
      return true;
   int starts[], ends[], n;
   return RG_ParseNoTradeSlots(InpNoTradeHours, starts, ends, n, err);
  }

//+------------------------------------------------------------------+
bool RG_IsNoTradeHoursActive()
  {
   if(!RG_PolicyNoTradeHoursOn())
      return false;
   int starts[], ends[], n;
   string err;
   if(!RG_ParseNoTradeSlots(InpNoTradeHours, starts, ends, n, err) || n <= 0)
      return true; // hours are set but unreadable — block rather than trade
   int nowm = RG_NowMinutesInClock(InpNoTradeClock);
   for(int i = 0; i < n; i++)
      if(RG_MinutesInSlot(nowm, starts[i], ends[i]))
         return true;
   return false;
  }

//+------------------------------------------------------------------+
string RG_NoTradeActiveSlotLabel()
  {
   int starts[], ends[], n;
   string err;
   if(!RG_ParseNoTradeSlots(InpNoTradeHours, starts, ends, n, err) || n <= 0)
      return "";
   int nowm = RG_NowMinutesInClock(InpNoTradeClock);
   int delta_min = (int)MathRound((double)RG_ServerMinusClockSec(InpNoTradeClock) / 60.0);
   for(int i = 0; i < n; i++)
      if(RG_MinutesInSlot(nowm, starts[i], ends[i]))
        {
         string zone = StringFormat("%s-%s %s",
                                    RG_FmtHm(starts[i]), RG_FmtHm(ends[i]),
                                    RG_ClockName(InpNoTradeClock));
         if(InpNoTradeClock == RG_CLOCK_SERVER)
            return zone;
         return zone + StringFormat(" (server %s-%s)",
                                    RG_FmtHm(starts[i] + delta_min),
                                    RG_FmtHm(ends[i] + delta_min));
        }
   return "";
  }

//+------------------------------------------------------------------+
string RG_NoTradeHoursPanelLine()
  {
   int starts[], ends[], n;
   string err;
   if(!RG_ParseNoTradeSlots(InpNoTradeHours, starts, ends, n, err) || n <= 0)
      return "";
   string slots = "";
   for(int i = 0; i < n; i++)
     {
      if(i > 0)
         slots += ", ";
      slots += RG_FmtHm(starts[i]) + "-" + RG_FmtHm(ends[i]);
     }
   MqlDateTime z, sv;
   TimeToStruct(RG_NowInClock(InpNoTradeClock), z);
   TimeToStruct(TimeTradeServer(), sv);
   string nowz = StringFormat("%02d:%02d", z.hour, z.min);
   string nows = StringFormat("%02d:%02d", sv.hour, sv.min);
   if(InpNoTradeClock == RG_CLOCK_SERVER)
      return StringFormat("No-trade %s  now %s server", slots, nows);
   return StringFormat("No-trade %s %s  now %s = server %s",
                       slots, RG_ClockName(InpNoTradeClock), nowz, nows);
  }

//+------------------------------------------------------------------+
void RG_LogNoTradeHoursMapping()
  {
   if(!RG_PolicyNoTradeHoursOn())
     {
      RG_Log(1, "no-trade hours off (box empty)");
      return;
     }
   string err;
   int starts[], ends[], n;
   if(!RG_ParseNoTradeSlots(InpNoTradeHours, starts, ends, n, err))
     {
      RG_Log(0, "no-trade hours invalid: " + err);
      return;
     }

   datetime gmt = TimeGMT();
   int delta = RG_ServerMinusClockSec(InpNoTradeClock);
   int behind_m = (int)MathRound(MathAbs((double)delta) / 60.0);

   MqlDateTime z, sv, u;
   TimeToStruct(RG_NowInClock(InpNoTradeClock), z);
   TimeToStruct(TimeTradeServer(), sv);
   TimeToStruct(gmt, u);

   string dst = "";
   if(InpNoTradeClock == RG_CLOCK_BERLIN)
      dst = RG_EuSummerGmt(gmt) ? " (CEST, UTC+2, summer)" : " (CET, UTC+1, winter)";
   else if(InpNoTradeClock == RG_CLOCK_LONDON)
      dst = RG_EuSummerGmt(gmt) ? " (BST, UTC+1, summer)" : " (GMT, winter)";
   else if(InpNoTradeClock == RG_CLOCK_NEWYORK)
      dst = RG_UsSummerGmt(gmt) ? " (EDT, UTC-4, summer)" : " (EST, UTC-5, winter)";

   RG_Log(1, "no-trade clock " + RG_ClockName(InpNoTradeClock) + dst);
   RG_Log(1, StringFormat("now %s %02d:%02d:%02d  |  server %02d:%02d:%02d  |  UTC %02d:%02d:%02d",
                          RG_ClockName(InpNoTradeClock), z.hour, z.min, z.sec,
                          sv.hour, sv.min, sv.sec,
                          u.hour, u.min, u.sec));

   if(InpNoTradeClock != RG_CLOCK_SERVER)
     {
      if(delta == 0)
         RG_Log(1, "server clock matches " + RG_ClockName(InpNoTradeClock));
      else if(delta < 0)
         RG_Log(1, StringFormat("server is %d minute(s) behind %s",
                                behind_m, RG_ClockName(InpNoTradeClock)));
      else
         RG_Log(1, StringFormat("server is %d minute(s) ahead of %s",
                                behind_m, RG_ClockName(InpNoTradeClock)));
     }

   int delta_min = (int)MathRound((double)delta / 60.0);
   for(int i = 0; i < n; i++)
     {
      string line = StringFormat("  slot %s-%s %s",
                                 RG_FmtHm(starts[i]), RG_FmtHm(ends[i]),
                                 RG_ClockName(InpNoTradeClock));
      if(InpNoTradeClock != RG_CLOCK_SERVER)
         line += StringFormat("  =  server %s-%s",
                              RG_FmtHm(starts[i] + delta_min),
                              RG_FmtHm(ends[i] + delta_min));
      RG_Log(1, line);
     }
   RG_Log(1, "during a slot: every watched trade is closed, new fills are closed, pendings are deleted");
  }

#endif // RISKGUARD_UTILS_MQH
