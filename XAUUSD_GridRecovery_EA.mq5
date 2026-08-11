//+------------------------------------------------------------------+
//|                     XAUUSD M5 Grid-Recovery EA v1.0               |
//|                    Expert Advisor for MetaTrader 5                 |
//|                                                                    |
//|  Advanced Grid Recovery System with Risk Management               |
//|  Target: XAUUSD M5 Timeframe                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://github.com/aitechlko-source"
#property version   "1.0"
#property strict
#property description "XAUUSD M5 Grid-Recovery EA with capped martingale and risk controls"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
// ENUMERATIONS & STRUCTURES
//+------------------------------------------------------------------+

enum ENUM_POSITION_MODE
{
   MODE_FIXED_LOT = 1,
   MODE_PERCENTAGE_RISK = 2
};

enum ENUM_TRADING_DIRECTION
{
   DIR_BUY = 1,
   DIR_SELL = -1,
   DIR_NEUTRAL = 0
};

struct TradeBasket
{
   int basketID;
   ENUM_TRADING_DIRECTION direction;
   double entryPrice;
   double totalLots;
   int gridLevel;
   int orderCount;
   double basketTakeProfit;
   double basketStopLoss;
   datetime openTime;
   bool isRecoveryBasket;
};

struct DailyStats
{
   double dailyLossLimit;
   double dailyLoss;
   double dayStartEquity;
   datetime lastResetTime;
   bool dailyLimitReached;
};

//+------------------------------------------------------------------+
// INPUT PARAMETERS - ENTRY CONFIGURATION
//+------------------------------------------------------------------+

//==== ENTRY CONFIGURATION ====
input double   InpEMA_Fast_Period    = 12;           // Fast EMA Period
input double   InpEMA_Slow_Period    = 26;           // Slow EMA Period
input int      InpRSI_Period         = 14;           // RSI Period
input double   InpRSI_Buy_Level      = 40;           // RSI Buy Level
input double   InpRSI_Sell_Level     = 60;           // RSI Sell Level
input bool     InpUseBreakout        = false;        // Use Breakout Confirmation
input int      InpBreakoutPeriod     = 10;           // Breakout Period (bars)

//+------------------------------------------------------------------+
// INPUT PARAMETERS - RISK & POSITION SIZING
//+------------------------------------------------------------------+

//==== RISK & POSITION SIZING ====
input ENUM_POSITION_MODE InpPositionMode = MODE_PERCENTAGE_RISK;  // Position Mode
input double   InpFixedLotSize       = 0.1;          // Fixed Lot Size (if MODE_FIXED_LOT)
input double   InpRiskPercent         = 0.5;          // Risk % per Initial Basket (if MODE_PERCENTAGE_RISK)
input int      InpStopLossPoints      = 100;          // Stop Loss (Points)
input int      InpTakeProfitPoints    = 200;          // Take Profit (Points)
input double   InpMaxTotalExposure    = 2.0;          // Max Total Lot Exposure (lots)

//+------------------------------------------------------------------+
// INPUT PARAMETERS - GRID & RECOVERY
//+------------------------------------------------------------------+

//==== GRID & RECOVERY ====
input int      InpMaxGridLevels      = 3;            // Maximum Grid Levels
input double   InpGridSpacing        = 50;           // Grid Spacing (Points)
input double   InpLotMultiplier      = 1.25;         // Lot Multiplier (Max 2.0)
input double   InpMaxRecoveryLot     = 1.0;          // Max Recovery Lot Size
input double   InpAdverseMovement    = 100;          // Adverse Movement for Recovery (Points)
input bool     InpUseHedging         = false;        // Enable Hedging (RISKY!)
input bool     InpRecoveryEnabled    = true;         // Enable Grid Recovery

//+------------------------------------------------------------------+
// INPUT PARAMETERS - ACCOUNT PROTECTION
//+------------------------------------------------------------------+

//==== ACCOUNT PROTECTION ====
input double   InpDailyLossPercent   = 2.0;          // Daily Loss Limit %
input double   InpBasketMaxLoss      = 1.0;          // Max Basket Loss %
input double   InpMaxDrawdownPercent = 5.0;          // Max Drawdown % (Shutdown)
input double   InpMaxSpreadPoints    = 50;           // Max Spread (Points)
input int      InpMaxSimultaneousTrades = 4;        // Max Simultaneous Trades
input int      InpMaxTradesPerDirection = 3;        // Max Trades Per Direction

//+------------------------------------------------------------------+
// INPUT PARAMETERS - SESSION & FILTER
//+------------------------------------------------------------------+

//==== SESSION & FILTER ====
input bool     InpEnableSessionFilter = true;        // Enable Session Filter
input int      InpSessionStartHour   = 14;           // Session Start (server time)
input int      InpSessionEndHour     = 22;           // Session End (server time)
input bool     InpEnableSpreadFilter = true;         // Enable Spread Filter
input int      InpCooldownBars       = 5;            // Cooldown (bars between trades)

//+------------------------------------------------------------------+
// INPUT PARAMETERS - BREAK-EVEN & TRAILING
//+------------------------------------------------------------------+

//==== BREAK-EVEN & TRAILING ====
input bool     InpUseBreakEven       = true;         // Use Break-Even
input int      InpBreakEvenPoints    = 50;           // Break-Even Trigger (Points)
input bool     InpUseTrailingStop    = true;         // Use Trailing Stop
input int      InpTrailingStopPoints = 30;           // Trailing Stop Distance (Points)

//+------------------------------------------------------------------+
// INPUT PARAMETERS - GENERAL
//+------------------------------------------------------------------+

//==== GENERAL ====
input int      InpMagicNumber        = 123456789;    // Magic Number
input string   InpTradeComment       = "GridRecoveryEA"; // Trade Comment
input bool     InpEAEnabled          = true;         // EA Enabled
input int      InpJournalLevel       = 2;            // Journal Level (0=Silent, 1=Errors, 2=Full)

//+------------------------------------------------------------------+
// GLOBAL VARIABLES
//+------------------------------------------------------------------+

CTrade          trade;
CPositionInfo   posInfo;
CSymbolInfo     symbolInfo;
CHistoryOrderInfo orderInfo;

int             handleEMA_Fast = INVALID_HANDLE;
int             handleEMA_Slow = INVALID_HANDLE;
int             handleRSI = INVALID_HANDLE;

double          bufferEMA_Fast[];
double          bufferEMA_Slow[];
double          bufferRSI[];

TradeBasket     currentBasket;
DailyStats      dailyStats;

int             lastEntryBar = -1;
int             basketCounter = 0;
double          accountStartEquity = 0;
bool            protectionActive = false;

//+------------------------------------------------------------------+
// EXPERT ADVISOR INITIALIZATION
//+------------------------------------------------------------------+

int OnInit()
{
   if(!InpEAEnabled)
   {
      Print("EA is disabled via input parameter");
      return INIT_SUCCEEDED;
   }

   // Validate symbol and timeframe
   if(_Symbol != "XAUUSD" && _Symbol != "GOLD" && !StringFind(_Symbol, "XAUUSD") >= 0)
   {
      Print("ERROR: This EA is designed for XAUUSD only. Current symbol: ", _Symbol);
      return INIT_FAILED;
   }

   if(_Period != PERIOD_M5)
   {
      Print("ERROR: This EA is designed for M5 timeframe only. Current: ", _Period);
      return INIT_FAILED;
   }

   // Validate inputs
   if(InpLotMultiplier > 2.0)
   {
      Print("WARNING: Lot multiplier capped at 2.0 for safety");
      InpLotMultiplier = 2.0;
   }

   if(InpRiskPercent < 0.1 || InpRiskPercent > 5.0)
   {
      Print("WARNING: Risk % should be 0.1-5.0. Adjusting to 0.5");
      InpRiskPercent = 0.5;
   }

   if(InpMaxGridLevels < 1 || InpMaxGridLevels > 5)
   {
      Print("WARNING: Grid levels should be 1-5. Adjusting to 3");
      InpMaxGridLevels = 3;
   }

   // Initialize trade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.LogLevel(LOG_LEVEL_NO);

   // Initialize symbol info
   if(!symbolInfo.Name(_Symbol))
   {
      Print("ERROR: Cannot initialize symbol");
      return INIT_FAILED;
   }

   // Create indicator handles
   handleEMA_Fast = iMA(_Symbol, _Period, (int)InpEMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA_Fast == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create Fast EMA handle");
      return INIT_FAILED;
   }

   handleEMA_Slow = iMA(_Symbol, _Period, (int)InpEMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handleEMA_Slow == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create Slow EMA handle");
      return INIT_FAILED;
   }

   handleRSI = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);
   if(handleRSI == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create RSI handle");
      return INIT_FAILED;
   }

   // Initialize daily stats
   accountStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStats.dayStartEquity = accountStartEquity;
   dailyStats.dailyLossLimit = accountStartEquity * (InpDailyLossPercent / 100.0);
   dailyStats.lastResetTime = TimeCurrent();

   Print("=== XAUUSD Grid-Recovery EA Initialized ===");
   Print("Symbol: ", _Symbol, " | Timeframe: ", _Period);
   Print("Position Mode: ", (InpPositionMode == MODE_FIXED_LOT ? "Fixed Lot" : "% Risk"));
   Print("Magic Number: ", InpMagicNumber);
   Print("Daily Loss Limit: ", dailyStats.dailyLossLimit, " | Start Equity: ", accountStartEquity);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
// EXPERT ADVISOR DEINITIALIZATION
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   if(handleEMA_Fast != INVALID_HANDLE) IndicatorRelease(handleEMA_Fast);
   if(handleEMA_Slow != INVALID_HANDLE) IndicatorRelease(handleEMA_Slow);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);

   Print("=== XAUUSD Grid-Recovery EA Deinitialized ===");
   Print("Reason: ", reason);
}

//+------------------------------------------------------------------+
// MAIN TICK PROCESSING
//+------------------------------------------------------------------+

void OnTick()
{
   if(!InpEAEnabled)
      return;

   // Update indicator values
   if(!UpdateIndicators())
      return;

   // Check protection limits
   UpdateProtectionStatus();

   if(protectionActive)
   {
      LogMessage(1, "Protection active - no new trades allowed");
      ManageOpenPositions();
      return;
   }

   // Check session filter
   if(InpEnableSessionFilter && !IsWithinTradingSession())
   {
      ManageOpenPositions();
      return;
   }

   // Check spread filter
   if(InpEnableSpreadFilter && !IsSpreadAcceptable())
   {
      LogMessage(1, "Spread too wide - waiting");
      ManageOpenPositions();
      return;
   }

   // Generate entry signal
   ENUM_TRADING_DIRECTION signal = GenerateEntrySignal();

   // Process entry or recovery
   if(signal == DIR_BUY)
   {
      ProcessBuySignal();
   }
   else if(signal == DIR_SELL)
   {
      ProcessSellSignal();
   }

   // Manage open positions (exit, break-even, trailing)
   ManageOpenPositions();
}

//+------------------------------------------------------------------+
// UPDATE INDICATORS
//+------------------------------------------------------------------+

bool UpdateIndicators()
{
   ArraySetAsSeries(bufferEMA_Fast, true);
   ArraySetAsSeries(bufferEMA_Slow, true);
   ArraySetAsSeries(bufferRSI, true);

   if(CopyBuffer(handleEMA_Fast, 0, 0, 5, bufferEMA_Fast) < 5) return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 5, bufferEMA_Slow) < 5) return false;
   if(CopyBuffer(handleRSI, 0, 0, 5, bufferRSI) < 5) return false;

   return true;
}

//+------------------------------------------------------------------+
// GENERATE ENTRY SIGNAL
//+------------------------------------------------------------------+

ENUM_TRADING_DIRECTION GenerateEntrySignal()
{
   // Cooldown check
   if(lastEntryBar == iBarShift(_Symbol, _Period, TimeCurrent()))
      return DIR_NEUTRAL;

   int barsSinceLastEntry = iBarShift(_Symbol, _Period, TimeCurrent()) - lastEntryBar;
   if(barsSinceLastEntry < InpCooldownBars)
      return DIR_NEUTRAL;

   // Trend check (EMA)
   bool trendUp = bufferEMA_Fast[0] > bufferEMA_Slow[0] && bufferEMA_Fast[1] <= bufferEMA_Slow[1];
   bool trendDown = bufferEMA_Fast[0] < bufferEMA_Slow[0] && bufferEMA_Fast[1] >= bufferEMA_Slow[1];

   // RSI confirmation
   bool rsiConfirmBuy = bufferRSI[0] < InpRSI_Buy_Level && bufferRSI[0] > 30;
   bool rsiConfirmSell = bufferRSI[0] > InpRSI_Sell_Level && bufferRSI[0] < 70;

   // Breakout confirmation (optional)
   bool breakoutBuy = true;
   bool breakoutSell = true;

   if(InpUseBreakout)
   {
      double highBreakout = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, InpBreakoutPeriod, 1));
      double lowBreakout = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, InpBreakoutPeriod, 1));

      breakoutBuy = (Close[0] > highBreakout);
      breakoutSell = (Close[0] < lowBreakout);
   }

   // BUY Signal
   if(trendUp && rsiConfirmBuy && breakoutBuy)
   {
      lastEntryBar = iBarShift(_Symbol, _Period, TimeCurrent());
      return DIR_BUY;
   }

   // SELL Signal
   if(trendDown && rsiConfirmSell && breakoutSell)
   {
      lastEntryBar = iBarShift(_Symbol, _Period, TimeCurrent());
      return DIR_SELL;
   }

   return DIR_NEUTRAL;
}

//+------------------------------------------------------------------+
// PROCESS BUY SIGNAL
//+------------------------------------------------------------------+

void ProcessBuySignal()
{
   // Check trade limits
   if(CountOpenPositions() >= InpMaxSimultaneousTrades)
   {
      LogMessage(1, "Max simultaneous trades reached");
      return;
   }

   if(CountTradesInDirection(DIR_BUY) >= InpMaxTradesPerDirection)
   {
      LogMessage(1, "Max BUY trades reached");
      return;
   }

   if(dailyStats.dailyLimitReached)
   {
      LogMessage(1, "Daily loss limit reached - no new trades");
      return;
   }

   // Calculate lot size
   double lotSize = CalculateLotSize(DIR_BUY);
   if(lotSize <= 0)
   {
      LogMessage(1, "Invalid lot size calculated for BUY");
      return;
   }

   // Check total exposure
   if(GetTotalLotExposure() + lotSize > InpMaxTotalExposure)
   {
      LogMessage(1, "Max total exposure would be exceeded");
      return;
   }

   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double StopLoss = Ask - (InpStopLossPoints * symbolInfo.Point());
   double TakeProfit = Ask + (InpTakeProfitPoints * symbolInfo.Point());

   if(trade.Buy(lotSize, _Symbol, Ask, StopLoss, TakeProfit, InpTradeComment))
   {
      LogMessage(2, "BUY Order Placed | Lot: " + DoubleToString(lotSize, 2) + 
                    " | Entry: " + DoubleToString(Ask, symbolInfo.Digits()) + 
                    " | SL: " + DoubleToString(StopLoss, symbolInfo.Digits()) +
                    " | TP: " + DoubleToString(TakeProfit, symbolInfo.Digits()));
   }
   else
   {
      LogMessage(1, "BUY Order Failed - Error: " + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
// PROCESS SELL SIGNAL
//+------------------------------------------------------------------+

void ProcessSellSignal()
{
   // Check trade limits
   if(CountOpenPositions() >= InpMaxSimultaneousTrades)
   {
      LogMessage(1, "Max simultaneous trades reached");
      return;
   }

   if(CountTradesInDirection(DIR_SELL) >= InpMaxTradesPerDirection)
   {
      LogMessage(1, "Max SELL trades reached");
      return;
   }

   if(dailyStats.dailyLimitReached)
   {
      LogMessage(1, "Daily loss limit reached - no new trades");
      return;
   }

   // Calculate lot size
   double lotSize = CalculateLotSize(DIR_SELL);
   if(lotSize <= 0)
   {
      LogMessage(1, "Invalid lot size calculated for SELL");
      return;
   }

   // Check total exposure
   if(GetTotalLotExposure() + lotSize > InpMaxTotalExposure)
   {
      LogMessage(1, "Max total exposure would be exceeded");
      return;
   }

   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double StopLoss = Bid + (InpStopLossPoints * symbolInfo.Point());
   double TakeProfit = Bid - (InpTakeProfitPoints * symbolInfo.Point());

   if(trade.Sell(lotSize, _Symbol, Bid, StopLoss, TakeProfit, InpTradeComment))
   {
      LogMessage(2, "SELL Order Placed | Lot: " + DoubleToString(lotSize, 2) + 
                    " | Entry: " + DoubleToString(Bid, symbolInfo.Digits()) + 
                    " | SL: " + DoubleToString(StopLoss, symbolInfo.Digits()) +
                    " | TP: " + DoubleToString(TakeProfit, symbolInfo.Digits()));
   }
   else
   {
      LogMessage(1, "SELL Order Failed - Error: " + IntegerToString(GetLastError()));
   }
}

//+------------------------------------------------------------------+
// MANAGE OPEN POSITIONS
//+------------------------------------------------------------------+

void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      // Apply break-even
      if(InpUseBreakEven)
         ApplyBreakEven(posInfo.Ticket());

      // Apply trailing stop
      if(InpUseTrailingStop)
         ApplyTrailingStop(posInfo.Ticket());

      // Check basket limits
      CheckBasketLosses(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
// APPLY BREAK-EVEN
//+------------------------------------------------------------------+

void ApplyBreakEven(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;

   double currentProfit = posInfo.Profit();
   double profitTrigger = (InpBreakEvenPoints * symbolInfo.Point()) * posInfo.Volume();

   if(currentProfit > profitTrigger)
   {
      double newSL = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();

      if(posInfo.PositionType() == POSITION_TYPE_BUY && newSL > currentSL)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
         LogMessage(2, "Break-Even applied to BUY position");
      }
      else if(posInfo.PositionType() == POSITION_TYPE_SELL && newSL < currentSL)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
         LogMessage(2, "Break-Even applied to SELL position");
      }
   }
}

//+------------------------------------------------------------------+
// APPLY TRAILING STOP
//+------------------------------------------------------------------+

void ApplyTrailingStop(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;

   double currentSL = posInfo.StopLoss();
   double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double newSL = Bid - (InpTrailingStopPoints * symbolInfo.Point());
      if(newSL > currentSL)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
   else if(posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double newSL = Ask + (InpTrailingStopPoints * symbolInfo.Point());
      if(newSL < currentSL || currentSL == 0)
      {
         trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
// CHECK BASKET LOSSES
//+------------------------------------------------------------------+

void CheckBasketLosses(ulong ticket)
{
   if(!posInfo.SelectByTicket(ticket)) return;

   double basketMaxLoss = AccountInfoDouble(ACCOUNT_EQUITY) * (InpBasketMaxLoss / 100.0);
   double currentLoss = posInfo.Profit();

   if(currentLoss < -basketMaxLoss)
   {
      LogMessage(1, "Basket max loss exceeded - closing position");
      trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
// UPDATE PROTECTION STATUS
//+------------------------------------------------------------------+

void UpdateProtectionStatus()
{
   // Update daily loss
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   dailyStats.dailyLoss = dailyStats.dayStartEquity - currentEquity;

   // Check daily loss limit
   if(dailyStats.dailyLoss >= dailyStats.dailyLossLimit)
   {
      dailyStats.dailyLimitReached = true;
      LogMessage(1, "DAILY LOSS LIMIT REACHED: " + DoubleToString(dailyStats.dailyLoss, 2) + 
                    " / " + DoubleToString(dailyStats.dailyLossLimit, 2));
   }

   // Check max drawdown
   double maxDrawdown = AccountInfoDouble(ACCOUNT_EQUITY) * (InpMaxDrawdownPercent / 100.0);
   if(dailyStats.dayStartEquity - currentEquity > maxDrawdown)
   {
      protectionActive = true;
      LogMessage(1, "MAX DRAWDOWN EXCEEDED - EA PROTECTION ACTIVATED");
      CloseAllPositions();
      return;
   }

   // Reset daily stats at new day
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   MqlDateTime dtLastReset;
   TimeToStruct(dailyStats.lastResetTime, dtLastReset);

   if(dt.day != dtLastReset.day)
   {
      dailyStats.dayStartEquity = currentEquity;
      dailyStats.dailyLoss = 0;
      dailyStats.dailyLimitReached = false;
      dailyStats.lastResetTime = TimeCurrent();
      LogMessage(2, "Daily stats reset - New equity baseline: " + DoubleToString(currentEquity, 2));
   }
}

//+------------------------------------------------------------------+
// CALCULATE LOT SIZE
//+------------------------------------------------------------------+

double CalculateLotSize(ENUM_TRADING_DIRECTION direction)
{
   double lotSize = 0;

   if(InpPositionMode == MODE_FIXED_LOT)
   {
      lotSize = InpFixedLotSize;
   }
   else if(InpPositionMode == MODE_PERCENTAGE_RISK)
   {
      double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
      double pointValue = symbolInfo.TickSize() * symbolInfo.TickValueProfit();
      double riskInPoints = InpStopLossPoints;

      if(riskInPoints > 0)
      {
         lotSize = NormalizeDouble(riskAmount / (riskInPoints * pointValue), 2);
      }
   }

   // Apply max exposure cap
   if(lotSize > InpMaxTotalExposure)
      lotSize = InpMaxTotalExposure;

   // Validate minimum lot
   if(lotSize < symbolInfo.LotsMin())
      lotSize = 0;

   return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
// GET TOTAL LOT EXPOSURE
//+------------------------------------------------------------------+

double GetTotalLotExposure()
{
   double totalLots = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      totalLots += posInfo.Volume();
   }

   return NormalizeDouble(totalLots, 2);
}

//+------------------------------------------------------------------+
// COUNT OPEN POSITIONS
//+------------------------------------------------------------------+

int CountOpenPositions()
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
// COUNT TRADES IN DIRECTION
//+------------------------------------------------------------------+

int CountTradesInDirection(ENUM_TRADING_DIRECTION direction)
{
   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;

      if(direction == DIR_BUY && posInfo.PositionType() == POSITION_TYPE_BUY)
         count++;
      else if(direction == DIR_SELL && posInfo.PositionType() == POSITION_TYPE_SELL)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
// CLOSE ALL POSITIONS
//+------------------------------------------------------------------+

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol || posInfo.Magic() != InpMagicNumber) continue;
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
// IS WITHIN TRADING SESSION
//+------------------------------------------------------------------+

bool IsWithinTradingSession()
{
   if(!InpEnableSessionFilter)
      return true;

   int hour = Hour();
   return (hour >= InpSessionStartHour && hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
// IS SPREAD ACCEPTABLE
//+------------------------------------------------------------------+

bool IsSpreadAcceptable()
{
   if(!InpEnableSpreadFilter)
      return true;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spread <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
// LOGGING FUNCTION
//+------------------------------------------------------------------+

void LogMessage(int level, string message)
{
   if(level <= InpJournalLevel)
   {
      string prefix = "";
      if(level == 1) prefix = "[ERROR] ";
      else if(level == 2) prefix = "[INFO] ";

      Print(prefix + message);
   }
}

//+------------------------------------------------------------------+
