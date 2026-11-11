# Backtest and forward-demo checklist

## A. Deterministic checks before market research

- [ ] Compile EA and `tests/BiltechVP_Tests.mq5` with zero errors/warnings; retain fresh logs and hashes.
- [ ] Run the native test EA in Strategy Tester's mathematical calculations mode (or FromDate > ToDate). It sends no orders. Require `BILTECH_NATIVE_RESULT ... failures=0`, a positive OnTester value, and an exported Journal. This native run has not been done in this delivery.
- [ ] Run `python -m unittest discover -s tests -p "test_*.py" -v`. These are independent specification/contract simulations, not native execution tests.
- [ ] Hand-check `tests/signal_handcheck.csv` against `signal_cases.json`: valid/invalid long and short A/B/C, expiry, rearm, frozen B buffer, separate bars and priority.
- [ ] On a demo account, verify Bid bars, exact contract calculation, tick size, point, volume min/max/step, stop/freeze distance, FOK/IOC support and session metadata. Compare an OrderCalcProfit-derived loss with the broker's own small demo loss/commission history.

## B. Data and clock audit

- [ ] Record exact broker/server, symbol, account currency, account mode, commission basis, leverage, data download date and terminal build.
- [ ] Obtain a verified historical broker offset schedule and holiday/early-close file covering warm-up through the test end. Check US/EU mismatched March/October weeks, broker fall-back ambiguity, exact NY endpoints and overnight custom windows.
- [ ] Select **Every tick based on real ticks**. Confirm tick history exists, download/synchronize ahead of the run, and inspect tester Journal for substitutions, generated ticks, history corrections and missing periods.
- [ ] Record these affected periods and exclude them from quote-profile claims or report them as separate labelled sensitivity runs. An EA minute-coverage pass alone does not certify real-tick provenance.
- [ ] Leave quote mode as quote mode; never silently replace it with M1. Test explicitly selected trade/M1 variants separately, including event counts and coverage rejection rates.
- [ ] Supply complete historical USD news CSV with independently verified COVERAGE, or deliberately use `NEWS_DISABLED_RESEARCH` with that label in every result. Transfer CSV files into the local agent sandbox; verify it reads the intended versions. Never use the synthetic sample for a market result.

## C. Baseline market runs

- [ ] Fix a baseline ParameterID and archive `.set`, source/binary hashes and all input-file hashes. Use a dedicated demo/simulation account without unrelated positions to make account equity drawdown attributable.
- [ ] Test each verified asset separately with **A only**, default settings, then **B only**, then **C only**. Do not combine first and lose attribution.
- [ ] Start sufficiently early for ATR and the prior complete reference; ignore warm-up before the first validated profile. Timer history loading consumes simulated time, so document session/profile-ready timestamps and keep preload/cache conditions consistent.
- [ ] Set realistic commission, broker spread and adverse-slippage assumptions. Test fixed and delayed execution where available. The sizing slippage allowance is a risk estimate; it does not force tester fills to exhibit that slippage. Actual execution stress must be configured/tested separately.
- [ ] Check requests have initial SL/TP; fill-based target revision; no widened stop; lot floor; POC space rejection; stale/spread/news/session skips; two/day and one/setup/direction/day limits.
- [ ] Reserve a later chronological unseen period before parameter changes. Do not choose it after seeing the results. Establish the baseline before parameter optimization; avoid broad searches over many settings.

For every closed **position lifecycle**, sum profit, commission, swaps and fees from all entry/exit deals. Divide its net by actual initial filled stop risk (document whether round-turn estimated costs are included in the denominator). Account for partial fills as one entry/lifecycle, not multiple trades. Reconcile totals against MT5's report/history, including externally charged costs if attributable.

Report at least: closed trade count; mean net R/trade (expectancy); gross net winners divided by absolute gross net losers (profit factor, undefined if there are no losers); maximum **equity** peak-to-trough drawdown in currency and percent; maximum consecutive net losing lifecycles; and results by NY month, session/reference date, asset, setup and direction. Include rejected-session/signal counts, space-filter skips, data mode, news mode and cost assumptions. Use the tester's equity report and the event-sampled equity CSV as cross-checks; balance drawdown is insufficient.

`results_template.csv` is deliberately blank/NOT_RUN. No performance figures have been invented.

## D. Portfolio and recovery acceptance tests on demo

- [ ] Run all three symbols simultaneously on separate charts in the **same terminal**, same account/group and consistent verified clock/news data. Verify unique magics, same daily/aggregate policy and no duplicate symbol owner.
- [ ] Synchronize Nasdaq/US30 signals to compete for the 0.50% group risk budget. Confirm atomic reservations block excess exposure even before orders/deals are fully visible. Test current-equity changes between requests. They are correlated equity CFDs; do not regard a two-position portfolio as diversified merely because symbols differ.
- [ ] Independent single-symbol backtests do not exercise simultaneous chart reservations. Use a synchronized event/portfolio replay harness or forward demo to test shared exposure and daily-loss behavior; do not obtain portfolio drawdown by adding independent maximum drawdowns or assume serial trade lists test races.
- [ ] Create unrelated hedging/netting exposure, including same magic with inconsistent opening history and external partial closes. Confirm no unrelated position is modified and the symbol/group blocks conservatively as documented.
- [ ] Force wide spreads, stale quotes, missing news/history, calendar errors, market close, unsupported fills, invalid stops, insufficient margin, requests rejected/placed/timed out, partial fills and delayed order/deal visibility. Confirm one entry request per ID, reservation retention and residual cancellation. Use broker demo facilities/controlled test harnesses; do not manufacture a live failure.
- [ ] Remove initial protection only in a controlled demo test: confirm persistent fatal block and emergency closure. Test over-risk fills and TP freeze/stops rejection. Confirm forced close retries through market/connection failures without reversing netting exposure.
- [ ] Restart terminal/EA with open exposure and pending/unknown requests; inspect journals, metadata, counters, consumed signals, group loss latch, owed closes and absent retroactive entries. Test a new NY day, midnight carryover and incomplete baseline/history. Do not delete state to make a test pass.
- [ ] At daily-loss breach, verify group realized+floating-change accounting including costs, latched block, retries of all owned closures, and reset only on the next NY date. Fatal protection errors must remain blocked beyond midnight until investigated.
- [ ] Measure handler latency with very large histories, downloads and account transactions. A long native call can delay management; confirm accepted broker-side protection remains present throughout.

## E. Forward demo record

- [ ] Run long enough to observe each intended setup and at least one session/news/DST or controlled boundary test; a fixed number of days with no trades is not execution validation.
- [ ] Reconcile every own order/deal to a signal ID and initial risk. Record actual slippage, commissions, rejected modifications and closure delays.
- [ ] Compare dashboard times with independent known UTC/NY timestamps. Review profile-ready status and missing sessions daily.
- [ ] Archive source/configuration/data versions, logs and reports. Record deviations before changing anything; change ParameterID for each substantive variant.

No live deployment or live account activation is part of this delivery. `AllowLiveTrading=false` remains the supplied default.
