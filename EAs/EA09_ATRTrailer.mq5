//+------------------------------------------------------------------+
//|                                                 ATRTrailerEA.mq5 |
//|                                  Copyright 2026, Gemini Notebook |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA ATR Forex Robot dengan MA Filter berdasarkan tutorial René Balke."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Signal & High/Low Settings ---"
input ENUM_TIMEFRAMES      InpSignalTimeframe = PERIOD_H1;
input int                  InpMinCandles      = 5;

input group "--- ATR Settings ---"
input ENUM_TIMEFRAMES      InpATRTimeframe    = PERIOD_D1;
input int                  InpATRPeriod       = 20;
input double               InpATRFactor       = 1.5;

input group "--- Moving Average Filter Settings ---"
input ENUM_TIMEFRAMES      InpMATimeframe     = PERIOD_D1;
input int                  InpMAPeriod        = 100;
input ENUM_MA_METHOD       InpMAMethod        = MODE_SMA;

input group "--- Trade & Risk Management ---"
input double               InpRiskMoney       = 500.0;
input double               InpSLATRFactor     = 1.0;
input double               InpTPATRFactor     = 1.0;
input ulong                InpMagicNumber     = 889900;

//--- Global Variables
CTrade   trade;
int      handleATR = INVALID_HANDLE;
int      handleMA  = INVALID_HANDLE;
int      totalBars = 0;
datetime lastTradeTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter validation
   if(InpMinCandles <= 0 ||
      InpATRPeriod <= 0 ||
      InpMAPeriod <= 0)
   {
      Print(
         "[Error] Parameter periode candle, ATR, dan MA harus lebih besar dari nol."
      );

      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Setup Magic Number
   trade.SetExpertMagicNumber(InpMagicNumber);

   //--- Initialize ATR
   handleATR = iATR(
      _Symbol,
      InpATRTimeframe,
      InpATRPeriod
   );

   //--- Initialize MA
   handleMA = iMA(
      _Symbol,
      InpMATimeframe,
      InpMAPeriod,
      0,
      InpMAMethod,
      PRICE_CLOSE
   );

   if(handleATR == INVALID_HANDLE ||
      handleMA == INVALID_HANDLE)
   {
      Print(
         "[Error] Gagal menginisialisasi handle indikator."
      );

      return(INIT_FAILED);
   }

   totalBars = iBars(
      _Symbol,
      InpSignalTimeframe
   );

   lastTradeTime = 0;

   Print(
      "[Init] EA ATR Trailer dengan MA Filter berhasil diinisialisasi."
   );

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);

   if(handleMA != INVALID_HANDLE)
      IndicatorRelease(handleMA);

   Print(
      "[Deinit] EA dihentikan. Reason: ",
      reason
   );
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //===============================================================
   // 1. NEW BAR CHECK
   //===============================================================
   int bars = iBars(
      _Symbol,
      InpSignalTimeframe
   );

   if(bars <= 0)
      return;

   if(bars == totalBars)
      return;

   // Update bar count immediately
   totalBars = bars;

   //===============================================================
   // 2. FILTER JAM PERDAGANGAN
   //===============================================================
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   if(dt.hour < 1)
      return;

   //===============================================================
   // 3. FIND LAST PIVOT HIGH / LOW
   //===============================================================
   double highVal = 0;
   double lowVal  = 0;
   datetime highLowTime = 0;

   int startShift =
      InpMinCandles + 1;

   int endShift =
      bars - InpMinCandles;

   int rangeCount =
      (InpMinCandles * 2) + 1;

   for(int i = startShift; i < endShift; i++)
   {
      int highestIdx = iHighest(
         _Symbol,
         InpSignalTimeframe,
         MODE_HIGH,
         rangeCount,
         i - InpMinCandles
      );

      int lowestIdx = iLowest(
         _Symbol,
         InpSignalTimeframe,
         MODE_LOW,
         rangeCount,
         i - InpMinCandles
      );

      if(i == highestIdx)
      {
         highVal = iHigh(
            _Symbol,
            InpSignalTimeframe,
            i
         );

         highLowTime = iTime(
            _Symbol,
            InpSignalTimeframe,
            i
         );

         break;
      }
      else if(i == lowestIdx)
      {
         lowVal = iLow(
            _Symbol,
            InpSignalTimeframe,
            i
         );

         highLowTime = iTime(
            _Symbol,
            InpSignalTimeframe,
            i
         );

         break;
      }
   }

   //--- Stop if no pivot found
   if(highVal == 0 && lowVal == 0)
      return;

   //===============================================================
   // 4. GET ATR & MA DATA
   //===============================================================
   double atrBuffer[1];
   double maBuffer[2];

   if(CopyBuffer(
      handleATR,
      0,
      1,
      1,
      atrBuffer
   ) < 1)
   {
      return;
   }

   if(CopyBuffer(
      handleMA,
      0,
      1,
      2,
      maBuffer
   ) < 2)
   {
      return;
   }

   //--- Convert arrays to scalar values
   double currentATR = atrBuffer[0];

   // CopyBuffer:
   // maBuffer[0] = older closed candle
   // maBuffer[1] = latest closed candle
   double maPrevious = maBuffer[0];
   double maCurrent  = maBuffer[1];

   //===============================================================
   // 5. CURRENT PRICE
   //===============================================================
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   if(ask <= 0 || bid <= 0)
      return;

   //===============================================================
   // 6. BUY SIGNAL
   //===============================================================
   if(highVal > 0 &&
      bid < (highVal - (currentATR * InpATRFactor)))
   {
      // MA slope naik
      bool maUpTrend =
         (maCurrent > maPrevious);

      if(maUpTrend &&
         highLowTime > lastTradeTime)
      {
         double slDistance =
            currentATR * InpSLATRFactor;

         double tpDistance =
            currentATR * InpTPATRFactor;

         double sl =
            NormalizeDouble(
               ask - slDistance,
               _Digits
            );

         double tp =
            NormalizeDouble(
               ask + tpDistance,
               _Digits
            );

         double lots =
            CalculateLots(slDistance);

         Print(
            "[Signal] BUY Signal Detected. High: ",
            highVal,
            " ATR: ",
            currentATR,
            " MA Previous: ",
            maPrevious,
            " MA Current: ",
            maCurrent
         );

         if(trade.Buy(
            lots,
            _Symbol,
            0,
            sl,
            tp,
            "ATR Trailer Buy"
         ))
         {
            lastTradeTime = highLowTime;

            Print(
               "[Success] BUY Order executed. Lots: ",
               lots
            );
         }
         else
         {
            Print(
               "[Error] BUY Order failed: ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }

   //===============================================================
   // 7. SELL SIGNAL
   //===============================================================
   else if(lowVal > 0 &&
           bid > (lowVal + (currentATR * InpATRFactor)))
   {
      // MA slope turun
      bool maDownTrend =
         (maCurrent < maPrevious);

      if(maDownTrend &&
         highLowTime > lastTradeTime)
      {
         double slDistance =
            currentATR * InpSLATRFactor;

         double tpDistance =
            currentATR * InpTPATRFactor;

         double sl =
            NormalizeDouble(
               bid + slDistance,
               _Digits
            );

         double tp =
            NormalizeDouble(
               bid - tpDistance,
               _Digits
            );

         double lots =
            CalculateLots(slDistance);

         Print(
            "[Signal] SELL Signal Detected. Low: ",
            lowVal,
            " ATR: ",
            currentATR,
            " MA Previous: ",
            maPrevious,
            " MA Current: ",
            maCurrent
         );

         if(trade.Sell(
            lots,
            _Symbol,
            0,
            sl,
            tp,
            "ATR Trailer Sell"
         ))
         {
            lastTradeTime = highLowTime;

            Print(
               "[Success] SELL Order executed. Lots: ",
               lots
            );
         }
         else
         {
            Print(
               "[Error] SELL Order failed: ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lots Based on Risk                                     |
//+------------------------------------------------------------------+
double CalculateLots(double slDistance)
{
   double tickSize =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_SIZE
      );

   double tickValue =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_TRADE_TICK_VALUE
      );

   double lotStep =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_STEP
      );

   if(tickSize <= 0 ||
      tickValue <= 0 ||
      lotStep <= 0)
   {
      return SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );
   }

   double slTicks =
      slDistance / tickSize;

   double riskPerLot =
      slTicks * tickValue;

   if(riskPerLot <= 0)
   {
      return SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );
   }

   double riskPerLotStep =
      riskPerLot * lotStep;

   int lotStepMultiplier =
      (int)(InpRiskMoney / riskPerLotStep);

   double calculatedLots =
      lotStep * lotStepMultiplier;

   //--- Broker limits
   double minLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MIN
      );

   double maxLot =
      SymbolInfoDouble(
         _Symbol,
         SYMBOL_VOLUME_MAX
      );

   if(calculatedLots < minLot)
      calculatedLots = minLot;

   if(calculatedLots > maxLot)
      calculatedLots = maxLot;

   return NormalizeDouble(
      calculatedLots,
      2
   );
}
//+------------------------------------------------------------------+
