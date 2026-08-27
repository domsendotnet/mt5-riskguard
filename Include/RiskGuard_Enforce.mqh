//+------------------------------------------------------------------+
//|                                          RiskGuard_Enforce.mqh |
//|  Invariant loop: every rule is true on every tick, or we act.  |
//|  No Sleep. Failed protective trades retry until the account is |
//|  legal or we cannot trade.                                     |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_ENFORCE_MQH
#define RISKGUARD_ENFORCE_MQH

#include "RiskGuard_Utils.mqh"

//+------------------------------------------------------------------+
bool RG_IsCooldownActive()
  {
   return (InpCooldownAfterLossSec > 0 && g_cooldownUntil > 0 &&
           TimeTradeServer() < g_cooldownUntil);
  }

//+------------------------------------------------------------------+
// skip_session_blocks: lot/risk privilege only (ignore lock/cooldown).
// Used to size the cap for EXISTING positions so cooldown does not
// flatten the trade that is already on.
//+------------------------------------------------------------------+
bool RG_AveragingPrivilegeOK(const string symbol, string &reason,
                             const bool skip_session_blocks = false)
  {
   reason = "";
   if(!RG_PolicyAveragingOn())
     {
      reason = "extras set to 0 in settings";
      return false;
     }
   if(!RG_IsHedgingAccount())
     {
      reason = "this account type cannot hold several trades on one symbol";
      return false;
     }
   if(!skip_session_blocks)
     {
      if(g_dayLocked)
        {
         reason = "the day is locked";
         return false;
        }
      if(RG_IsCooldownActive())
        {
         reason = "revenge pause after a loss";
         return false;
        }
      if(RG_IsNoTradeHoursActive())
        {
         reason = "no-trade hours";
         return false;
        }
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(g_pos.Volume() > InpAveragingMaxLot + 1e-8)
        {
         reason = StringFormat("a trade is %.2f lot (adds need ≤ %.2f)", g_pos.Volume(), InpAveragingMaxLot);
         return false;
        }
     }

   double basis = RG_RiskBasis();
   if(basis <= 0.0)
     {
      reason = "account size not available";
      return false;
     }
   double risk_pct = 100.0 * RG_TotalOpenRiskMoney(symbol) / basis;
   if(InpAveragingMaxRiskPercent > 0.0 && risk_pct > InpAveragingMaxRiskPercent + 1e-9)
     {
      reason = StringFormat("open risk %.2f%% (adds need ≤ %.2f%%)", risk_pct, InpAveragingMaxRiskPercent);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
// Position cap from lot/risk privilege. Does NOT zero out for
// cooldown/lock — those have their own "new vs existing" rules.
//+------------------------------------------------------------------+
int RG_AllowedMaxPositions(const string symbol)
  {
   string reason;
   bool avg_ok = RG_AveragingPrivilegeOK(symbol, reason, true);
   int hard = RG_PolicyHardMaxPositions();
   int soft = avg_ok ? hard : 1;
   return (int)MathMin(soft, hard);
  }

//+------------------------------------------------------------------+
bool RG_ClosePositionTicket(const ulong ticket, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   string symbol = g_pos.Symbol();
   RG_PrepareTrade(symbol);
   g_trade.SetExpertMagicNumber(g_pos.Magic());
   int dev = RG_DeviationPoints(symbol);
   bool ok = g_trade.PositionClose(ticket, (ulong)dev);
   uint rc = g_trade.ResultRetcode();
   // A full close that only partially fills is not closed.
   if(ok && rc == TRADE_RETCODE_DONE_PARTIAL)
      ok = false;
   if(ok && g_pos.SelectByTicket(ticket))
     {
      // Terminal cache can lag a real close. A deal ticket means the
      // broker took it — treat as success and let the next sweep confirm
      // it is gone. No deal + still selected = did not actually close.
      if(g_trade.ResultDeal() == 0)
        {
         RG_Log(0, StringFormat("close said OK but #%s still open (no deal) — will retry",
                                IntegerToString((long)ticket)));
         ok = false;
        }
     }
   if(ok)
      RG_Notify(StringFormat("closed #%s (%s) — %s", IntegerToString((long)ticket), symbol, why));
   else
      RG_Log(0, StringFormat("close FAILED #%s retcode=%d %s — will retry",
                             IntegerToString((long)ticket), g_trade.ResultRetcode(), why));
   return ok;
  }

//+------------------------------------------------------------------+
bool RG_ReducePositionTo(const ulong ticket, const double target_lots, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   double cur = g_pos.Volume();
   string symbol = g_pos.Symbol();
   double tgt = RG_NormalizeVolume(symbol, target_lots);
   if(tgt <= 0.0)
      return RG_ClosePositionTicket(ticket, why + " (reduce->close)");
   if(tgt >= cur - 1e-8)
      return true;
   double close_vol = RG_NormalizeVolume(symbol, cur - tgt);
   if(close_vol <= 0.0)
      return false;
   RG_PrepareTrade(symbol);
   g_trade.SetExpertMagicNumber(g_pos.Magic());
   int dev = RG_DeviationPoints(symbol);
   bool ok = g_trade.PositionClosePartial(ticket, close_vol, (ulong)dev);
   if(ok)
     {
      double filled = g_trade.ResultVolume();
      bool volume_ok = false;
      if(!g_pos.SelectByTicket(ticket))
         volume_ok = true; // gone entirely
      else if(g_pos.Volume() <= tgt + 1e-8)
         volume_ok = true;
      else if(filled + 1e-8 >= close_vol && g_trade.ResultDeal() > 0)
         volume_ok = true; // cache still shows old volume; broker filled the cut
      if(!volume_ok)
        {
         RG_Log(0, StringFormat("partial close said OK but #%s still %.2f (wanted %.2f, filled %.2f)",
                                IntegerToString((long)ticket),
                                g_pos.SelectByTicket(ticket) ? g_pos.Volume() : 0.0, tgt, filled));
         ok = false;
        }
     }
   if(ok)
      RG_Notify(StringFormat("reduced #%s to %.2f — %s", IntegerToString((long)ticket), tgt, why));
   else
      RG_Log(0, StringFormat("partial close FAILED #%s retcode=%d — falling back to full close",
                             IntegerToString((long)ticket), g_trade.ResultRetcode()));
   return ok;
  }

//+------------------------------------------------------------------+
bool RG_FlattenSymbol(const string symbol, const string why)
  {
   bool any = false;
   bool all_ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(RG_ClosePositionTicket(g_pos.Ticket(), why))
         any = true;
      else
         all_ok = false;
     }
   return any && all_ok;
  }

//+------------------------------------------------------------------+
bool RG_FlattenAllManaged(const string why)
  {
   bool pending = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(!RG_ClosePositionTicket(g_pos.Ticket(), why))
         pending = true;
     }
   return !pending;
  }

//+------------------------------------------------------------------+
bool RG_DeletePending(const ulong ticket, const string why)
  {
   string symbol = "";
   long magic = 0;
   bool found = false;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) != ticket)
         continue;
      symbol = OrderGetString(ORDER_SYMBOL);
      magic = OrderGetInteger(ORDER_MAGIC);
      found = true;
      break;
     }
   if(!found)
      return false;
   RG_PrepareTrade(symbol);
   g_trade.SetExpertMagicNumber(magic);
   bool ok = g_trade.OrderDelete(ticket);
   if(ok)
      RG_Notify(StringFormat("deleted pending #%s (%s) — %s", IntegerToString((long)ticket), symbol, why));
   else
      RG_Log(0, StringFormat("pending delete FAILED #%s retcode=%d %s — will retry",
                             IntegerToString((long)ticket), g_trade.ResultRetcode(), why));
   return ok;
  }

//+------------------------------------------------------------------+
void RG_DeleteManagedPendings(const string symbol_filter, const string why)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!RG_IsPendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(!RG_SymbolAllowed(symbol) || !RG_MagicAllowed(magic))
         continue;
      if(StringLen(symbol_filter) > 0 && symbol != symbol_filter)
         continue;
      RG_DeletePending(ticket, why);
     }
  }

//+------------------------------------------------------------------+
double RG_MaxSLDistance(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE otype, const double open_price)
  {
   double money = RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
   double dist = 0.0;
   if(RG_MoneyToDistance(symbol, lots, otype, open_price, money, dist))
      return dist;
   return 0.0;
  }

//+------------------------------------------------------------------+
double RG_DesiredTPDistance(const string symbol, const double lots,
                            const ENUM_ORDER_TYPE otype, const double open_price)
  {
   double money = RG_ScaledMoneyPer001(InpTP_MoneyPer001, lots);
   double dist = 0.0;
   if(!RG_MoneyToProfitDistance(symbol, lots, otype, open_price, money, dist))
      return 0.0;
   return dist;
  }

//+------------------------------------------------------------------+
bool RG_ModifySLTP(const ulong ticket, double sl, double tp, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   string symbol = g_pos.Symbol();
   sl = (sl > 0.0) ? RG_RoundToTick(symbol, sl) : 0.0;
   tp = (tp > 0.0) ? RG_RoundToTick(symbol, tp) : 0.0;

   RG_PrepareTrade(symbol);
   int attempts = MathMax(1, RG_MODIFY_RETRIES);
   for(int attempt = 0; attempt < attempts; attempt++)
     {
      g_trade.SetExpertMagicNumber(g_pos.Magic());
      if(g_trade.PositionModify(ticket, sl, tp))
        {
         RG_Log(1, StringFormat("modified #%s SL=%.5f TP=%.5f — %s",
                                IntegerToString((long)ticket), sl, tp, why));
         return true;
        }
      if(!g_pos.SelectByTicket(ticket))
         return false;
     }
   RG_Log(0, StringFormat("modify FAILED #%s retcode=%d — %s (retry next tick)",
                          IntegerToString((long)ticket), g_trade.ResultRetcode(), why));
   return false;
  }

//+------------------------------------------------------------------+
// Returns false if the position was closed as a safety action.
//+------------------------------------------------------------------+
bool RG_ApplyAutoSLTP(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;

   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   double open_price = g_pos.PriceOpen();
   ENUM_POSITION_TYPE ptype = g_pos.PositionType();
   ENUM_ORDER_TYPE otype = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double cur_sl = g_pos.StopLoss();
   double cur_tp = g_pos.TakeProfit();

   int basket = RG_CountManaged(symbol);
   bool in_basket = (basket >= 2);

   double sl_dist = RG_MaxSLDistance(symbol, lots, otype, open_price);
   double max_sl_dist = sl_dist;

   if(sl_dist <= 0.0 && cur_sl <= 0.0)
     {
      RG_Log(0, StringFormat("cannot compute SL distance #%s — money math failed",
                             IntegerToString((long)ticket)));
      return true; // naked-timeout path will kill it; do not guess points
     }

   double tp_dist = RG_DesiredTPDistance(symbol, lots, otype, open_price);

   double new_sl = cur_sl;
   double new_tp = cur_tp;
   bool changed = false;
   bool sl_past_max = false;

   if(cur_sl <= 0.0 && sl_dist > 0.0)
     {
      double target_sl = (ptype == POSITION_TYPE_BUY) ? (open_price - sl_dist)
                                                      : (open_price + sl_dist);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if((ptype == POSITION_TYPE_BUY && bid > 0.0 && bid <= target_sl) ||
         (ptype == POSITION_TYPE_SELL && ask > 0.0 && ask >= target_sl))
        {
         RG_ClosePositionTicket(ticket, "already past your stop — closed");
         return false;
        }
      new_sl = RG_ClampToStops(symbol, ptype, open_price, target_sl, true);
      changed = true;
     }

   if(max_sl_dist > 0.0)
     {
      double sl_now = (new_sl > 0.0 ? new_sl : cur_sl);
      if(sl_now > 0.0)
        {
         double cur_dist = MathAbs(open_price - sl_now);
         if(cur_dist > max_sl_dist + RG_TickSize(symbol) * 0.5)
           {
            double snap = (ptype == POSITION_TYPE_BUY) ? (open_price - max_sl_dist)
                                                       : (open_price + max_sl_dist);
            new_sl = RG_ClampToStops(symbol, ptype, open_price, snap, true);
            // Only send a modify if this is actually closer to entry than the
            // stop we have now. Broker min-distance can refuse a 5-per-0.01
            // stop at entry; we keep the tightest legal stop and retry later.
            double new_dist = MathAbs(open_price - new_sl);
            if(new_dist + RG_TickSize(symbol) * 0.5 < cur_dist)
              {
               changed = true;
               sl_past_max = true;
              }
           }
        }
     }

   if(in_basket)
     {
      if(cur_tp > 0.0)
        {
         new_tp = 0.0;
         changed = true;
        }
     }
   else if(cur_tp <= 0.0)
     {
      if(tp_dist > 0.0)
        {
         double target_tp = (ptype == POSITION_TYPE_BUY) ? (open_price + tp_dist)
                                                         : (open_price - tp_dist);
         new_tp = RG_ClampToStops(symbol, ptype, open_price, target_tp, false);
         changed = true;
        }
     }

   if(changed)
     {
      bool ok = RG_ModifySLTP(ticket, new_sl, new_tp, "auto SL/TP");
      if(!ok)
         return true; // retry next tick; do not close a live trade over a rejected snap
      if(!g_pos.SelectByTicket(ticket))
         return false;
      if(sl_past_max)
         RG_Notify(StringFormat("stop on #%s pulled closer to your max loss",
                                IntegerToString((long)ticket)));
     }
   return true;
  }

//+------------------------------------------------------------------+
double RG_MaxAllowedLotForRisk(const string symbol, const ENUM_ORDER_TYPE otype,
                               const double open_price, const double sl_distance)
  {
   double basis = RG_RiskBasis();
   double max_by_cap = InpMaxLot;
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   double lo = 0.0;
   double hi = max_by_cap;
   double best = 0.0;
   for(int i = 0; i < 32; i++)
     {
      double mid = RG_NormalizeVolume(symbol, (lo + hi) * 0.5);
      if(mid < vmin)
        {
         hi = MathMax(0.0, mid - step);
         continue;
        }
      double dist = sl_distance;
      double risk = 0.0;
      bool measured = (dist > 0.0 && RG_DistanceToMoney(symbol, mid, otype, open_price, dist, risk));
      if(!measured)
         risk = RG_ScaledMoneyPer001(InpMaxLossPer001, mid);

      bool ok = (mid <= InpMaxLot + 1e-8);
      if(InpMaxRiskPercentPerTrade > 0.0 && basis > 0.0)
        {
         double pct_cap = basis * InpMaxRiskPercentPerTrade / 100.0;
         if(risk > pct_cap + 1e-8)
            ok = false;
        }
      if(ok)
        {
         best = mid;
         lo = mid + step * 0.5;
        }
      else
         hi = mid - step * 0.5;
      if(hi <= lo)
         break;
     }
   return RG_NormalizeVolume(symbol, best);
  }

//+------------------------------------------------------------------+
void RG_EnforceMaxLot(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return;
   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   if(lots <= InpMaxLot + 1e-8)
      return;

   double cap = RG_NormalizeVolume(symbol, InpMaxLot);
   if(cap <= 0.0 || cap >= lots - 1e-8)
     {
      RG_ClosePositionTicket(ticket, StringFormat("lot %.2f over max %.2f — closed", lots, InpMaxLot));
      return;
     }
   if(!RG_ReducePositionTo(ticket, cap, StringFormat("lot %.2f over max %.2f", lots, InpMaxLot)))
      RG_ClosePositionTicket(ticket, StringFormat("lot %.2f over max %.2f — could not shrink, closed", lots, InpMaxLot));
  }

//+------------------------------------------------------------------+
void RG_EnforceSize(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return;

   // Lot cap does not need a stop. Waiting for SL was why a 0.09 could
   // sit under a 0.08 max — we put SL/TP on it and skipped size.
   RG_EnforceMaxLot(ticket);
   if(!g_pos.SelectByTicket(ticket))
      return;

   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   double open_price = g_pos.PriceOpen();
   ENUM_ORDER_TYPE otype = (g_pos.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ENUM_POSITION_TYPE ptype = g_pos.PositionType();

   double sl = g_pos.StopLoss();
   if(sl <= 0.0)
      return; // % risk still needs an SL; lot cap already ran

   double dist = MathAbs(open_price - sl);
   double risk = 0.0;
   if(!RG_DistanceToMoney(symbol, lots, otype, open_price, dist, risk))
     {
      RG_ClosePositionTicket(ticket, "cannot calculate risk — closed for safety");
      return;
     }

   double basis = RG_RiskBasis();
   double risk_pct = (basis > 0.0) ? (100.0 * risk / basis) : 999.0;

   bool over_lot = (lots > InpMaxLot + 1e-8);
   bool over_risk = (InpMaxRiskPercentPerTrade > 0.0 &&
                     risk_pct > InpMaxRiskPercentPerTrade + 1e-9);
   bool over_per001 = false;
   if(lots >= 0.01 - 1e-8)
     {
      double per001 = risk / (lots / 0.01);
      if(per001 > InpMaxLossPer001 + 1e-6)
         over_per001 = true;
     }

   if(over_per001)
     {
      // Distance problem, not a lot problem. Pull the stop as close as the
      // broker allows. If it still sits past 5/0.01 (min stop distance on
      // gold, freeze, requote), keep the trade and retry next tick — do not
      // close a scalp because the ceiling cannot be placed *this second*.
      double max_dist = RG_MaxSLDistance(symbol, lots, otype, open_price);
      if(max_dist > 0.0)
        {
         double snap = (ptype == POSITION_TYPE_BUY) ? (open_price - max_dist)
                                                    : (open_price + max_dist);
         snap = RG_ClampToStops(symbol, ptype, open_price, snap, true);
         double cur_dist = MathAbs(open_price - sl);
         double snap_dist = MathAbs(open_price - snap);
         if(snap_dist + RG_TickSize(symbol) * 0.5 < cur_dist)
           {
            double tp = g_pos.TakeProfit();
            if(RG_ModifySLTP(ticket, snap, tp, "snap SL to max loss/0.01"))
              {
               if(!g_pos.SelectByTicket(ticket))
                  return;
               RG_Notify(StringFormat("stop on #%s pulled closer to your max loss",
                                      IntegerToString((long)ticket)));
              }
            else
               RG_Log(2, StringFormat("could not tighten stop #%s this tick — retry",
                                      IntegerToString((long)ticket)));
           }
        }
      if(!g_pos.SelectByTicket(ticket))
         return;
      sl = g_pos.StopLoss();
      lots = g_pos.Volume();
      open_price = g_pos.PriceOpen();
      dist = MathAbs(open_price - sl);
      if(!RG_DistanceToMoney(symbol, lots, otype, open_price, dist, risk))
         return;
      risk_pct = (basis > 0.0) ? (100.0 * risk / basis) : 999.0;
      over_lot = (lots > InpMaxLot + 1e-8);
      over_risk = (InpMaxRiskPercentPerTrade > 0.0 &&
                   risk_pct > InpMaxRiskPercentPerTrade + 1e-9);
     }

   if(!over_lot && !over_risk)
      return;

   double allowed = RG_MaxAllowedLotForRisk(symbol, otype, open_price, dist);
   if(allowed > InpMaxLot)
      allowed = InpMaxLot;
   allowed = RG_NormalizeVolume(symbol, allowed);
   if(allowed <= 0.0 || allowed >= lots - 1e-8)
     {
      RG_ClosePositionTicket(ticket, "too big and cannot shrink to a safe lot — closed");
      return;
     }
   if(!RG_ReducePositionTo(ticket, allowed, StringFormat("too big — shrunk from %.2f", lots)))
      RG_ClosePositionTicket(ticket, "could not shrink the lot — closed the whole trade");
  }

//+------------------------------------------------------------------+
// If floating loss (or the quote) is already at/through the money stop,
// close now. Do NOT plant a stop behind the market — that is how a 5
// ceiling quietly became a 8–10 loss when the fill had no SL yet.
// 1.21 still applies when you are NOT through: keep the tightest legal
// stop and retry. This only fires once you have already used the 5.
//+------------------------------------------------------------------+
void RG_EnforceHardMoneyStop(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return;
   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   if(lots <= 0.0)
      return;
   double open_price = g_pos.PriceOpen();
   ENUM_POSITION_TYPE ptype = g_pos.PositionType();
   ENUM_ORDER_TYPE otype = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double max_loss = RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
   double pnl = g_pos.Profit() + g_pos.Swap();
   bool through = (pnl <= -max_loss);

   // Geometric backup when floating P/L has not caught up yet (fresh fill
   // into a gap). Skip when already green — the quote cannot be through.
   if(!through && pnl <= 0.0)
     {
      double sl_dist = RG_MaxSLDistance(symbol, lots, otype, open_price);
      if(sl_dist > 0.0)
        {
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         if(ptype == POSITION_TYPE_BUY)
            through = (bid > 0.0 && bid <= open_price - sl_dist);
         else
            through = (ask > 0.0 && ask >= open_price + sl_dist);
        }
     }

   if(through)
      RG_ClosePositionTicket(ticket, "already past your stop — closed");
  }

//+------------------------------------------------------------------+
void RG_CloseNewestOnSymbol(const string symbol, const int close_count, const string why)
  {
   if(close_count <= 0)
      return;
   ulong tickets[];
   datetime times[];
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(times, n + 1);
      tickets[n] = g_pos.Ticket();
      times[n] = g_pos.Time();
      n++;
     }
   for(int a = 0; a < n; a++)
      for(int b = a + 1; b < n; b++)
         if(times[b] > times[a])
           {
            datetime td = times[a]; times[a] = times[b]; times[b] = td;
            ulong tk = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tk;
           }
   int left = close_count;
   for(int k = 0; k < n && left > 0; k++)
     {
      // Do not skip to an older leg if the newest close fails — retry that
      // ticket next tick. Skipping would kill the original instead of the add.
      if(!RG_ClosePositionTicket(tickets[k], why))
         return;
      left--;
     }
  }

//+------------------------------------------------------------------+
void RG_CloseWrongDirectionOnSymbol(const string symbol, const string why)
  {
   datetime oldest_time = 0;
   ENUM_POSITION_TYPE keep = POSITION_TYPE_BUY;
   bool have = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      datetime t = g_pos.Time();
      if(!have || t < oldest_time)
        {
         have = true;
         oldest_time = t;
         keep = g_pos.PositionType();
        }
     }
   if(!have)
      return;

   ulong tickets[];
   datetime times[];
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(g_pos.PositionType() == keep)
         continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(times, n + 1);
      tickets[n] = g_pos.Ticket();
      times[n] = g_pos.Time();
      n++;
     }
   for(int a = 0; a < n; a++)
      for(int b = a + 1; b < n; b++)
         if(times[b] > times[a])
           {
            datetime td = times[a]; times[a] = times[b]; times[b] = td;
            ulong tk = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tk;
           }
   for(int k = 0; k < n; k++)
     {
      if(!RG_ClosePositionTicket(tickets[k], why))
         return;
     }
  }

//+------------------------------------------------------------------+
void RG_EnforcePositionCaps()
  {
   string symbols[];
   RG_CollectManagedSymbols(symbols);
   int ns = ArraySize(symbols);

   for(int s = 0; s < ns; s++)
     {
      string symbol = symbols[s];

      if(g_dayLocked && g_lockTime > 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(!RG_SelectManagedByIndex(i))
               continue;
            if(g_pos.Symbol() != symbol)
               continue;
            datetime opened = g_pos.Time();
            if(opened >= g_lockTime)
               RG_ClosePositionTicket(g_pos.Ticket(), "day is locked — new trade closed");
           }
        }

      if(RG_IsCooldownActive() && g_cooldownStarted > 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            if(!RG_SelectManagedByIndex(i))
               continue;
            if(g_pos.Symbol() != symbol)
               continue;
            datetime opened = g_pos.Time();
            if(opened >= g_cooldownStarted)
               RG_ClosePositionTicket(g_pos.Ticket(), "revenge pause — new trade closed");
           }
        }

      int total = RG_CountManaged(symbol);
      if(total >= 2)
        {
         int buys = RG_CountManagedDirection(symbol, POSITION_TYPE_BUY);
         int sells = RG_CountManagedDirection(symbol, POSITION_TYPE_SELL);
         if(buys > 0 && sells > 0)
           {
            // Keep the oldest leg's direction. Closing "newest extra" without
            // looking at side could kill a same-direction add and leave the
            // hedge sitting for another tick.
            RG_CloseWrongDirectionOnSymbol(symbol, "buy+sell mix not allowed — extra trade closed");
            total = RG_CountManaged(symbol);
           }
        }

      int allowed = RG_AllowedMaxPositions(symbol);
      total = RG_CountManaged(symbol);
      if(total > allowed)
         RG_CloseNewestOnSymbol(symbol, total - allowed,
                                StringFormat("too many trades (max %d) — extra closed", allowed));
     }
  }

//+------------------------------------------------------------------+
bool RG_PendingWouldBeIllegal(const string symbol, const double volume,
                              const long order_type, string &why)
  {
   why = "";
   if(volume > InpMaxLot + 1e-8)
     {
      why = StringFormat("pending lot %.2f is over your max %.2f", volume, InpMaxLot);
      return true;
     }

   bool pending_buy = (order_type == ORDER_TYPE_BUY_LIMIT ||
                       order_type == ORDER_TYPE_BUY_STOP ||
                       order_type == ORDER_TYPE_BUY_STOP_LIMIT);
   int buys = RG_CountManagedDirection(symbol, POSITION_TYPE_BUY);
   int sells = RG_CountManagedDirection(symbol, POSITION_TYPE_SELL);
   if(pending_buy && sells > 0)
     {
      why = "pending is the other direction — mix not allowed";
      return true;
     }
   if(!pending_buy && buys > 0)
     {
      why = "pending is the other direction — mix not allowed";
      return true;
     }

   if(InpMaxRiskPercentPerTrade > 0.0)
     {
      double basis = RG_RiskBasis();
      if(basis > 0.0)
        {
         double worst = RG_ScaledMoneyPer001(InpMaxLossPer001, volume);
         if(100.0 * worst / basis > InpMaxRiskPercentPerTrade + 1e-9)
           {
            why = "pending would risk more than one trade is allowed to";
            return true;
           }
        }
     }

   if(g_dayLocked)
     {
      why = "the day is locked";
      return true;
     }
   if(RG_IsCooldownActive())
     {
      why = "revenge pause after a loss";
      return true;
     }
   if(RG_IsNoTradeHoursActive())
     {
      why = "no-trade hours";
      return true;
     }

   int positions = RG_CountManaged(symbol);
   int allowed = RG_AllowedMaxPositions(symbol);
   if(positions >= allowed)
     {
      why = "you already have as many trades as allowed";
      return true;
     }

   if(positions >= 1)
     {
      string reason;
      if(!RG_AveragingPrivilegeOK(symbol, reason, false))
        {
         why = "adding to losers not allowed — " + reason;
         return true;
        }
      if(volume > InpAveragingMaxLot + 1e-8)
        {
         why = StringFormat("pending lot %.2f is bigger than add-on max %.2f", volume, InpAveragingMaxLot);
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
void RG_EnforcePendings()
  {
   if(g_dayLocked)
     {
      RG_DeleteManagedPendings("", "the day is locked");
      return;
     }
   if(RG_IsCooldownActive())
     {
      RG_DeleteManagedPendings("", "revenge pause after a loss");
      return;
     }
   if(RG_IsNoTradeHoursActive())
     {
      RG_DeleteManagedPendings("", "no-trade hours");
      return;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!RG_IsPendingType(OrderGetInteger(ORDER_TYPE)))
         continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(!RG_SymbolAllowed(symbol) || !RG_MagicAllowed(magic))
         continue;

      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      long otype = OrderGetInteger(ORDER_TYPE);
      string why;
      if(RG_PendingWouldBeIllegal(symbol, volume, otype, why))
         RG_DeletePending(ticket, why);
     }

   // Remaining pendings vs leftover slots (oldest kept, extras deleted)
   string symbols[];
   RG_CollectManagedSymbols(symbols);
   for(int s = 0; s < ArraySize(symbols); s++)
     {
      string symbol = symbols[s];
      int positions = RG_CountManaged(symbol);
      int allowed = RG_AllowedMaxPositions(symbol);
      int slots = allowed - positions;
      if(slots < 0)
         slots = 0;

      ulong tickets[];
      datetime times[];
      int n = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(!RG_IsPendingType(OrderGetInteger(ORDER_TYPE)))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != symbol)
            continue;
         if(!RG_MagicAllowed(OrderGetInteger(ORDER_MAGIC)))
            continue;
         ArrayResize(tickets, n + 1);
         ArrayResize(times, n + 1);
         tickets[n] = ticket;
         times[n] = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
         n++;
        }
      if(n <= slots)
         continue;
      // newest extras first
      for(int a = 0; a < n; a++)
         for(int b = a + 1; b < n; b++)
            if(times[b] > times[a])
              {
               datetime td = times[a]; times[a] = times[b]; times[b] = td;
               ulong tk = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tk;
              }
      int extra = n - slots;
      for(int k = 0; k < extra; k++)
         RG_DeletePending(tickets[k], "too many pending orders for the free slots left");
     }
  }

//+------------------------------------------------------------------+
void RG_EnforceTotalRisk()
  {
   if(InpMaxTotalRiskPercent <= 0.0)
      return;
   double basis = RG_RiskBasis();
   if(basis <= 0.0)
      return;
   double total = RG_TotalOpenRiskMoney();
   double pct = 100.0 * total / basis;
   if(pct <= InpMaxTotalRiskPercent + 1e-9)
      return;

   RG_Notify(StringFormat("all trades together risk %.2f%% (max %.2f%%) — closing the biggest risk first",
                          pct, InpMaxTotalRiskPercent));

   ulong tickets[];
   double risks[];
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(risks, n + 1);
      tickets[n] = g_pos.Ticket();
      risks[n] = RG_PositionRiskMoney(g_pos.Ticket());
      n++;
     }
   for(int a = 0; a < n; a++)
      for(int b = a + 1; b < n; b++)
         if(risks[b] > risks[a])
           {
            double rd = risks[a]; risks[a] = risks[b]; risks[b] = rd;
            ulong tk = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tk;
           }

   for(int k = 0; k < n; k++)
     {
      double basis2 = RG_RiskBasis();
      double pct2 = (basis2 > 0.0) ? (100.0 * RG_TotalOpenRiskMoney() / basis2) : 0.0;
      if(pct2 <= InpMaxTotalRiskPercent + 1e-9)
         break;
      RG_ClosePositionTicket(tickets[k], "combined risk too high — closed the biggest one");
     }
  }

//+------------------------------------------------------------------+
void RG_EnforceBasketExit(const string symbol)
  {
   int n = RG_CountManaged(symbol);
   if(n < 2)
      return;
   double net = RG_BasketNetProfit(symbol);
   double target = RG_BasketExitTarget(symbol);
   if(net + 1e-8 >= target)
      RG_FlattenSymbol(symbol, StringFormat("all trades together in profit (%.2f ≥ %.2f) — closed all", net, target));
  }

//+------------------------------------------------------------------+
void RG_EnforceTimeGuard()
  {
   if(!RG_PolicyTimeOn())
      return;
   datetime now = TimeTradeServer();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      string symbol = g_pos.Symbol();
      datetime opened = g_pos.Time();
      double net = RG_PositionNetAfterCosts();
      ulong ticket = g_pos.Ticket();
      int basket = RG_CountManaged(symbol);
      if(basket >= 2)
         continue;

      int age = (int)(now - opened);

      if(net >= InpTimeGuardExemptProfit)
         continue;

      if(InpMaxHoldSeconds > 0 && age >= InpMaxHoldSeconds)
        {
         RG_ClosePositionTicket(ticket, StringFormat("held too long (%d seconds)", InpMaxHoldSeconds));
         continue;
        }
      if(InpMustBeGreenSeconds > 0 && age >= InpMustBeGreenSeconds && net <= 0.0)
        {
         RG_ClosePositionTicket(ticket, StringFormat("still not in profit after %d seconds (after costs)", InpMustBeGreenSeconds));
         continue;
        }
     }
  }

//+------------------------------------------------------------------+
void RG_EnforceNakedSL()
  {
   datetime now = TimeTradeServer();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.StopLoss() > 0.0)
         continue;
      datetime opened = g_pos.Time();
      int age = (int)(now - opened);
      ulong ticket = g_pos.Ticket();
      RG_ApplyAutoSLTP(ticket);
      if(!g_pos.SelectByTicket(ticket))
         continue;
      if(g_pos.StopLoss() > 0.0)
         continue;
      if(age >= RG_NAKED_SL_TIMEOUT_SEC)
         RG_ClosePositionTicket(ticket, "no stop loss could be set — closed");
     }
  }

//+------------------------------------------------------------------+
void RG_UpdateDayState()
  {
   int stamp = RG_DayStampNow();
   if(stamp != g_dayStamp)
     {
      g_dayStamp = stamp;
      g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dayClosedTrades = 0;
      g_lockTime = 0;
      if(g_dayLocked)
        {
         g_dayLocked = false;
         RG_Notify("new day — trading unlocked");
        }
      RG_StateSave();
     }

   if(!RG_PolicyDayOn())
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = equity;

   double day_pnl = equity - g_dayStartEquity;
   double day_loss_pct = 0.0;
   if(g_dayStartEquity > 0.0 && day_pnl < 0.0)
      day_loss_pct = 100.0 * (-day_pnl) / g_dayStartEquity;

   bool lock = false;
   string why = "";
   if(InpMaxDayLossPercent > 0.0 && day_loss_pct >= InpMaxDayLossPercent)
     {
      lock = true;
      why = StringFormat("day loss %.2f%%", day_loss_pct);
     }
   if(InpMaxDayTrades > 0 && g_dayClosedTrades >= InpMaxDayTrades)
     {
      lock = true;
      why = StringFormat("day trades %d", g_dayClosedTrades);
     }

   if(lock && !g_dayLocked)
     {
      g_dayLocked = true;
      g_lockTime = TimeTradeServer();
      g_lastStatusReason = "DAY LOCKED: " + why;
      RG_Notify("DAY LOCKED — " + why);
      RG_StateSave();
     }
  }

//+------------------------------------------------------------------+
void RG_OnDealClosedLoss(const double deal_profit)
  {
   if(deal_profit < 0.0 && InpCooldownAfterLossSec > 0)
     {
      g_cooldownStarted = TimeTradeServer();
      g_cooldownUntil = g_cooldownStarted + InpCooldownAfterLossSec;
     }
   g_dayClosedTrades++;
   RG_StateSave();
  }

//+------------------------------------------------------------------+
bool RG_PositionStillOpen(const ulong position_id)
  {
   if(position_id == 0)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i))
         continue;
      if((ulong)g_pos.Identifier() == position_id || g_pos.Ticket() == position_id)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
bool RG_HistoryDealSelectRetry(const ulong deal)
  {
   if(deal == 0)
      return false;
   if(HistoryDealSelect(deal))
      return true;
   datetime now = TimeTradeServer();
   HistorySelect(now - 180, now + 30);
   return HistoryDealSelect(deal);
  }

//+------------------------------------------------------------------+
void RG_ProcessClosedDeal(const ulong deal)
  {
   if(RG_DealAlreadySeen(deal))
      return;
   if(!RG_HistoryDealSelectRetry(deal))
      return;

   long deal_type = HistoryDealGetInteger(deal, DEAL_TYPE);
   if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
     {
      RG_MarkDealSeen(deal);
      return;
     }

   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT)
     {
      RG_MarkDealSeen(deal);
      return;
     }

   string symbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
   if(!RG_SymbolAllowed(symbol) || !RG_MagicAllowed(magic))
     {
      RG_MarkDealSeen(deal);
      return;
     }

   datetime deal_time = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   if(g_eaStartTime > 0 && deal_time + 2 < g_eaStartTime)
     {
      RG_MarkDealSeen(deal);
      return;
     }

   ulong pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(entry != DEAL_ENTRY_INOUT && RG_PositionStillOpen(pos_id))
     {
      // On DEAL_ADD the position list can still show a ticket that just
      // fully closed. Marking it seen here ate full losses as "partials"
      // and never started the revenge pause. Wait until it has settled:
      // still open after 2s → real partial; gone on harvest → full close.
      if((int)(TimeTradeServer() - deal_time) < 2)
         return;
      RG_MarkDealSeen(deal);
      return;
     }

   RG_MarkDealSeen(deal);
   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(deal, DEAL_SWAP)
                   + HistoryDealGetDouble(deal, DEAL_COMMISSION);
   RG_OnDealClosedLoss(profit);
   RG_UpdateDayState();
  }

//+------------------------------------------------------------------+
void RG_HarvestClosedDeals()
  {
   datetime now = TimeTradeServer();
   datetime from = now - 180;
   if(g_eaStartTime > from)
      from = g_eaStartTime;
   if(from <= 0)
      from = now - 180;
   if(!HistorySelect(from, now + 5))
      return;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      RG_ProcessClosedDeal(deal);
     }
  }

//+------------------------------------------------------------------+
void RG_RefreshStatusReason()
  {
   if(!InpEnableGuard)
     {
      g_lastStatusReason = "protection OFF (panel only)";
      return;
     }
   if(!g_tradingOk)
     {
      g_lastStatusReason = "CANNOT TRADE: " + g_tradingBlockReason;
      return;
     }
   if(g_dayLocked)
     {
      g_lastStatusReason = "day locked — no new risk";
      return;
     }
   if(RG_IsNoTradeHoursActive())
     {
      string slot = RG_NoTradeActiveSlotLabel();
      g_lastStatusReason = (StringLen(slot) > 0)
                           ? ("no-trade hours " + slot)
                           : "no-trade hours";
      return;
     }
   if(RG_IsCooldownActive())
     {
      g_lastStatusReason = "revenge pause after a loss";
      return;
     }
   string r;
   bool avg = RG_AveragingPrivilegeOK(_Symbol, r, false);
   g_lastStatusReason = avg ? "protecting · adding to losers OK"
                            : ("protecting · no adds: " + r);
  }

//+------------------------------------------------------------------+
void RG_GuardianSweep()
  {
   RG_UpdateDayState();
   RG_HarvestClosedDeals();
   RG_RefreshTradingStatus();

   if(!InpEnableGuard)
     {
      RG_RefreshStatusReason();
      return;
     }

   if(!g_tradingOk)
     {
      RG_RefreshStatusReason();
      return;
     }

   // 1. Pendings — the only pre-fill prevention we have
   RG_EnforcePendings();

   // 2. Day lock flatten until actually flat (if a close fails, fall through
   //    and still put SL/size on whatever remains)
   if(g_dayLocked)
     {
      bool flat = RG_FlattenAllManaged("day locked — closing everything");
      RG_DeleteManagedPendings("", "the day is locked");
      if(flat && RG_CountManaged() == 0)
        {
         RG_RefreshStatusReason();
         return;
        }
     }

   // 2b. No-trade hours — same flatten-until-flat as day lock, time-boxed
   if(RG_IsNoTradeHoursActive())
     {
      if(!g_noTradeWasActive)
        {
         string slot = RG_NoTradeActiveSlotLabel();
         RG_Notify((StringLen(slot) > 0)
                   ? ("NO-TRADE HOURS — closing everything (" + slot + ")")
                   : "NO-TRADE HOURS — closing everything");
        }
      g_noTradeWasActive = true;
      bool flat = RG_FlattenAllManaged("no-trade hours — trade closed");
      RG_DeleteManagedPendings("", "no-trade hours");
      if(flat && RG_CountManaged() == 0)
        {
         RG_RefreshStatusReason();
         return;
        }
     }
   else
      g_noTradeWasActive = false;

   // 3. Caps / cooldown-new / hedge / illegal adds — continuous
   RG_EnforcePositionCaps();

   // 4. Per position: already-through-stop first (never plant a stop
   //    behind the market), then lot cap (no stop needed), then SL/TP,
   //    then % risk vs the SL that actually landed.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      ulong ticket = g_pos.Ticket();
      RG_EnforceHardMoneyStop(ticket);
      if(!g_pos.SelectByTicket(ticket))
         continue;
      RG_EnforceMaxLot(ticket);
      if(!g_pos.SelectByTicket(ticket))
         continue;
      if(!RG_ApplyAutoSLTP(ticket))
         continue;
      if(!g_pos.SelectByTicket(ticket))
         continue;
      RG_EnforceSize(ticket);
     }

   RG_EnforceNakedSL();
   RG_EnforceTimeGuard();
   RG_EnforceTotalRisk();

   string symbols[];
   RG_CollectManagedSymbols(symbols);
   for(int s = 0; s < ArraySize(symbols); s++)
      RG_EnforceBasketExit(symbols[s]);

   RG_RefreshStatusReason();
  }

#endif // RISKGUARD_ENFORCE_MQH
