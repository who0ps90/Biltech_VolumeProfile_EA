# Biltech_VolumeProfile_EA

Native MQL5 research EA for a previous completed New York session profile. One instance trades only its chart's exact `_Symbol`. Select GOLD, NASDAQ100 or US30 explicitly; there is no broker symbol guessing. Defaults are research assumptions, not optimized settings or profitability claims.

## Verification delivered

MetaEditor 5.0 build 6281 compiled the EA and the native test EA with **0 errors and 0 warnings**. The portable specification suite passed **28 tests**, including 25 synthetic signal cases. The native MQL test harness was compiled but has not been executed. No broker-data backtest, demo execution test or performance measurement has been completed. No terminal/account was launched. See [verification record](docs/VERIFICATION.md), actual [compiler log](logs/compile-main.log), [native compiler log](logs/compile-native-tests.log) and [portable test output](logs/portable-tests.log).

## Install and compile

1. In MT5, choose **File → Open Data Folder**. Use a demo installation for initial work.
2. Copy this whole project folder under `MQL5\Experts\Biltech_VolumeProfile_EA`, preserving `Include\BiltechVP` and `tests`. Includes are project relative; nothing needs to go into the terminal's global Include folder.
3. Open `Biltech_VolumeProfile_EA.mq5` in MetaEditor and press **F7**. Require zero errors/warnings and a fresh `.ex5`. The supplied `.ex5` was built locally; rebuilding with your own terminal is recommended for compatibility.
4. Compile `tests\BiltechVP_Tests.mq5` similarly. Instructions for running its pure deterministic checks are in [test notes](docs/test-notes.md).
5. On this computer, recompilation is also available through PowerShell:

   ```powershell
   .\tools\compile.ps1
   # Another installation:
   .\tools\compile.ps1 -MetaEditor 'C:\path\to\MetaEditor64.exe'
   ```

The script runs only MetaEditor and verifies the compiler's result plus fresh binaries. It never starts MT5 or logs into an account.

## Configure before expecting entries

1. Open your verified broker instrument chart. Verify its contract description and Bid-based bar convention. The EA rejects Last-based charts. Do not infer that similarly named CFDs have the same contract or session.
2. Load `presets\GOLD_research.set`, `NASDAQ100_research.set` or `US30_research.set` through the EA Inputs **Load** button. These select the asset only; they do not select symbols. All three have `AllowLiveTrading=false`, setup A on and setups B/C off.
3. Set `BrokerTimeMode` from verified broker information. Presets deliberately use **BROKER_TIME_UNKNOWN** and block entries. Modes: fixed offset; US transitions; harmonized EU transitions; or a bounded historical UTC schedule. `BrokerBaseUTCOffsetMinutes` is the standard-time offset, not the current summer offset. Schedule is preferred when the broker's historical policy changed. Never derive historical offsets from today's PC clock.
4. Use the same verified clock mapping, account, terminal installation and `StrategyGroupID` on every portfolio chart. Use a unique `InstanceMagic` for each exact symbol. The presets use 2600101/2600102/2600103. Duplicate symbol instances are refused. The group policy is immutable without a deliberate flat-account reset or a fresh group ID; see [recovery notes](docs/execution-notes.md).
5. Select a data mode explicitly. Default is **Bid quote-activity profile**. There is no automatic fallback to M1 or trade data. History, session schedule and minute coverage must validate before entries are possible.
6. Configure news. Demo can use MT5's USD calendar. Backtests require your historical CSV in `NEWS_HISTORICAL_CSV`, or the explicit separately labelled `NEWS_DISABLED_RESEARCH` mode. Never label a disabled-filter test as news-filtered. The bundled news file is synthetic and rejected unless `AllowSyntheticNewsFixtures=true`; it is only for controlled fixtures.
7. Set estimated round-turn commissions per lot in account currency and adverse stop slippage ticks. The commission default `0` is a placeholder to replace with your verified broker cost, including zero only where appropriate. No contract values are hardcoded. Risk defaults: 0.25% per trade, 0.50% group open planned risk, 1.00% daily loss, three consecutive group losses.
8. Validate the dashboard and logs, then follow [backtest and demo checklist](docs/BACKTEST_CHECKLIST.md). Native execution/restart/concurrency tests remain necessary before relying on the controls.

## Research windows

All strategy inputs below are **America/New_York**. Malaysia is display-only UTC+8. Reference and entry windows are half-open, `[start,end)`.

| Preset | Reference window | Entry window / forced close |
|---|---|---|
| GOLD | 08:20–13:30 | 08:30–11:00; close at 11:00 |
| NASDAQ100 | 09:30–16:00 | 09:45–11:30; close at 11:30 |
| US30 | 09:30–16:00 | 09:45–11:30; close at 11:30 |

`UseCustomNYWindows=true` enables the four custom `HH:MM` inputs, including overnight windows. These are research windows, not assertions about exchange hours or optimal trading times. Provide verified holiday/early-close rows to avoid treating a shortened reference as complete.

## Files and persistence

- Input files belong in the terminal's **`MQL5\Files`** sandbox, referenced by filename. [Data schemas](docs/DATA_FORMATS.md) describe the news, offset and holiday files.
- Local tester agents have their own `MQL5\Files` folder. Copy verified CSVs there before a local test, or add literal `#property tester_file "yourfilename.csv"` lines to the EA and recompile so MT5 transfers them. Dynamic input filenames are not automatically transferred. Restart/reload the agent after updating files. Avoid cloud/remote testing until file transfer has been independently verified.
- Per-instance CSV signals/fills/exits and equity snapshots are written to the running terminal/tester's `MQL5\Files`. Execution audits and durable journals use `Terminal\Common\Files`. Names begin `BiltechVP_`/`BVP1.`. Equity snapshots contain account equity; isolate the strategy on a test account to attribute drawdown.
- Reservations, ownership registry, risk metadata and fatal flags persist. Do not delete them to bypass a block. Investigate open positions/orders/history first. [Execution notes](docs/execution-notes.md) describe safe reset conditions.
- Synchronization covers charts on **one account in one terminal**. Running the same strategy account from another terminal, machine or manual trader bypasses this mutex and is outside the supported portfolio-control scope.

## Specifications and limits

Read [strategy specification](docs/STRATEGY_SPECIFICATION.md), [time/profile details](docs/time-profile-notes.md), [execution/recovery details](docs/execution-notes.md) and [known limitations](docs/KNOWN_LIMITATIONS.md).

There are no paid indicators, DLL imports, API keys or external runtime services in the EA. Python is used only for optional offline specification tests and reporting. Break-even, trailing stops, discretionary partial profit exits, martingale, grids and recovery sizing are absent.

Native history/calendar/trade APIs can wait internally. Loading is incremental and outside `OnTick`, but this is not a hard real-time execution system. Protective SL/TP remains broker-side when accepted. Compilation and synthetic specification tests do not establish profitability or broker correctness.
