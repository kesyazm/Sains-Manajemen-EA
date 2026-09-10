//+------------------------------------------------------------------+
//|                                             BollingerBandsEA.mq5 |
//|                                  Copyright 2026, Gemini Notebook |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Bollinger Bands Mean Reversion berdasarkan tutorial René Balke."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Bollinger Bands Settings ---"
input int                  InpBandsPeriod    = 20;
input int                  InpBandsShift     = 0;
input double               InpBandsDev       = 2.0;
input ENUM_APPLIED_PRICE   InpAppliedPrice   = PRICE_CLOSE;

input group "--- Risk & Trade Settings ---"
input double               InpLotSize        = 0.1;
input ulong                InpStopLoss       = 100;
input bool                 InpCloseAtMiddle  = true;
input ulong                InpMagicNumber    = 555111;

//--- Global Variables
CTrade   trade;
int      handleBands = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter validation
   if(InpBandsPeriod <= 0 || InpBandsDev <= 0)
   {
      Print("[Error] Periode dan Deviasi Bollinger Bands harus lebih besar dari nol.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[Error] Lot size di luar batas yang diizinkan broker.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Set magic number
   trade.SetExpertMagicNumber(InpMagicNumber);

   //--- Create Bollinger Bands handle
   // Buffer:
   // 0 = Middle / Base Line
   // 1 = Upper Band
   // 2 = Lower Band
   handleBands = iBands(
      _Symbol,
      _Period,
      InpBandsPeriod,
      InpBandsShift,
      InpBandsDev,
      InpAppliedPrice
   );

   if(handleBands == INVALID_HANDLE)
   {
      Print("[Error] Gagal menginisialisasi handle Bollinger Bands.");
      return(INIT_FAILED);
   }

   Print("[Init] EA Bollinger Bands Mean Reversion berhasil diinisialisasi.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleBands != INVALID_HANDLE)
      IndicatorRelease(handleBands);

   Print("[Deinit] EA dihentikan. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Buffer untuk Bollinger Bands
   double middleBuffer[2];
   double upperBuffer[2];
   double lowerBuffer[2];

   //--- Copy indicator values
   if(CopyBuffer(handleBands, 0, 0, 2, middleBuffer) < 2)
      return;

   if(CopyBuffer(handleBands, 1, 0, 2, upperBuffer) < 2)
      return;

   if(CopyBuffer(handleBands, 2, 0, 2, lowerBuffer) < 2)
      return;

   //--- Convert array values to scalar
   double middleCurrent = middleBuffer[0];
   double middlePrevious = middleBuffer[1];

   double upperPrevious = upperBuffer[1];
   double lowerPrevious = lowerBuffer[1];

   //===============================================================
   // 1. EXIT MANAGEMENT
   //===============================================================
   if(InpCloseAtMiddle)
   {
      CheckMiddleBandExit(middleCurrent);
   }

   //===============================================================
   // 2. NEW BAR CHECK
   //===============================================================
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime == 0)
      return;

   if(currentBarTime == lastBarTime)
      return;

   //--- Update last bar immediately
   lastBarTime = currentBarTime;

   //===============================================================
   // 3. GET PREVIOUS CANDLE CLOSE
   //===============================================================
   double close1 = iClose(_Symbol, _Period, 1);

   if(close1 <= 0)
      return;

   //===============================================================
   // 4. MEAN REVERSION SIGNAL
   //===============================================================
   bool buySignal  = (close1 < lowerPrevious);
   bool sellSignal = (close1 > upperPrevious);

   //--- BUY signal
   if(buySignal)
   {
      Print(
         "[Signal] BUY Mean Reversion. Close1: ",
         close1,
         " < Lower Band: ",
         lowerPrevious
      );

      ExecuteBuy();
   }

   //--- SELL signal
   else if(sellSignal)
   {
      Print(
         "[Signal] SELL Mean Reversion. Close1: ",
         close1,
         " > Upper Band: ",
         upperPrevious
      );

      ExecuteSell();
   }
}

//+------------------------------------------------------------------+
//| Execute Buy                                                      |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   //--- Prevent duplicate BUY
   if(HasOpenPosition(POSITION_TYPE_BUY))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(ask <= 0)
      return;

   double sl = 0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         ask - InpStopLoss * _Point,
         _Digits
      );
   }

   Print(
      "[Order] Mengirim order BUY @ ",
      ask,
      " | SL: ",
      sl
   );

   if(trade.Buy(
      InpLotSize,
      _Symbol,
      0,
      sl,
      0,
      "BB Buy"
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
//| Execute Sell                                                     |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   //--- Prevent duplicate SELL
   if(HasOpenPosition(POSITION_TYPE_SELL))
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(bid <= 0)
      return;

   double sl = 0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         bid + InpStopLoss * _Point,
         _Digits
      );
   }

   Print(
      "[Order] Mengirim order SELL @ ",
      bid,
      " | SL: ",
      sl
   );

   if(trade.Sell(
      InpLotSize,
      _Symbol,
      0,
      sl,
      0,
      "BB Sell"
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
         string symbol = PositionGetString(POSITION_SYMBOL);
         long magic = PositionGetInteger(POSITION_MAGIC);
         long positionType = PositionGetInteger(POSITION_TYPE);

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
//| Check Middle Band Exit                                           |
//+------------------------------------------------------------------+
void CheckMiddleBandExit(double currentMiddleBand)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket <= 0)
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if(symbol != _Symbol ||
         magic != (long)InpMagicNumber)
      {
         continue;
      }

      ENUM_POSITION_TYPE posType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double currentPrice =
         PositionGetDouble(POSITION_PRICE_CURRENT);

      //--- Close BUY at Middle Band
      if(posType == POSITION_TYPE_BUY &&
         currentPrice >= currentMiddleBand)
      {
         Print(
            "[Exit] Closing BUY #",
            ticket,
            " at Middle Band: ",
            currentMiddleBand
         );

         if(!trade.PositionClose(ticket))
         {
            Print(
               "[Error] Gagal close BUY #",
               ticket,
               ": ",
               trade.ResultRetcodeDescription()
            );
         }
      }

      //--- Close SELL at Middle Band
      else if(posType == POSITION_TYPE_SELL &&
              currentPrice <= currentMiddleBand)
      {
         Print(
            "[Exit] Closing SELL #",
            ticket,
            " at Middle Band: ",
            currentMiddleBand
         );

         if(!trade.PositionClose(ticket))
         {
            Print(
               "[Error] Gagal close SELL #",
               ticket,
               ": ",
               trade.ResultRetcodeDescription()
            );
         }
      }
   }
}
//+------------------------------------------------------------------+
