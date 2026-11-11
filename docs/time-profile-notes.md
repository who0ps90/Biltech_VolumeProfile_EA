# Clock and profile implementation notes

All user session times are New York wall-clock labels. The supported New York calendar is 1970–2099. US DST uses the historical federal dates, including the January 6, 1974 and February 23, 1975 emergency starts. Dates before 1970 or after 2099 fail closed. New York spring gaps and autumn repeated times are rejected if converting a wall-clock session boundary to UTC. Historical rule references: [IANA time-zone rules](https://data.iana.org/time-zones/tzdb-2026a/tz-how-to.html) and [US Department of Transportation, October 1974](https://rosap.ntl.bts.gov/view/dot/86630/dot_86630_DS1.pdf).

Broker offsets are explicit. Fixed offsets never consult today's computer clock. `BROKER_US_DST` changes the configured winter offset at the US/New York transition instants (07:00 UTC in spring, 06:00 UTC in autumn). `BROKER_EU_DST` uses the harmonized 1996-onward EU rule, at 01:00 UTC on the last Sundays of March and October. A broker following other transition instants, or EU history before 1996, requires a historical offset schedule. UTC dates outside a schedule interval block conversion; repeated broker wall times are rejected. A reference crossing a broker offset transition is conservatively rejected by the loader.

Broker-offset file format, relative to `MQL5/Files`:

```csv
start_utc,end_utc,offset_minutes
2026-01-01T00:00:00Z,2026-03-29T01:00:00Z,120
2026-03-29T01:00:00Z,2026-10-25T01:00:00Z,180
```

These are synthetic schema examples, not a statement about any broker. Intervals are half open, sorted, nonoverlapping, and limited to 4,096 rows. Explicit gaps are allowed but block trading during the gap. No automatic broker-offset inference occurs.

Holiday/early-close file format:

```csv
date,reference_start,reference_end,entry_end
2026-12-25,CLOSED,,
2026-11-27,09:30,13:00,11:00
```

These are synthetic examples requiring broker/calendar verification. `entry_end` is optional. Closed dates are skipped. A custom reference row overrides both reference endpoints and can explicitly make a weekend date eligible. Duplicate dates or malformed rows reject configuration. Ordinary weekdays without overrides are candidates, whose actual history and broker session coverage must subsequently pass validation. The file is not an exchange-holiday database. `24:00` is accepted as an end time. An end at/before the start denotes an overnight interval. Early-close entry overrides for a daytime window must remain after the entry start; a day with no permitted entries should be marked `CLOSED`.

The previous reference candidate is the most recent fully ended eligible interval as of the decision timestamp. Selection never includes a currently unfinished reference. Failed/incomplete candidates may be skipped in favor of earlier complete sessions within the configured lookback. Profiles are frozen after acceptance.

## Histogram

For observed minimum `min`, maximum `max`, trade tick `t`, and requested rows `R`, lower boundary is `floor(min/t)*t`. Width is at least one tick and otherwise `ceil((max-lower)/(R*t))*t`. Actual rows are `max(1, ceil((max-lower)/width))`. Thus actual rows may be fewer than requested. Floating arithmetic uses a small tolerance at tick-grid boundaries. A point exactly at the maximum falls into the final bin, including when it equals its upper edge. POC ties use distance from the complete histogram midpoint, then the lower bin. Value-area adjacency ties expand downward first. POC is a bin midpoint and therefore may lie between executable trade ticks; technical order prices are normalized separately.

In quote mode, each record must have a valid Bid, the Bid-change flag, and a Bid different from the preceding valid snapshot. Ask-only and unchanged snapshots do not contribute weight. The first valid Bid-change record is accepted based on its flag because no pre-session quote is imputed. Invalid Bid snapshots clear that comparison state. A terminal-supplied record is processed once; no timestamp-based deduplication discards legitimate same-millisecond changes.

Trade mode requires a Last/volume/buy/sell trade flag, valid Last, and positive real volume (or integer trade volume when real volume is unavailable). It never weights a quote-only record using its carried Last/volume. Identical same-millisecond trade records are retained as distinct events; the terminal supplies event identity, which this EA cannot independently prove.

M1 approximation uses completed bars, apportions `tick_volume` according to each bin's overlap with High–Low, and assigns a zero-range bar to its containing bin. A floating residue is assigned to the last overlapping bin to conserve total weight. Reference close is the final valid Bid snapshot, eligible trade Last, or M1 close, respectively.

## Loading, coverage, and limitations

Only `OnTimer` advances the loader, at most one requested chunk per invocation. Adjacent accepted requests use disjoint millisecond intervals and inclusive API end `end-1`. Tick chunks also stop at minute boundaries. A static 65,536-record buffer bounds each tick request. A smaller configured `max_chunk_ticks` also applies. Any timeout, buffer error, other API error, unordered response, or out-of-range record discards the entire chunk without advancing the cursor. Retries are bounded; tick chunks shrink down to one second. A single second exceeding the buffer/cap fails closed. Total stored events are bounded at configuration time to at most 2,000,000. An expected tick minute containing no valid source record replays its entire interval from a saved comparison-state checkpoint, even when the API returned error zero. Such a minute has contributed no events, so replay cannot double-count prior events. M1 responses missing an expected trading minute retry the whole uncommitted chunk. After bounded gap retries, only an explicitly relaxed coverage percentage below 100 together with a positive allowed gap can tolerate the known gap; final full-session percentage and longest-gap checks still apply. API timeout/error responses are never accepted as relaxed coverage.

**Native history APIs can block the EA's event thread.** MQL5 documents that tick synchronization can wait up to 45 seconds. Moving loading out of `OnTick`, checking `SERIES_SYNCHRONIZED`, and keeping chunks small do not turn `CopyTicksRange`/`CopyRates` into cancellable asynchronous APIs. During such a native call, timer/tick position supervision in that EA is delayed; broker-held protective SL/TP remain essential. Preload and verify broker history before research, and forward-demo this limitation. No guaranteed millisecond timer latency is claimed.

Expected minutes come from the symbol's broker trading-session metadata intersected with the reference, including overnight broker sessions. Absent symbol schedule metadata blocks acceptance. A supplied equal start/end session pair means a full day; an absent pair means no scheduled session. Coverage means at least one valid raw Bid snapshot per expected minute in quote mode, an eligible trade event per minute in trade mode, or a valid positive-tick-volume M1 bar per minute. Closed minutes are excluded from the denominator and break a missing-minute run. Coverage percentage, longest missing run, event count, and data-mode label are reported; thresholds are explicit, with strict settings recommended for baseline research.

Minute coverage is a conservative availability check, not proof that every original tick survived broker archival. A historical broker can return a complete API response containing archival omissions or reconstructed ticks; these cannot be independently authenticated by this EA. A zero-trade minute can also reject a legitimate but sparse trade feed. Broker weekly sessions are current symbol metadata and may not encode historical schedule changes; verified custom session/holiday inputs and manual history review remain necessary. No mode automatically substitutes for another.

Relevant primary API references: [CopyTicksRange](https://www.mql5.com/en/docs/series/copyticksrange), [CopyTicks and synchronization wait](https://www.mql5.com/en/docs/series/copyticks), [tick flags](https://www.mql5.com/en/docs/constants/structures/mqltick), and [native server time](https://www.mql5.com/en/book/common/timing/timing_local_server).
