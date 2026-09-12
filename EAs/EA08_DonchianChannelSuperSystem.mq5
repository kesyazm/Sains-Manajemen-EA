//+------------------------------------------------------------------+
//|                                    DonchianChannelSuperSystem.mq5|
//|                                  Copyright 2026, Gemini Notebook |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Gemini Notebook"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "EA Donchian Channel Super System berdasarkan tutorial René Balke (Part 1)."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Donchian Channel Settings ---"
input string               InpIndicatorPath  = "donkey channel.ex5";
input int                  InpCandlesPeriod  = 20;

input group "--- Risk & Trade Settings ---"
input double               InpLotSize        = 0.1;
input ulong                InpMagicNumber    = 123999;

//--- Global Variables
CTrade trade;
int    handleDC = INVALID_HANDLE;
ulong  positionTicket = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter validation
   if(InpCandlesPeriod <= 0)
   {
      Print(
         "[Error] Periode Donchian Channel harus lebih besar dari nol."
      );

      return(INIT_PARAMETERS_INCORRECT);
   }

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
         "[Error] Lot size di luar batas izin broker."
      );

      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Setup Magic Number
   trade.SetExpertMagicNumber(InpMagicNumber);

   //--- Initialize Donchian Channel
   handleDC = iCustom(
      _Symbol,
      PERIOD_CURRENT,
      InpIndicatorPath,
      InpCandlesPeriod
   );

   if(handleDC == INVALID_HANDLE)
   {
      Print(
         "[Error] Gagal membuat handle indikator Donchian Channel: ",
         InpIndicatorPath
      );

      return(INIT_FAILED);
   }

   positionTicket = 0;

   Print(
      "[Init] EA Donchian Channel Super System berhasil diinisialisasi."
   );

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleDC != INVALID_HANDLE)
      IndicatorRelease(handleDC);

   Print(
      "[Deinit] EA dihentikan. Reason code: ",
      reason
   );
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //===============================================================
// 1. COPY DONCHIAN CHANNEL
//===============================================================

// Buffer:
// 0 = Upper Line
// 1 = Lower Line

double upperBuffer[1];
double lowerBuffer[1];

if(CopyBuffer(
   handleDC,
   0,
   0,
   1,
   upperBuffer
) < 1)
{
   return;
}

if(CopyBuffer(
   handleDC,
   1,
   0,
   1,
   lowerBuffer
) < 1)
{
   return;
}

//--- Convert array to scalar
double dcUpper = upperBuffer[0];
double dcLower = lowerBuffer[0];
   //===============================================================
   // 2. CURRENT PRICE
   //===============================================================

   double bid = SymbolInfoDouble(
      _Symbol,
      SYMBOL_BID
   );

   double ask = SymbolInfoDouble(
      _Symbol,
      SYMBOL_ASK
   );

   if(bid <= 0 || ask <= 0)
      return;

   //===============================================================
   // 3. BUY SIGNAL
   //===============================================================

   if(bid >= dcUpper)
   {
      //--- Close SELL position
      if(positionTicket > 0)
      {
         if(PositionSelectByTicket(positionTicket))
         {
            ENUM_POSITION_TYPE positionType =
               (ENUM_POSITION_TYPE)PositionGetInteger(
                  POSITION_TYPE
               );

            if(positionType == POSITION_TYPE_SELL)
            {
               if(trade.PositionClose(positionTicket))
               {
                  Print(
                     "[Close] Posisi SELL #",
                     positionTicket,
                     " berhasil ditutup pada sinyal BUY."
                  );

                  positionTicket = 0;
               }
            }
         }
         else
         {
            // Ticket sudah tidak valid
            positionTicket = 0;
         }
      }

      //--- Open BUY
      if(positionTicket <= 0)
      {
         Print(
            "[Signal] BUY terdeteksi. Bid: ",
            bid,
            " >= DC Upper: ",
            dcUpper
         );

         if(trade.Buy(
            InpLotSize,
            _Symbol,
            0,
            0,
            0,
            "Donchian Buy"
         ))
         {
            positionTicket = trade.ResultOrder();

            Print(
               "[Success] Posisi BUY berhasil dibuka. ",
               "Order Ticket: ",
               positionTicket
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
   }

   //===============================================================
   // 4. SELL SIGNAL
   //===============================================================

   else if(bid <= dcLower)
   {
      //--- Close BUY position
      if(positionTicket > 0)
      {
         if(PositionSelectByTicket(positionTicket))
         {
            ENUM_POSITION_TYPE positionType =
               (ENUM_POSITION_TYPE)PositionGetInteger(
                  POSITION_TYPE
               );

            if(positionType == POSITION_TYPE_BUY)
            {
               if(trade.PositionClose(positionTicket))
               {
                  Print(
                     "[Close] Posisi BUY #",
                     positionTicket,
                     " berhasil ditutup pada sinyal SELL."
                  );

                  positionTicket = 0;
               }
            }
         }
         else
         {
            // Ticket sudah tidak valid
            positionTicket = 0;
         }
      }

      //--- Open SELL
      if(positionTicket <= 0)
      {
         Print(
            "[Signal] SELL terdeteksi. Bid: ",
            bid,
            " <= DC Lower: ",
            dcLower
         );

         if(trade.Sell(
            InpLotSize,
            _Symbol,
            0,
            0,
            0,
            "Donchian Sell"
         ))
         {
            positionTicket = trade.ResultOrder();

            Print(
               "[Success] Posisi SELL berhasil dibuka. ",
               "Order Ticket: ",
               positionTicket
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

   //===============================================================
   // 5. CHART STATUS
   //===============================================================

   Comment(
      "Position Ticket: ",
      positionTicket,
      "\nDonchian Upper: ",
      dcUpper,
      "\nDonchian Lower: ",
      dcLower
   );
}
//+------------------------------------------------------------------+
