//+------------------------------------------------------------------+
//| EA-Algometa5.mq5                                                 |
//| Comprehensive Automated Trading Expert Advisor                   |
//| Features: EMA Trend, RSI Confirmation, ATR Filter, Risk Mgmt     |
//+------------------------------------------------------------------+
#property copyright "2024 AlgoMeta"
#property link "https://algometa.com"
#property version "5.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Indicators\Trend.mqh>

// ===== ENUMERATIONS =====
enum RISK_TYPE { FIXED_LOT, RISK_PERCENT, ATR_BASED };
enum SESSION_TYPE { ASIAN, EUROPEAN, AMERICAN, ALL_DAY };

// ===== INPUT PARAMETERS =====
input group "=== EMA SETTINGS ==="
input int FastEMA = 12;           // Fast EMA Period
input int SlowEMA = 26;           // Slow EMA Period
input int SignalEMA = 9;          // Signal EMA Period

input group "=== RSI SETTINGS ==="
input int RSIPeriod = 14;         // RSI Period
input int RSIOverbought = 70;     // RSI Overbought Level
input int RSIOversold = 30;       // RSI Oversold Level

input group "=== ATR VOLATILITY FILTER ==="
input int ATRPeriod = 14;         // ATR Period
input double ATRMultiplier = 2.0; // ATR Multiplier for Entry
input double ATRMinVolatility = 10; // Minimum Volatility (pips)

input group "=== SPREAD FILTER ==="
input int MaxSpread = 3;          // Maximum Spread (pips)
input bool UseSpreadFilter = true; // Enable Spread Filter

input group "=== SESSION FILTER ==="
input SESSION_TYPE TradingSession = AMERICAN; // Trading Session
input bool UseSessionFilter = true; // Enable Session Filter

input group "=== ECONOMIC NEWS FILTER ==="
input bool UseNewsFilter = true;  // Enable News Filter
input int NewsFilterMinutes = 60; // Minutes before/after news event

input group "=== RISK MANAGEMENT ==="
input RISK_TYPE RiskType = RISK_PERCENT; // Risk Type
input double RiskPercent = 2.0;   // Risk % per Trade
input double FixedLotSize = 0.1;  // Fixed Lot Size
input double MaxLossPerDay = 5.0; // Maximum Daily Loss (%)
input int MaxConsecutiveLosses = 3; // Max Consecutive Losses

input group "=== STOP LOSS & TAKE PROFIT ==="
input int StopLossPips = 50;      // Stop Loss in Pips
input int TakeProfitPips = 100;   // Take Profit in Pips
input bool UseBreakEven = true;   // Enable Break Even
input int BreakEvenPips = 10;     // Break Even Trigger (pips)
input bool UseTrailing = true;    // Enable Trailing Stop
input int TrailStopPips = 15;     // Trailing Stop Distance (pips)

input group "=== GENERAL SETTINGS ==="
input bool UseAskForSell = true;  // Use Ask for Sell Entry
input bool UseBidForBuy = true;   // Use Bid for Buy Entry
input int Slippage = 3;           // Allowed Slippage (pips)
input bool PrintDebug = true;     // Print Debug Info

// ===== GLOBAL VARIABLES =====
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;
datetime lastTradeTime = 0;
double dailyLoss = 0;
int consecutiveLosses = 0;
datetime dayStart = 0;

// ===== HANDLE ARRAYS =====
int handleEMAFast = INVALID_HANDLE;
int handleEMASlow = INVALID_HANDLE;
int handleRSI = INVALID_HANDLE;
int handleATR = INVALID_HANDLE;

// ===== INDICATOR BUFFERS =====
double bufferEMAFast[];
double bufferEMASlow[];
double bufferRSI[];
double bufferATR[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(20240814);
   trade.SetTypeFillingByMarket();
   
   // Create indicator handles
   handleEMAFast = iMA(_Symbol, _Period, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleEMASlow = iMA(_Symbol, _Period, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);
   handleATR = iATR(_Symbol, _Period, ATRPeriod);
   
   // Check if handles are valid
   if(handleEMAFast == INVALID_HANDLE || handleEMASlow == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Alert("Error creating indicators");
      return INIT_FAILED;
   }
   
   ArraySetAsSeries(bufferEMAFast, true);
   ArraySetAsSeries(bufferEMASlow, true);
   ArraySetAsSeries(bufferRSI, true);
   ArraySetAsSeries(bufferATR, true);
   
   dayStart = TimeCurrent();
   
   if(PrintDebug) Print("EA Initialized Successfully");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMAFast != INVALID_HANDLE) IndicatorRelease(handleEMAFast);
   if(handleEMASlow != INVALID_HANDLE) IndicatorRelease(handleEMASlow);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new day started for daily drawdown
   if(TimeDayOfWeek(TimeCurrent()) != TimeDayOfWeek(dayStart))
   {
      dailyLoss = 0;
      dayStart = TimeCurrent();
   }
   
   // Update indicator buffers
   if(CopyBuffer(handleEMAFast, 0, 0, 3, bufferEMAFast) <= 0) return;
   if(CopyBuffer(handleEMASlow, 0, 0, 3, bufferEMASlow) <= 0) return;
   if(CopyBuffer(handleRSI, 0, 0, 3, bufferRSI) <= 0) return;
   if(CopyBuffer(handleATR, 0, 0, 3, bufferATR) <= 0) return;
   
   // Check filters before processing trades
   if(!CheckAllFilters()) return;
   
   // Process existing positions
   ManagePositions();
   
   // Check for new trading signals
   if(PositionsTotal() == 0)
   {
      CheckBuySignal();
      CheckSellSignal();
   }
}

//+------------------------------------------------------------------+
//| Check all filters                                                 |
//+------------------------------------------------------------------+
bool CheckAllFilters()
{
   // Spread Filter
   if(UseSpreadFilter && GetSpreadInPips() > MaxSpread)
   {
      if(PrintDebug) Print("Spread filter rejected: ", GetSpreadInPips(), " pips");
      return false;
   }
   
   // Session Filter
   if(UseSessionFilter && !CheckSessionFilter())
   {
      if(PrintDebug) Print("Session filter rejected");
      return false;
   }
   
   // News Filter
   if(UseNewsFilter && CheckNewsEvent())
   {
      if(PrintDebug) Print("News filter rejected");
      return false;
   }
   
   // Daily Loss Filter
   if(dailyLoss >= MaxLossPerDay)
   {
      if(PrintDebug) Print("Daily loss limit reached");
      return false;
   }
   
   // Consecutive Losses Filter
   if(consecutiveLosses >= MaxConsecutiveLosses)
   {
      if(PrintDebug) Print("Max consecutive losses reached");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check Buy Signal                                                  |
//+------------------------------------------------------------------+
void CheckBuySignal()
{
   // EMA Trend: Fast EMA > Slow EMA (Bullish)
   if(bufferEMAFast[0] <= bufferEMASlow[0]) return;
   
   // RSI Confirmation: 30 < RSI < 70 (Not oversold/overbought)
   if(bufferRSI[0] <= RSIOversold || bufferRSI[0] >= RSIOverbought) return;
   
   // ATR Volatility Filter: Ensure sufficient volatility
   double atrValue = bufferATR[0] / _Point;
   if(atrValue < ATRMinVolatility) return;
   
   // Place Buy Order
   ExecuteBuyOrder(atrValue);
}

//+------------------------------------------------------------------+
//| Check Sell Signal                                                 |
//+------------------------------------------------------------------+
void CheckSellSignal()
{
   // EMA Trend: Fast EMA < Slow EMA (Bearish)
   if(bufferEMAFast[0] >= bufferEMASlow[0]) return;
   
   // RSI Confirmation: 30 < RSI < 70
   if(bufferRSI[0] <= RSIOversold || bufferRSI[0] >= RSIOverbought) return;
   
   // ATR Volatility Filter
   double atrValue = bufferATR[0] / _Point;
   if(atrValue < ATRMinVolatility) return;
   
   // Place Sell Order
   ExecuteSellOrder(atrValue);
}

//+------------------------------------------------------------------+
//| Execute Buy Order                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double atrValue)
{
   double volume = CalculateVolume();
   if(volume <= 0) return;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = price - (StopLossPips * _Point);
   double takeProfit = price + (TakeProfitPips * _Point);
   
   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = ORDER_TYPE_BUY;
   request.price = price;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = Slippage;
   request.magic = 20240814;
   request.comment = "Algometa5 BUY";
   
   MqlTradeResult result = {};
   OrderSend(request, result);
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      if(PrintDebug) Print("Buy Order Placed: Volume=", volume, " Price=", price);
      lastTradeTime = TimeCurrent();
   }
   else
   {
      if(PrintDebug) Print("Buy Order Failed: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Execute Sell Order                                                |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double atrValue)
{
   double volume = CalculateVolume();
   if(volume <= 0) return;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = price + (StopLossPips * _Point);
   double takeProfit = price - (TakeProfitPips * _Point);
   
   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = volume;
   request.type = ORDER_TYPE_SELL;
   request.price = price;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = Slippage;
   request.magic = 20240814;
   request.comment = "Algometa5 SELL";
   
   MqlTradeResult result = {};
   OrderSend(request, result);
   
   if(result.retcode == TRADE_RETCODE_DONE)
   {
      if(PrintDebug) Print("Sell Order Placed: Volume=", volume, " Price=", price);
      lastTradeTime = TimeCurrent();
   }
   else
   {
      if(PrintDebug) Print("Sell Order Failed: ", result.comment);
   }
}

//+------------------------------------------------------------------+
//| Calculate Volume Based on Risk Management                         |
//+------------------------------------------------------------------+
double CalculateVolume()
{
   double volume = 0;
   
   switch(RiskType)
   {
      case FIXED_LOT:
         volume = FixedLotSize;
         break;
      
      case RISK_PERCENT:
      {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount = balance * (RiskPercent / 100.0);
         double riskInPips = StopLossPips;
         double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         volume = NormalizeDouble(riskAmount / (riskInPips * pipValue), 2);
         break;
      }
      
      case ATR_BASED:
      {
         double atrValue = bufferATR[0] / _Point;
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount = balance * (RiskPercent / 100.0);
         double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         volume = NormalizeDouble(riskAmount / (atrValue * pipValue), 2);
         break;
      }
   }
   
   // Validate volume
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   volume = NormalizeDouble(volume, 2);
   if(volume < minVol) volume = minVol;
   if(volume > maxVol) volume = maxVol;
   volume = NormalizeDouble(MathFloor(volume / step) * step, 2);
   
   return volume;
}

//+------------------------------------------------------------------+
//| Manage Existing Positions (Break Even, Trailing Stop)             |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(positionInfo.SelectByIndex(i) && positionInfo.Magic() == 20240814)
      {
         if(UseBreakEven)
            ApplyBreakEven(positionInfo);
         
         if(UseTrailing)
            ApplyTrailingStop(positionInfo);
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Break Even Protection                                       |
//+------------------------------------------------------------------+
void ApplyBreakEven(CPositionInfo &pos)
{
   double breakEvenLevel = pos.PriceOpen() + (BreakEvenPips * _Point * (pos.PositionType() == POSITION_TYPE_BUY ? 1 : -1));
   
   if(pos.PositionType() == POSITION_TYPE_BUY && pos.PriceCurrent() >= breakEvenLevel)
   {
      if(pos.StopLoss() < pos.PriceOpen())
      {
         trade.PositionModify(pos.Ticket(), pos.PriceOpen(), pos.TakeProfit());
      }
   }
   else if(pos.PositionType() == POSITION_TYPE_SELL && pos.PriceCurrent() <= breakEvenLevel)
   {
      if(pos.StopLoss() > pos.PriceOpen())
      {
         trade.PositionModify(pos.Ticket(), pos.PriceOpen(), pos.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Apply Trailing Stop                                               |
//+------------------------------------------------------------------+
void ApplyTrailingStop(CPositionInfo &pos)
{
   double trailingLevel;
   double newSL;
   
   if(pos.PositionType() == POSITION_TYPE_BUY)
   {
      trailingLevel = pos.PriceCurrent() - (TrailStopPips * _Point);
      newSL = MathMax(pos.StopLoss(), trailingLevel);
      if(newSL > pos.StopLoss())
         trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
   }
   else if(pos.PositionType() == POSITION_TYPE_SELL)
   {
      trailingLevel = pos.PriceCurrent() + (TrailStopPips * _Point);
      newSL = MathMin(pos.StopLoss(), trailingLevel);
      if(newSL < pos.StopLoss())
         trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
   }
}

//+------------------------------------------------------------------+
//| Get Spread in Pips                                                |
//+------------------------------------------------------------------+
double GetSpreadInPips()
{
   return (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
}

//+------------------------------------------------------------------+
//| Check Session Filter                                              |
//+------------------------------------------------------------------+
bool CheckSessionFilter()
{
   if(!UseSessionFilter) return true;
   
   int hour = TimeHour(TimeCurrent());
   
   switch(TradingSession)
   {
      case ASIAN:
         return (hour >= 21 && hour < 24) || (hour >= 0 && hour < 9); // 21:00-09:00 GMT
      case EUROPEAN:
         return (hour >= 8 && hour < 17); // 08:00-17:00 GMT
      case AMERICAN:
         return (hour >= 13 && hour < 22); // 13:00-22:00 GMT
      case ALL_DAY:
         return true;
      default:
         return true;
   }
}

//+------------------------------------------------------------------+
//| Check News Event (Placeholder - Requires Calendar Integration)    |
//+------------------------------------------------------------------+
bool CheckNewsEvent()
{
   // This is a placeholder. For production, integrate with economic calendar
   // Example: Check if current time is within NewsFilterMinutes of any high-impact event
   return false; // Safe default: no news event
}

//+------------------------------------------------------------------+
//| On Trade (Callback for closed positions)                          |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Update daily loss tracking and consecutive losses
   UpdateRiskMetrics();
}

//+------------------------------------------------------------------+
//| Update Risk Metrics                                               |
//+------------------------------------------------------------------+
void UpdateRiskMetrics()
{
   double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   static double previousBalance = 0;
   
   if(previousBalance == 0)
      previousBalance = currentBalance;
   
   double dayProfit = currentBalance - previousBalance;
   
   if(dayProfit < 0)
   {
      dailyLoss += MathAbs(dayProfit);
      consecutiveLosses++;
   }
   else
   {
      consecutiveLosses = 0;
   }
   
   if(PrintDebug)
      Print("Daily Loss: ", dailyLoss, "% | Consecutive Losses: ", consecutiveLosses);
}

//+------------------------------------------------------------------+
