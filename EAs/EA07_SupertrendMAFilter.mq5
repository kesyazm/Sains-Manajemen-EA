//+------------------------------------------------------------------+
//|                                        SupertrendMAFilterEA.mq5  |
//|                                  Copyright 2026, Gemini Notebook |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Supertrend dengan Moving Average Filter berdasarkan tutorial René Balke."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Supertrend Settings ---"
input string               InpSTPath          = "free indicators\\Supertrend.ex5";
input int                  InpSTATRPeriod     = 10;
input double               InpSTATRMultiplier = 3.0;

input group "--- Moving Average Filter Settings ---"
input bool                 InpUseMAFilter     = true;
input ENUM_TIMEFRAMES      InpMATimeframe     = PERIOD_CURRENT;
input int                  InpMAPeriod        = 200;
input ENUM_MA_METHOD       InpMAMethod        = MODE_SMA;
input ENUM_APPLIED_PRICE   InpMAPrice         = PRICE_CLOSE;

input group "--- Trade & Risk Settings ---"
input double               InpLotSize         = 0.1;
input ulong                InpStopLoss        = 0;
input ulong                InpTakeProfit      = 0;
input ulong                InpMagicNumber     = 334455;

//--- Global Variables
CTrade   trade;
int      handleSupertrend = INVALID_HANDLE;
int      handleMA         = INVALID_HANDLE;
datetime lastBarTime      = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter Validation
   if(InpMAPeriod <= 0 ||
      InpSTATRPeriod <= 0 ||
      InpSTATRMultiplier <= 0)
   {
      Print("[Error] Parameter indikator harus lebih besar dari nol.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Lot validation
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[Error] Lot size di luar batas yang diizinkan broker.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Initialize CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);

   //===============================================================
   // Supertrend
   //===============================================================
   handleSupertrend = iCustom(
      _Symbol,
      _Period,
      InpSTPath,
      InpSTATRPeriod,
      InpSTATRMultiplier
   );

   if(handleSupertrend == INVALID_HANDLE)
   {
      Print(
         "[Error] Gagal membuat handle indikator Supertrend: ",
         InpSTPath
      );

      return(INIT_FAILED);
   }

   //===============================================================
   // Moving Average
   //===============================================================
   handleMA = iMA(
      _Symbol,
      InpMATimeframe,
      InpMAPeriod,
      0,
      InpMAMethod,
      InpMAPrice
   );

   if(handleMA == INVALID_HANDLE)
   {
      Print("[Error] Gagal membuat handle Moving Average Filter.");

      return(INIT_FAILED);
   }

   lastBarTime = 0;

   Print("[Init] EA Supertrend dengan MA Filter berhasil dimuat.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleSupertrend != INVALID_HANDLE)
      IndicatorRelease(handleSupertrend);

   if(handleMA != INVALID_HANDLE)
      IndicatorRelease(handleMA);

   Print("[Deinit] EA dihentikan. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //===============================================================
   // 1. NEW BAR CHECK
   //===============================================================
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime == 0)
      return;

   if(currentBarTime == lastBarTime)
      return;

   // Update immediately supaya satu candle hanya diproses sekali
   lastBarTime = currentBarTime;

   //===============================================================
   // 2. COPY MOVING AVERAGE
   //===============================================================
   double maBuffer[1];

   if(CopyBuffer(
      handleMA,
      0,
      1,
      1,
      maBuffer
   ) < 1)
   {
      Print("[Warning] Gagal mengambil buffer Moving Average.");
      return;
   }

   // Convert array → scalar
   double maValue = maBuffer[0];

   //===============================================================
   // 3. COPY SUPERTREND
   //===============================================================
   double stBuffer[2];

   if(CopyBuffer(
      handleSupertrend,
      0,
      1,
      2,
      stBuffer
   ) < 2)
   {
      Print("[Warning] Gagal mengambil buffer Supertrend.");
      return;
   }

   //--- Supertrend values
   double stCurrent  = stBuffer[0];
   double stPrevious = stBuffer[1];

   //===============================================================
   // 4. CLOSED CANDLE PRICE
   //===============================================================
   double close1 = iClose(_Symbol, _Period, 1);
   double close2 = iClose(_Symbol, _Period, 2);

   if(close1 <= 0 || close2 <= 0)
      return;

   //===============================================================
   // 5. SUPERTREND SIGNAL
   //===============================================================
   bool stBuySignal =
      (close2 <= stPrevious) &&
      (close1 > stCurrent);

   bool stSellSignal =
      (close2 >= stPrevious) &&
      (close1 < stCurrent);

   //===============================================================
   // 6. MOVING AVERAGE FILTER
   //===============================================================
   bool maBuyCondition =
      (!InpUseMAFilter || close1 > maValue);

   bool maSellCondition =
      (!InpUseMAFilter || close1 < maValue);

   //===============================================================
   // 7. BUY SIGNAL
   //===============================================================
   if(stBuySignal && maBuyCondition)
   {
      Print(
         "[Signal] BUY Supertrend & MA Filter terpenuhi. ",
         "Close1: ",
         close1,
         " > MA: ",
         maValue
      );

      //--- Close opposite SELL
      ClosePositionsByType(POSITION_TYPE_SELL);

      //--- Open BUY
      if(!HasOpenPosition(POSITION_TYPE_BUY))
      {
         ExecuteBuy();
      }
   }

   //===============================================================
   // 8. SELL SIGNAL
   //===============================================================
   else if(stSellSignal && maSellCondition)
   {
      Print(
         "[Signal] SELL Supertrend & MA Filter terpenuhi. ",
         "Close1: ",
         close1,
         " < MA: ",
         maValue
      );

      //--- Close opposite BUY
      ClosePositionsByType(POSITION_TYPE_BUY);

      //--- Open SELL
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
      "[Order] Sending BUY @ ",
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
      "Supertrend Buy"
   ))
   {
      Print("[Success] Order BUY berhasil.");
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
      "[Order] Sending SELL @ ",
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
      "Supertrend Sell"
   ))
   {
      Print("[Success] Order SELL berhasil.");
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
//| Check Existing Open Positions                                    |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_POSITION_TYPE type)
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
         positionType == (long)type)
      {
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Close Position by Type                                           |
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
