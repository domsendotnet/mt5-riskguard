//+------------------------------------------------------------------+
//|                                          RiskGuard_SelfTest.mq5 |
//|  Live-symbol math checks. Attach to XAUUSD (or your symbol)     |
//|  during liquid hours. Read PASS/FAIL in the Experts tab.        |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property version   "1.23"
#property strict
#property script_show_confirm
#property description "RiskGuard self-test: money math, tick rounding, volume, basket target."

#include "../Include/RiskGuard_Utils.mqh"

int g_pass = 0;
int g_fail = 0;

//+------------------------------------------------------------------+
void RG_Expect(const bool cond, const string name, const string detail)
  {
   if(cond)
     {
      g_pass++;
      Print("PASS  ", name);
     }
   else
     {
      g_fail++;
      Print("FAIL  ", name, "  —  ", detail);
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   Print("========== RiskGuard self-test 1.23 ==========");
   Print("Symbol ", _Symbol, "  digits ", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         "  tick ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 8),
         "  tick_value ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 8));

   RG_Expect(RG_ScaledMoneyPer001(3.0, 0.01) > 2.999 && RG_ScaledMoneyPer001(3.0, 0.01) < 3.001,
             "scale 0.01 x 3", DoubleToString(RG_ScaledMoneyPer001(3.0, 0.01), 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(3.0, 0.02) - 6.0) < 1e-9,
             "scale 0.02 x 3", DoubleToString(RG_ScaledMoneyPer001(3.0, 0.02), 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(5.0, 0.05) - 25.0) < 1e-9,
             "scale 0.05 x 5", DoubleToString(RG_ScaledMoneyPer001(5.0, 0.05), 4));

   RG_Expect(MathAbs(RG_CommissionForLots(0.01) - InpCommissionPer001) < 1e-9,
             "commission 0.01", DoubleToString(RG_CommissionForLots(0.01), 4));
   double tgt = RG_ExitTargetForLots(0.02);
   double expect_tgt = InpBasketMinProfit + InpCommissionPer001 * 2.0;
   RG_Expect(MathAbs(tgt - expect_tgt) < 1e-9,
             "basket target two 0.01 lots",
             StringFormat("got %.4f expected %.4f", tgt, expect_tgt));

   double dist = 0.0;
   RG_Expect(!RG_MoneyToDistance(_Symbol, 0.0, ORDER_TYPE_BUY, 1.0, 3.0, dist),
             "money-distance rejects lots=0", "");
   RG_Expect(!RG_MoneyToDistance(_Symbol, 0.01, ORDER_TYPE_BUY, 1.0, 0.0, dist),
             "money-distance rejects money=0", "");

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   bool quotes_ok = (bid > 0.0 && tick_value > 0.0 && tick_size > 0.0);

   if(!quotes_ok)
     {
      Print("SKIP  live OrderCalcProfit tests — no tick value/bid. Run during liquid hours.");
     }
   else
     {
      double lots_list[4] = {0.01, 0.01, 0.02, 0.05};
      double money_list[4] = {3.0, 5.0, 3.0, 5.0};
      for(int i = 0; i < 4; i++)
        {
         double d = 0.0;
         bool ok = RG_MoneyToDistance(_Symbol, lots_list[i], ORDER_TYPE_BUY, bid, money_list[i], d);
         RG_Expect(ok && d > 0.0,
                   StringFormat("SL distance lots=%.2f money=%.1f", lots_list[i], money_list[i]),
                   ok ? DoubleToString(d, 5) : "OrderCalcProfit failed");
         if(!ok)
            continue;
         double m = 0.0;
         bool mok = RG_DistanceToMoney(_Symbol, lots_list[i], ORDER_TYPE_BUY, bid, d, m);
         RG_Expect(mok && m + 0.05 >= money_list[i],
                   StringFormat("SL round-trip lots=%.2f (got %.3f, want >= %.1f)",
                                lots_list[i], m, money_list[i]),
                   StringFormat("money=%.4f dist=%.5f", m, d));
         // must not wildly overshoot (tick granularity aside)
         RG_Expect(mok && m <= money_list[i] * 1.25 + 0.5,
                   StringFormat("SL distance not bloated lots=%.2f", lots_list[i]),
                   StringFormat("money=%.4f vs target %.1f", m, money_list[i]));
        }

      double tp_d = 0.0;
      bool tp_ok = RG_MoneyToProfitDistance(_Symbol, 0.01, ORDER_TYPE_BUY, bid, 4.0, tp_d);
      RG_Expect(tp_ok && tp_d > 0.0, "TP distance 0.01 x 4.0",
                tp_ok ? DoubleToString(tp_d, 5) : "failed");

      double rounded = RG_RoundToTick(_Symbol, bid + tick_size * 0.4);
      double q = rounded / tick_size;
      RG_Expect(MathAbs(q - MathRound(q)) < 1e-4, "round-to-tick lands on tick",
                DoubleToString(rounded, 8));

      double sl_far = bid - 50.0 * tick_size;
      if(sl_far > 0.0)
        {
         double clamped = RG_ClampToStops(_Symbol, POSITION_TYPE_BUY, bid, sl_far, true);
         RG_Expect(clamped > 0.0 && clamped <= bid,
                   "clamp SL stays below bid", DoubleToString(clamped, 5));
         double q2 = clamped / tick_size;
         RG_Expect(MathAbs(q2 - MathRound(q2)) < 1e-4, "clamped SL on tick",
                   DoubleToString(clamped, 8));
        }

      double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double nv = RG_NormalizeVolume(_Symbol, vmin + step * 0.4);
      RG_Expect(nv + 1e-12 >= vmin || nv == 0.0, "normalize volume >= min or 0",
                DoubleToString(nv, 8));
      double too_small = RG_NormalizeVolume(_Symbol, vmin * 0.1);
      RG_Expect(too_small == 0.0 || too_small + 1e-12 >= vmin,
                "tiny volume does not round below min as a live lot",
                DoubleToString(too_small, 8));
     }

   string why;
   bool allowed = RG_TradingAllowed(why);
   Print(allowed ? "INFO  trading allowed" : ("INFO  trading blocked: " + why));
   RG_Expect(true, "TradingAllowed() callable", why);

   Print("========== ", g_pass, " passed, ", g_fail, " failed ==========");
   if(g_fail > 0)
      Alert("RiskGuard self-test: ", g_fail, " FAILED (see Experts)");
   else
      Alert("RiskGuard self-test: ALL ", g_pass, " PASSED");
  }
//+------------------------------------------------------------------+
