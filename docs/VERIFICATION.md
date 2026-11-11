# Verification record

Session date: **25 October 2026, Asia/Kuala_Lumpur**. Workspace was initially empty; no unrelated source was overwritten.

## Actual work performed

| Item | Actual evidence | Result |
|---|---|---|
| Main EA and all production headers | `logs/compile-main.log`; fresh `Biltech_VolumeProfile_EA.ex5` | MetaEditor 5.0.0.6281, zero errors and warnings |
| Native production-header test EA | `logs/compile-native-tests.log`; fresh `tests/BiltechVP_Tests.ex5` | Zero errors and warnings; compilation only |
| Independent Python specification/contracts | `logs/portable-tests.log` | 28 test methods passed |
| Hand-checkable signal fixtures | `tests/signal_cases.json`, `signal_handcheck.csv`, `generated_signal_fixtures.mqh` | 25 synthetic cases / 79 completed candles; valid/invalid A/B/C |
| Package consistency | `logs/package-verification.log` | Presets, includes, documentation links, synthetic labels and fresh binaries checked |
| Offline native execution preflight | `logs/native-runtime-isolation-check.log` | Not run: guaranteed offline isolation unavailable; no terminal/account launched |

Compiler invocation is reproduced in `tools/compile.ps1`. The script checks the log's result and freshness of the EX5 rather than trusting the compiler process exit code. `logs/SHA256SUMS.txt` identifies the delivered source, presets, data templates, docs and binaries.

## What the portable tests prove

They execute the independent Python oracle and synthetic contracts: tick-grid bins and total weight conservation; POC/value-area tie choices; M1 overlap; quote/trade flags and same-millisecond events; missing coverage/news; session boundaries and prior eligible dates; historical US DST and mismatched EU weeks; all signal prefixes, expiry and duplicates; POC space; lot floor and stated account-currency risk; group daily P/L/reset; concurrent reservation contract; restart, failed/partial request and netting ownership contracts.

They do **not** execute the MQL5 production engine, its terminal mutex, OrderCalcProfit, real account history, broker API responses, common-file persistence or actual crash boundaries. Python threading and JSON serialization tests are models of the required contracts, not MT5 integration results.

## Native tests supplied but not executed

The compiled native harness directly calls production profile, clock, tick filters, signal machines, missing-news behavior and volume floor. Running its assertions in a controlled MT5 mathematical test environment is still required. Require its Journal to show `BILTECH_NATIVE_RESULT ... failures=0` and archive that actual output. No native passing result has been fabricated in this delivery.

Final source review also checked symbol-scoped signal IDs, failed-init chart-object preservation, late-history fill metadata, partial-fill reservations, persistent owed closes and opening provenance beyond bare magic numbers. These review fixes compile; broker-native behavior remains untested.

## Not performed

- Market backtesting on any Gold, Nasdaq100 or US30 broker symbol.
- Live or demo account login, account activation, order submission or forward testing.
- Runtime MT5 multi-chart concurrency, partial/delayed fills, external netting contamination, interrupted persistence, emergency closures, large-history latency or day-start reconstruction tests.
- Independent verification of broker tick/news history, historical UTC offsets, holidays, contract costs or calendar event classifications.
- Optimization, profitability/expectancy measurement, profit factor, equity drawdown or monthly performance reporting. All performance fields remain NOT_RUN.

The installed terminal was deliberately left unopened. The native-test preflight found no guaranteed offline isolation and stopped without launching it. Continue with `BACKTEST_CHECKLIST.md` on a verified demo/tester environment; no live deployment is part of this task.
