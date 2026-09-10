//+------------------------------------------------------------------+
//|                                      EA04_MeanReversionEA.mq5     |
//|                         Copyright 2026, Kesya Izumi              |
//+------------------------------------------------------------------+
#property copyright "Kesya Izumi"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Mean Reversion menggunakan MA, RSI, dan ATR."

#include <Trade\Trade.mqh>

//--- Moving Average 1
input group "--- Moving Average 1 (Chart Signal) ---"

input ENUM_TIMEFRAMES    InpMA1Timeframe = PERIOD_M15;
input int                InpMA1Period    = 360;
input ENUM_MA_METHOD     InpMA1Method    = MODE_SMA;
input ENUM_APPLIED_PRICE InpMA1Price     = PRICE_CLOSE;


//--- Moving Average 2
input group "--- Moving Average 2 (Trend Filter) ---"

input ENUM_TIMEFRAMES    InpMA2Timeframe = PERIOD_D1;
input int                InpMA2Period    = 20;
input ENUM_MA_METHOD     InpMA2Method    = MODE_SMA;
input ENUM_APPLIED_PRICE InpMA2Price     = PRICE_CLOSE;


//--- ATR Settings
input group "--- ATR Settings ---"

input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_M15;
input int             InpATR1Period   = 10;
input int             InpATR2Period   = 20;


//--- RSI Settings
input group "--- RSI Settings ---"

input ENUM_TIMEFRAMES    InpRSITimeframe = PERIOD_M15;
input int                InpRSIPeriod    = 20;
input ENUM_APPLIED_PRICE InpRSIPrice     = PRICE_CLOSE;


//--- Strategy & Risk
input group "--- Strategy & Risk Parameters ---"

input double InpMinMAGapPercent = 0.6;
input double InpLotSize         = 0.1;
input double InpSLPercent       = 0.0;
input double InpTPPercent       = 0.0;
input ulong  InpMagicNumber     = 112233;


//--- Global Variables
CTrade trade;

int handleMA1  = INVALID_HANDLE;
int handleMA2  = INVALID_HANDLE;
int handleATR1 = INVALID_HANDLE;
int handleATR2 = INVALID_HANDLE;
int handleRSI  = INVALID_HANDLE;

datetime lastBarTime = 0;


//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate periods
   if(InpMA1Period <= 0 ||
      InpMA2Period <= 0 ||
      InpATR1Period <= 0 ||
      InpATR2Period <= 0 ||
      InpRSIPeriod <= 0)
   {
      Print("[Error] Semua periode indikator harus lebih besar dari 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }


   //--- Validate MA gap
   if(InpMinMAGapPercent < 0)
   {
      Print("[Error] Minimum MA Gap tidak boleh negatif.");
      return(INIT_PARAMETERS_INCORRECT);
   }


   //--- Validate lot size
   double minLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MIN
   );

   double maxLot = SymbolInfoDouble(
      _Symbol,
      SYMBOL_VOLUME_MAX
   );


   if(InpLotSize < minLot ||
      InpLotSize > maxLot)
   {
      Print(
         "[Error] Lot size ",
         InpLotSize,
         " berada di luar batas broker [",
         minLot,
         ", ",
         maxLot,
         "]."
      );

      return(INIT_PARAMETERS_INCORRECT);
   }


   //--- Initialize trade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();


   //--- Create MA1
   handleMA1 = iMA(
      _Symbol,
      InpMA1Timeframe,
      InpMA1Period,
      0,
      InpMA1Method,
      InpMA1Price
   );


   //--- Create MA2
   handleMA2 = iMA(
      _Symbol,
      InpMA2Timeframe,
      InpMA2Period,
      0,
      InpMA2Method,
      InpMA2Price
   );


   //--- Create ATR1
   handleATR1 = iATR(
      _Symbol,
      InpATRTimeframe,
      InpATR1Period
   );


   //--- Create ATR2
   handleATR2 = iATR(
      _Symbol,
      InpATRTimeframe,
      InpATR2Period
   );


   //--- Create RSI
   handleRSI = iRSI(
      _Symbol,
      InpRSITimeframe,
      InpRSIPeriod,
      InpRSIPrice
   );


   //--- Check indicator handles
   if(handleMA1 == INVALID_HANDLE ||
      handleMA2 == INVALID_HANDLE ||
      handleATR1 == INVALID_HANDLE ||
      handleATR2 == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE)
   {
      Print("[Error] Gagal membuat salah satu indicator handle.");
      return(INIT_FAILED);
   }


   lastBarTime = 0;


   Print(
      "[Init] EA04 Mean Reversion berhasil diinisialisasi."
   );


   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleMA1 != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA1);
      handleMA1 = INVALID_HANDLE;
   }


   if(handleMA2 != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA2);
      handleMA2 = INVALID_HANDLE;
   }


   if(handleATR1 != INVALID_HANDLE)
   {
      IndicatorRelease(handleATR1);
      handleATR1 = INVALID_HANDLE;
   }


   if(handleATR2 != INVALID_HANDLE)
   {
      IndicatorRelease(handleATR2);
      handleATR2 = INVALID_HANDLE;
   }


   if(handleRSI != INVALID_HANDLE)
   {
      IndicatorRelease(handleRSI);
      handleRSI = INVALID_HANDLE;
   }


   Print(
      "[Deinit] EA04 dihentikan. Reason: ",
      reason
   );
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Manage existing positions first
   ManageOpenPositions();


   //--- Detect new M15 candle
   datetime currentBarTime = iTime(
      _Symbol,
      InpMA1Timeframe,
      0
   );


   if(currentBarTime == 0)
      return;


   if(currentBarTime == lastBarTime)
      return;


   //--- Check enough indicator data
   if(BarsCalculated(handleMA1) < InpMA1Period + 2)
      return;


   if(BarsCalculated(handleMA2) < InpMA2Period + 2)
      return;


   if(BarsCalculated(handleATR1) < InpATR1Period + 2)
      return;


   if(BarsCalculated(handleATR2) < InpATR2Period + 2)
      return;


   if(BarsCalculated(handleRSI) < InpRSIPeriod + 2)
      return;


   //--- Indicator arrays
   double ma1Buffer[1];
   double ma2Buffer[1];

   double atr1Buffer[1];
   double atr2Buffer[1];

   double rsiBuffer[2];


   //--- Get MA1 from latest closed candle
   if(CopyBuffer(
      handleMA1,
      0,
      1,
      1,
      ma1Buffer
   ) < 1)
   {
      Print("[Warning] Gagal mengambil MA1.");
      return;
   }


   //--- Get MA2 from latest closed candle
   if(CopyBuffer(
      handleMA2,
      0,
      1,
      1,
      ma2Buffer
   ) < 1)
   {
      Print("[Warning] Gagal mengambil MA2.");
      return;
   }


   //--- Get ATR1
   if(CopyBuffer(
      handleATR1,
      0,
      1,
      1,
      atr1Buffer
   ) < 1)
   {
      Print("[Warning] Gagal mengambil ATR1.");
      return;
   }


   //--- Get ATR2
   if(CopyBuffer(
      handleATR2,
      0,
      1,
      1,
      atr2Buffer
   ) < 1)
   {
      Print("[Warning] Gagal mengambil ATR2.");
      return;
   }


   //--- Get RSI
   if(CopyBuffer(
      handleRSI,
      0,
      1,
      2,
      rsiBuffer
   ) < 2)
   {
      Print("[Warning] Gagal mengambil RSI.");
      return;
   }


   //--- Convert arrays to scalar values
   double ma1Value  = ma1Buffer[0];
   double ma2Value  = ma2Buffer[0];

   double atr1Value = atr1Buffer[0];
   double atr2Value = atr2Buffer[0];

   // rsiBuffer[0] = older closed candle
   // rsiBuffer[1] = latest closed candle
   double rsiPrevious = rsiBuffer[0];
   double rsiCurrent  = rsiBuffer[1];


   //--- Get latest closed candle price
   double closePrice = iClose(
      _Symbol,
      InpMA1Timeframe,
      1
   );


   if(closePrice <= 0 ||
      ma1Value <= 0 ||
      ma2Value <= 0 ||
      atr1Value <= 0 ||
      atr2Value <= 0)
   {
      lastBarTime = currentBarTime;
      return;
   }


   //==============================================================
   // Strategy Conditions
   //==============================================================

   //--- ATR condition
   bool isAtrValid =
      (atr1Value < atr2Value);


   //--- MA gap
   double gapPercent =
      MathAbs(closePrice - ma1Value)
      / ma1Value
      * 100.0;


   bool isBuyGap =
      closePrice < ma1Value &&
      gapPercent >= InpMinMAGapPercent;


   bool isSellGap =
      closePrice > ma1Value &&
      gapPercent >= InpMinMAGapPercent;


   //--- MA2 trend filter
   bool isBuyTrend =
      closePrice > ma2Value;


   bool isSellTrend =
      closePrice < ma2Value;


   //--- RSI movement
   bool isRsiBuy =
      rsiCurrent > rsiPrevious;


   bool isRsiSell =
      rsiCurrent < rsiPrevious;


   //--- Current prices
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );


   if(ask <= 0 || bid <= 0)
   {
      lastBarTime = currentBarTime;
      return;
   }


   //==============================================================
   // BUY SIGNAL
   //==============================================================

   if(isAtrValid &&
      isBuyGap &&
      isBuyTrend &&
      isRsiBuy &&
      !HasPositionType(POSITION_TYPE_BUY))
   {
      double sl = 0.0;
      double tp = 0.0;


      if(InpSLPercent > 0)
      {
         sl = NormalizeDouble(
            ask -
            (ask * InpSLPercent / 100.0),
            _Digits
         );
      }


      if(InpTPPercent > 0)
      {
         tp = NormalizeDouble(
            ask +
            (ask * InpTPPercent / 100.0),
            _Digits
         );
      }


      Print(
         "[Signal] BUY Mean Reversion | ",
         "Close: ",
         DoubleToString(closePrice, _Digits),
         " | MA1: ",
         DoubleToString(ma1Value, _Digits),
         " | MA2: ",
         DoubleToString(ma2Value, _Digits),
         " | RSI: ",
         DoubleToString(rsiCurrent, 2)
      );


      if(trade.Buy(
         InpLotSize,
         _Symbol,
         ask,
         sl,
         tp,
         "Mean Reversion BUY"
      ))
      {
         Print(
            "[Success] BUY berhasil dibuka. Ticket: ",
            trade.ResultOrder()
         );
      }
      else
      {
         Print(
            "[Error] BUY gagal. Code: ",
            trade.ResultRetcode(),
            " | ",
            trade.ResultRetcodeDescription()
         );
      }
   }


   //==============================================================
   // SELL SIGNAL
   //==============================================================

   else if(isAtrValid &&
           isSellGap &&
           isSellTrend &&
           isRsiSell &&
           !HasPositionType(POSITION_TYPE_SELL))
   {
      double sl = 0.0;
      double tp = 0.0;


      if(InpSLPercent > 0)
      {
         sl = NormalizeDouble(
            bid +
            (bid * InpSLPercent / 100.0),
            _Digits
         );
      }


      if(InpTPPercent > 0)
      {
         tp = NormalizeDouble(
            bid -
            (bid * InpTPPercent / 100.0),
            _Digits
         );
      }


      Print(
         "[Signal] SELL Mean Reversion | ",
         "Close: ",
         DoubleToString(closePrice, _Digits),
         " | MA1: ",
         DoubleToString(ma1Value, _Digits),
         " | MA2: ",
         DoubleToString(ma2Value, _Digits),
         " | RSI: ",
         DoubleToString(rsiCurrent, 2)
      );


      if(trade.Sell(
         InpLotSize,
         _Symbol,
         bid,
         sl,
         tp,
         "Mean Reversion SELL"
      ))
      {
         Print(
            "[Success] SELL berhasil dibuka. Ticket: ",
            trade.ResultOrder()
         );
      }
      else
      {
         Print(
            "[Error] SELL gagal. Code: ",
            trade.ResultRetcode(),
            " | ",
            trade.ResultRetcodeDescription()
         );
      }
   }


   //--- Mark candle as processed
   lastBarTime = currentBarTime;
}


//+------------------------------------------------------------------+
//| Manage existing positions                                        |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   //--- Get MA1 value
   double ma1Buffer[1];


   if(CopyBuffer(
      handleMA1,
      0,
      1,
      1,
      ma1Buffer
   ) < 1)
   {
      return;
   }


   double ma1Value = ma1Buffer[0];


   if(ma1Value <= 0)
      return;


   //--- Check all positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);


      if(ticket <= 0)
         continue;


      string symbol =
         PositionGetString(POSITION_SYMBOL);


      long magic =
         PositionGetInteger(POSITION_MAGIC);


      if(symbol != _Symbol ||
         magic != (long)InpMagicNumber)
      {
         continue;
      }


      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);


      double profit =
         PositionGetDouble(POSITION_PROFIT);


      double currentPrice =
         PositionGetDouble(POSITION_PRICE_CURRENT);


      //--- BUY: close when price returns above MA1
      if(type == POSITION_TYPE_BUY)
      {
         if(profit > 0 &&
            currentPrice > ma1Value)
         {
            Print(
               "[Close] BUY position #",
               ticket,
               " ditutup karena price kembali ke MA1."
            );


            if(!trade.PositionClose(ticket))
            {
               Print(
                  "[Error] Gagal menutup BUY #",
                  ticket,
                  ": ",
                  trade.ResultRetcodeDescription()
               );
            }
         }
      }


      //--- SELL: close when price returns below MA1
      else if(type == POSITION_TYPE_SELL)
      {
         if(profit > 0 &&
            currentPrice < ma1Value)
         {
            Print(
               "[Close] SELL position #",
               ticket,
               " ditutup karena price kembali ke MA1."
            );


            if(!trade.PositionClose(ticket))
            {
               Print(
                  "[Error] Gagal menutup SELL #",
                  ticket,
                  ": ",
                  trade.ResultRetcodeDescription()
               );
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Check position by type                                           |
//+------------------------------------------------------------------+
bool HasPositionType(
   ENUM_POSITION_TYPE positionType
)
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


      ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)
         PositionGetInteger(POSITION_TYPE);


      if(symbol == _Symbol &&
         magic == (long)InpMagicNumber &&
         type == positionType)
      {
         return true;
      }
   }


   return false;
}
//+------------------------------------------------------------------+
