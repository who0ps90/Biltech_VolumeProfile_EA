# Deterministic test evidence and limits

All fixture prices, volumes, dates and events are synthetic. They are not broker history or performance results.

## Actual verification performed

- `tests/portable-test-log.txt`: 28 portable Python `unittest` methods passed. These execute the independent `spec_oracle.py`, never MQL5 or MT5 APIs. They check the specification and fixture expectations, including every signal prefix, exact histogram distribution/conservation, DST mismatched weeks and execution contract simulations.
- `tests/compile-native-tests.log`: MetaEditor compiled `tests/BiltechVP_Tests.mq5` with zero errors and warnings. Compilation does not execute assertions.
- The native test EA has not been executed in MT5. No user terminal or trading account was launched for these tests. There are no claims of successful MT5 runtime, broker execution, backtests or profitability.

The main EA compilation evidence is maintained separately in `logs/`.

## Native production tests

`tests/BiltechVP_Tests.mq5` directly includes and calls the delivered production `Signals.mqh`, `TimeProfile.mqh`, `News.mqh` and pure `BVPVolumeFloor` helper from `Execution.mqh`. It never initializes the execution engine or sends trade requests. It runs assertions in `OnInit`, prints `BILTECH_NATIVE_RESULT checks=N failures=N version=1.00`, and returns the assertion count through `OnTester` when all pass, or negative failures otherwise. A successful runtime result requires `failures=0`; the compiled EX5 alone proves no assertions.

After installing the project with its folder structure intact, compile the test EA in MetaEditor. In a separate demo/tester environment, select this test EA in Strategy Tester and choose **Math calculations** when available. This mode needs no price ticks, account trading or broker sizing calls. Inspect the Experts/agent journal for the result line. If the terminal build does not offer that mode, use the tester with existing local history and a demo configuration; do not attach this test harness to a live account. Its `OnTick` is empty and all tests are run by `OnInit`.

Native assertions cover deterministic POC/VA outcomes and tick-aligned bins; M1 overlap and zero range; empty profile input; exact US historical transitions; broker EU DST independent from US DST; DST wall-time ambiguity; entry and reference boundaries; weekend previous-session selection; overnight windows; unknown clock rejection; absent required news; explicit disabled news mode; actual quote/trade-event filters including same-millisecond events; actual volume flooring; all 25 signal fixtures, their stop/ATR/buffer/ID/expiry outputs, and duplicate/reset behavior.

Native profile API returns levels and total input weight, rather than the histogram itself. Exact per-bin conservation/distribution is independently hand-checked by the Python oracle; native expected levels detect material allocation changes but are not a direct bin-by-bin histogram export test.

## Fixture regeneration and portable test commands

From the project directory, with Python 3.10 or newer:

```powershell
python tests/generate_native_fixtures.py
python -m unittest discover -s tests -v
```

The JSON source `tests/signal_cases.json` contains 25 cases and 79 completed Bid candles. The generator checks OHLC consistency and writes `tests/signal_handcheck.csv` and `tests/generated_signal_fixtures.mqh`. The generated MQL contains input bars and fixed expected results; production `CBVPSignals` calculates the actual output. Regenerate and recompile if expectations change.

Each case uses VAL=100, VAH=110, POC=105, tick=0.1, M5 bars and buffer `max(0.2, 0.10*completed ATR)`. The initial previous candle and previous reference close are explicit/defaulted in JSON. Bar 0 starts at 2026-01-05 14:00 UTC. A signal emitted from bar index `i` becomes eligible at that candle's completion and expires at the end of the following candle. Every earlier candle has an expected absence of that signal, so a premature implementation fails the native fixture.

`A_long_default_space_valid` and its short mirror also pass the default POC space filter when proposed entry equals signal close. Other `A_*_valid` cases isolate structural confirmation and stops; some deliberately have insufficient POC space for an actual entry. The production signal engine emits structural signals; the execution engine applies the space filter to proposed Ask/Bid entry and logs a separate rejection. No fixture labeled structurally valid promises an accepted trade.

## Operational interpretations tested

- A: the initial outside candle has age zero. Exactly the next three completed candles are confirmation opportunities. Additional outside closes do not restart the timer. A strict inside close confirms; a close on VAL/VAH does not. Expiry requires a later inclusive inside-value candle before another excursion can start. Excursion extrema include the initial and confirmation candles. The confirmation candle's ATR supplies its buffer. If both directions confirm together, long wins the otherwise equal-priority tie.
- B: breakout, retest and confirmation use separate candles. The sixth retest and third confirmation opportunities remain eligible. The breakout ATR/buffer remain frozen through confirmation, including invalidation and stop padding. Retest and confirmation extrema use only their actual completed candles. An invalidating close is processed before any confirmation on the same candle. An expired/invalidated state cannot restart on that same candle.
- C: a band touch is any inclusive high-low overlap. The immediately prior close must lie strictly on the approach side of the **signal candle's completed-ATR** band; the signal must close strictly beyond that near edge and have the requested candle body direction. Closing through the opposite edge cannot qualify. These are operational research definitions, not independently verified original-video rules.
- All enabled state machines advance even if another setup has priority. Only one output survives: A, then B, then C. Signal identity depends on frozen reference start, signal candle open time, setup and direction. The caller scopes it to symbol/account state. Signals reset on day/reference changes and history gaps; main EA restart does not reconstruct and enter old signals.

## Execution simulations are contracts, not integration tests

Portable risk tests use stated synthetic account-currency losses, commissions and slippage; they do not run `OrderCalcProfit` or verify broker contracts. Python threads demonstrate a serialized reservation contract, not MT5 terminal global-variable atomicity. JSON round-trips demonstrate required durable state semantics, not production crash consistency. Duplicate/failed/partial scenarios express the expected lifecycle without a broker.

Still required in controlled demo/tester validation: real `OrderCalcProfit`/`OrderCalcMargin` and minimum-volume behavior for each broker symbol; cross-chart concurrent reservations and process termination at every persistence boundary; actual failed/delayed/partial fills; netting position mixing; emergency protection repair/closure; daily loss reconciliation across chart instances and restart; tick/news history failure recovery; actual history API coverage/chunk behavior; accounting CSV values after partial and final exits. The full flow has not been proven by the portable tests or by compilation.
