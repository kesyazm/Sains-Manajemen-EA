//+------------------------------------------------------------------+
//|                                           MACDCrossoverEA.mq5    |
//|                                  Copyright 2026, Gemini Notebook |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA MACD Crossover berdasarkan tutorial René Balke."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- MACD Indicator Settings ---"
input int                  InpFastEMA        = 12;
input int                  InpSlowEMA        = 26;
input int                  InpSignalSMA      = 9;
input ENUM_APPLIED_PRICE   InpAppliedPrice   = PRICE_CLOSE;

input group "--- Risk & Trade Settings ---"
input double               InpLotSize        = 0.1;
input ulong                InpStopLoss       = 100;
input ulong                InpTakeProfit     = 100;
input ulong                InpMagicNumber    = 777888;

//--- Global Variables
CTrade trade;
int handleMACD = INVALID_HANDLE;
int barsTotal = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter Validation
   if(InpFastEMA <= 0 || InpSlowEMA <= 0 || InpSignalSMA <= 0)
   {
      Print("[Error] Periode indikator MACD harus lebih besar dari nol.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpFastEMA >= InpSlowEMA)
   {
      Print("[Error] Fast EMA harus lebih kecil dari Slow EMA.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[Error] Lot size di luar batas izin broker.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Setup CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);

   //--- Initialize MACD Handle
   handleMACD = iMACD(
      _Symbol,
      _Period,
      InpFastEMA,
      InpSlowEMA,
      InpSignalSMA,
      InpAppliedPrice
   );

   if(handleMACD == INVALID_HANDLE)
   {
      Print("[Error] Gagal membuat handle indikator iMACD.");
      return(INIT_FAILED);
   }

   barsTotal = iBars(_Symbol, _Period);

   Print("[Init] EA MACD Crossover berhasil diinisialisasi.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleMACD != INVALID_HANDLE)
      IndicatorRelease(handleMACD);

   Print("[Deinit] EA dihentikan. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check New Bar
   int bars = iBars(_Symbol, _Period);

   if(bars <= 0)
      return;

   if(bars == barsTotal)
      return;

   //--- Update bar count immediately
   barsTotal = bars;

   //--- MACD buffers
   double macdVal[2];
   double signalVal[2];

   //--- Copy MACD Main Line
   if(CopyBuffer(
      handleMACD,
      MAIN_LINE,
      1,
      2,
      macdVal
   ) < 2)
   {
      return;
   }

   //--- Copy MACD Signal Line
   if(CopyBuffer(
      handleMACD,
      SIGNAL_LINE,
      1,
      2,
      signalVal
   ) < 2)
   {
      return;
   }

   //===============================================================
   // MACD VALUES
   //===============================================================
   // macdVal[0]   = candle index 1
   // macdVal[1]   = candle index 2
   //
   // Karena ArraySetAsSeries(true), kita gunakan:
   // current = bar yang baru saja tertutup
   // previous = bar sebelum itu
   //===============================================================

   double macdCurr   = macdVal[0];
   double macdPrev   = macdVal[1];

   double signalCurr = signalVal[0];
   double signalPrev = signalVal[1];

   //===============================================================
   // CROSSOVER SIGNAL
   //===============================================================

   bool buySignal =
      (macdPrev <= signalPrev) &&
      (macdCurr > signalCurr);

   bool sellSignal =
      (macdPrev >= signalPrev) &&
      (macdCurr < signalCurr);

   //===============================================================
   // BUY SIGNAL
   //===============================================================
   if(buySignal)
   {
      Print(
         "[Signal] BUY Crossover MACD terdeteksi pada bar tertutup."
      );

      //--- Close SELL position
      ClosePositionsByType(POSITION_TYPE_SELL);

      //--- Open BUY if no BUY exists
      if(!HasOpenPosition(POSITION_TYPE_BUY))
      {
         ExecuteBuy();
      }
   }

   //===============================================================
   // SELL SIGNAL
   //===============================================================
   else if(sellSignal)
   {
      Print(
         "[Signal] SELL Crossover MACD terdeteksi pada bar tertutup."
      );

      //--- Close BUY position
      ClosePositionsByType(POSITION_TYPE_BUY);

      //--- Open SELL if no SELL exists
      if(!HasOpenPosition(POSITION_TYPE_SELL))
      {
         ExecuteSell();
      }
   }
}

//+------------------------------------------------------------------+
//| Execute BUY                                                      |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ask <= 0)
      return;

   double sl = 0;
   double tp = 0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         ask - InpStopLoss * _Point,
         _Digits
      );
   }

   if(InpTakeProfit > 0)
   {
      tp = NormalizeDouble(
         ask + InpTakeProfit * _Point,
         _Digits
      );
   }

   Print(
      "[Order] Mengirim order BUY @ ",
      ask,
      " | SL: ",
      sl,
      " | TP: ",
      tp
   );

   if(trade.Buy(
      InpLotSize,
      _Symbol,
      0,
      sl,
      tp,
      "MACD Buy"
   ))
   {
      Print("[Success] Order BUY berhasil diproses.");
   }
   else
   {
      Print(
         "[Error] Order BUY gagal: ",
         trade.ResultRetcodeDescription()
      );
   }
}

//+------------------------------------------------------------------+
//| Execute SELL                                                     |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bid <= 0)
      return;

   double sl = 0;
   double tp = 0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         bid + InpStopLoss * _Point,
         _Digits
      );
   }

   if(InpTakeProfit > 0)
   {
      tp = NormalizeDouble(
         bid - InpTakeProfit * _Point,
         _Digits
      );
   }

   Print(
      "[Order] Mengirim order SELL @ ",
      bid,
      " | SL: ",
      sl,
      " | TP: ",
      tp
   );

   if(trade.Sell(
      InpLotSize,
      _Symbol,
      0,
      sl,
      tp,
      "MACD Sell"
   ))
   {
      Print("[Success] Order SELL berhasil diproses.");
   }
   else
   {
      Print(
         "[Error] Order SELL gagal: ",
         trade.ResultRetcodeDescription()
      );
   }
}

//+------------------------------------------------------------------+
//| Check Open Position                                              |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0)
      {
         string symbol =
            PositionGetString(POSITION_SYMBOL);

         long magic =
            PositionGetInteger(POSITION_MAGIC);

         long positionType =
            PositionGetInteger(POSITION_TYPE);

         if(symbol == _Symbol &&
            magic == (long)InpMagicNumber &&
            positionType == (long)type)
         {
            return true;
         }
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Close Positions By Type                                          |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE typeToClose)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket <= 0)
         continue;

      string symbol =
         PositionGetString(POSITION_SYMBOL);

      long magic =
         PositionGetInteger(POSITION_MAGIC);

      long positionType =
         PositionGetInteger(POSITION_TYPE);

      if(symbol == _Symbol &&
         magic == (long)InpMagicNumber &&
         positionType == (long)typeToClose)
      {
         Print(
            "[Close] Menutup posisi berlawanan #",
            ticket
         );

         if(!trade.PositionClose(ticket))
         {
            Print(
               "[Error] Gagal menutup posisi #",
               ticket,
               ": ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }
}
//+------------------------------------------------------------------+
