# Input formats

Files are plain ASCII/UTF-8 without BOM (ANSI-safe field text recommended) inside `MQL5\Files` of the running terminal or tester agent. Paths are relative to that sandbox. News rows have exactly eight unquoted comma-separated fields; titles cannot contain commas or newlines. Offset and holiday parsers allow empty lines and `#` comments. Never place passwords, account credentials or API keys in these files.

## Historical news

```csv
kind,start_utc,end_utc,currency,impact,fomc,title,synthetic
```

- `kind`: exactly `COVERAGE` or `EVENT`.
- Exactly one continuous `COVERAGE` row is mandatory; it asserts the provider verified complete USD news coverage in `[start_utc,end_utc)`, including dates with no events. A nonempty event list is not a completeness assertion.
- Timestamps: `YYYY-MM-DDTHH:MM:SSZ`, `YYYY-MM-DD HH:MM:SS` or dotted dates with seconds; all represent **UTC**. Invalid dates fail validation. `EVENT` start/end may be equal for a punctual release; longer intervals represent known uncertainty/exclusions.
- `currency`: `USD` for coverage and relevant events.
- `impact`: `HIGH` for high impact events; other impacts do not trigger the ordinary filter.
- `fomc`: `0` or `1` on every EVENT; flagged events receive the configured FOMC window when enabled, even if not marked HIGH.
- `title`: plain text without commas; only descriptive, not machine-classified for CSV events.
- `synthetic`: `0` for independently verified source data, `1` for synthetic fixtures. Every row must specify it. Setting zero does not make a file historically authentic; provenance must be audited separately.
- All included events must lie within the declared coverage. Entry requires coverage for the complete maximum pre/post exclusion neighborhood. Missing, malformed or uncovered data blocks entries.

`data/news_SYNTHETIC.csv` demonstrates the exact shape using deliberately artificial events and coverage. It is **not** an economic calendar export and is rejected by default. `AllowSyntheticNewsFixtures=true` is solely for labelled synthetic tests; never use it to claim historical news filtering.

MT5 live/demo calendar values are server-wall timestamps, converted with the configured historical broker clock. Successful bounded queries plus event metadata are required. Untimed/tentative high impact events exclude their entire server day. Live FOMC classification uses `FOMC`/`FEDERAL OPEN MARKET` in name/event code; localization and classification must be checked on the actual calendar feed. Refresh failures block new entries; they do not gate protective management.

## Historical broker offsets

```csv
start_utc,end_utc,offset_minutes
```

Each row defines the broker wall clock as `UTC + offset_minutes` for `[start_utc,end_utc)`. Supply strict UTC timestamps, sorted nonoverlapping rows and integer minute offsets from -840 to +840. Gaps block conversion, rather than extending the last known offset. Provide coverage for the complete warm-up/reference and trade period, including NY midnight and calendar query neighborhoods. Broker ambiguous repeated wall-clock hours are rejected because inverse conversion cannot select an occurrence safely.

`data/broker_offsets_TEMPLATE.csv` contains no offset rows: a broker timezone was not supplied, so no historical broker values have been invented. Fill it from broker documentation, archived server-time observations or independently verified historical records.

## Holiday and early-close overrides

```csv
date,reference_start,reference_end,entry_end
```

Dates are New York calendar dates `YYYY-MM-DD` (dotted form accepted). Windows belong to their starting NY date. Formats:

```text
YYYY-MM-DD,CLOSED,,
YYYY-MM-DD,HH:MM,HH:MM,HH:MM
```

`CLOSED` removes that date. A custom row overrides reference start/end; optional final `entry_end` also changes the entry cutoff/forced close. Reference times must differ. `24:00` is accepted for end times. An end earlier than the start belongs to the next calendar day. A custom row can explicitly open a weekend; otherwise weekends are ineligible. Duplicate dates, malformed fields and extra values on CLOSED rows fail validation.

The template intentionally contains no asserted holidays. Missing overrides cannot reveal an unsupplied special holiday: conservative minute coverage should reject an unexplained shortened session, but verify the actual calendar rather than relying on that side effect.

## Output CSVs

Main audit rows contain signal/trade ID, version/parameter ID, exact symbol and magic, setup/direction, data-mode label, broker/UTC/NY times, profile and signal levels, prices, quantities, costs, slippage, order/deal/position IDs and reason. Text values are CSV-quoted, with line breaks flattened. Execution audit reasons sanitize commas/quotes/newlines to keep each record on one line. Tester runs receive separate audit names/namespaces.

`FILL` and `EXIT_DEAL` link back to persisted signal metadata where available. Requested order details also appear in the execution reason. `planned_risk_account_ccy` is the order's planned risk including configured costs; `initial_filled_stop_risk_account_ccy` reconstructs filled entry-to-initial-SL loss plus charged opening commissions/fees. The latter excludes future unknown exit costs; those enter actual net P/L. An entry deal's R is left blank; exit-deal R is a contribution, not the complete lifecycle R. Sum all opening/closing net P/L and divide by the final initial filled risk for the closed lifecycle. Do not average individual partial-deal Rs. A missing denominator remains blank.

On attach, audit history reconciliation can recover previously unseen own deals. History absence, truncated comments, absent original order metadata or broker-specific charges may limit reconstruction. Deduplicate by deal ID within one run; do not mix multiple tester runs whose deal IDs restart. Equity snapshots are sampled by EA events when equity changes or at least once a minute; they are not an assertion that every exchange/quote tick was observed.
