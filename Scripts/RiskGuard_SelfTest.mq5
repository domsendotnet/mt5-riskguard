//+------------------------------------------------------------------+
//|                                          RiskGuard_SelfTest.mq5 |
//|  Live-symbol math checks. Attach to XAUUSD (or your symbol)     |
//|  during liquid hours. Read PASS/FAIL in the Experts tab.        |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property version   "1.31"
#property strict
#property script_show_confirm
#property description "RiskGuard self-test: money math, tick rounding, volume, basket target, no-trade hours."

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
   Print("========== RiskGuard self-test 1.31 ==========");
   Print("Symbol ", _Symbol, "  digits ", (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
         "  tick ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), 8),
         "  tick_value ", DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), 8));

   RG_Expect(RG_ScaledMoneyPer001(3.0, 0.01) > 2.999 && RG_ScaledMoneyPer001(3.0, 0.01) < 3.001,
             "scale 0.01 x 3", DoubleToString(RG_ScaledMoneyPer001(3.0, 0.01), 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(3.0, 0.02) - 6.0) < 1e-9,
             "scale 0.02 x 3", DoubleToString(RG_ScaledMoneyPer001(3.0, 0.02), 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(5.0, 0.05) - 25.0) < 1e-9,
             "scale 0.05 x 5", DoubleToString(RG_ScaledMoneyPer001(5.0, 0.05), 4));
   RG_Expect(RG_AveragingStopFactor() >= 1.0, "averaging stop factor >= 1",
             DoubleToString(RG_AveragingStopFactor(), 2));
   RG_Expect(MathAbs(RG_StopMoneyPer001(_Symbol) - InpMaxLossPer001) < 1e-9,
             "single-trade stop money (no basket)",
             DoubleToString(RG_StopMoneyPer001(_Symbol), 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(InpTP_MoneyPer001, 0.01) * 0.70 -
                     InpTP_MoneyPer001 * 0.70) < 1e-9,
             "BE trigger 70% of TP on 0.01",
             DoubleToString(RG_ScaledMoneyPer001(InpTP_MoneyPer001, 0.01) * 0.70, 4));
   RG_Expect(MathAbs(RG_ScaledMoneyPer001(0.10, 0.01) - 0.10) < 1e-9,
             "BE lock 0.10 per 0.01",
             DoubleToString(RG_ScaledMoneyPer001(0.10, 0.01), 4));
   RG_Expect(!RG_PolicyBreakEvenOn() || InpBE_TriggerPercent > 0.0,
             "BE off unless % > 0",
             DoubleToString(InpBE_TriggerPercent, 2));
   RG_Expect(MathAbs(RG_RescueCloseNet(-30.0, 6) + 5.0) < 1e-9,
             "rescue -30 hole / 6 = -5",
             DoubleToString(RG_RescueCloseNet(-30.0, 6), 4));
   RG_Expect(RG_RescueCloseNet(-30.0, 1) == 0.0,
             "rescue N=1 refused (would close at the bottom)",
             DoubleToString(RG_RescueCloseNet(-30.0, 1), 4));
   RG_Expect(RG_RescueCloseNet(0.0, 6) == 0.0,
             "rescue no hole → no level",
             DoubleToString(RG_RescueCloseNet(0.0, 6), 4));

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

   RG_Expect(RG_DayOfWeekYMD(2026, 3, 29) == 0, "29 Mar 2026 is Sunday",
             IntegerToString(RG_DayOfWeekYMD(2026, 3, 29)));
   RG_Expect(RG_LastSundayDay(2026, 3) == 29, "last Sunday March 2026 = 29",
             IntegerToString(RG_LastSundayDay(2026, 3)));
   RG_Expect(RG_LastSundayDay(2026, 10) == 25, "last Sunday October 2026 = 25",
             IntegerToString(RG_LastSundayDay(2026, 10)));
   RG_Expect(RG_NthSundayDay(2026, 3, 2) == 8, "2nd Sunday March 2026 = 8",
             IntegerToString(RG_NthSundayDay(2026, 3, 2)));
   RG_Expect(RG_MinutesInSlot(14 * 60 + 3, 13 * 60 + 45, 15 * 60 + 15),
             "14:03 inside 13:45-15:15", "");
   RG_Expect(!RG_MinutesInSlot(13 * 60 + 44, 13 * 60 + 45, 15 * 60 + 15),
             "13:44 outside 13:45-15:15", "");
   RG_Expect(RG_MinutesInSlot(16 * 60 + 5, 16 * 60, 16 * 60 + 5),
             "16:05 included in 16:00-16:05", "");
   RG_Expect(RG_MinutesInSlot(23 * 60, 22 * 60, 2 * 60),
             "23:00 inside wrapping 22:00-02:00", "");
   RG_Expect(!RG_MinutesInSlot(12 * 60, 22 * 60, 2 * 60),
             "12:00 outside wrapping 22:00-02:00", "");

   int starts[], ends[], nslots;
   string perr;
   bool pok = RG_ParseNoTradeSlots("13:45-15:15, 16:00-16:05", starts, ends, nslots, perr);
   bool parse_ok = (pok && nslots == 2);
   if(parse_ok)
      parse_ok = (starts[0] == 13 * 60 + 45 && ends[0] == 15 * 60 + 15 &&
                  starts[1] == 16 * 60 && ends[1] == 16 * 60 + 5);
   RG_Expect(parse_ok, "parse 13:45-15:15,16:00-16:05", perr);
   pok = RG_ParseNoTradeSlots("", starts, ends, nslots, perr);
   RG_Expect(pok && nslots == 0, "empty no-trade string is off", perr);
   pok = RG_ParseNoTradeSlots("25:00-26:00", starts, ends, nslots, perr);
   RG_Expect(!pok, "reject 25:00", pok ? "accepted" : perr);
   RG_Expect(RG_FmtHm(13 * 60 + 45) == "13:45", "fmt 13:45", RG_FmtHm(13 * 60 + 45));

   MqlDateTime gmt_now;
   TimeToStruct(TimeGMT(), gmt_now);
   bool eu_summer = RG_EuSummerGmt(TimeGMT());
   if(gmt_now.mon >= 4 && gmt_now.mon <= 9)
      RG_Expect(eu_summer, "EU summer in Apr-Sep", "DST flag false");
   else
      RG_Expect(true, "EU DST helper callable", eu_summer ? "summer" : "winter");
   Print("INFO  clock Berlin now offset vs GMT ",
         IntegerToString(RG_ClockGmtOffsetSec(RG_CLOCK_BERLIN, TimeGMT()) / 3600), "h  |  server vs GMT ",
         IntegerToString((int)(TimeTradeServer() - TimeGMT()) / 3600), "h");

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
