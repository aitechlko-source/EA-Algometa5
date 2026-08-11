//+------------------------------------------------------------------+
//|                    Zefinx_GoldQueen_EA_MT5_V12_WE.mq5             |
//|                          Expert Advisor for MetaTrader 5           |
//|                                                                    |
//|  Zefinx Gold Queen EA - Advanced Gold Trading System              |
//|  Version: 12 (Weekend Edition)                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026 - Zefinx Trading Systems"
#property link      "https://github.com/aitechlko-source"
#property version   "12.0"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
// ENUMERATIONS
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1,
   SIGNAL_NEUTRAL = 0
};

enum ENUM_MARKET_CONDITION
{
   TREND_UP = 1,
   TREND_DOWN = -1,
   TREND_NEUTRAL = 0
};

//+------------------------------------------------------------------+
// INPUT PARAMETERS
//+------------------------------------------------------------------+

// Account & Position Management
input double   InpLotSize              = 0.1;           // Base Lot Size
input double   InpRiskPercent          = 2.0;           // Risk % per Trade
input int      InpStopLossPoints       = 150;           // Stop Loss in Points
input int      InpTakeProfitPoints     = 300;           // Take Profit in Points
input bool     InpUseTrailingStop      = true;          // Use Trailing Stop
input int      InpTrailingStopPoints   = 75;            // Trailing Stop Distance

// Moving Average Settings
input int      InpMA_Fast_Period       = 9;             // Fast MA Period
input int      InpMA_Slow_Period       = 21;            // Slow MA Period
input int      InpMA_Signal_Period     = 5;             // Signal MA Period
input ENUM_MA_METHOD InpMA_Method      = MODE_EMA;      // MA Method

// RSI Settings
input int      InpRSI_Period           = 14;            // RSI Period
input double   InpRSI_Overbought       = 70;            // RSI Overbought Level
input double   InpRSI_Oversold         = 30;            // RSI Oversold Level

// MACD Settings
input int      InpMACD_Fast            = 12;            // MACD Fast EMA
input int      InpMACD_Slow            = 26;            // MACD Slow EMA
input int      InpMACD_Signal          = 9;             // MACD Signal Line

// Bollinger Bands Settings
input int      InpBB_Period            = 20;            // BB Period
input double   InpBB_StdDev            = 2.0;           // BB Standard Deviation

// Strategy Settings
input bool     InpUseTrendFilter       = true;          // Use Trend Filter
input bool     InpUseRSIFilter         = true;          // Use RSI Filter
input bool     InpUseVolatilityFilter  = true;          // Use Volatility Filter
input int      InpMaxOpenPositions     = 5;             // Maximum Open Positions
input bool     InpCloseAllOnWeekend    = true;          // Close All Positions on Weekend
input bool     InpUsePartialClose      = true;          // Use Partial Profit Taking
input double   InpPartialClosePercent  = 50.0;          // Partial Close Percent

// Time & Session Settings
input int      InpStartHour            = 1;             // Start Trading Hour (0-23)
input int      InpEndHour              = 22;            // End Trading Hour (0-23)
input bool     InpTradeOnWeekends      = false;         // Trade on Weekends
input bool     InpUseNews              = false;         // Avoid News Times

// Advanced Settings
input bool     InpUseMoneyManagement   = true;          // Use Dynamic Money Management
input double   InpMaxDrawdown          = 5.0;           // Max Drawdown % to Stop Trading
input int      InpMaxConsecutiveLosses = 5;             // Max Consecutive Losses
input bool     InpDebugMode            = false;         // Enable Debug Mode

//+------------------------------------------------------------------+
// GLOBAL VARIABLES
//+------------------------------------------------------------------+

CTrade          trade;                                  // Trade object
CPositionInfo   posInfo;                                // Position info object
COrderInfo      orderInfo;                              // Order info object
CSymbolInfo     symbolInfo;                             // Symbol info object

int             handleMA_Fast       = INVALID_HANDLE;   // Fast MA handle
int             handleMA_Slow       = INVALID_HANDLE;   // Slow MA handle
int             handleMA_Signal     = INVALID_HANDLE;   // Signal MA handle
int             handleRSI           = INVALID_HANDLE;   // RSI handle
int             handleMACD          = INVALID_HANDLE;   // MACD handle
int             handleBB            = INVALID_HANDLE;   // Bollinger Bands handle
int             handleATR           = INVALID_HANDLE;   // ATR handle

double          bufferMA_Fast[];                        // Fast MA buffer
double          bufferMA_Slow[];                        // Slow MA buffer
double          bufferMA_Signal[];                      // Signal MA buffer
double          bufferRSI[];                            // RSI buffer
double          bufferMACD_Main[];                      // MACD Main buffer
double          bufferMACD_Signal[];                    // MACD Signal buffer
double          bufferMACD_Hist[];                      // MACD Histogram buffer
double          bufferBB_Upper[];                       // BB Upper buffer
double          bufferBB_Lower[];                       // BB Lower buffer
double          bufferBB_Middle[];                      // BB Middle buffer
double          bufferATR[];                            // ATR buffer

int             lastSignalBar       = -1;               // Last signal bar
ENUM_SIGNAL_TYPE lastSignal         = SIGNAL_NEUTRAL;  // Last signal type

int             consecutiveLosses   = 0;               // Consecutive losses counter
double          accountBalance      = 0.0;             // Initial account balance
double          highestBalance      = 0.0;             // Highest balance for drawdown calc

//+------------------------------------------------------------------+
// EXPERT ADVISOR INITIALIZATION
//+------------------------------------------------------------------+

int OnInit()
{
   // Set magic number based on EA name
   trade.SetExpertMagicNumber(112000);
   
   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("Error: Cannot initialize symbol info for ", _Symbol);
      return INIT_FAILED;
   }
   
   // Store initial balance
   accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   highestBalance = accountBalance;
   
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
      return INIT_FAILED;
   }
   
   handleMA_Signal = iMA(_Symbol, _Period, InpMA_Signal_Period, 0, InpMA_Method, PRICE_CLOSE);
   if(handleMA_Signal == INVALID_HANDLE)
   {
      Print("Error: Cannot create Signal MA handle");
      return INIT_FAILED;
   }
   
   // Create RSI handle
   handleRSI = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
   if(handleRSI == INVALID_HANDLE)
   {
      Print("Error: Cannot create RSI handle");
      return INIT_FAILED;
   }
   
   // Create MACD handle
   handleMACD = iMACD(_Symbol, _Period, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
   if(handleMACD == INVALID_HANDLE)
   {
      Print("Error: Cannot create MACD handle");
      return INIT_FAILED;
   }
   
   // Create Bollinger Bands handle
   handleBB = iBands(_Symbol, _Period, InpBB_Period, 0, InpBB_StdDev, PRICE_CLOSE);
   if(handleBB == INVALID_HANDLE)
   {
      Print("Error: Cannot create Bollinger Bands handle");
      return INIT_FAILED;
   }
   
   // Create ATR handle
   handleATR = iATR(_Symbol, _Period, 14);
   if(handleATR == INVALID_HANDLE)
   {
      Print("Error: Cannot create ATR handle");
      return INIT_FAILED;
   }
   
   Print("================================================");
   Print("Zefinx Gold Queen EA V12 WE initialized");
   Print("Symbol: ", _Symbol);
   Print("Timeframe: ", _Period);
   Print("Lot Size: ", InpLotSize);
   Print("Risk %: ", InpRiskPercent);
   Print("================================================");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// EXPERT ADVISOR DEINITIALIZATION
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   // Release all indicator handles
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
   
   if(handleMA_Signal != INVALID_HANDLE)
   {
      IndicatorRelease(handleMA_Signal);
      handleMA_Signal = INVALID_HANDLE;
   }
   
   if(handleRSI != INVALID_HANDLE)
   {
      IndicatorRelease(handleRSI);
      handleRSI = INVALID_HANDLE;
   }
   
   if(handleMACD != INVALID_HANDLE)
   {
      IndicatorRelease(handleMACD);
      handleMACD = INVALID_HANDLE;
   }
   
   if(handleBB != INVALID_HANDLE)
   {
      IndicatorRelease(handleBB);
      handleBB = INVALID_HANDLE;
   }
   
   if(handleATR != INVALID_HANDLE)
   {
      IndicatorRelease(handleATR);
      handleATR = INVALID_HANDLE;
   }
   
   Print("Zefinx Gold Queen EA V12 WE deinitialized - Reason: ", reason);
}

//+------------------------------------------------------------------+
// TICK PROCESSING
//+------------------------------------------------------------------+

void OnTick()
{
   // Check trading hours
   if(!IsWithinTradingHours())
   {
      if(InpCloseAllOnWeekend && IsWeekend())
         CloseAllPositions();
      return;
   }
   
   // Check drawdown limit
   if(!CheckDrawdownLimit())
   {
      if(InpDebugMode)
         Print("Drawdown limit exceeded. Stopping trading.");
      return;
   }
   
   // Update all indicator values
   if(!UpdateIndicators())
   {
      if(InpDebugMode)
         Print("Failed to update indicators");
      return;
   }
   
   // Analyze market condition
   ENUM_MARKET_CONDITION marketCondition = AnalyzeMarketCondition();
   
   // Generate trading signal
   ENUM_SIGNAL_TYPE signal = GenerateSignal(marketCondition);
   
   // Execute trading logic
   if(signal == SIGNAL_BUY && !PositionExists(POSITION_TYPE_BUY))
   {
      ExecuteBuySignal();
   }
   else if(signal == SIGNAL_SELL && !PositionExists(POSITION_TYPE_SELL))
   {
      ExecuteSellSignal();
   }
   
   // Manage open positions
   ManagePositions();
   
   // Update highest balance for drawdown calculation
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(currentBalance > highestBalance)
      highestBalance = currentBalance;
}

//+------------------------------------------------------------------+
// UPDATE INDICATORS
//+------------------------------------------------------------------+

bool UpdateIndicators()
{
   // Resize buffers
   ArraySetAsSeries(bufferMA_Fast, true);
   ArraySetAsSeries(bufferMA_Slow, true);
   ArraySetAsSeries(bufferMA_Signal, true);
   ArraySetAsSeries(bufferRSI, true);
   ArraySetAsSeries(bufferMACD_Main, true);
   ArraySetAsSeries(bufferMACD_Signal, true);
   ArraySetAsSeries(bufferMACD_Hist, true);
   ArraySetAsSeries(bufferBB_Upper, true);
   ArraySetAsSeries(bufferBB_Lower, true);
   ArraySetAsSeries(bufferBB_Middle, true);
   ArraySetAsSeries(bufferATR, true);
   
   // Copy indicator data
   if(CopyBuffer(handleMA_Fast, 0, 0, 3, bufferMA_Fast) < 3)
      return false;
   
   if(CopyBuffer(handleMA_Slow, 0, 0, 3, bufferMA_Slow) < 3)
      return false;
   
   if(CopyBuffer(handleMA_Signal, 0, 0, 3, bufferMA_Signal) < 3)
      return false;
   
   if(CopyBuffer(handleRSI, 0, 0, 3, bufferRSI) < 3)
      return false;
   
   if(CopyBuffer(handleMACD, 0, 0, 3, bufferMACD_Main) < 3)
      return false;
   
   if(CopyBuffer(handleMACD, 1, 0, 3, bufferMACD_Signal) < 3)
      return false;
   
   if(CopyBuffer(handleMACD, 2, 0, 3, bufferMACD_Hist) < 3)
      return false;
   
   if(CopyBuffer(handleBB, 1, 0, 3, bufferBB_Upper) < 3)
      return false;
   
   if(CopyBuffer(handleBB, 2, 0, 3, bufferBB_Lower) < 3)
      return false;
   
   if(CopyBuffer(handleBB, 0, 0, 3, bufferBB_Middle) < 3)
      return false;
   
   if(CopyBuffer(handleATR, 0, 0, 3, bufferATR) < 3)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
// ANALYZE MARKET CONDITION
//+------------------------------------------------------------------+

ENUM_MARKET_CONDITION AnalyzeMarketCondition()
{
   // Strong uptrend
   if(bufferMA_Fast[0] > bufferMA_Slow[0] && bufferMA_Slow[0] > bufferMA_Signal[0])
      return TREND_UP;
   
   // Strong downtrend
   if(bufferMA_Fast[0] < bufferMA_Slow[0] && bufferMA_Slow[0] < bufferMA_Signal[0])
      return TREND_DOWN;
   
   return TREND_NEUTRAL;
}

//+------------------------------------------------------------------+
// GENERATE TRADING SIGNAL
//+------------------------------------------------------------------+

ENUM_SIGNAL_TYPE GenerateSignal(ENUM_MARKET_CONDITION marketCondition)
{
   // Avoid multiple signals on same bar
   int currentBar = iBarShift(_Symbol, _Period, TimeCurrent());
   if(lastSignalBar == currentBar)
      return SIGNAL_NEUTRAL;
   
   // Trend Filter
   bool trendUp = bufferMA_Fast[0] > bufferMA_Slow[0];
   bool trendDown = bufferMA_Fast[0] < bufferMA_Slow[0];
   
   if(InpUseTrendFilter && marketCondition == TREND_NEUTRAL)
      return SIGNAL_NEUTRAL;
   
   // RSI Filter
   bool rsiOversold = bufferRSI[0] < InpRSI_Oversold;
   bool rsiOverbought = bufferRSI[0] > InpRSI_Overbought;
   
   // MACD confirmation
   bool macdBullish = bufferMACD_Main[0] > bufferMACD_Signal[0] && bufferMACD_Main[1] <= bufferMACD_Signal[1];
   bool macdBearish = bufferMACD_Main[0] < bufferMACD_Signal[0] && bufferMACD_Main[1] >= bufferMACD_Signal[1];
   
   // Volatility check
   double volatility = bufferBB_Upper[0] - bufferBB_Lower[0];
   bool highVolatility = (volatility > bufferATR[0] * 2);
   
   // BUY Signal
   if(trendUp && macdBullish)
   {
      if(!InpUseRSIFilter || rsiOversold)
      {
         if(!InpUseVolatilityFilter || highVolatility)
         {
            lastSignalBar = currentBar;
            lastSignal = SIGNAL_BUY;
            if(InpDebugMode)
               Print("BUY Signal Generated at Bar: ", currentBar);
            return SIGNAL_BUY;
         }
      }
   }
   
   // SELL Signal
   if(trendDown && macdBearish)
   {
      if(!InpUseRSIFilter || rsiOverbought)
      {
         if(!InpUseVolatilityFilter || highVolatility)
         {
            lastSignalBar = currentBar;
            lastSignal = SIGNAL_SELL;
            if(InpDebugMode)
               Print("SELL Signal Generated at Bar: ", currentBar);
            return SIGNAL_SELL;
         }
      }
   }
   
   return SIGNAL_NEUTRAL;
}

//+------------------------------------------------------------------+
// EXECUTE BUY SIGNAL
//+------------------------------------------------------------------+

void ExecuteBuySignal()
{
   // Check if we already have max positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;
   
   // Check consecutive losses
   if(consecutiveLosses >= InpMaxConsecutiveLosses)
      return;
   
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double StopLoss = Bid - InpStopLossPoints * symbolInfo.Point();
   double TakeProfit = Ask + InpTakeProfitPoints * symbolInfo.Point();
   
   double lotSize = CalculateLotSize();
   
   if(trade.Buy(lotSize, _Symbol, Ask, StopLoss, TakeProfit, "GoldQueen BUY"))
   {
      if(InpDebugMode)
         Print("BUY Order Placed - Ask: ", Ask, " SL: ", StopLoss, " TP: ", TakeProfit, " Lot: ", lotSize);
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
   // Check if we already have max positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;
   
   // Check consecutive losses
   if(consecutiveLosses >= InpMaxConsecutiveLosses)
      return;
   
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double StopLoss = Ask + InpStopLossPoints * symbolInfo.Point();
   double TakeProfit = Bid - InpTakeProfitPoints * symbolInfo.Point();
   
   double lotSize = CalculateLotSize();
   
   if(trade.Sell(lotSize, _Symbol, Bid, StopLoss, TakeProfit, "GoldQueen SELL"))
   {
      if(InpDebugMode)
         Print("SELL Order Placed - Bid: ", Bid, " SL: ", StopLoss, " TP: ", TakeProfit, " Lot: ", lotSize);
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
      
      // Partial profit taking
      if(InpUsePartialClose)
      {
         CheckPartialClose(posInfo.Ticket());
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
      if(newSL > currentSL && newSL > 0)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
   else if(posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double newSL = Ask + InpTrailingStopPoints * symbolInfo.Point();
      if((newSL < currentSL || currentSL == 0) && newSL > 0)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
// CHECK PARTIAL CLOSE
//+------------------------------------------------------------------+

void CheckPartialClose(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket))
      return;
   
   double profitPercent = (posInfo.Profit() / posInfo.Volume()) * 100;
   double targetProfit = InpTakeProfitPoints * symbolInfo.Point();
   double halfway = targetProfit / 2;
   
   double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double distance = MathAbs(currentPrice - posInfo.PriceOpen());
   
   if(distance >= halfway && !IsPartialClosed(ticket))
   {
      double closeVolume = posInfo.Volume() * (InpPartialClosePercent / 100);
      trade.PositionClosePartial(ticket, closeVolume);
      
      if(InpDebugMode)
         Print("Partial close executed for ticket: ", ticket);
   }
}

bool IsPartialClosed(ulong ticket)
{
   // Simple check - in production, track partial closes separately
   return false;
}

//+------------------------------------------------------------------+
// CALCULATE LOT SIZE
//+------------------------------------------------------------------+

double CalculateLotSize()
{
   if(!InpUseMoneyManagement)
      return InpLotSize;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPercent / 100);
   double pointValue = symbolInfo.TickValue();
   double pipValue = pointValue * InpStopLossPoints;
   
   double calculatedLot = riskAmount / pipValue;
   
   // Apply limits
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   calculatedLot = MathMax(calculatedLot, minLot);
   calculatedLot = MathMin(calculatedLot, maxLot);
   calculatedLot = MathFloor(calculatedLot / stepLot) * stepLot;
   
   return calculatedLot;
}

//+------------------------------------------------------------------+
// CHECK DRAWDOWN LIMIT
//+------------------------------------------------------------------+

bool CheckDrawdownLimit()
{
   if(!InpUseMoneyManagement)
      return true;
   
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = ((highestBalance - currentBalance) / highestBalance) * 100;
   
   if(InpDebugMode && drawdown > 0)
      Print("Current Drawdown: ", drawdown, "%");
   
   return (drawdown <= InpMaxDrawdown);
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
   bool withinHours = (currentHour >= InpStartHour && currentHour <= InpEndHour);
   
   if(!InpTradeOnWeekends && IsWeekend())
      return false;
   
   return withinHours;
}

bool IsWeekend()
{
   int dayOfWeek = DayOfWeek();
   return (dayOfWeek == 0 || dayOfWeek == 6); // Sunday or Saturday
}

void OnDeal()
{
   // Track consecutive losses
   CDealInfo deal;
   if(deal.SelectByIndex(DealsInMemory() - 1))
   {
      if(deal.Profit() < 0)
         consecutiveLosses++;
      else
         consecutiveLosses = 0;
   }
}

//+------------------------------------------------------------------+
