//+------------------------------------------------------------------+
//|                    EA02_KeltnerChannelMeanReversion.mq5          |
//|                         Copyright 2026, Kesya Izumi              |
//+------------------------------------------------------------------+
#property copyright "Kesya Izumi"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Mean Reversion Keltner Channel untuk MT5."

#include <Trade\Trade.mqh>

//--- Keltner Channel Settings
input group "--- Keltner Channel Settings ---"

input int      InpKeltnerEMAPeriod     = 20;
// Keltner EMA Period

input int      InpKeltnerATRPeriod     = 10;
// Keltner ATR Period

input double   InpKeltnerATRMultiplier = 2.0;
// Keltner ATR Multiplier

input string   InpIndicatorPath =
               "free indicators\\Keltner Channel.ex5";
// Custom Indicator Path


//--- Risk & Trade Settings
input group "--- Risk & Trade Settings ---"

input double   InpLotSize    = 0.1;
// Lot Size

input ulong    InpTakeProfit = 500;
// Take Profit in Points

input ulong    InpStopLoss   = 2000;
// Stop Loss in Points

input ulong    InpMagicNumber = 654321;
// Magic Number


//--- Global Variables
CTrade   trade;

int      handleKeltner = INVALID_HANDLE;

datetime lastBarTime = 0;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate Keltner parameters
   if(InpKeltnerEMAPeriod <= 0)
   {
      Print("[Error] Keltner EMA Period harus lebih besar dari 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpKeltnerATRPeriod <= 0)
   {
      Print("[Error] Keltner ATR Period harus lebih besar dari 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpKeltnerATRMultiplier <= 0)
   {
      Print("[Error] Keltner ATR Multiplier harus lebih besar dari 0.");
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


   //--- Create Keltner Channel indicator handle
   handleKeltner = iCustom(
      _Symbol,
      _Period,
      InpIndicatorPath,
      InpKeltnerEMAPeriod,
      InpKeltnerATRPeriod,
      InpKeltnerATRMultiplier,
      false
   );


   //--- Validate indicator handle
   if(handleKeltner == INVALID_HANDLE)
   {
      Print(
         "[Error] Gagal memuat indikator Keltner Channel: ",
         InpIndicatorPath
      );

      return(INIT_FAILED);
   }


   //--- Initialize last bar
   lastBarTime = 0;


   Print(
      "[Init] EA02 Keltner Channel Mean Reversion berhasil dimuat."
   );

   Print(
      "[Init] EMA Period: ",
      InpKeltnerEMAPeriod,
      " | ATR Period: ",
      InpKeltnerATRPeriod,
      " | ATR Multiplier: ",
      InpKeltnerATRMultiplier
   );

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator
   if(handleKeltner != INVALID_HANDLE)
   {
      IndicatorRelease(handleKeltner);
      handleKeltner = INVALID_HANDLE;
   }


   Print(
      "[Deinit] EA02 dihentikan. Reason: ",
      reason
   );
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Get current candle time
   datetime currentBarTime = iTime(
      _Symbol,
      _Period,
      0
   );


   //--- Process only once per new candle
   if(currentBarTime == 0)
      return;

   if(currentBarTime == lastBarTime)
      return;


   //--- Make sure indicator has enough data
   if(BarsCalculated(handleKeltner) < 3)
   {
      Print(
         "[Warning] Data Keltner Channel belum cukup."
      );

      return;
   }


   //--- Buffer arrays
   double kUpper[1];
   double kLower[1];


   //--- Get Upper Channel
   //--- Buffer 0 = Upper Channel
   //--- Candle shift 1 = last closed candle
   int copiedUpper = CopyBuffer(
      handleKeltner,
      0,
      1,
      1,
      kUpper
   );


   //--- Get Lower Channel
   //--- Buffer 2 = Lower Channel
   //--- Candle shift 1 = last closed candle
   int copiedLower = CopyBuffer(
      handleKeltner,
      2,
      1,
      1,
      kLower
   );


   //--- Check copied data
   if(copiedUpper < 1 || copiedLower < 1)
   {
      Print(
         "[Warning] Gagal mengambil data buffer Keltner Channel."
      );

      return;
   }


   //--- Extract scalar values from arrays
   double upperChannel = kUpper[0];
   double lowerChannel = kLower[0];


   //--- Get close price of last closed candle
   double closePrice = iClose(
      _Symbol,
      _Period,
      1
   );


   //--- Validate prices
   if(closePrice <= 0 ||
      upperChannel <= 0 ||
      lowerChannel <= 0)
   {
      Print(
         "[Warning] Nilai harga atau Keltner Channel tidak valid."
      );

      lastBarTime = currentBarTime;
      return;
   }


   //--- Mean Reversion Signals
   bool buySignal =
      (closePrice < lowerChannel);

   bool sellSignal =
      (closePrice > upperChannel);


   //--- BUY Signal
   if(buySignal)
   {
      Print(
         "[Signal] BUY Mean Reversion | Close: ",
         DoubleToString(closePrice, _Digits),
         " < Lower: ",
         DoubleToString(lowerChannel, _Digits)
      );

      ExecuteBuy();
   }


   //--- SELL Signal
   else if(sellSignal)
   {
      Print(
         "[Signal] SELL Mean Reversion | Close: ",
         DoubleToString(closePrice, _Digits),
         " > Upper: ",
         DoubleToString(upperChannel, _Digits)
      );

      ExecuteSell();
   }


   //--- Mark current candle as processed
   lastBarTime = currentBarTime;
}


//+------------------------------------------------------------------+
//| Execute BUY Order                                                |
//+------------------------------------------------------------------+
void ExecuteBuy()
{
   //--- Prevent multiple positions
   if(HasOpenPosition())
   {
      Print(
         "[Info] BUY dilewati karena sudah ada posisi aktif."
      );

      return;
   }


   //--- Get Ask price
   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );


   if(ask <= 0)
   {
      Print("[Error] Harga ASK tidak valid.");
      return;
   }


   //--- Calculate Stop Loss
   double sl = 0.0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         ask - InpStopLoss * _Point,
         _Digits
      );
   }


   //--- Calculate Take Profit
   double tp = 0.0;

   if(InpTakeProfit > 0)
   {
      tp = NormalizeDouble(
         ask + InpTakeProfit * _Point,
         _Digits
      );
   }


   //--- Send BUY order
   Print(
      "[Order] BUY | Price: ",
      DoubleToString(ask, _Digits),
      " | SL: ",
      DoubleToString(sl, _Digits),
      " | TP: ",
      DoubleToString(tp, _Digits)
   );


   if(trade.Buy(
      InpLotSize,
      _Symbol,
      ask,
      sl,
      tp,
      "Keltner Mean Reversion BUY"
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
   //--- Prevent multiple positions
   if(HasOpenPosition())
   {
      Print(
         "[Info] SELL dilewati karena sudah ada posisi aktif."
      );

      return;
   }


   //--- Get Bid price
   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );


   if(bid <= 0)
   {
      Print("[Error] Harga BID tidak valid.");
      return;
   }


   //--- Calculate Stop Loss
   double sl = 0.0;

   if(InpStopLoss > 0)
   {
      sl = NormalizeDouble(
         bid + InpStopLoss * _Point,
         _Digits
      );
   }


   //--- Calculate Take Profit
   double tp = 0.0;

   if(InpTakeProfit > 0)
   {
      tp = NormalizeDouble(
         bid - InpTakeProfit * _Point,
         _Digits
      );
   }


   //--- Send SELL order
   Print(
      "[Order] SELL | Price: ",
      DoubleToString(bid, _Digits),
      " | SL: ",
      DoubleToString(sl, _Digits),
      " | TP: ",
      DoubleToString(tp, _Digits)
   );


   if(trade.Sell(
      InpLotSize,
      _Symbol,
      bid,
      sl,
      tp,
      "Keltner Mean Reversion SELL"
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
//| Check Existing Position                                          |
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
