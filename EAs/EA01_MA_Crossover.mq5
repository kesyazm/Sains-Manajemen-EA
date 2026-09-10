//+------------------------------------------------------------------+
//|                                      EA01_MA_Crossover.mq5        |
//|                                  Copyright 2026, Kesya Izumi      |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Kesya Izumi"
#property link      "https://mql5.com"
#property version   "1.00"
#property description "MT5 Moving Average Crossover Expert Advisor."

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "--- Moving Average Settings ---"
input int                  InpFastMAPeriod   = 20;            // Fast MA Period
input ENUM_MA_METHOD       InpFastMAMethod   = MODE_SMA;      // Fast MA Method
input ENUM_APPLIED_PRICE   InpFastMAPrice    = PRICE_CLOSE;   // Fast MA Applied Price

input int                  InpSlowMAPeriod   = 200;           // Slow MA Period
input ENUM_MA_METHOD       InpSlowMAMethod   = MODE_SMA;      // Slow MA Method
input ENUM_APPLIED_PRICE   InpSlowMAPrice    = PRICE_CLOSE;   // Slow MA Applied Price

input group "--- Trade & Risk Management ---"
input double               InpLotSize        = 0.1;            // Trade Lot Size
input ulong                InpStopLoss       = 1000;           // Stop Loss (points)
input ulong                InpTakeProfit     = 1000;           // Take Profit (points)

input group "--- Execution & Logic ---"
input bool                 InpAllowBuy       = true;           // Allow Buy Trades
input bool                 InpAllowSell      = true;           // Allow Sell Trades
input bool                 InpCloseOpposite  = true;           // Close Opposite Position
input bool                 InpMaxOnePerDir   = true;           // Max One Position Per Direction

input group "--- EA Identification ---"
input ulong                InpMagicNumber    = 123456;         // EA Magic Number

//--- Global Variables
CTrade   trade;
int      handleFastMA = INVALID_HANDLE;
int      handleSlowMA = INVALID_HANDLE;
datetime lastBarTime  = 0;


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parameter Validation
   if(InpFastMAPeriod <= 0 || InpSlowMAPeriod <= 0)
   {
      Print("[Error] MA Periods must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpFastMAPeriod >= InpSlowMAPeriod)
   {
      Print("[Error] Fast MA Period must be smaller than Slow MA Period.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Validate lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[Error] Lot size ", InpLotSize,
            " is outside allowed limits [", minLot,
            ", ", maxLot, "].");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();

   //--- Create MA indicator handles
   handleFastMA = iMA(
      _Symbol,
      _Period,
      InpFastMAPeriod,
      0,
      InpFastMAMethod,
      InpFastMAPrice
   );

   handleSlowMA = iMA(
      _Symbol,
      _Period,
      InpSlowMAPeriod,
      0,
      InpSlowMAMethod,
      InpSlowMAPrice
   );

   //--- Validate handles
   if(handleFastMA == INVALID_HANDLE ||
      handleSlowMA == INVALID_HANDLE)
   {
      Print("[Error] Failed to initialize indicator handles.");
      return(INIT_FAILED);
   }

   lastBarTime = 0;

   Print("[Init] Moving Average Crossover EA loaded successfully.");
   Print("[Init] Magic Number: ", InpMagicNumber);

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFastMA != INVALID_HANDLE)
      IndicatorRelease(handleFastMA);

   if(handleSlowMA != INVALID_HANDLE)
      IndicatorRelease(handleSlowMA);

   Print("[Deinit] EA removed. Reason code: ", reason);
}


//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Detect new candle
   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime == lastBarTime)
      return;

   //--- MA arrays
   double fastMA[2];
   double slowMA[2];

   //--- Copy MA values from closed candles
   //--- shift 1 = latest closed candle
   //--- shift 2 = previous closed candle
   if(CopyBuffer(handleFastMA, 0, 1, 2, fastMA) < 2 ||
      CopyBuffer(handleSlowMA, 0, 1, 2, slowMA) < 2)
   {
      Print("[Warning] Failed to copy indicator buffer values.");
      return;
   }

   //--- IMPORTANT:
   //--- fastMA[0] = older closed candle
   //--- fastMA[1] = latest closed candle
   //--- slowMA[0] = older closed candle
   //--- slowMA[1] = latest closed candle

   double fastPrev = fastMA[0];
   double fastCurr = fastMA[1];

   double slowPrev = slowMA[0];
   double slowCurr = slowMA[1];

   //--- Detect crossover
   bool buySignal =
      (fastPrev <= slowPrev) &&
      (fastCurr > slowCurr);

   bool sellSignal =
      (fastPrev >= slowPrev) &&
      (fastCurr < slowCurr);

   //--- BUY signal
   if(buySignal)
   {
      Print(
         "[Signal] BUY Crossover detected. ",
         "Fast MA: ", fastCurr,
         " > Slow MA: ", slowCurr
      );

      ExecuteBuySignal();
      lastBarTime = currentBarTime;
   }

   //--- SELL signal
   else if(sellSignal)
   {
      Print(
         "[Signal] SELL Crossover detected. ",
         "Fast MA: ", fastCurr,
         " < Slow MA: ", slowCurr
      );

      ExecuteSellSignal();
      lastBarTime = currentBarTime;
   }

   //--- No signal: update bar time anyway
   else
   {
      lastBarTime = currentBarTime;
   }
}


//+------------------------------------------------------------------+
//| Execute Buy Logic                                                |
//+------------------------------------------------------------------+
void ExecuteBuySignal()
{
   int buyPositions  = 0;
   int sellPositions = 0;

   CountPositions(buyPositions, sellPositions);

   //--- Close opposite SELL positions
   if(InpCloseOpposite && sellPositions > 0)
   {
      Print(
         "[Action] Closing ",
         sellPositions,
         " opposite SELL position(s)."
      );

      ClosePositionsByType(POSITION_TYPE_SELL);
   }

   //--- Check whether BUY is allowed
   if(!InpAllowBuy)
   {
      Print("[Info] BUY skipped: InpAllowBuy is false.");
      return;
   }

   //--- Maximum one BUY position
   if(InpMaxOnePerDir && buyPositions > 0)
   {
      Print(
         "[Info] BUY skipped: Maximum one BUY position rule active."
      );

      return;
   }

   //--- Get ASK price
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- Calculate SL and TP
   double sl = 0;
   double tp = 0;

   if(InpStopLoss > 0)
      sl = NormalizeDouble(
         ask - InpStopLoss * _Point,
         _Digits
      );

   if(InpTakeProfit > 0)
      tp = NormalizeDouble(
         ask + InpTakeProfit * _Point,
         _Digits
      );

   //--- Send BUY order
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
      ask,
      sl,
      tp,
      "MA Crossover Buy"
   ))
   {
      Print(
         "[Success] BUY order executed. Ticket: ",
         trade.ResultOrder()
      );
   }
   else
   {
      Print(
         "[Error] BUY order failed. Return code: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );
   }
}


//+------------------------------------------------------------------+
//| Execute Sell Logic                                               |
//+------------------------------------------------------------------+
void ExecuteSellSignal()
{
   int buyPositions  = 0;
   int sellPositions = 0;

   CountPositions(buyPositions, sellPositions);

   //--- Close opposite BUY positions
   if(InpCloseOpposite && buyPositions > 0)
   {
      Print(
         "[Action] Closing ",
         buyPositions,
         " opposite BUY position(s)."
      );

      ClosePositionsByType(POSITION_TYPE_BUY);
   }

   //--- Check whether SELL is allowed
   if(!InpAllowSell)
   {
      Print("[Info] SELL skipped: InpAllowSell is false.");
      return;
   }

   //--- Maximum one SELL position
   if(InpMaxOnePerDir && sellPositions > 0)
   {
      Print(
         "[Info] SELL skipped: Maximum one SELL position rule active."
      );

      return;
   }

   //--- Get BID price
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Calculate SL and TP
   double sl = 0;
   double tp = 0;

   if(InpStopLoss > 0)
      sl = NormalizeDouble(
         bid + InpStopLoss * _Point,
         _Digits
      );

   if(InpTakeProfit > 0)
      tp = NormalizeDouble(
         bid - InpTakeProfit * _Point,
         _Digits
      );

   //--- Send SELL order
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
      bid,
      sl,
      tp,
      "MA Crossover Sell"
   ))
   {
      Print(
         "[Success] SELL order executed. Ticket: ",
         trade.ResultOrder()
      );
   }
   else
   {
      Print(
         "[Error] SELL order failed. Return code: ",
         trade.ResultRetcode(),
         " - ",
         trade.ResultRetcodeDescription()
      );
   }
}


//+------------------------------------------------------------------+
//| Count active positions for this EA                                |
//+------------------------------------------------------------------+
void CountPositions(
   int &buyCount,
   int &sellCount
)
{
   buyCount  = 0;
   sellCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0)
      {
         if(
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber
         )
         {
            ENUM_POSITION_TYPE posType =
               (ENUM_POSITION_TYPE)
               PositionGetInteger(POSITION_TYPE);

            if(posType == POSITION_TYPE_BUY)
               buyCount++;

            if(posType == POSITION_TYPE_SELL)
               sellCount++;
         }
      }
   }
}


//+------------------------------------------------------------------+
//| Close positions by type                                           |
//+------------------------------------------------------------------+
void ClosePositionsByType(
   ENUM_POSITION_TYPE typeToClose
)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket > 0)
      {
         if(
            PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == typeToClose
         )
         {
            if(!trade.PositionClose(ticket))
            {
               Print(
                  "[Error] Failed to close position #",
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
