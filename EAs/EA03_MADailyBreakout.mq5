//+------------------------------------------------------------------+
//|                         EA03_MADailyBreakout.mq5                  |
//|                         Copyright 2026, Kesya Izumi               |
//+------------------------------------------------------------------+
#property copyright "Kesya Izumi"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Daily Breakout dengan Moving Average Filter."

#include <Trade\Trade.mqh>

//--- Moving Average Filter
input group "--- Moving Average Filter ---"

input int                InpMAPeriod    = 100;
// MA Period

input ENUM_MA_METHOD     InpMAMethod    = MODE_SMA;
// MA Method

input ENUM_APPLIED_PRICE InpMAPrice     = PRICE_CLOSE;
// MA Applied Price


//--- Trade & Exit Settings
input group "--- Trade & Exit Settings ---"

input double InpLotSize     = 0.1;
// Lot Size

input int    InpCloseHour   = 22;
// Closing Time Hour

input int    InpCloseMinute = 0;
// Closing Time Minute

input ulong  InpMagicNumber = 987654;
// Magic Number


//--- Global Variables
CTrade trade;

int handleMA = INVALID_HANDLE;

datetime lastBarTime = 0;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate MA period
   if(InpMAPeriod <= 0)
   {
      Print("[Error] MA Period harus lebih besar dari nol.");
      return(INIT_PARAMETERS_INCORRECT);
   }


   //--- Validate closing hour
   if(InpCloseHour < 0 || InpCloseHour > 23)
   {
      Print("[Error] Close Hour harus berada antara 0-23.");
      return(INIT_PARAMETERS_INCORRECT);
   }


   //--- Validate closing minute
   if(InpCloseMinute < 0 || InpCloseMinute > 59)
   {
      Print("[Error] Close Minute harus berada antara 0-59.");
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


   if(InpLotSize < minLot || InpLotSize > maxLot)
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


   //--- Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();


   //--- Create Moving Average handle
   handleMA = iMA(
      _Symbol,
      _Period,
      InpMAPeriod,
      0,
      InpMAMethod,
      InpMAPrice
   );


   //--- Check handle
   if(handleMA == INVALID_HANDLE)
   {
      Print(
         "[Error] Gagal membuat handle Moving Average."
      );

      return(INIT_FAILED);
   }


   lastBarTime = 0;


   Print(
      "[Init] EA03 MA Daily Breakout berhasil dimuat."
   );

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleMA != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA);
      handleMA = INVALID_HANDLE;
   }


   Print(
      "[Deinit] EA03 dihentikan. Reason: ",
      reason
   );
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Current server time
   datetime now = TimeCurrent();

   MqlDateTime dt;

   TimeToStruct(now, dt);


   //--- Set today's closing time
   dt.hour = InpCloseHour;
   dt.min  = InpCloseMinute;
   dt.sec  = 0;


   datetime timeClose = StructToTime(dt);


   //--- Close EA positions at closing time
   ClosePositionsAtClosingTime(now, timeClose);


   //--- Do not open new trades after closing time
   if(now >= timeClose)
      return;


   //--- Check whether there is already an open position
   if(HasOpenPosition())
      return;


   //--- Detect new candle
   datetime currentBarTime = iTime(
      _Symbol,
      _Period,
      0
   );


   if(currentBarTime == 0)
      return;


   if(currentBarTime == lastBarTime)
      return;


   //--- Make sure MA has enough data
   if(BarsCalculated(handleMA) < InpMAPeriod + 2)
   {
      Print(
         "[Warning] Data Moving Average belum cukup."
      );

      return;
   }


   //--- MA buffer
   double maVal[1];


   //--- Get MA value from latest closed candle
   int copied = CopyBuffer(
      handleMA,
      0,
      1,
      1,
      maVal
   );


   if(copied < 1)
   {
      Print(
         "[Warning] Gagal mengambil nilai Moving Average."
      );

      return;
   }


   //--- Convert array value to scalar
   double maValue = maVal[0];


   //--- Get previous candle data
   double close1 = iClose(
      _Symbol,
      _Period,
      1
   );

   double high1 = iHigh(
      _Symbol,
      _Period,
      1
   );

   double low1 = iLow(
      _Symbol,
      _Period,
      1
   );


   //--- Current price
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );


   //--- Validate market data
   if(
      close1 <= 0 ||
      high1 <= 0 ||
      low1 <= 0 ||
      maValue <= 0 ||
      ask <= 0 ||
      bid <= 0
   )
   {
      Print(
         "[Warning] Data market tidak valid."
      );

      lastBarTime = currentBarTime;
      return;
   }


   //--- Determine trend
   bool isBuyTrend =
      (close1 > maValue);

   bool isSellTrend =
      (close1 < maValue);


   //--- Breakout conditions
   //--- BUY: current Ask breaks previous candle high
   bool buyBreakout =
      (ask > high1);

   //--- SELL: current Bid breaks previous candle low
   bool sellBreakout =
      (bid < low1);


   //--- BUY signal
   if(isBuyTrend && buyBreakout)
   {
      Print(
         "[Signal] BUY Daily Breakout detected.",
         " Close1: ",
         DoubleToString(close1, _Digits),
         " > MA: ",
         DoubleToString(maValue, _Digits),
         " | Ask: ",
         DoubleToString(ask, _Digits),
         " > High1: ",
         DoubleToString(high1, _Digits)
      );


      ExecuteBuy();
   }


   //--- SELL signal
   else if(isSellTrend && sellBreakout)
   {
      Print(
         "[Signal] SELL Daily Breakout detected.",
         " Close1: ",
         DoubleToString(close1, _Digits),
         " < MA: ",
         DoubleToString(maValue, _Digits),
         " | Bid: ",
         DoubleToString(bid, _Digits),
         " < Low1: ",
         DoubleToString(low1, _Digits)
      );


      ExecuteSell();
   }


   //--- Mark candle as processed
   lastBarTime = currentBarTime;
}


//+------------------------------------------------------------------+
//| Execute BUY Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   //--- Safety check
   if(HasOpenPosition())
      return;


   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );


   if(ask <= 0)
   {
      Print("[Error] Harga ASK tidak valid.");
      return;
   }


   //--- Open BUY without SL/TP
   //--- Closing is handled by daily closing time
   if(trade.Buy(
      InpLotSize,
      _Symbol,
      ask,
      0,
      0,
      "MA Daily Breakout BUY"
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


//+------------------------------------------------------------------+
//| Execute SELL Order                                               |
//+------------------------------------------------------------------+
void ExecuteSell()
{
   //--- Safety check
   if(HasOpenPosition())
      return;


   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );


   if(bid <= 0)
   {
      Print("[Error] Harga BID tidak valid.");
      return;
   }


   //--- Open SELL without SL/TP
   //--- Closing is handled by daily closing time
   if(trade.Sell(
      InpLotSize,
      _Symbol,
      bid,
      0,
      0,
      "MA Daily Breakout SELL"
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


//+------------------------------------------------------------------+
//| Check whether EA has open position                               |
//+------------------------------------------------------------------+
bool HasOpenPosition()
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


         if(
            symbol == _Symbol &&
            magic == (long)InpMagicNumber
         )
         {
            return true;
         }
      }
   }


   return false;
}


//+------------------------------------------------------------------+
//| Close positions at daily closing time                            |
//+------------------------------------------------------------------+
void ClosePositionsAtClosingTime(
   datetime now,
   datetime timeClose
)
{
   if(now < timeClose)
      return;


   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);


      if(ticket > 0)
      {
         string symbol =
            PositionGetString(POSITION_SYMBOL);

         long magic =
            PositionGetInteger(POSITION_MAGIC);


         if(
            symbol == _Symbol &&
            magic == (long)InpMagicNumber
         )
         {
            if(trade.PositionClose(ticket))
            {
               Print(
                  "[Close] Posisi #",
                  ticket,
                  " berhasil ditutup pada closing time."
               );
            }
            else
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
}
//+------------------------------------------------------------------+
