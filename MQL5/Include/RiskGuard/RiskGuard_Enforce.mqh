//+------------------------------------------------------------------+
//|                                          RiskGuard_Enforce.mqh |
//+------------------------------------------------------------------+
#ifndef RISKGUARD_ENFORCE_MQH
#define RISKGUARD_ENFORCE_MQH

#include "RiskGuard_Utils.mqh"

//+------------------------------------------------------------------+
bool RG_IsCooldownActive()
  {
   return (InpCooldownAfterLossSec > 0 && TimeTradeServer() < g_cooldownUntil);
  }

//+------------------------------------------------------------------+
bool RG_AveragingPrivilegeOK(const string symbol, string &reason)
  {
   reason = "";
   if(!InpAveragingEnabled)
     {
      reason = "averaging disabled";
      return false;
     }
   if(!RG_IsHedgingAccount())
     {
      reason = "netting account (hedging required for multi-leg)";
      return false;
     }
   if(g_dayLocked)
     {
      reason = "day locked";
      return false;
     }
   if(RG_IsCooldownActive())
     {
      reason = "cooldown active";
      return false;
     }

   // all legs must be ≤ averaging max lot
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(g_pos.Volume() > InpAveragingMaxLot + 1e-8)
        {
         reason = StringFormat("leg lot %.2f > avg max %.2f", g_pos.Volume(), InpAveragingMaxLot);
         return false;
        }
     }

   double basis = RG_RiskBasis();
   if(basis <= 0.0)
     {
      reason = "invalid equity/balance";
      return false;
     }
   double risk_pct = 100.0 * RG_TotalOpenRiskMoney(symbol) / basis;
   if(risk_pct > InpAveragingMaxRiskPercent + 1e-9)
     {
      reason = StringFormat("open risk %.2f%% > avg max %.2f%%", risk_pct, InpAveragingMaxRiskPercent);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
int RG_AllowedMaxPositions(const string symbol)
  {
   if(g_dayLocked || RG_IsCooldownActive())
      return 0;

   string reason;
   bool avg_ok = RG_AveragingPrivilegeOK(symbol, reason);
   int soft = InpMaxOpenPositions;
   if(avg_ok)
      soft = 1 + InpAveragingMaxAdds;
   int hard = InpHardMaxOpenPositions;
   if(hard < 1)
      hard = 1;
   return (int)MathMin(soft, hard);
  }

//+------------------------------------------------------------------+
bool RG_ClosePositionTicket(const ulong ticket, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   string symbol = g_pos.Symbol();
   g_trade.SetExpertMagicNumber(g_pos.Magic());
   bool ok = g_trade.PositionClose(ticket, InpMaxSlippagePoints);
   if(ok)
      RG_Notify(StringFormat("closed #%s (%s) — %s", IntegerToString((long)ticket), symbol, why));
   else
      RG_Log(0, StringFormat("close FAILED #%s retcode=%d %s", IntegerToString((long)ticket), g_trade.ResultRetcode(), why));
   return ok;
  }

//+------------------------------------------------------------------+
bool RG_ReducePositionTo(const ulong ticket, const double target_lots, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   double cur = g_pos.Volume();
   double tgt = RG_NormalizeVolume(g_pos.Symbol(), target_lots);
   if(tgt <= 0.0)
      return RG_ClosePositionTicket(ticket, why + " (reduce->close)");
   if(tgt >= cur - 1e-8)
      return true;
   double close_vol = RG_NormalizeVolume(g_pos.Symbol(), cur - tgt);
   if(close_vol <= 0.0)
      return false;
   g_trade.SetExpertMagicNumber(g_pos.Magic());
   bool ok = g_trade.PositionClosePartial(ticket, close_vol, InpMaxSlippagePoints);
   if(ok)
      RG_Notify(StringFormat("reduced #%s to %.2f — %s", IntegerToString((long)ticket), tgt, why));
   else
      RG_Log(0, StringFormat("partial close FAILED #%s retcode=%d", IntegerToString((long)ticket), g_trade.ResultRetcode()));
   return ok;
  }

//+------------------------------------------------------------------+
bool RG_FlattenSymbol(const string symbol, const string why)
  {
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.Symbol() != symbol)
         continue;
      if(RG_ClosePositionTicket(g_pos.Ticket(), why))
         any = true;
     }
   return any;
  }

//+------------------------------------------------------------------+
bool RG_FlattenAllManaged(const string why)
  {
   bool any = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(RG_ClosePositionTicket(g_pos.Ticket(), why))
         any = true;
     }
   return any;
  }

//+------------------------------------------------------------------+
double RG_DesiredSLDistance(const string symbol, const double lots,
                            const ENUM_ORDER_TYPE otype, const double open_price)
  {
   if(InpSLMode == RG_SL_POINTS)
      return InpSL_Points * RG_Point(symbol);

   double money = RG_ScaledMoneyPer001(InpSL_MoneyPer001, lots);
   // also respect preferred vs max: auto uses preferred (InpSL_MoneyPer001),
   // widen block uses max separately
   double dist = 0.0;
   if(!RG_MoneyToDistance(symbol, lots, otype, open_price, money, dist))
      return InpSL_Points * RG_Point(symbol);
   return dist;
  }

//+------------------------------------------------------------------+
double RG_MaxSLDistance(const string symbol, const double lots,
                        const ENUM_ORDER_TYPE otype, const double open_price)
  {
   if(InpSLMode == RG_SL_POINTS)
     {
      // max risk distance from money ceiling converted, take max of points mode money cap
      double money = RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
      double dist_money = 0.0;
      if(RG_MoneyToDistance(symbol, lots, otype, open_price, money, dist_money))
         return dist_money;
      return InpSL_Points * RG_Point(symbol);
     }
   double money = RG_ScaledMoneyPer001(InpMaxLossPer001, lots);
   double dist = 0.0;
   if(!RG_MoneyToDistance(symbol, lots, otype, open_price, money, dist))
      return InpSL_Points * RG_Point(symbol);
   return dist;
  }

//+------------------------------------------------------------------+
double RG_DesiredTPDistance(const string symbol, const double lots,
                            const ENUM_ORDER_TYPE otype, const double open_price,
                            const double sl_distance)
  {
   if(InpTPMode == RG_TP_POINTS)
      return InpTP_Points * RG_Point(symbol);
   if(InpTPMode == RG_TP_R_MULTIPLE)
      return MathMax(sl_distance, RG_Point(symbol)) * InpTP_RMultiple;

   double money = RG_ScaledMoneyPer001(InpTP_MoneyPer001, lots);
   double dist = 0.0;
   if(!RG_MoneyToProfitDistance(symbol, lots, otype, open_price, money, dist))
      return InpTP_Points * RG_Point(symbol);
   return dist;
  }

//+------------------------------------------------------------------+
bool RG_ModifySLTP(const ulong ticket, double sl, double tp, const string why)
  {
   if(!g_pos.SelectByTicket(ticket))
      return false;
   string symbol = g_pos.Symbol();
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   sl = (sl > 0.0) ? NormalizeDouble(sl, digits) : 0.0;
   tp = (tp > 0.0) ? NormalizeDouble(tp, digits) : 0.0;

   for(int attempt = 0; attempt < MathMax(1, InpModifyRetries); attempt++)
     {
      g_trade.SetExpertMagicNumber(g_pos.Magic());
      if(g_trade.PositionModify(ticket, sl, tp))
        {
         RG_Log(1, StringFormat("modified #%s SL=%.5f TP=%.5f — %s", IntegerToString((long)ticket), sl, tp, why));
         return true;
        }
      Sleep(InpRetryPauseMs);
      g_pos.SelectByTicket(ticket);
     }
   RG_Log(0, StringFormat("modify FAILED #%s retcode=%d — %s", IntegerToString((long)ticket), g_trade.ResultRetcode(), why));
   return false;
  }

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

   double sl_dist = RG_DesiredSLDistance(symbol, lots, otype, open_price);
   double max_sl_dist = RG_MaxSLDistance(symbol, lots, otype, open_price);
   double tp_dist = RG_DesiredTPDistance(symbol, lots, otype, open_price, sl_dist);

   double new_sl = cur_sl;
   double new_tp = cur_tp;
   bool changed = false;

   // --- SL ---
   if(InpForceSL)
     {
      double target_sl = (ptype == POSITION_TYPE_BUY) ? (open_price - sl_dist)
                                                      : (open_price + sl_dist);
      target_sl = RG_ClampToStops(symbol, ptype, open_price, target_sl, true);

      if(cur_sl <= 0.0)
        {
         new_sl = target_sl;
         changed = true;
        }
      else
        {
         double cur_dist = MathAbs(open_price - cur_sl);
         // widen block: if farther than max allowed risk distance, snap back
         if(InpBlockWidenSL && cur_dist > max_sl_dist + RG_Point(symbol) * 0.5)
           {
            double snap = (ptype == POSITION_TYPE_BUY) ? (open_price - max_sl_dist)
                                                       : (open_price + max_sl_dist);
            new_sl = RG_ClampToStops(symbol, ptype, open_price, snap, true);
            changed = true;
            RG_Notify(StringFormat("SL widen blocked #%s — snapped to max risk", IntegerToString((long)ticket)));
           }
        }
     }
   else if(InpBlockRemoveSL && cur_sl <= 0.0)
     {
      // still force a protective SL even if ForceSL false? BlockRemove implies we set one
      double target_sl = (ptype == POSITION_TYPE_BUY) ? (open_price - sl_dist)
                                                      : (open_price + sl_dist);
      new_sl = RG_ClampToStops(symbol, ptype, open_price, target_sl, true);
      changed = true;
     }

   // --- TP ---
   if(in_basket && InpDisableTPInBasket)
     {
      if(cur_tp > 0.0)
        {
         new_tp = 0.0;
         changed = true;
        }
     }
   else if(InpForceTP)
     {
      double target_tp = (ptype == POSITION_TYPE_BUY) ? (open_price + tp_dist)
                                                      : (open_price - tp_dist);
      target_tp = RG_ClampToStops(symbol, ptype, open_price, target_tp, false);
      if(cur_tp <= 0.0)
        {
         new_tp = target_tp;
         changed = true;
        }
     }

   if(!changed)
      return true;

   bool ok = RG_ModifySLTP(ticket, new_sl, new_tp, "auto SL/TP");
   if(!ok && InpCloseIfSLModifyFails && (new_sl > 0.0) && (cur_sl <= 0.0 || InpBlockWidenSL))
     {
      RG_ClosePositionTicket(ticket, "SL modify failed — safety close");
      return false;
     }
   return ok;
  }

//+------------------------------------------------------------------+
double RG_MaxAllowedLotForRisk(const string symbol, const ENUM_ORDER_TYPE otype,
                               const double open_price, const double sl_distance_hint)
  {
   double basis = RG_RiskBasis();
   double max_by_cap = InpMaxLot;
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   // binary search lot such that risk money <= min(maxlossper001 scale, %cap)
   double lo = 0.0;
   double hi = max_by_cap;
   double best = 0.0;
   for(int i = 0; i < 32; i++)
     {
      double mid = RG_NormalizeVolume(symbol, (lo + hi) * 0.5);
      if(mid < vmin)
        {
         hi = mid;
         continue;
        }
      double dist = sl_distance_hint;
      if(dist <= 0.0)
         dist = RG_DesiredSLDistance(symbol, mid, otype, open_price);
      double risk = 0.0;
      if(!RG_DistanceToMoney(symbol, mid, otype, open_price, dist, risk))
         risk = RG_ScaledMoneyPer001(InpMaxLossPer001, mid);

      double max_risk_money = RG_ScaledMoneyPer001(InpMaxLossPer001, mid);
      // percent cap for this trade
      double pct_cap = basis * InpMaxRiskPercentPerTrade / 100.0;
      // lot is OK if risk at its SL <= pct_cap AND risk-per-001 ceiling respected
      // For ceiling: risk should be <= Scaled(MaxLossPer001)
      bool ok = (risk <= pct_cap + 1e-8) && (risk <= max_risk_money + 1e-6) && (mid <= InpMaxLot + 1e-8);
      // Actually MaxLossPer001 scales with lot so risk≈scaled always if SL set to that — percent and MaxLot matter most
      ok = (mid <= InpMaxLot + 1e-8) && (risk <= pct_cap + 1e-8);
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
void RG_EnforceSize(const ulong ticket)
  {
   if(!g_pos.SelectByTicket(ticket))
      return;
   string symbol = g_pos.Symbol();
   double lots = g_pos.Volume();
   double open_price = g_pos.PriceOpen();
   ENUM_ORDER_TYPE otype = (g_pos.PositionType() == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double sl = g_pos.StopLoss();
   double dist = (sl > 0.0) ? MathAbs(open_price - sl)
                            : RG_DesiredSLDistance(symbol, lots, otype, open_price);
   double risk = 0.0;
   RG_DistanceToMoney(symbol, lots, otype, open_price, dist, risk);
   double basis = RG_RiskBasis();
   double risk_pct = (basis > 0.0) ? (100.0 * risk / basis) : 999.0;

   bool over_lot = (lots > InpMaxLot + 1e-8);
   bool over_risk = (risk_pct > InpMaxRiskPercentPerTrade + 1e-9);
   bool over_per001 = false;
   if(lots >= 0.01 - 1e-8)
     {
      double per001 = risk / (lots / 0.01);
      if(per001 > InpMaxLossPer001 + 1e-6)
         over_per001 = true;
     }

   if(!over_lot && !over_risk && !over_per001)
      return;

   if(InpOnOversize == RG_OVERSIZE_CLOSE)
     {
      RG_ClosePositionTicket(ticket, StringFormat("oversize/risk (lot=%.2f risk%%=%.2f)", lots, risk_pct));
      return;
     }

   double allowed = RG_MaxAllowedLotForRisk(symbol, otype, open_price, dist);
   // also clamp by MaxLot and by MaxLossPer001 at current dist
   if(allowed > InpMaxLot)
      allowed = InpMaxLot;
   allowed = RG_NormalizeVolume(symbol, allowed);
   if(allowed <= 0.0 || allowed >= lots - 1e-8)
     {
      // cannot reduce enough — close
      RG_ClosePositionTicket(ticket, "oversize — cannot reduce to safe lot");
      return;
     }
   RG_ReducePositionTo(ticket, allowed, StringFormat("oversize/risk reduce (was %.2f)", lots));
  }

//+------------------------------------------------------------------+
void RG_EnforcePositionCount(const ulong new_ticket)
  {
   if(!g_pos.SelectByTicket(new_ticket))
      return;
   string symbol = g_pos.Symbol();

   int total = RG_CountManaged(symbol);
   int allowed = RG_AllowedMaxPositions(symbol);

   if(g_dayLocked)
     {
      RG_ClosePositionTicket(new_ticket, "day lock — new trade rejected");
      return;
     }
   if(RG_IsCooldownActive())
     {
      RG_ClosePositionTicket(new_ticket, "cooldown — new trade rejected");
      return;
     }

   // Reject hedges when same-direction averaging is required
   if(InpAveragingSameDirection && total >= 2)
     {
      int buys = RG_CountManagedDirection(symbol, POSITION_TYPE_BUY);
      int sells = RG_CountManagedDirection(symbol, POSITION_TYPE_SELL);
      if(buys > 0 && sells > 0)
        {
         if(InpOnIllegalAdd == RG_ILLEGAL_FLATTEN)
            RG_FlattenSymbol(symbol, "hedge not allowed — flatten");
         else
            RG_ClosePositionTicket(new_ticket, "hedge not allowed — closed add");
         return;
        }
     }

   if(total <= allowed)
     {
      if(total >= 2)
        {
         string reason;
         if(!RG_AveragingPrivilegeOK(symbol, reason))
           {
            if(InpOnIllegalAdd == RG_ILLEGAL_FLATTEN)
               RG_FlattenSymbol(symbol, "illegal average — flatten (" + reason + ")");
            else
               RG_ClosePositionTicket(new_ticket, "illegal average — " + reason);
           }
        }
      return;
     }

   string reason;
   bool avg = RG_AveragingPrivilegeOK(symbol, reason);
   if(!avg || total > allowed)
     {
      if(InpOnIllegalAdd == RG_ILLEGAL_FLATTEN)
         RG_FlattenSymbol(symbol, "position cap — flatten");
      else
         RG_ClosePositionTicket(new_ticket, StringFormat("position cap %d exceeded", allowed));
     }
  }

//+------------------------------------------------------------------+
void RG_EnforceTotalRisk()
  {
   double basis = RG_RiskBasis();
   if(basis <= 0.0)
      return;
   double total = RG_TotalOpenRiskMoney();
   double pct = 100.0 * total / basis;
   if(pct <= InpMaxTotalRiskPercent + 1e-9)
      return;

   // close newest managed positions until under cap
   RG_Notify(StringFormat("total risk %.2f%% > max %.2f%% — trimming", pct, InpMaxTotalRiskPercent));

   // gather tickets with open time
   ulong tickets[];
   datetime times[];
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      ArrayResize(tickets, n + 1);
      ArrayResize(times, n + 1);
      tickets[n] = g_pos.Ticket();
      times[n] = (datetime)PositionGetInteger(POSITION_TIME);
      n++;
     }
   // sort newest first (simple selection)
   for(int a = 0; a < n; a++)
      for(int b = a + 1; b < n; b++)
         if(times[b] > times[a])
           {
            datetime td = times[a]; times[a] = times[b]; times[b] = td;
            ulong tk = tickets[a]; tickets[a] = tickets[b]; tickets[b] = tk;
           }

   for(int k = 0; k < n; k++)
     {
      double basis2 = RG_RiskBasis();
      double pct2 = (basis2 > 0.0) ? (100.0 * RG_TotalOpenRiskMoney() / basis2) : 0.0;
      if(pct2 <= InpMaxTotalRiskPercent + 1e-9)
         break;
      RG_ClosePositionTicket(tickets[k], "total risk trim");
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
      RG_FlattenSymbol(symbol, StringFormat("basket BE+ exit net=%.2f target=%.2f", net, target));
  }

//+------------------------------------------------------------------+
void RG_EnforceTimeGuard()
  {
   if(!InpTimeGuardEnabled)
      return;
   datetime now = TimeTradeServer();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      string symbol = g_pos.Symbol();
      int basket = RG_CountManaged(symbol);
      if(InpTimeGuardSkipBasket && basket >= 2)
         continue;

      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int age = (int)(now - opened);
      double profit = g_pos.Profit() + g_pos.Swap();
      ulong ticket = g_pos.Ticket();

      if(profit >= InpTimeGuardExemptProfit)
         continue;

      if(InpMaxHoldSeconds > 0 && age >= InpMaxHoldSeconds)
        {
         RG_ClosePositionTicket(ticket, StringFormat("max hold %ds", InpMaxHoldSeconds));
         continue;
        }
      if(InpMustBeGreenSeconds > 0 && age >= InpMustBeGreenSeconds && profit <= 0.0)
        {
         RG_ClosePositionTicket(ticket, StringFormat("not green after %ds", InpMustBeGreenSeconds));
         continue;
        }
     }
  }

//+------------------------------------------------------------------+
void RG_EnforceNakedSL()
  {
   if(!InpBlockRemoveSL && !InpForceSL)
      return;
   datetime now = TimeTradeServer();
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      if(g_pos.StopLoss() > 0.0)
         continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      int age = (int)(now - opened);
      ulong ticket = g_pos.Ticket();
      // try set SL first
      RG_ApplyAutoSLTP(ticket);
      if(!g_pos.SelectByTicket(ticket))
         continue;
      if(g_pos.StopLoss() > 0.0)
         continue;
      if(InpNakedSLTimeoutSec >= 0 && age >= InpNakedSLTimeoutSec)
         RG_ClosePositionTicket(ticket, "naked SL timeout");
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
      if(g_dayLocked)
        {
         g_dayLocked = false;
         RG_Notify("new risk day — lock cleared");
        }
      RG_StateSave();
     }

   if(!InpDayLockEnabled)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEquity <= 0.0)
      g_dayStartEquity = equity;

   double day_pnl = equity - g_dayStartEquity;
   // also add floating? for lock we use equity delta from day start (includes floating)
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
      g_lastStatusReason = "DAY LOCK: " + why;
      RG_Notify("DAY LOCK — " + why);
      RG_StateSave();
      if(InpDayLockFlatten)
         RG_FlattenAllManaged("day lock flatten");
     }
  }

//+------------------------------------------------------------------+
void RG_OnDealClosedLoss(const double deal_profit)
  {
   if(deal_profit < 0.0 && InpCooldownAfterLossSec > 0)
      g_cooldownUntil = TimeTradeServer() + InpCooldownAfterLossSec;
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
void RG_EnforceNewPosition(const ulong ticket)
  {
   if(!InpEnableGuard)
      return;
   if(!RG_PositionManaged(ticket))
      return;

   RG_EnforcePositionCount(ticket);
   if(!g_pos.SelectByTicket(ticket))
      return; // closed already

   RG_EnforceSize(ticket);
   if(!g_pos.SelectByTicket(ticket))
      return;

   RG_ApplyAutoSLTP(ticket);
   RG_EnforceTotalRisk();
  }

//+------------------------------------------------------------------+
void RG_EnforceAll()
  {
   if(!InpEnableGuard)
      return;

   RG_UpdateDayState();

   // snapshot symbols with positions
   string symbols[];
   int ns = 0;
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

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!RG_SelectManagedByIndex(i))
         continue;
      ulong ticket = g_pos.Ticket();
      RG_EnforceSize(ticket);
      if(!g_pos.SelectByTicket(ticket))
         continue;
      RG_ApplyAutoSLTP(ticket);
     }

   RG_EnforceNakedSL();
   RG_EnforceTimeGuard();
   RG_EnforceTotalRisk();

   for(int s = 0; s < ns; s++)
      RG_EnforceBasketExit(symbols[s]);

   // refresh status reason
   if(g_dayLocked)
      g_lastStatusReason = "LOCKED (day)";
   else if(RG_IsCooldownActive())
      g_lastStatusReason = "COOLDOWN";
   else
     {
      string r;
      bool avg = RG_AveragingPrivilegeOK(_Symbol, r);
      g_lastStatusReason = avg ? "ARMED · averaging OK" : ("ARMED · avg blocked: " + r);
     }
  }

#endif // RISKGUARD_ENFORCE_MQH
