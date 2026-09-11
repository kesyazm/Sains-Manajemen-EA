//+------------------------------------------------------------------+
//|                                           IchimokuATR_YouTube.mq5 |
//|                                  Copyright 2026, Gemini Notebook |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Ichimoku Crossover dengan ATR Take Profit & Stop Loss berdasarkan tutorial René Balke."

#include <Trade\Trade.mqh>

//--- Ichimoku Settings
input group "--- Ichimoku Indicator Settings ---"
input ENUM_TIMEFRAMES InpIchiTimeframe     = PERIOD_H1;
input int             InpTenkanPeriod      = 9;
input int             InpKijunPeriod       = 26;
input int             InpSenkouSpanBPeriod = 52;

//--- ATR Settings
input group "--- ATR Indicator Settings ---"
input ENUM_TIMEFRAMES InpATRTimeframe      = PERIOD_D1;
input int             InpATRPeriod         = 14;
input double          InpATRSLFactor       = 1.0;
input double          InpATRTPFactor       = 1.0;

//--- Trade Settings
input group "--- Trade Settings ---"
input double          InpLotSize           = 0.1;
input ulong            InpMagicNumber       = 445566;

//--- Global Variables
CTrade   trade;
int      handleIchimoku = INVALID_HANDLE;
int      handleATR      = INVALID_HANDLE;
datetime lastBarTime    = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate parameters
   if(InpTenkanPeriod <= 0 ||
      InpKijunPeriod <= 0 ||
      InpSenkouSpanBPeriod <= 0 ||
      InpATRPeriod <= 0)
   {
      Print("[Error] Periode indikator harus lebih besar dari nol.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Validate lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[Error] Lot size berada di luar batas izin broker.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Setup trade
   trade.SetExpertMagicNumber(InpMagicNumber);

   //===============================================================
   // ICHIMOKU
   //===============================================================
   handleIchimoku = iIchimoku(
      _Symbol,
      InpIchiTimeframe,
      InpTenkanPeriod,
      InpKijunPeriod,
      InpSenkouSpanBPeriod
   );

   if(handleIchimoku == INVALID_HANDLE)
   {
      Print("[Error] Gagal membuat handle Ichimoku.");
      return(INIT_FAILED);
   }

   //===============================================================
   // ATR
   //===============================================================
   handleATR = iATR(
      _Symbol,
      InpATRTimeframe,
      InpATRPeriod
   );

   if(handleATR == INVALID_HANDLE)
   {
      Print("[Error] Gagal membuat handle ATR.");
      return(INIT_FAILED);
   }

   Print("[Init] EA Ichimoku ATR berhasil diinisialisasi.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleIchimoku != INVALID_HANDLE)
      IndicatorRelease(handleIchimoku);

   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);

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
   datetime currentBarTime =
      iTime(_Symbol, InpIchiTimeframe, 0);

   if(currentBarTime <= 0)
      return;

   if(currentBarTime == lastBarTime)
      return;

   // Update immediately
   lastBarTime = currentBarTime;

   //===============================================================
   // 2. GET ICHIMOKU DATA
   //===============================================================
   // iIchimoku buffer:
   // 0 = Tenkan-sen
   // 1 = Kijun-sen
   // 2 = Senkou Span A
   // 3 = Senkou Span B
   // 4 = Chikou Span
   //
   // Kita menggunakan buffer 0 dan 1.

   double tenkanBuffer[2];
   double kijunBuffer[2];

   if(CopyBuffer(
      handleIchimoku,
      0,
      1,
      2,
      tenkanBuffer
   ) != 2)
   {
      Print("[Warning] Gagal mengambil data Tenkan-sen.");
      return;
   }

   if(CopyBuffer(
      handleIchimoku,
      1,
      1,
      2,
      kijunBuffer
   ) != 2)
   {
      Print("[Warning] Gagal mengambil data Kijun-sen.");
      return;
   }

   //--- CopyBuffer start = 1, count = 2
   //--- [0] = bar 2
   //--- [1] = bar 1 / latest closed bar

   double tenkanPrev = tenkanBuffer[0];
   double tenkanCurr = tenkanBuffer[1];

   double kijunPrev = kijunBuffer[0];
   double kijunCurr = kijunBuffer[1];

   //===============================================================
   // 3. DETECT CROSSOVER
   //===============================================================
   bool buySignal =
      (tenkanPrev <= kijunPrev) &&
      (tenkanCurr > kijunCurr);

   bool sellSignal =
      (tenkanPrev >= kijunPrev) &&
      (tenkanCurr < kijunCurr);

   if(!buySignal && !sellSignal)
      return;

   //===============================================================
   // 4. GET ATR
   //===============================================================
   double atrBuffer[1];

   if(CopyBuffer(
      handleATR,
      0,
      1,
      1,
      atrBuffer
   ) != 1)
   {
      Print("[Warning] Gagal mengambil data ATR.");
      return;
   }

   double currentATR = atrBuffer[0];

   if(currentATR <= 0)
      return;

   //===============================================================
   // 5. GET CURRENT PRICE
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
   // 6. BUY
   //===============================================================
   if(buySignal)
   {
      double sl =
         NormalizeDouble(
            ask - (currentATR * InpATRSLFactor),
            _Digits
         );

      double tp =
         NormalizeDouble(
            ask + (currentATR * InpATRTPFactor),
            _Digits
         );

      Print(
         "[Signal] BUY Ichimoku Crossover | ",
         "Ask: ", ask,
         " | Tenkan: ", tenkanCurr,
         " | Kijun: ", kijunCurr,
         " | ATR: ", currentATR,
         " | SL: ", sl,
         " | TP: ", tp
      );

      if(trade.Buy(
         InpLotSize,
         _Symbol,
         0,
         sl,
         tp,
         "Ichimoku Buy"
      ))
      {
         Print(
            "[Success] Order BUY berhasil. Ticket: ",
            trade.ResultOrder()
         );
      }
      else
      {
         Print(
            "[Error] Order BUY gagal: ",
            trade.ResultRetcodeDescription()
         );
      }
   }

   //===============================================================
   // 7. SELL
   //===============================================================
   else if(sellSignal)
   {
      double sl =
         NormalizeDouble(
            bid + (currentATR * InpATRSLFactor),
            _Digits
         );

      double tp =
         NormalizeDouble(
            bid - (currentATR * InpATRTPFactor),
            _Digits
         );

      Print(
         "[Signal] SELL Ichimoku Crossover | ",
         "Bid: ", bid,
         " | Tenkan: ", tenkanCurr,
         " | Kijun: ", kijunCurr,
         " | ATR: ", currentATR,
         " | SL: ", sl,
         " | TP: ", tp
      );

      if(trade.Sell(
         InpLotSize,
         _Symbol,
         0,
         sl,
         tp,
         "Ichimoku Sell"
      ))
      {
         Print(
            "[Success] Order SELL berhasil. Ticket: ",
            trade.ResultOrder()
         );
      }
      else
      {
         Print(
            "[Error] Order SELL gagal: ",
            trade.ResultRetcodeDescription()
         );
      }
   }
}
//+------------------------------------------------------------------+
