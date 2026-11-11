# Operational strategy specification — v1.00

This defines executable research interpretations. The original request is preserved in `REQUEST.txt`. No original video was supplied or independently verified. In particular, the POC bounce candle definitions implement the requested operational interpretation and are not authenticated original-video rules.

## Price and information conventions

Signals use the broker's Bid-based completed bars, M5 by default. Last-based symbol charts are rejected. ATR is MT5 iATR, period 14 by default, read at shift 1. No forming-bar ATR, unconfirmed fractal, future swing or current-session reference profile is used. A buy is priced at Ask and a sell at Bid. Broker-side buy-position SL/TP distances are validated from Bid; sell-position distances from Ask. Technical stops round outward to trade tick size; targets round outward to the tick grid. Outward rounding changes the exact target slightly from 2R and is recorded in actual prices.

The reference must have ended by the signal bar's start. Levels freeze after data and coverage validation. If the newest eligible session fails, search older individual sessions within the configured calendar lookback; never combine partial days. Signals cannot be rebuilt retroactively when late data arrives.

On attach/restart, the current forming bar is observed without trading the preceding completed bar. The next consecutive completed bar can update setup states. Reconnect/series gaps reset states; no missed-bar sequence is reconstructed for entry. Setup state advances only while the current entry window is open, and resets across NY day changes, reference changes and outside entry windows. Therefore an excursion begun entirely before that window is not carried into it. The preceding completed bar can still be used as the explicit approach/crossing bar for B/C. This conservative session gating is an operational interpretation.

## Profiles

| Mode | Price | Weight | Label |
|---|---|---|---|
| QUOTE_TICK_PROFILE | Valid Bid, flagged Bid-change event with changed observed Bid | 1/event | Bid quote-activity profile |
| TRADE_VOLUME_PROFILE | Valid Last, eligible trade/Last/volume flags, positive real volume or integer volume | Supplied trade volume | Broker-supplied trade-volume profile |
| M1_APPROXIMATION | Completed M1 High–Low interval | M1 tick volume proportionally by bin overlap | M1 approximate tick-volume profile |

Ask-only updates and unchanged snapshots do not contribute quote weight. Valid raw Bid snapshots can establish minute availability and the previous Bid close without becoming profile events. Stale Last/volume carried in a quote-only record is excluded from trade mode. Same-millisecond event multiplicity is preserved, rather than deduplicating timestamps. Whole timed chunks are committed once; errored partial responses are discarded before retry. No reliable exchange trade identifiers are available in MqlTick, so identical delivered trade events cannot be distinguished from duplicates inserted by a broker.

M1 zero-range bars assign their entire weight to the containing bin. Positive ranges distribute weight by overlap length divided by High–Low length; floating arithmetic residue is returned to the final overlapping bin to conserve weight. Bar close is Bid in this approximation.

The lower boundary is `floor(min/tick)*tick`. Width is at least one tick, and otherwise `ceil((max-lower)/(RequestedRows*tick))*tick`. Actual rows are `max(1,ceil((max-lower)/width))`. Arithmetic has small grid tolerances to avoid a spurious extra row from floating error. Interior bins are half-open; the maximum observed price is explicitly included in the final bin. Actual rows may be fewer than the requested 60 and are shown with width on the dashboard.

POC is the greatest-weight bin; equal weights choose the bin center closest to the midpoint of the full bin extent, then the lower bin. POC price is that center. Value area starts with POC. Each step compares the immediately adjacent unused lower/upper bin and adds the greater weight, choosing lower first on exact ties, until at least the requested weight fraction is included. VAL/VAH are outer edges of the included contiguous bins. Floating weight ties use exact accumulated double equality; this deterministic choice may differ from another platform's tolerance or volume aggregation.

Previous-session close is the final valid raw Bid (quote mode), eligible Last (trade mode) or completed M1 close (approximation). Inside value means `VAL <= close <= VAH`. Previous close for trade profiles uses Last because the requested same-convention rule requires it; subsequent CFD signal bars remain Bid. Feed basis differences must be evaluated explicitly when researching trade mode.

These bins, event filters, tie rules, session windows and data feed need not match TradingView. No cross-platform equivalence is claimed.

## History validation and timing

Expected trading minutes are the intersection of the requested NY reference and the symbol's published broker trading-session schedule. Missing metadata blocks the reference. Coverage records are valid raw Bid minutes, eligible Last/volume minutes, or completed positive-volume M1 minutes, according to mode. Defaults require every expected minute, at least 100 qualifying profile events, and no missing minute gap. Dashboard and audit report event count, covered/expected minutes and longest missing run.

The loader processes one bounded chunk per timer, caps tick requests at minute boundaries, and shrinks errored requests down to a one-second minimum. A missing expected minute is replayed from a checkpoint with bounded retries. Explicitly relaxed coverage can admit known gaps only under the configured percentage and gap limit; it is not a mode fallback. A completed M1 chunk with a missing expected bar is conservatively rejected after retries. Native API latency is not controllable; see known limitations.

US Eastern DST is calculated by date for 1970–2099, including 1974/1975 emergency starts, pre-1987 and pre-2007 rules. EU broker DST supports the harmonized rule from 1996. The explicit US broker rule changes at the US UTC transition instants; a broker using another rule needs a schedule. Broker standard offset and DST delta are independent of US Eastern. Historical schedules have bounded intervals and reject uncovered or ambiguous inverse wall times. Reference sessions crossing a broker wall-clock discontinuity are rejected. Malaysia is only `UTC+8` dashboard output.

All sessions use `[start,end)`. Overnight windows are anchored to the starting NY date. Weekend/holiday search uses that date. Holiday/early-close rows override the exact date and may change the entry cutoff. A missed prior close is caught up after restart. Session closes are market-close attempts and can execute later when the market/connection permits; they are not guaranteed exact-time fills.

## Signal lifecycle and priority

Buffer is `max(2*trade_tick_size,0.10*completed_ATR)` by default. A confirmed bar at time `t` completes at `t+period`; its candidate can submit during the following bar, `[t+period,t+2*period)`. The first subsequent tick passing every filter can submit once. Filters can wait for a later eligible tick until expiry. Once OrderSend is attempted, its durable identifier is consumed even on failure/timeout; the signal never produces a second entry request. If no eligible tick occurs, it expires and is logged.

Executable entry must remain within 0.20 ATR of signal Bid close. This includes buy spread displacement. Spread must be at most 0.10 ATR and 15% of proposed stop distance. Values are configurable and never widened automatically. Candidate state updates occur for every enabled setup before priority resolves: A value re-entry, then B breakout, then C bounce. A discarded lower-priority candidate is not replayed later. Signal IDs include exact symbol, reference start, signal bar time, setup and direction.

## A — value-area re-entry (enabled)

Eligible only when the previous reference closed inside value. A long starts when a completed close is strictly below VAL; a short when strictly above VAH. The excursion extreme includes the initial candle and every candle through confirmation. Exactly the next three completed candles are confirmation opportunities by default. The timer does not restart on further outside closes. Strict inside confirmation is `VAL < close < VAH`, excluding equality at either edge.

Confirmation proposes a stop below the excursion low minus current completed-bar buffer for a long, or above its high plus buffer for a short. A nonconfirming third opportunity expires the excursion; a later inclusive inside-value candle is required to rearm that direction and cannot itself begin another excursion. Confirmed excursions reset their direction to armed. If ATR was unavailable, the confirmation is consumed without entry. Long and short state machines are independent.

Default POC space is checked against executable entry and tick-rounded target: a long must enter below POC with target <= POC; a short above POC with target >= POC. Its rejections are separately logged as the POC space filter. Disabling it changes the research variant and should use a different ParameterID.

## B — breakout continuation (disabled)

Previous close can be inside or outside. Long: a completed close exceeds `VAH+Buffer` after the preceding completed close was at/below that same threshold. Freeze that breakout bar's high, ATR and buffer. A later candle within the next six bars must intersect `[VAH-buffer,VAH+buffer]` and close above VAH. This is the retest; freeze its high. Within the next three bars after retest, a separate later candle must close strictly above `max(breakout_high,retest_high)`. Stop is below the lowest low from retest through confirmation minus frozen buffer.

Any bar after breakout that closes strictly below `VAH-buffer` invalidates. Sixth/third bars remain eligible; otherwise states expire after those limits. The short mirrors at VAL, crossing below `VAL-buffer`, retesting the band with close below VAL, confirming below `min(breakout_low,retest_low)`, and stopping above retest-through-confirmation high plus frozen buffer. Invalidating short close is strictly above `VAL+buffer`. Breakout, retest and confirmation must occupy different bars. The frozen breakout ATR is also used by its candidate's drift/spread filters.

## C — POC bounce (disabled)

Long eligibility requires previous reference close strictly above VAH. Preceding completed candle closes above `POC+current_buffer`. The signal candle intersects the POC band, closes above its upper edge, and is bullish (`close>open`). Stop is signal low minus buffer. Short requires previous close strictly below VAL, approach from below the lower POC band, band touch, close below that band and a bearish candle, with stop above signal high plus buffer. Dojis, far-side closes and band-edge equality fail the rejection criteria. Wicks through the far side are allowed if the close satisfies the requested rejection definition. These are research interpretations.

## Risk and execution

Size uses current equity and OrderCalcProfit in account currency for the proposed entry and adverse-slipped stop, plus estimated round-turn commission per lot. Volume floors to the permitted step and maximum; if the minimum cannot fit, skip. The technical stop is never tightened to fit a budget. OrderCalcMargin and OrderCheck must pass, and the symbol must permit market orders with initial SL and TP. Supported FOK/IOC policies are selected dynamically; unsupported execution modes block entries. Direction, session, freshness, stop/freeze distances and terminal/account permissions are checked.

Every market entry submits SL and TP. Actual fill risk and original stop are reconciled from history. Missing protection triggers a persistent fatal block and emergency closure. TP is adjusted to actual weighted fill-based R where broker distances permit. The initial stop is never widened. Fill risk above the configured 5% tolerance triggers full safe closure, including retry after definitive temporary failures. Emergency closes are risk actions, not discretionary partial profit exits.

One position per exact symbol, no pyramiding or opposite hedges. A single partially filled order counts as one filled entry. Daily defaults are two filled symbol entries and one per setup/direction. Counts rebuild from position/order/deal history. Any existing symbol position/order blocks entry; foreign or mixed netting lifecycles are never modified. Magic is not considered sufficient proof when lifecycle history conflicts.

All group charts share an atomic account-scoped terminal mutex and write-ahead risk reservations. Aggregate cap includes open planned risk plus unresolved reservations; during reconciliation a fill can temporarily be counted twice, conservatively. Delayed/unknown sends are quarantined until terminal order and complete deal-volume evidence resolve them. Exit requests have separate durable intent to avoid duplicate closes reversing a netting position. Multi-terminal and noncooperating external actors are outside the synchronization scope.

Daily group P/L is attributable realized profit/commission/swap/fees plus change in group floating profit/swap from NY day-start. Unrelated account trades affect the account-equity denominator but are excluded from group P/L. The baseline persists; a flat-at-midnight account can reconstruct midnight equity from balance and subsequent booked impacts. Unknown carryover baseline blocks entries. Threshold breach or three consecutive fully closed losing lifecycles latches a group block until the next NY day; by default close all unambiguously group-owned exposure. Protection errors latch beyond the day and require investigation. Baseline assumptions and account-history limits are detailed in execution notes.

Break-even, trailing, normal partial exits and recovery sizing are absent. Planned risk limits cannot guarantee realized loss through gaps, execution failures, disappearing history or broker rejection.

## Primary implementation references

- [CopyTicksRange flags, inclusive millisecond bounds and partial errors](https://www.mql5.com/en/docs/series/copyticksrange)
- [CopyTicks full snapshots and internal history synchronization waits](https://www.mql5.com/en/docs/series/copyticks)
- [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [OrderCheck](https://www.mql5.com/en/docs/trading/ordercheck)
- [CalendarValueHistory server-time convention and errors](https://www.mql5.com/en/docs/calendar/calendarvaluehistory)
- [Strategy Tester and mathematical mode](https://www.mql5.com/en/docs/runtime/testing)

These sources describe platform behavior. They do not validate the strategy, data feed or financial performance.
