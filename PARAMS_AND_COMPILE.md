# Algometa5 — Parameters, Compilation & Delivery Guide

This document explains how to compile Algometa5.mq5 into an `.ex5`, lists the EA input parameters with descriptions and defaults, and provides a recommended testing checklist and safety notes.

IMPORTANT: I cannot compile `.mq5` to `.ex5` inside this environment because compilation requires MetaEditor (Windows). Below are clear, reproducible steps you can run locally to produce the `.ex5` and to test the EA.

---

## 1) Where the source is

File: `Algometa5.mq5`
Location in repo: root

---

## 2) Inputs (from the current source)

- InpLotSize (double) = 0.1
  - Fixed lot size used for orders when the EA calls trade.Buy/trade.Sell.
- InpRiskPercent (double) = 2.0
  - (Present in the source but not actively used in the simplified position logic.) Intended percent risk per trade when percentage sizing is implemented.
- InpStopLossPoints (int) = 100
  - Stop loss in points.
- InpTakeProfitPoints (int) = 200
  - Take profit in points.
- InpUseTrailingStop (bool) = true
  - Enable trailing stop handling.
- InpTrailingStopPoints (int) = 50
  - Distance in points to maintain trailing stop.
- InpMA_Fast_Period (int) = 12
  - Fast moving average period.
- InpMA_Slow_Period (int) = 26
  - Slow moving average period.
- InpMA_Method (ENUM_MA_METHOD) = MODE_EMA
  - MA calculation method (EMA by default).
- InpRSI_Period (int) = 14
  - RSI lookback period.
- InpRSI_Overbought (double) = 70
  - RSI overbought level used for sell filtering.
- InpRSI_Oversold (double) = 30
  - RSI oversold level used for buy filtering.
- InpUseTrendFilter (bool) = true
  - Apply MA trend filter before allowing entries.
- InpUseRSIFilter (bool) = true
  - Apply RSI filter before allowing entries.
- InpMaxOpenPositions (int) = 3
  - Max simultaneous positions opened by the EA on the symbol.
- InpCloseAllOnWeekend (bool) = true
  - Whether to force-close EA positions when the weekend starts.
- InpStartHour (int) = 0
  - Earliest server-hour the EA will trade.
- InpEndHour (int) = 23
  - Latest server-hour the EA will trade.

Notes:
- Magic number is set in code via trade.SetExpertMagicNumber(123456). If you want a custom magic number, modify the source.
- Many of the advanced features described in your specification (capped grid recovery, percent-risk sizing, daily loss limits, persistent protections, panel UI, hedging option) are not present in this repository copy. This repository contains a simpler EA core with MA+RSI entry, fixed-lot sizing, SL/TP and trailing stop logic.

---

## 3) How to compile (.mq5 -> .ex5)

You must compile the source with MetaEditor (part of MetaTrader 5). Steps:

1. Open MetaTrader 5 on a Windows machine with MetaEditor installed.
2. File -> Open -> navigate to the `Algometa5.mq5` file (copy it into your MQL5/Experts folder or open directly from the repo copy).
3. In MetaEditor, press the "Compile" button (or F7).
4. Fix any compile errors if present (errors will appear in the Toolbox/Errors pane).
5. On successful compilation, MetaEditor creates `Algometa5.ex5` in the `MQL5/Experts` folder of your terminal data directory.
6. In MT5, press Ctrl+N -> Experts -> refresh or restart terminal so EA appears in Navigator.

If you need me to, I can provide a short troubleshooting checklist for common compiler errors.

---

## 4) How to prepare a parameter (`.set`) file for backtesting

1. Attach the EA to a chart in MT5 (demo account recommended).
2. Configure inputs in the EA properties -> Inputs tab.
3. From the same dialog, click "Save" and export a `.set` file to reuse in the Strategy Tester.

---

## 5) Backtest & forward-test checklist

- Use real-tick (1:1) tick data for XAUUSD if available in your broker's history for most accurate grid/backtest results.
- Test under different spreads and slippage settings. XAUUSD often has wider spreads; verify MaxSpread and SL/TP point scaling.
- Test with variable digit brokers (3/5 digits) — ensure point-based SL/TP scale correctly.
- Run long multi-year tests and sample forward test on demo account.
- If you plan grid-recovery or multiplier changes, stress-test with volatile market conditions.

---

## 6) Broker-specific checks

- Verify SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_SIZE and SYMBOL_VOLUME_* values for proper lot sizing if you later implement percent-risk sizing.
- Check minimum and step volumes: SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_MAX.
- Confirm order modification permissions (some brokers reject PositionModify calls or modify behaviour on netting vs hedging accounts).

---

## 7) Deliverables I can prepare for you

I cannot produce the compiled `.ex5` here, but I can:

- Create a `PARAMS_AND_COMPILE.md` (this file) in the repository (done).
- Add a `.set` example (text) that you can load in the Strategy Tester.
- Add a GitHub Actions workflow scaffold that documents how a Windows runner could be used to run the MetaEditor compiler (note: MetaTrader/MetaEditor are not licensed for headless CI by default; you may prefer to compile locally).
- Implement the remaining advanced features from your specification (capped grid, persistent protections, hedging toggle, UI panel) as source changes and push updates to this repo.

Tell me which of these you want next. If you want the compiled `.ex5`, I can provide a build checklist and you can either run MetaEditor locally or provide access to an environment that can run MetaEditor.

---

## 8) Quick commands / troubleshooting

- Common compile errors:
  - "Undefined identifier" -> missing include or wrong symbol/function name.
  - "Too many errors" -> fix earliest error first; later errors usually cascade.
  - If CopyBuffer or indicator handles fail, ensure indicator handles are created for the chart timeframe and symbol.

---

If you want, I will now:
- (A) add a `.set` sample to the repo for Strategy Tester, or
- (B) implement the remaining advanced features (grid-recovery, percent-risk sizing, protections) in a new branch, or
- (C) add a GitHub Actions `windows-latest` workflow scaffold that documents how you could automate compilation (you must provide a licensed MetaEditor runner). 

Reply with A, B, or C and I’ll proceed.
