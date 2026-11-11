# Execution and recovery notes

`Include/BiltechVP/Execution.mqh` uses native trade requests. It does not attach to an account or start a terminal. `AllowLiveTrading=false` rejects entries on real accounts; demo and tester execution are permitted when other checks pass.

## Coordination scope

All portfolio instances must run in **one MT5 terminal on one account/server**. MT5 terminal Global Variables provide a compare-and-swap mutex, an account-symbol instance lease, a persistent magic registry, daily latches, and risk reservations. The namespace includes a hash of account login and server. A unique positive magic belongs permanently to one symbol and group. Account/group IDs and magic values must fit the exact integer range of a double, at most 9,007,199,254,740,991.

The account mutex remains leased for up to six minutes during a native synchronous broker request. A crashed owner can therefore delay reattachment. An idle chart retains its symbol lease for two minutes, refreshed by supervision. Shutdown releases only this instance's lease. Registry ownership, risk journals and group latches remain.

MT5 Global Variables are terminal-local. Multiple terminals, computers, or unrelated EAs do not participate in the atomic reservation protocol. Running a second terminal against the same account is outside the supported portfolio configuration. Terminal-native synchronous `OrderSend` can itself block while the platform waits for the broker; another chart cannot bypass the mutex during that request.

Every Strategy Tester run uses a separate metadata namespace because simulated position identifiers are reused between backtests. A previous tester pass's common-files metadata cannot influence a new run. This also means separate tester passes do not share live portfolio reservations; correlated portfolio evaluation requires combined chronological analysis or a purpose-built multi-symbol harness.

## Risk calculation and fills

Entry sizing calculates account-currency loss using `OrderCalcProfit`, including the configured adverse stop slippage and round-trip commission estimate. Volume is floored to the broker's step. The technical stop is rounded outward to the trade tick; it is never tightened to make minimum volume fit. A minimum-lot risk greater than the budget blocks the entry. `OrderCalcMargin` and `OrderCheck` precede the request.

The account lock covers history reconciliation, group open risk plus outstanding reservations, and the write-ahead reservation before `OrderSend`. Initial SL and TP accompany every entry. Supported FOK is preferred, then IOC. Instant/request execution may use FOK independently of filling flags. Market/exchange symbols advertising neither FOK nor IOC are rejected; RETURN-only operation is outside this implementation.

The initial stop, submitted volume and planned budget persist by position identifier. Actual volume and fill price determine post-fill risk. A fill exceeding the configured tolerance triggers a full safe close. Remaining TP is adjusted to actual average entry plus/minus the configured R times the original stop distance, when broker stop/freeze restrictions allow it. An invalid modification is deferred while existing SL and TP remain active. Missing protection, missing original risk metadata, or an externally widened stop creates a persistent group execution-error latch and safe closure attempts. No break-even, trailing, partial take-profit, recovery sizing or averaging is implemented.

The engine manages positions only when their complete lifecycle proves group ownership. An unrelated existing position/order on the chart symbol blocks entry. A foreign opening/increase contaminates a lifecycle. On a netting account, **any external trade deal in a still-open lifecycle**, including a manual partial exit, causes a management conflict; the engine does not modify that position. Manual exit P/L can still be attributed to an originally group-owned lifecycle when no foreign opening/increase occurred. Such conflicts need operator resolution.

A fresh magic is rejected if it appears in any existing account position, order or available history. Registered magic alone is insufficient to adopt later opening exposure: its structured entry comment must match persisted signal metadata, or the actual order ID must have our stored submission metadata. Unproven exposure carrying a registered group magic blocks group risk checks and is never emergency-closed as though it were ours. Audit metadata fallback also compares the position's own opening signal hash; an old position cannot inherit the latest pending signal merely because its magic was reused.

## Daily baseline and attribution

The daily threshold uses true NY day-start **account equity**, while measured daily P/L contains only the strategy group's realized P/L, commissions, swap and deal fees, plus its floating P/L change since midnight. Position identifiers attribute manual closing deals and close-by deals. Costs booked by a broker as standalone balance adjustments without a position identifier cannot safely be assigned to a group and are excluded from group P/L; reconcile those separately with the broker report.

When supervision sees an exact broker timestamp corresponding to NY midnight, it records account equity and group floating P/L then. A later attachment can reconstruct the baseline only when complete account lifecycle history proves that **the entire account was flat at NY midnight**. In that case, midnight balance plus credit is reconstructed by reversing all subsequent account balance impacts, and the group floating baseline is zero. Current floating P/L is never substituted for the historical baseline.

If any account position spanned midnight and no genuine saved baseline exists, entries remain blocked until a later reconstructable day. Protective supervision continues. Attaching before midnight does not guarantee capture if the broker supplies no midnight tick or time observation. History availability, precision and provenance remain broker dependent; demo verification is required.

Consecutive losses count completed position lifecycles, including entry/exit costs, rather than individual partial exit deals. Zero or positive net results reset the consecutive sequence. Reaching the maximum anywhere in the day latches the group. A daily P/L breach also latches the group until the next NY day. Default action repeatedly closes safely owned group positions. No unrelated position is modified.

## Durable identifiers and pending requests

Comments use `BVP1:<setup number>:<direction 1 or -1>:<signal hash>`. Setup values are 1 = value re-entry, 2 = breakout continuation, 3 = POC bounce. Deal comments fall back to historical order comments and stored order metadata. Missing setup metadata counts conservatively against each candidate setup/direction limit. Filled entries count distinct opening order IDs, so partial fills count once.

A signal is consumed immediately before its one broker submission, after entry filters and `OrderCheck`. Temporary filter rejection leaves the candidate eligible only until its original expiry; an accepted, failed or indeterminate `OrderSend` consumes its durable identifier. FNV hashes compact identifiers; accidental collisions cause conservative suppression/conflicts, and are not a cryptographic identity scheme.

A common-files write-ahead journal persists the risk, signal hash, day, time, original stop and submitted volume. Unknown requests retain full risk indefinitely. Accepted orders retain their reservation until active remainders are canceled and terminal history shows at least every executed lot implied by initial minus remaining order volume. This includes canceled partial fills whose deals arrive after the order status. No timeout alone releases risk. Broker-rewritten/missing comments can prevent proof of settlement; this produces a conservative quarantine requiring operator reconciliation.

Closures also use durable per-position intent and unique `BVPX:<hash>` comments. Accepted or indeterminate closing requests are not duplicated while their result is unknown. Definitive rejections permit a later retry. Residual orders are canceled and actual deal volumes reconciled before a further close, preventing repeated close requests from accidentally reversing netting exposure. A broker that strips these comments can require manual reconciliation before automatic retries resume.

An independently persisted must-close flag retains every required exit until the position is gone. A temporary rejection, NY day rollover, or unavailable time conversion does not cancel that obligation. When a filled position/deal appears before its historical order, matching active reservation metadata supplies its original risk plan; otherwise actual protection remains checked and the full reservation stays held while history catches up.

## Files and reset procedure

Files are stored in the terminal's **Common Files** directory (MT5: File → Open Common Data Folder → Files). Their names begin `BVP1.<account/server hash>`:

- `_registry.csv`: durable magic/group/symbol policy registry; also restores registry state after MT5 Global Variable expiry.
- `_active_<magic>.csv`: unresolved opening reservation journal.
- `_pending_<magic>.csv`: full signal and planned-risk metadata written before submission.
- `_position_<identifier>.csv`: copied position metadata used by the audit log.
- `.G<group>_fatal.txt`: persistent protection-error marker.
- `BiltechVP_execution_<login>_<magic>.csv`: execution events; the main EA also maintains its detailed strategy audit.

Do not remove active journals merely to unblock trading. First disable new entry execution, reconcile broker orders/deals and all open exposure, and resolve ownership. Reset a fatal marker only after the protective problem is understood and exposure reconciled; both its common file and matching terminal Global Variable must be cleared with the EA detached. Registry policy changes should normally use a new group ID. Removal of an old registry is appropriate only for a deliberately verified-flat research reset with no pending/unknown request.

The implementation queries full account trade history for lifecycle attribution. Very large histories can make supervision expensive; this build prioritizes provenance over an unsafe recent-history cutoff. Test terminal responsiveness on the intended demo account. Broker outages and unavailable lifecycle history can prevent safe automated action; the EA blocks new exposure and reports the conflict.

## Verification boundary

Compilation and pure deterministic fixtures do not verify broker execution, server stop enforcement, partial-fill timing, terminal crash recovery, group concurrency, or netting ownership. Those need deliberate demo/tester scenarios and their actual logs. No live account test or performance result is implied by this source.

