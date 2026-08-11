//+------------------------------------------------------------------+
//|                                                  Algometa5.mq5    |
//|                          Expert Advisor for MetaTrader 5           |
//|                                                                    |
//|  EA Algometa5 - Advanced Algorithmic Trading System               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://github.com/aitechlko-source"
#property version   "1.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
// ENUMERATIONS
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1,
   SIGNAL_NEUTRAL = 0
};

//+------------------------------------------------------------------+
// INPUT PARAMETERS
//+------------------------------------------------------------------+

// Trading Settings
input double   InpLotSize           = 0.1;           // Lot Size
input double   InpRiskPercent        = 2.0;           // Risk Percent per Trade
input int      InpStopLossPoints     = 100;          // Stop Loss in Points
input int      InpTakeProfitPoints   = 200;          // Take Profit in Points
input bool     InpUseTrailingStop    = true;         // Use Trailing Stop
input int      InpTrailingStopPoints = 50;           // Trailing Stop Distance

// Moving Average Settings
input int      InpMA_Fast_Period     = 12;           // Fast MA Period
input int      InpMA_Slow_Period     = 26;           // Slow MA Period
input ENUM_MA_METHOD InpMA_Method    = MODE_EMA;    // MA Method

// RSI Settings
input int      InpRSI_Period         = 14;           // RSI Period
input double   InpRSI_Overbought     = 70;           // RSI Overbought Level
input double   InpRSI_Oversold       = 30;           // RSI Oversold Level

// Strategy Settings
input bool     InpUseTrendFilter     = true;         // Use Trend Filter
input bool     InpUseRSIFilter       = true;         // Use RSI Filter
input int      InpMaxOpenPositions   = 3;            // Maximum Open Positions
input bool     InpCloseAllOnWeekend  = true;         // Close All on Weekend

// Time Settings
input int      InpStartHour          = 0;            // Start Trading Hour (0-23)
input int      InpEndHour            = 23;           // End Trading Hour (0-23)

//+------------------------------------------------------------------+
// GLOBAL VARIABLES
//+------------------------------------------------------------------+

CTrade          trade;                               // Trade object
CPositionInfo   posInfo;                             // Position info object
CSymbolInfo     symbolInfo;                          // Symbol info object

int             handleMA_Fast = INVALID_HANDLE;      // Fast MA handle
int             handleMA_Slow = INVALID_HANDLE;      // Slow MA handle
int             handleRSI     = INVALID_HANDLE;      // RSI handle

double          bufferMA_Fast[];                     // Fast MA buffer
double          bufferMA_Slow[];                     // Slow MA buffer
double          bufferRSI[];                         // RSI buffer

int             lastSignalBar  = -1;                 // Last signal bar
ENUM_SIGNAL_TYPE lastSignal   = SIGNAL_NEUTRAL;     // Last signal type

//+------------------------------------------------------------------+
// EXPERT ADVISOR INITIALIZATION
//+------------------------------------------------------------------+

int OnInit()
{
   // Set magic number
   trade.SetExpertMagicNumber(123456);
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Error: Cannot initialize symbol info");
      return INIT_FAILED;
   }
   
   // Create Moving Average handles
   handleMA_Fast = iMA(_Symbol, _Period, InpMA_Fast_Period, 0, InpMA_Method, PRICE_CLOSE);
   if(handleMA_Fast == INVALID_HANDLE)
   {
      Print("Error: Cannot create Fast MA handle");
      return INIT_FAILED;
   }
   
   handleMA_Slow = iMA(_Symbol, _Period, InpMA_Slow_Period, 0, InpMA_Method, PRICE_CLOSE);
   if(handleMA_Slow == INVALID_HANDLE)
   {
      Print("Error: Cannot create Slow MA handle");
      handleMA_Fast = INVALID_HANDLE;
      return INIT_FAILED;
   }
   
   // Create RSI handle
   handleRSI = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
   if(handleRSI == INVALID_HANDLE)
   {
      Print("Error: Cannot create RSI handle");
      handleMA_Fast = INVALID_HANDLE;
      handleMA_Slow = INVALID_HANDLE;
      return INIT_FAILED;
   }
   
   Print("EA Algometa5 initialized successfully");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// EXPERT ADVISOR DEINITIALIZATION
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleMA_Fast != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA_Fast);
      handleMA_Fast = INVALID_HANDLE;
   }
   
   if(handleMA_Slow != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA_Slow);
      handleMA_Slow = INVALID_HANDLE;
   }
   
   if(handleRSI != INVALID_HANDLE)
   {
      IndicatorRelease(handleRSI);
      handleRSI = INVALID_HANDLE;
   }
   
   Print("EA Algometa5 deinitialized");
}

//+------------------------------------------------------------------+
// TICK PROCESSING
//+------------------------------------------------------------------+

void OnTick()
{
   // Check if we're within trading hours
   if(!IsWithinTradingHours())
      return;
   
   // Close all positions on weekend if enabled
   if(InpCloseAllOnWeekend && IsWeekend())
   {
      CloseAllPositions();
      return;
   }
   
   // Update indicator values
   if(!UpdateIndicators())
      return;
   
   // Generate trading signal
   ENUM_SIGNAL_TYPE signal = GenerateSignal();
   
   // Execute trading logic
   if(signal == SIGNAL_BUY)
   {
      ExecuteBuySignal();
   }
   else if(signal == SIGNAL_SELL)
   {
      ExecuteSellSignal();
   }
   
   // Manage open positions
   ManagePositions();
}

//+------------------------------------------------------------------+
// UPDATE INDICATORS
//+------------------------------------------------------------------+

bool UpdateIndicators()
{
   // Resize buffers
   ArraySetAsSeries(bufferMA_Fast, true);
   ArraySetAsSeries(bufferMA_Slow, true);
   ArraySetAsSeries(bufferRSI, true);
   
   // Copy data
   if(CopyBuffer(handleMA_Fast, 0, 0, 3, bufferMA_Fast) < 3)
      return false;
   
   if(CopyBuffer(handleMA_Slow, 0, 0, 3, bufferMA_Slow) < 3)
      return false;
   
   if(CopyBuffer(handleRSI, 0, 0, 3, bufferRSI) < 3)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
// GENERATE TRADING SIGNAL
//+------------------------------------------------------------------+

ENUM_SIGNAL_TYPE GenerateSignal()
{
   // Avoid multiple signals on same bar
   if(lastSignalBar == iBarShift(_Symbol, _Period, TimeCurrent()))
      return SIGNAL_NEUTRAL;
   
   // Trend Filter
   bool trendUp = bufferMA_Fast[0] > bufferMA_Slow[0];
   bool trendDown = bufferMA_Fast[0] < bufferMA_Slow[0];
   
   if(InpUseTrendFilter)
   {
      if(!trendUp && !trendDown)
         return SIGNAL_NEUTRAL;
   }
   
   // RSI Filter
   bool rsiOversold = bufferRSI[0] < InpRSI_Oversold;
   bool rsiOverbought = bufferRSI[0] > InpRSI_Overbought;
   
   // BUY Signal: Fast MA above Slow MA + RSI Oversold
   if(trendUp && (!InpUseRSIFilter || rsiOversold))
   {
      if(bufferMA_Fast[1] <= bufferMA_Slow[1] && bufferMA_Fast[0] > bufferMA_Slow[0])
      {
         lastSignalBar = iBarShift(_Symbol, _Period, TimeCurrent());
         lastSignal = SIGNAL_BUY;
         return SIGNAL_BUY;
      }
   }
   
   // SELL Signal: Fast MA below Slow MA + RSI Overbought
   if(trendDown && (!InpUseRSIFilter || rsiOverbought))
   {
      if(bufferMA_Fast[1] >= bufferMA_Slow[1] && bufferMA_Fast[0] < bufferMA_Slow[0])
      {
         lastSignalBar = iBarShift(_Symbol, _Period, TimeCurrent());
         lastSignal = SIGNAL_SELL;
         return SIGNAL_SELL;
      }
   }
   
   return SIGNAL_NEUTRAL;
}

//+------------------------------------------------------------------+
// EXECUTE BUY SIGNAL
//+------------------------------------------------------------------+

void ExecuteBuySignal()
{
   // Check if we already have positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;
   
   // Check if we already have a BUY position
   if(PositionExists(POSITION_TYPE_BUY))
      return;
   
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double StopLoss = Bid - InpStopLossPoints * symbolInfo.Point();
   double TakeProfit = Ask + InpTakeProfitPoints * symbolInfo.Point();
   
   if(trade.Buy(InpLotSize, _Symbol, Ask, StopLoss, TakeProfit, "Algometa5 BUY"))
   {
      Print("BUY Order Placed - Ask: ", Ask, " SL: ", StopLoss, " TP: ", TakeProfit);
   }
   else
   {
      Print("BUY Order Failed - Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
// EXECUTE SELL SIGNAL
//+------------------------------------------------------------------+

void ExecuteSellSignal()
{
   // Check if we already have positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;
   
   // Check if we already have a SELL position
   if(PositionExists(POSITION_TYPE_SELL))
      return;
   
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double StopLoss = Ask + InpStopLossPoints * symbolInfo.Point();
   double TakeProfit = Bid - InpTakeProfitPoints * symbolInfo.Point();
   
   if(trade.Sell(InpLotSize, _Symbol, Bid, StopLoss, TakeProfit, "Algometa5 SELL"))
   {
      Print("SELL Order Placed - Bid: ", Bid, " SL: ", StopLoss, " TP: ", TakeProfit);
   }
   else
   {
      Print("SELL Order Failed - Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
// MANAGE OPEN POSITIONS
//+------------------------------------------------------------------+

void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i))
         continue;
      
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != trade.GetMagicNumber())
         continue;
      
      // Apply Trailing Stop
      if(InpUseTrailingStop)
      {
         ApplyTrailingStop(posInfo.Ticket());
      }
   }
}

//+------------------------------------------------------------------+
// APPLY TRAILING STOP
//+------------------------------------------------------------------+

void ApplyTrailingStop(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket))
      return;
   
   double currentSL = posInfo.StopLoss();
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = Bid - InpTrailingStopPoints * symbolInfo.Point();
      if(newSL > currentSL)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
   else if(posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double newSL = Ask + InpTrailingStopPoints * symbolInfo.Point();
      if(newSL < currentSL || currentSL == 0)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
// UTILITY FUNCTIONS
//+------------------------------------------------------------------+

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == trade.GetMagicNumber())
            count++;
      }
   }
   return count;
}

bool PositionExists(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && 
            posInfo.Magic() == trade.GetMagicNumber() &&
            posInfo.PositionType() == posType)
            return true;
      }
   }
   return false;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == trade.GetMagicNumber())
         {
            trade.PositionClose(posInfo.Ticket());
         }
      }
   }
}

bool IsWithinTradingHours()
{
   int currentHour = Hour();
   return (currentHour >= InpStartHour && currentHour <= InpEndHour);
}

bool IsWeekend()
{
   int dayOfWeek = DayOfWeek();
   return (dayOfWeek == 0 || dayOfWeek == 6); // Sunday or Saturday
}

//+------------------------------------------------------------------+
