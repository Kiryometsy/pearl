# Clipboard persistence implementation plan and final architecture gate

Date: 2026-11-01. Repository: `/home/kiryo/Projects/Clipboard/pearl`.
Branch: `feat/clipboard-persistence`. HEAD and required base:
`4b8097add7de09647382fc6ae88c467ea832d473`.

Status: **feasible for a staged implementation plan; implementation is not authorized**.
No unresolved CRITICAL or HIGH implementation-feasibility contradiction was found.
Operational acceptance, clock ratification, dependency preparation, baseline execution,
and each coding milestone require the separate approvals below. A plan pass is not
a baseline pass, resource-budget approval, or permission to implement.

## 1. Authority, preflight, and evidence

The [functional specification](CLIPBOARD_PERSISTENCE_SPEC.md) is the normative
contract; the [technical design](CLIPBOARD_PERSISTENCE_DESIGN.md) supplies the
proposed architecture. Both were read in full, including their requirement,
acceptance, traceability, failure, and limitation sections. Neither was edited.
`AGENTS.md` requires Zig production code and permits Python testing/harnesses.
Only this plan is an authorized new repository file.

Preflight found the requested branch and exact HEAD/base, no staged or tracked
changes, and only these existing untracked files:

- `docs/CLIPBOARD_PERSISTENCE_SPEC.md`.
- `docs/CLIPBOARD_PERSISTENCE_DESIGN.md`.

Document identities at review:

| Document | SHA-256 |
| --- | --- |
| Specification | `eda17358c4d982df887a0f5be03a35b04a59d375573df872e4773b421de9382a` |
| Design | `0e9b8039cecbc7e16233459fe2b9b907b6a1448a98bef5b372ff236df31b6e31` |

An independent read-only content audit compared requirement-block test lists,
acceptance-block test lists, the specification matrix, and the design matrix.
All four mappings agree: **52 unique requirements, 52 matching acceptance
scenarios, 80 unique proposed tests: 28 UT, 14 FT, 38 IT**. No duplicate test ID
or orphan was found. Repetition of an ID across the four representations is
intentional. These counts describe proposed coverage, not executable tests.

Production and infrastructure evidence inspected directly:

| Files | Finding and consequence |
| --- | --- |
| `src/services/clipboard.zig`, `clipboard_policy.zig` | Baseline is memory-only, 20 entries; front duplicate is a no-op; local producers can mutate before publication succeeds; lock/device loss/stop clear history. Preserve MIME/PNG/transfer defenses while replacing these semantics. |
| `src/config/io.zig` | Existing atomic write loop is reusable, but parent pathname reopening/ignored open failure, path etags, and replacement read cap cannot implement this store. Add a descriptor-based primitive. |
| `src/ui/surfaces/manager.zig`, `src/services/lifecycle.zig`, `capture.zig` | Full privacy predicate exists; screenshot ownership and cancellation are separate. Route every action through that predicate and replace add-then-select. |
| `src/core/application.zig` | `State.stop` immediately calls manager deinit; `cleanup` also calls it. An application hold alone does not preserve manager internals. M6 must split begin-stop from final destruction and gate both paths on drained persistence ownership. This additional change location is necessary to realize design section 7.4. |
| `src/cli/protocol.zig`, `options.zig`, `server.zig`, `src/pearlctl.zig`, `src/aqueous/entities.zig`, `transport.zig` | Flat schema, numeric correlation IDs, eight clients, five-second timeouts, synchronous handler, newline-excluding size check, and queued output require explicit integration work. Client currently exits on envelope `ok` only. |
| `src/desktop/clipboard_capture.zig` | Fixed capacity arrays, ID-only change hash, folded previews, thumbnail decode, obsolete privacy strings, and synchronous removal feedback require revision-based integration. |
| `src/tests.zig`, `build.zig`, root/FFI/translation manifests | Zig 0.17.0 pin; pure test aggregator imports policy and CLI tests. `test` also runs Unicode filtering and translation checks. Build graph can resolve dependencies even for narrow targets. |
| `tests/fixtures/clipboard.zig`, clipboard/calculator/security integrations | Private native producer/session foundation exists; deterministic clocks, storage faults, controlled callbacks, rich MIME offers, and restart preservation do not yet exist. |
| `scripts/test.py`, `test_environment.py`, `test_process.py`, `test-suites.json`, `pearl_session.py`, `build-aqueous-master.py`, manifests, `docs/TESTING.md` | Official evidence/registration, workspace preparation and isolated HOME/XDG/buses/Wayland exist. Native doctor/preparation can start a private compositor; they are not read-only substitutes for approval. |

### 1.1 Gate disposition

| Severity | Finding | Required treatment |
| --- | --- | --- |
| CRITICAL/HIGH | None unresolved within the stated local-filesystem/cooperative-writer threat model | Plan creation permitted. Reopen the gate if implementation disproves an ownership, durability, or isolation invariant. |
| MEDIUM | FIFO barriers can retain hundreds of MiB; the design's additive envelope double-counts some shared/live data | Approve the resource tradeoff and measure distinct allocations at M4/M10; section 2 gives the corrected accounting. |
| MEDIUM | Full-file clock checkpoints write during idle; fast storage can write every mutation | Approve this operational cost or review a design amendment before M2/M4. No numerical write budget has yet been approved. |
| MEDIUM | Startup tolerance remains provisional; clock consistency is not UTC authentication | Ratify 300 seconds explicitly before freezing clock fixtures. |
| MEDIUM | Application stop/final cleanup must preserve service state as well as application lifetime | Include `src/core/application.zig` in M6; prove stop/cleanup/completion ordering before wiring persistence into normal startup. |
| MEDIUM | Proposed tests require new deterministic seams | Implement the bounded reusable seams in section 5 before using their tests as acceptance evidence. |
| MEDIUM | Native fixture, pinned Python dependencies, baseline, physical durability and library RSS remain unverified | M0 and M10/M11 are blocking execution/release gates. Missing evidence is not a passing result. |

The spec and design agree on all normative behavior. The spec's draft header does
not constitute implementation approval; the task treats its requirements as the
functional authority. The design's proposed format, wire syntax, and provisional
clock value still require review. There is no approved total-process RSS or
GiB/day target to claim the current architecture meets.

## 2. Memory architecture review

Let H=16777216 bytes (16 MiB), I=8388608 (8 MiB), T=262144
(256 KiB), N=100, S=65536. H is the **combined live text/PNG payload cap**.
It must never be increased or reinterpreted as an RSS cap. Allocation capacity,
not merely used length, must be counted. Blob headers, fixed arrays, allocator
overhead, thread stack, library allocations, and kernel caches are additional.

| Category / maximum | Owner and lifetime | Simultaneous instances / history charge | Coexistence and required cleanup |
| --- | --- | --- | --- |
| Retained text: each <=T; aggregate <=H | Main-context model holds immutable blob refs until Delete/Clear/expiry/eviction/stop | <=100 rows shared with PNG; live bytes count in H | May coexist with selected/transfer/worker data. Decrement refs on removal; final ref securely zeroes full allocation then frees. |
| Retained PNG: each <=I; combined live payload <=H | Main model, memory only, until removal/stop | <=100 total rows; at most two I-sized PNGs; charged in H | Full text H and PNG H cannot coexist live. Never acquire persistence refs. Same final-zero rule. |
| Independent selected payload: <=I (<=T for text) | Wayland service, until cancellation/replacement/Clear/suspension/stop | One steady; old plus new transiently during prepared replacement; outside H | Survives Delete/expiry/eviction. Preserve old source on preflight failure; zero both proper allocations on eventual release. |
| Incoming raw data: <=I or T plus 64 KiB read scratch | One transfer, until EOF/rejection/replacement/deadline/privacy closure | One; outside H until adopted as canonical input | Can overlap four outgoing transfers and history. Reserve capped capacity; zero full capacity and scratch, remove watches/timer, close FD on every exit. |
| Outgoing transfer copies: <=4I=32 MiB | Four transfer slots until complete/EPIPE/deadline/cancel | Four; outside H | Old selected values can differ from current source/history. Delete does not cancel; Clear/suspension does. Wipe capacities and close each FD. |
| Prepared canonical candidate: <=I or T of new bytes | One non-yielding model/source preflight; candidate row metadata references existing blobs | One candidate, outside H until commit | PNG sanitizer output is this candidate if ownership moves. Never add a second I charge for the same allocation. Abort releases candidate refs/source/projection reservations; commit transfers ownership without allocating. |
| Immutable persistence snapshots: <=H referenced text per snapshot | Active worker, FIFO barriers, latest ordinary pending descriptor | <=34 snapshot descriptors: 32 outstanding removal/retry operations including active removal, one active ordinary, one pending ordinary; outside live H except shared refs | Metadata/timestamps copied; text bytes shared atomically. Replacement, fence, abort, completion and shutdown release refs. A completion owns the active slot's refs, not an extra full snapshot. |
| In-flight worker buffers: S+96+24 plus hash/iteration state | One filesystem worker, operation lifetime | One active disk operation; outside H | Two-pass hashing/streaming adds no H-sized encoding buffer. Wipe scratch, close own temp; preserve effect/cleanup outcome. Worker-local expiry view adds metadata/refs only. |
| Queued operations/receipts | Coordinator owns fixed job metadata, 32 outstanding and 64 terminal receipts | 34 snapshot arrays *100*64 <=217600 bytes; 96 receipts *256 <=24576 bytes, plus fixed headers/control/completion | Terminal receipts contain no payload. 33rd outstanding operation is Busy before mutation; 65th terminal evicts oldest terminal only. No per-copy task or client snapshot. |
| Serialization/decoding | Worker streams codec; decoded blobs staged until full validation/install | Encoding scratch as above; decode <=H+S; outside H until installed | Load/revalidation only after jobs drain/fence. Hidden old live H may coexist with decoded H, not 32 frozen barriers. Corrupt/short/OOM decode wipes all staging and returns no partial model. |
| Restored text | Worker-to-main staging then atomic model install | <=100 blobs, <=H; charged in H after ownership transfer | Do not duplicate all H at install. Fresh IDs/instance do not renew timestamps or publish. Old hidden model and staging are at most 2H before replacement. |
| UI previews/models | Main/view until rebuild/suspension/disposal | <=12100 bytes raw previews; <=102400 folded bytes; query <=4096 and fold <=16384; fixed 100 row metadata | No full-payload model copy. GTK strings may duplicate bounded strings externally. Wipe owned labels/folds/query/identities/feedback; immediately detach labels/thumbnails on suspension. |
| UI thumbnail pixel planes | Main/view GdkPixbuf refs until rebuild/suspension | <=100*160*96*4=6144000 bytes of accounted pixel planes; outside H | Validate actual dimensions/stride. Can coexist with retained PNG/worker refs; release refs on every failed/replaced row. Text/PNG count shares N, making this all-PNG figure loose with full text. |
| PNG decode/re-encode | One synchronous sanitizer: raw <=I, filtered <=I, pixels <=4I=32 MiB, callback output <=I | One sanitizer on main context; outside H until output committed | Fresh wrapper shares pixels. Bounded output sink; reject before append beyond I. Release loader/pixbufs and wipe owned filtered/output on all failures. Library internal copies/workspace remain separate. |
| Errors and teardown | Last owning component, bounded by the same slots | No extra retry/failure payload copies permitted | No realloc that releases old plaintext unwiped; explicit allocate/copy/zero/free. Never zero a shared blob early. Cancel timers/waiters, drain worker and completion, join, detach source, then destroy model/control block. Preserve uncertainty without retaining payload in error messages. |

### 2.1 What the 560 MiB figure means

The design adds live H to 34 possible snapshot references: 35H=560 MiB.
This is a safe loose payload envelope, not a proof that 35 disjoint H allocations
can exist. A pending ordinary snapshot references the latest live text blobs.
An accepted text change replaces it; a removal discards it and installs its
barrier. PNG-only changes add no snapshot blobs. Thus the ordinary pending
descriptor and current live rows do not contribute disjoint H payloads in the
normal admitted state. Prepared transactions add only their new input bytes.

With an active ordinary operation stalled and 32 barriers queued, a tighter
distinct-payload envelope is **active H +32H barrier refs +live H =34H=544 MiB**,
before candidate/source/transfer/UI allocations. An active removal counts within
the 32; that case needs at most 33H. Each actual Delete removes at least one
byte if text, and Clear stores no payload; these reduce attainable maxima.

Hundreds of MiB nevertheless are attainable: pause an ordinary write; cycle in
nearly disjoint full text histories, deleting a tiny marker between replacements
to enqueue each frozen post-Delete barrier; refill/replace before the next
Delete. This requires thousands of accepted copies and 32 outstanding removals,
not ordinary typing or repeated recopy of one blob. Consecutive Deletes without
refills share almost all bytes. A genuinely later copy of equal bytes may create
a new blob because removed history cannot deduplicate through worker-only refs.

Use 560 MiB as the existing conservative design planning envelope until an
allocation-identity proof/test establishes the tighter bound. Do not silently
reduce the approved receipt capacity or H to meet a memory target. Snapshot
metadata can reach 34 arrays even when their referenced bytes overlap.

### 2.2 Steady state, typical peaks, bounded worst case, external allocations

- **Normal steady state:** live <=H, selected <=I, bounded previews/thumbnail
  planes and metadata. No disk jobs when no text and no outstanding removal.
  A full text model plus one maximum text selection is about 16.25 MiB payload;
  100 distinct 256-byte texts use only 25600 bytes of retained payload.
- **Typical peak (illustrative workload, not a measured percentile):** one
  ordinary active write, latest pending refs sharing live text, and one new text
  give near H+T for slowly changing full text. A wholly replaced live model can
  coexist with old active H, near 2H. One PNG sanitation may add raw I+filtered
  I+32 MiB pixels+output I=56 MiB transient working set; old selection and paste
  copies can coexist. Measure on CachyOS before assigning timing/RSS percentiles.
- **Worst-case controlled envelope:** the design already quotes 710852608 bytes
  (677.92 MiB) including old/new source replacement, before metadata/libraries.
  Its terms double-count candidate/output and pending/live refs and combine
  mutually incompatible all-text/all-PNG maxima; it remains a conservative
  budgeting envelope, not an attainable measured peak. Using distinct live/
  snapshot payload <=544 MiB, two source allocations <=16 MiB, four outgoing
  <=32 MiB, incoming <=8 MiB, filtered <=8 MiB, output/candidate <=8 MiB,
  decoded pixels <=32 MiB, thumbnails <=5.86 MiB and two S scratch buffers
  gives `34H+14I+6144000+2S+2 MiB =696238080 bytes` (663.98 MiB),
  even reserving a separate additional I candidate and 1 MiB each for fixed
  bookkeeping and the worker stack. A proposed **680 MiB** controlled-allocation
  guard leaves about 16 MiB slack beyond that additive sum. Enforce/check
  actual stack configuration rather than assume Zig's default. It is a
  proposed allocation-accounting test ceiling, not an RSS guarantee. The
  existing 677.92 MiB formula omitted incoming stack scratch and fixed costs.
  Freeze the final exact owned-allocation assertion at M4 after struct sizes
  and scratch lifetimes are known; do not allocate this envelope eagerly.
- **External/unproven:** GdkPixbuf/libpng encode/decode workspace, GTK texture and
  widget copies, GLib/Wayland allocation overhead, allocator caches, filesystem
  page cache, kernel buffers and the independent screenshot pipeline. Existing
  capture permits a 40 MiB mapping/copy-scale buffer and 24 MiB RGB conversion;
  encoded preview/Save can exceed clipboard I. They are not all clipboard-owned
  allocations and cannot be assigned a proven combined RSS ceiling from this
  design. M10 must report observed RSS separately from owned-allocation counts.

### 2.3 Duplication reductions compatible with the design

Adopt validated incoming text allocation as its immutable blob; transfer restored
blobs into the model; share immutable refs and copy only snapshot metadata; use
streaming codec and callback-bounded PNG output; reuse the pixel plane via the
fresh metadata-free wrapper; release superseded ordinary refs immediately;
reserve bounded scratch/slots once; avoid decoded staging during queued writes.
Do not share mutable model rows with workers or replace independent selection
semantics casually. Outgoing immutable-byte sharing, thumbnail laziness, a
smaller receipt limit, and proof-preserving barrier coalescing require reviewed
ownership/API changes if they depart from the chosen design. No unbounded queue
is acceptable even when storage blocks indefinitely.

## 3. Disk write amplification and operational gate

For N text rows with P payload bytes, snapshot bytes W=96+24N+P; Wmax=16779712.
An empty projection unlinks instead of writing an empty snapshot. A successful
nonempty rewrite ordinarily causes one file fsync and one directory fsync;
first-path link syncs and temp cleanup add calls. Unlink/validated absence and
Clear need directory fsync, even when logical payload bytes written are zero.
These are application logical bytes, excluding metadata/journal/device write
amplification. No SSD lifetime or physical-write estimate is justified without
device/filesystem measurements.

Assumptions for comparable figures: small text=256 bytes; distinct copies reach
100 rows (P=25600, W=28096); one 60-second floor checkpoint per minute while text
remains; instantaneous enough disk that no queue coalescing occurs. Mutation and
checkpoint phases may overlap, so ranges below bound merged vs separate requests.
Steady workloads use unexpired/refreshed rows; an idle store eventually expires
and unlinks after seven days, so idle full-size writes do not continue forever.

| Workload | Bytes per effective mutation / rewrites per hour | Logical bytes/hour | Logical GiB/day |
| --- | --- | --- | --- |
| A: idle empty | 0; no file, no recurring floor write | 0 | 0 |
| A: idle small loaded model | No mutation; 60 checkpoints of 28096 | 1685760 | 0.03768 |
| A: idle full 16 MiB text | No mutation; 60 checkpoints of Wmax | 1006782720 | 22.50335 |
| B: one small copy/minute | W=28096; 60..120 rewrites/h | 1685760..3371520 | 0.03768..0.07536 |
| C: ten small copies/minute | W=28096; 600..660 rewrites/h | 16857600..18543360 | 0.37680..0.41448 |
| D: sixty small copies/minute | W=28096; 3600..3660 rewrites/h | 101145600..102831360 | 2.26078..2.29846 |
| E: recopy existing entry, 60/minute | W of current projection, despite identical payload; 3600..3660/h | Small model: same as D; full model: same as F | Small 2.26078..2.29846; full 1350.20084..1372.70419 |
| F: full text, 60 mutations/minute | Wmax; 3600..3660/h | 60406963200..61413745920 | 1350.20084..1372.70419 |
| F: stress full text, 10 mutations/second | Wmax; 36000..36060/h | 604069632000..605076414720 | 13502.00844..13524.51179 |
| G: PNG admissions evict saved text | Each victim change rewrites remaining text Wj, or unlinks at zero | Sum Wj for evictions, plus floor checkpoints while text remains | 24*hourly sum/1073741824 for a repeating workload |
| H: expiry/deletion | Each expiry batch writes surviving Wj or unlinks; each admitted Delete is a separate barrier | Sum Wj; if m barriers/h near full, <=m*Wmax plus <=60*Wmax floor bytes | <=0.37505579*m+22.50335 while text remains |

For B..D the table is steady state. Starting empty, the first min(100,m) distinct
small copies grow Wk=96+280k, then saturate at 28096; bytes for the first 100
mutation writes total 1423600. B reaches saturation after 100 minutes, C after
10 minutes, D after 100 seconds. These finite warm-up costs replace the same
number of steady-state rewrites; checkpoint bytes use the model at that instant.
Repeated recopy preserves only its row's age; unrefreshed other rows eventually
expire. Same-second recopy still changes sequence and must request persistence.
For a store containing only one 256-byte text, W is 376 bytes; at 60 recopies
per minute the same calculation is 1353600..1376160 bytes/hour, approximately
0.03026..0.03076 GiB/day. Payload equality does not eliminate the metadata write.

For G, inserting two fresh 8 MiB PNGs into a full-text model without intervening
text typically rewrites roughly 8 MiB surviving text once, then unlinks; further
PNG-only churn writes zero text bytes. In a repeating text-refill/PNG-eviction
workload, sum the refill rewrites too. At g text-evicting PNG events/hour with
average surviving snapshot Wbar, write g*Wbar/hour and 24g*Wbar/day, plus ordinary
refills/checkpoints. Never skip a projection change merely because the incoming
kind is PNG. For H, 100 rows expiring on one dispatch should produce one pruned
projection, not 100 ordinary writes. Explicit Delete receipts remain separate
FIFO barriers; Clear writes zero payload but must remove validated temps and
sync. A storm of no-op Clear requests can still cause metadata I/O.

### 3.1 Coalescing, backpressure, loss window and barriers

The existing design can immediately replace one pending ordinary description
with its newest revision and keep only one active operation. This helps when
disk is slower than arrivals; it does **not** rate-limit fast storage. Never
allocate one job per copy. A checkpoint can be satisfied by an already requested
snapshot with an adequate saved floor; comparing floor and descriptor avoids a
redundant write at that instant. Projection identity includes timestamp and
sequence: equal payload is not an unchanged recopy projection. PNG changes that
do not evict text need no text rewrite.

Ordinary pending copies have no hard durability deadline in v1. With healthy
storage and no extra debounce they lose at most the not-yet-committed work at
crash; a blocked disk, FIFO barriers, failed save or explicit-retry fence can
make that time window unbounded. A 60-second checkpoint period bounds dispatch
intent, not durable completion or powered-off time accuracy. Never advertise
“at most one minute of data loss.”

Delete/Clear bypass any proposed ordinary debounce, retain their identity, and
wait behind older admitted effects. Directory/file sync cannot be deferred past
their durable acknowledgement. At three elapsed seconds return non-success
DurabilityUnknown/token when still authorized; five-second transport limits and
privacy may close the waiter sooner. The operation continues without the client.
32 outstanding operations backpressure destructive requests; later writes are
fenced after removal failure or uncertainty. No stale frozen snapshot is retried.

### 3.2 Budget decisions; no implicit architecture replacement

V1 is implementable, but 22.50 GiB/day of idle full-text checkpointing and about
1.34 TiB/day at one full-history mutation/second are substantial writes. They
cannot satisfy a proposed general-purpose budget such as <=1 GiB/day for idle
full text. No such numerical budget is currently approved, so this is an explicit
operational acceptance decision, not an invented normative contradiction.

Before M2/M4 choose and record one reviewed outcome:

1. Accept the measured v1 costs and define deployment-specific write/latency
   budgets compatible with them. No claim of low write amplification is made.
2. Approve a design amendment. A bounded ordinary debounce, for example 250 ms
   quiet time with a 1-second maximum dispatch delay from first dirty revision,
   reduces bursts but still permits ~1.34 TiB/day for sustained one-second
   mutations and does not fix idle checkpoints. Timers cannot reset indefinitely.
   It adds that dispatch delay to ordinary crash exposure, plus storage backlog.
3. For a materially lower idle budget, remove full-snapshot heartbeat rewrites
   via an approved small clock-floor record/journal tied to snapshot identity
   and generation, with atomic ordering, corruption validation, Clear unlink,
   directory sync, and restart rules. This changes the single-authoritative-file
   format/recovery design and is not authorized by this plan. Alternatively,
   approve less frequent full floor checkpoints: <=1 GiB/day requires a period
   of at least about 1351 seconds at Wmax, changing design section 3.2's
   60-second checkpoint policy and weakening restart floor freshness.

An incremental text journal could also lower per-recopy writes, but needs
bounded compaction, removal tombstone proofs, durable generation fencing,
old-segment cleanup, validation limits and plaintext-remnant disclosure. It is
not the smallest v1 implementation. Any amendment must preserve automatic text
saving, recopy age/sequence, seven-day expiry, PNG eviction, durable removal and
no stale resurrection, and be reviewed in the design before implementation.

M10 measures fsync counts, logical/observed host bytes, CPU/hash cost, peak owned
allocations and status/privacy progress. It must fail acceptance if the selected
budget is exceeded; do not silently amend budgets after measurements. Writes
run off GTK, but memory pressure, hashing, sanitizer CPU and storage contention
can still affect responsiveness. Physical wear depends on the actual device.

## 4. Clock policy final review

Recommend **ratifying the existing inclusive 300-second policy**, subject to
explicit approval. It balances small local correction availability against
withholding substantially future state; it is not evidence of authenticated
time. Approval is still required because both documents retain provisional text.

| Event | Precise outcome |
| --- | --- |
| Startup wall 299 seconds behind saved floor F | Accept valid snapshot, effective=max(W,F)=F; preserve last-copy timestamps; prune before exposure; no publication. |
| Exactly 300 seconds behind F | Same acceptance; threshold is inclusive. |
| 301 seconds behind F | ClockUntrusted; no restore exposure/collection/recopy/individual Delete/automatic overwrite; preserve file. Safe privacy/path/lock-authorized Clear remains possible. |
| Large forward adjustment | effective follows wall; prune at the next eligible timer/operation before exposure, possibly expiring everything early; later rollback cannot revive removed entries. |
| Runtime rollback with valid boottime | effective_ns=max(wall_ns, previous_effective_ns+nonnegative elapsed_ns), retaining fractional carry. Ordinary wall rollback alone does not enter ClockUntrusted. Reset/missing/overflowed inputs do. |
| Correction after ClockUntrusted | Correction alone changes no gate. Explicit retry validates privacy/store/lock/format/clock. Runtime retry requires wall no more than 300 seconds behind max(last trusted in-memory floor, stored floor), then resets elapsed origin, seeds at max(floors,wall), prunes and reconnects with initial skip. No recopy/publication. |
| Reboot with untrusted time | New elapsed origin proves no powered-off duration. Invalid local input or F-W>300 withholds unchanged authoritative state until explicit validated retry/Clear. A locally plausible but false wall value cannot be detected reliably. |
| Seven-day boundary | Checked age 604799: retained; 604800 and 604801: expired for text and PNG. Restore/retry never renew age. Independent selected bytes follow DEL-003; Clear/suspension revoke them. |

There is no trusted external clock, tamper-proof floor, or offline elapsed-time
source. Repeated restarts, stalled checkpoint writes, false-but-consistent wall
time and a false forward jump limit real-time guarantees. A saved floor prevents
accepted rollback from rewinding that floor, not arbitrary extension or premature
expiry under bad clocks. Adding external time/hardware trust is out of scope.

## 5. Concurrency, crash safety, and reusable test seams

| Required property | Implementable mechanism / mandatory gate evidence |
| --- | --- |
| One serialized writer | One long-lived worker owns store/lock/codec; no GTask per mutation. Instrument maximum active disk operations=1. |
| Revision/generation tracking | Separate instance, L/P/J/trust E/barrier B and exact content descriptor; checked counters; older result cannot confirm newer P. |
| One active and bounded pending | One active, one latest ordinary pending, <=32 outstanding barriers/retries including active, one control and one completion slot. Metadata and blob identities audited under blocked worker. |
| No stale overwrite | FIFO barriers behind older admitted effects; Clear discards pre-Clear pending; worker holds no replayable old job after barrier. Later equal intentional copy is allowed. |
| Durable Delete | Immediate logical hide only after preflight reservation; write remaining text or sync unlink/absence, including PNG Delete ordering. Acknowledgement follows required sync. |
| Durable Clear | Revoke only Pearl source/cancel transfers; drain older effect, unlink main and every validated payload temp, rescan and sync; later copy waits behind barrier. |
| Queryable receipts | 32 outstanding +64 terminal, new tokens for repair, instance-scoped queries, three-second unknown; original failed receipts stay factual. |
| Cancellation/shutdown | Main revokes admission; no forcible thread detach. App/manager/control block survive until worker+completion drained. Both `State.stop` and `cleanup` use the same idempotent finalization guard. |
| Fsync uncertainty | Phase-rich failed vs uncertain result; post-rename/unlink errors fence all automatic jobs. No rollback rename or invented durable receipt. |
| Callback safety | Stable control block, service lifetime epoch, waiter slot epoch, copied bounded request ID; no retained request arena/UI row pointer. Join before final free. |
| One authoritative writer | Pinned directory lock then stable validated writer.lock nonblocking flock; hold descriptors for lifetime. Within the configured user-wide XDG root; different configured roots are separate stores as the design states. |
| StoreBusy | Loser closes descriptors without payload reads/cleanup/collection/takeover; explicit retry only; external selection preserved. |
| Authoritative-only restore | Load history.bin only; never read/promote temp payload; bounded 128-entry cleanup batches, no name list. |
| Path security | Component-wise NOFOLLOW opens, ownership/mode/nlink/type checks, identity-linked ancestor and leaf revalidation, pinned directory sync. No alternate store or existing chmod/chown repair. |
| Trust/privacy races | Irreversible admission records J/E before syscall without holding main lock across I/O; revocation before admission cancels, after admission fences uncertainty. Privacy closes output immediately but accepted trusted saves may finish hidden. |

No state transition is inherently impossible under the stated boundaries. The
application teardown integration must be made concrete, not assumed solved by
an application hold. The exact generated Wayland marshalling behavior also needs
inspection at M5: all fallible source/request setup must precede the model commit;
once setSelection queues, the event is accepted and later flush failure cannot
roll it back. If generated APIs cannot support the preflight contract, stop M5
for review of a prepared publication adapter; do not silently weaken HIST-003.

Fault/error results must retain known disk-effect identity for revalidation.
Retry of a failed/uncertain Clear first completes its cleanup obligation, then
publishes only genuinely later current text. Retry never replays failed frozen
barriers. Unsupported/corrupt/ClockUntrusted state permits safe Clear only after
privacy, exclusive ownership and path validation; StoreBusy cannot Clear.

### 5.1 Smallest reusable testing interfaces

1. Inject wall/boottime `Sample` provider; pure clock/model with failing allocator
   and final-zero observer. Share this provider with service and worker leases,
   never modify system time or wait seven days.
2. Codec bounded ByteReader/ByteWriter callbacks; exact maximum fixtures generated
   from synthetic bytes. No dependency on GTK/filesystem in codec tests.
3. Store syscall table for descriptor opens/stat/lock/random/read/write/close/
   rename/unlink/fsync/iteration plus deterministic before/after phase hooks.
   Fake durable filesystem separates volatile inode/namespace from synchronized
   crash images; real temp-root tests complement the fake model.
4. Coordinator fake worker/mailbox and explicit scheduler steps: block at admission,
   rename, directory sync and result delivery; no sleeps to guess ordering.
5. Private-root driver process for lock races, restart/new instance and SIGKILL;
   keep only private state between processes. Private native clock/fault controls
   compile only into instrumented artifacts and require private roots/endpoints.
6. Publication adapter failure seams, synthetic multi-MIME/primary/null offers,
   bounded private paste receiver, transport short-write control and waiter slot
   reuse driver. Production artifact probes verify hook rejection.

Current producer lacks the full MIME-order/primary/send-failure controls. Existing
PrivateSession deletes its temporary root at teardown; restart tests need an
explicit preserved private state fixture, not copying the user's state. Real
power-loss persistence is not proved by SIGKILL: use crash images for ordering
and report real-file fsync evidence conditional on filesystem/device guarantees.
Allocation wiping needs an allocator observer; RSS alone cannot prove it.
Rare races and three-second deadlines are unreliable without these seams.
IT-LOCK-001/002 also need a deterministic way to emit second-seat ambiguity,
registry removal and device-finished events. The existing clipboard producer
cannot do that. Use a compile-time-private Wayland adapter event driver or a
reviewed private protocol server fixture; do not manipulate live devices or
assume restarting a producer simulates compositor/device loss. IT-LOCK-003 needs
controlled primary/null first-event ordering. IT-HIST-003 requires publication
allocation/request failure injection; UT/IT-RES-004 require transfer timers tied
to the injected elapsed provider. A real sleep alone is not reliable deadline
or race evidence. Foreign-UID validation and inaccessible-object paths can be
tested with injected stat/syscall outcomes alongside real same-UID mode/link
fixtures; no privileged chown or host permission changes are required.

All automated tests must assert private absolute HOME/XDG roots, headless
compositor endpoints, private buses/PAM and no inherited desktop sockets/FDs
before any child connects. Do not use nested live KDE displays, live wl-copy/
wl-paste, host logind/Polkit, host state or physical reboot. Native manual visual
acceptance uses synthetic data inside the same private environment.

## 6. Baseline and dependency approvals (M0 gates)

Audit inputs carried into this task: Zig 0.17.0 installed; core native-library
checks passed; Aqueous fixture and pinned Python requirements not prepared;
existing unchanged-source baseline not executed. No version command, doctor,
dependency resolver, build, test, compositor or Pearl process was run here.
Historic artifacts are not fresh baseline evidence.

**Production-code changes cannot begin until the unchanged-source CachyOS core
and relevant native baseline is approved, executed, reviewed and accepted.**
Do not update baseline expectations or tests first to conceal an existing
failure. Baseline source identity must equal the reviewed commit; document-only
untracked additions may remain. Existing failures need explicit disposition;
exceptions require human approval and may not waive safety/durability silently.

| Separate approval | Authorized future scope | Inputs, outputs, impact and exit gate |
| --- | --- | --- |
| A: core Zig dependency preparation | Review/fetch only necessary root/FFI/translation Zig graphs into workspace caches; no test execution | Root manifest pins translate-c 2.0.2, zig-wayland v0.7.0, generated ghostty-gobject release `0.11.0-zig-0.17.0-2026-10-02-38-1`; lazy generator commit `4272fe9e0a1b7d8c0e6bd8ffe258e787b80ed038` only if the selected fetch graph requires it. URLs and content hashes in `build.zig.zon`; nested manifests checked too. Store downloads/packages in `.cache/zig`, build cache `.zig-cache`, evidence `.cache/test-preparation`; offline graph roots `zig-pkg` including translation subbuild must be verified/materialized separately. Estimated hundreds of MiB to a few GiB; exact downloaded/unpacked sizes unknown until manifest inspection. No compiler download needed if installed pin matches. |
| B: compositor-free unchanged-source baseline | Run selected existing pure/CLI/policy/translation and native binding/adapter tests; no compositor | Requires A's complete graph and exact toolchain/native versions. Record exit codes, logs, toolchain/source hashes and runner evidence. `.zig-cache`, `zig-out` as graph requires, `.cache/test-runs` evidence; reserve a few GiB provisionally, report actual delta. Any unprepared transitive graph blocks rather than fetches during execution. Stop and review failures before C/D or code. |
| C: native fixture preparation | Review/download/build pinned Aqueous, patched wlroots and matching helpers; prepare pinned Python in local venv; explicitly include the runner's private compositor smoke probe | `scripts/aqueous-target.json`: Seafoam-Labs/Aqueous commit `debc0353e745890f205cd399613f942f83e34986`, helper 0.8.2. `tests/runner-requirements.txt`: Pillow==12.3.0 from approved Python index/cache; availability/compatibility unverified, never silently unpin. `.cache/test-runner/aqueous.git`, `aqueous/production-<input hash>/source`, prefix/bin/logs/metadata, `.deps/wlroots-render-hook`, downloads, Python venv and wheels; shared workspace Zig cache. Provisional several-GiB to tens-of-GiB reserve (e.g. 10..20 GiB), measure/review before exhausting disk. No system install. |
| D: native unchanged-source integration baseline | Execute existing clipboard/capture, calculator, security, lock, lifecycle and capture-master suites in private headless sessions | Requires C validated fixture hashes, real production-policy Vulkan capability where suite demands it, input tools/fonts/PAM/PyGObject/Pillow. Capture per-suite reports/screenshots/logs and source fingerprint. Reserve additional 1..5 GiB evidence provisionally; actual sizes unknown. Missing capability is blocked, never a pass or automatic host package install. Review baseline and explicitly approve M1. |

Preparation scripts already inspected here are the local orchestrator and local
Aqueous builder, not every pinned upstream script or downloaded dependency.
Before C executes `compositor/scripts/build-wlroots-render-hook.sh` or upstream
build hooks, read their exact pinned contents, patch list, URLs, checksums,
subprocesses, network behavior and install destinations. The local builder's
offline flag does not itself prove every invoked shell script honors offline
mode. Review that before running it. If previously unseen hooks expand scope,
stop for approval of the concrete added work. Do not run generic broad prepare
groups that pull unrelated plugin/Rust/Wasmtime/model dependencies.

Generated files stay within Pearl's cache/output directories and private `/tmp`
roots. Core preparation must explicitly set workspace cache paths; never use
system-wide pip, pacman, services, PAM files, compositor installs or parent
workspace metadata. Existing missing native packages are reported for separate
approval; this plan does not prescribe a system installation. Disk estimates
are reservations, not measured claims.

### 6.1 Verified command catalog for later approved execution

All commands below were verified by reading existing parser/build/registry code,
not by executing them. Run from the Pearl root only after the corresponding
approval. No future proposed clipboard-specific target is presented as existing.

| Reference | Command / qualification |
| --- | --- |
| C0 | `git branch --show-current`; `git rev-parse HEAD`; `git status --short`; `git diff --check`; `git diff --cached --check` (separate commands). Include an explicit content-aware scan of untracked documents. |
| C1 | `python3 scripts/test.py list --json` is discovery only; `python3 scripts/test.py run --suite test --dry-run --json` previews commands. Do not substitute native `doctor`: it may start compositor probes. |
| C2 | `python3 scripts/test.py prepare --suite test` is a candidate A command after reviewing its actual fetch scope; it calls `zig build --fetch=all` and may fetch lazy graphs. Approve those exact dependencies first. It does not establish the runner's offline `zig-pkg` layout automatically. |
| C3 | `python3 scripts/test.py run --suite test --offline` is B's core runner command only once root and nested offline graphs exist. Existing direct target: `zig build test -Doptimize=safe`; it can resolve/download if dependencies are absent, so do not use it as an offline guarantee. |
| C4 | `python3 scripts/test.py run --suite test-bindings --suite test-adapter-unit --offline` is B's native compositor-free extension after offline graphs/native prerequisites are verified. |
| C5 | `python3 scripts/test.py prepare --suite test-clipboard-capture --suite test-launcher-calculator --suite test-security --suite test-lock --suite integration --suite test-capture-master` is C's candidate after upstream-script and download review. It includes Python setup, fixture builds, Zig fetch and private smoke execution. |
| C6 | `python3 scripts/test.py run --suite test-clipboard-capture --suite test-launcher-calculator --suite test-security --suite test-lock --suite integration --suite test-capture-master --offline` is D and later relevant native regressions. Runner selects prepared production fixture and supplies artifact paths. |
| C7 | `python3 scripts/test.py run --suite test-i18n --offline` verifies affected translation inventory. Existing aggregate C3 also includes it. |

The executable schema/target names, not environmental readiness, are verified.
The exact offline graph materialization command is **unverified** and deliberately
not invented here. Resolve it in approval A from installed Zig 0.17 tooling and
reviewed package layout, including `translations/build.zig`'s child invocation;
otherwise B is blocked. No new downloads are authorized by B/D. Verify registry
IDs and command syntax again after any relevant infrastructure change.

## 7. Milestone dependencies and delivery discipline

Sequence: M0 -> M1 -> M2 -> M3 -> M4 -> M5 -> M6 -> M7 -> M8 -> M9
-> M10 -> M11 -> M12. M1 needs clock approval; M2 needs format/resource/write
decision; M4 needs the operational budget decision recorded. M3 consumes codec
outcomes; M4 requires real store phase semantics; M6 needs the worker shutdown
contract. M7 completes public destructive operations; M8 completes public
enumeration/feedback. M5 adapters stay isolated/unwired until M6 can preserve
privacy and lifetime, and the public persistence feature stays unavailable until
the M7/M8 contract is complete. Do not ship an intermediate milestone as a feature.

This follows the requested order while explicitly splitting coordinator receipt
mechanics (M4) from UI/CLI destructive command exposure (M7). Preventing an unsafe
intermediate hookup is a dependency constraint, not permission to combine M5–M8
into one large change. Every milestone is a separate review/approval stop.

Each A–P table below is a future work order. Commands C0–C7 refer to section 6.1;
new test target names require future build/registry implementation and syntax
verification before use. “Tests first” requires a real demonstrated expected
failure in that later approved task, never a fabricated red/green transcript.

### M0 — Baseline and safe test-environment preparation

| Item | Milestone contract |
| --- | --- |
| A. Objective | Establish approved unchanged-source CachyOS evidence and private test capability before any production changes. |
| B. Requirements | NFR-002 infrastructure prerequisite for all 52; does not implement feature behavior. |
| C. Exact expected files | No source/test edits. Generated `.cache/test-runner/**`, `.cache/zig/**`, `.zig-cache/**`, `zig-out/**`, verified offline `zig-pkg/**` and `translations/zig-pkg/**`, private temp roots and baseline evidence only. Record acceptance in this plan after separate documentation authorization; spec/design unchanged. |
| D. Interfaces | Official runner, Zig manifests, environment checks, private Aqueous prefix, Python venv, unchanged producer/PAM fixtures. |
| E. Tests first | Existing C3/C4/C6 baseline; inspect assertions and fixture environment before execution. No new behavior assertions or test modifications. |
| F. Expected initial failures | Presently blocked by unprepared native/Python/offline graph prerequisites. Actual baseline failures unknown until separately approved execution; never presume pass. |
| G. Minimal steps | Approvals A, B, C, D separately; review every unseen upstream hook; preserve source fingerprint; run exact selected baseline; review results and obtain explicit baseline acceptance. |
| H. Edges | Installed Zig vs downloaded pin, missing Pillow release, nested translation graph, absent Vulkan, stale fixture provenance, full disk, interrupted preparation. |
| I. Security | Private headless endpoints/UID fixtures; no host clipboard, services, system installation, parent metadata or inherited live sockets. |
| J. Regressions | Existing pure/Unicode/translation, bindings/adapter, clipboard, calculator, security, lock, lifecycle, capture-master suites. |
| K. Commands | C0–C7 only within their separate approval scopes; unknown offline graph preparation remains a prerequisite. |
| L. Evidence | Source/toolchain/dependency hashes, exact commands/exit codes, generated locations, disk delta, private-root assertions, results.json/JUnit/logs and screenshots. |
| M. Acceptance | Baseline reviewed and accepted on unchanged code; no unexplained required failures; environment demonstrably private and reproducible. |
| N. Rollback | Stop only fixture-owned children; keep failure evidence; remove only newly generated task-owned cache paths with approval where required. Never reset source or delete existing caches indiscriminately. |
| O. Out of scope | Feature implementation/test expectation edits, Devario, system package installation, live desktop checks. |
| P. Human approval | A/B/C/D separately, baseline exceptions, added downloads/disk scope, final baseline acceptance, and authorization to start M1. |

### M1 — Pure Zig history model and fake clock

| Item | Milestone contract |
| --- | --- |
| A. Objective | Transactional bounded model, immutable blobs, exact copy/expiry semantics and deterministic time. |
| B. Requirements | Model portions HIST-002..004, RES-001/002/004, TIME-001..006, PERS-001/004, DEL-001/003, SEC-005, CLI-005, NFR-002; integrated portions complete later as mapped in section 8. |
| C. Exact expected files | New `src/services/clipboard_model.zig`, `src/services/clipboard_clock.zig`; extend `src/services/clipboard_policy.zig`, `src/tests.zig`. Inline Zig tests first; no service wiring. |
| D. Interfaces | Model prepare/commit/abort, candidate snapshot, injected Sample/Stamp, fixed row arrays, immutable atomic refs, failing allocator observer. |
| E. Tests first | UT-HIST-002/003/004, UT-RES-001/002, UT-TIME-001..006, model portions UT-PERS-001/004, UT-SEC-005, UT-CLI-005, UT-NFR-002. Allocation failures at every index; H/H+1, 100/101, skew/expiry boundaries. |
| F. Expected initial failures | Missing model/clock interfaces; front recopy no-op and pre-eviction allocation behavior in baseline; missing timestamps/counters. |
| G. Minimal steps | Fixed rows and owning blob type; clock checked arithmetic/fractional carry; allocation-safe prepare; nonallocating commit/prune; candidate snapshot refs; atomic restore install; bounded next-expiry metadata. |
| H. Edges | Expire before failed copy; same-second events; expired duplicate gets new ID; sequence/ID/revision exhaustion; clock reset; safe timeless Clear; PNG text victims. |
| I. Security | Full UTF-8/no NUL; no mutable worker views, early shared wipe or unchecked lengths; no logging payloads. |
| J. Regressions | Existing clipboard policy, CLI/parser/model/Unicode/translation tests through C3. |
| K. Commands | C0, C3; imports must make new pure tests discoverable. |
| L. Evidence | Red/green tests with IDs, deterministic samples, invariant/property cases, allocator/refcount/zero observations and no leaks. |
| M. Acceptance | Every commit <=100/H; abort preserves nonexpired model; all clock boundaries exact; no GTK dependency; fresh/nonreused identities. |
| N. Rollback | Revert only reviewed milestone diff after approval; modules remain unwired and disk untouched. Preserve tests/evidence for review. |
| O. Out of scope | Filesystem, threads, Wayland/UI, real clock changes, reduced history cap. |
| P. Human approval | Accepted M0, ratified 300 seconds, counter/clock API review; stop on normative ambiguity; obtain approval before M2. |

### M2 — Binary codec and bounded validation

| Item | Milestone contract |
| --- | --- |
| A. Objective | Exact v1 byte format with streaming bounded all-or-nothing encode/decode. |
| B. Requirements | PERS-003; codec portions RES-002, TIME-005, PERS-001, SEC-005, ERR-002/003, NFR-002. |
| C. Exact expected files | New `src/services/clipboard_codec.zig`; extend `src/tests.zig`; synthetic byte fixtures inline in codec tests, not copied user state. |
| D. Interfaces | ByteReader/ByteWriter, validateHeader, digest/encode/encodedSize/decode, LoadedText and immutable Snapshot. |
| E. Tests first | UT-PERS-003 plus codec parameters in UT-RES-002, UT-TIME-005, UT-SEC-005; malformed/unsupported cases later reused by FT-ERR-002/003. |
| F. Expected initial failures | No magic/header/record layout, integrity validation, streaming callbacks or exact EOF behavior. |
| G. Minimal steps | Encode explicit LE integers/96-byte header/24-byte record; hash header prefix+records; first digest pass then stream; validate file size/count/sums before record allocation; decode into isolated blobs then install only on full success. |
| H. Edges | Exact Wmax=16779712; spec ceiling 16842752; zero-record valid fixture vs zero-byte corrupt; duplicate text/sequence, future record, truncation, reserved bits, trailing byte, OOM. |
| I. Security | Checked arithmetic/lengths before allocation; no PNG/ID/instance/paths; raw text plaintext explicitly; SHA is integrity, not authentication. |
| J. Regressions | C3 including model/clock/policy/CLI and translations. |
| K. Commands | C0, C3; no filesystem target yet. |
| L. Evidence | Golden offsets/endianness, max roundtrip, byte-region fault coverage, fixed scratch/capacity accounting, wiped partial loads. |
| M. Acceptance | One valid canonical representation, fully bounded decode, no partial restore, no H-sized serialized buffer or opaque object dump. |
| N. Rollback | Unwired module rollback; do not rewrite any real snapshot or change spec/design to match implementation. |
| O. Out of scope | Journal/format amendments without review, migration, actual persistence. |
| P. Human approval | Format v1 ratification and operational/resource option from section 3; changed design requires separate reviewed amendment; approval before M3. |

### M3 — Private filesystem store and atomic durability

| Item | Milestone contract |
| --- | --- |
| A. Objective | Anchored private store with stable writer exclusion, atomic publication and phase-accurate durability. |
| B. Requirements | PERS-006/008; SEC-001/002/003/006; filesystem parts PERS-003/005, DEL-001/002/004, ERR-002/003/004, NFR-002. |
| C. Exact expected files | New `src/services/clipboard_store.zig`, `src/clipboard_store_tests.zig`; additive `src/config/io.zig`; `build.zig`, `scripts/test-suites.json` registration. No broad path-helper behavior changes. |
| D. Interfaces | Private-root constructor, AtomicSyscalls/PublishOutcome/atomicAt, pinned ancestors/dir/lock/history identities, codec stream adapter and deterministic durable-image test filesystem. |
| E. Tests first | UT-SEC-001; FT-PERS-006, FT-SEC-001/002/003/006, filesystem halves FT-DEL-001/002/004, FT-ERR-002/003/004; two-process private flock race precursor to IT-PERS-008. |
| F. Expected initial failures | Current io helpers lack pinned-parent acknowledgement and full validation; no store lock protocol, temp scanner or injected crash images. |
| G. Minimal steps | Pure XDG resolver; component walk and exact newly created modes; directory then file lock; authoritative load; additive atomicAt; fsync content/parent/new links; safe unlink and batched temp cleanup; errors mapped by irreversible phase. Review each security boundary separately. |
| H. Edges | Umask strips owner bits; sticky /tmp; 256 components; file/lock inode swaps, FIFO, nlink>1, absent main/newer temp, 128/129 entries, EINTR/short/zero write, close/fsync failure, applied-then-error. |
| I. Security | Never follow symlinks, repair existing permissions, read losing-process history or remove unrelated/unsafe objects. Same-UID malicious race isolation remains outside guarantee. |
| J. Regressions | C3/C4 and affected existing I/O users' private preference/capture-save regressions through relevant C6 suites. |
| K. Commands | C0, C3/C4; new private store target must first be registered and verified in build/runner, then report its exact approved command. |
| L. Evidence | Syscall-order/identity traces, phase faults, synchronized crash images, untouched outside sentinels, file/dir modes, stable lock inode, bounded iterator/FD accounting. |
| M. Acceptance | No required sync/open failure earns durable; no main-file in-place writes; only authoritative restore; loser inert; faults clean owned buffers/FDs. |
| N. Rollback | Stop private drivers; preserve images; undo additive primitive/store diff only after review; never rename old plaintext back as runtime rollback. |
| O. Out of scope | Real user state, deployment, path-helper overhaul, network filesystem certification. |
| P. Human approval | Local filesystem support target, additive io API and any unrelated caller change; approve milestone before M4. |

### M4 — Serialized background persistence coordinator

| Item | Milestone contract |
| --- | --- |
| A. Objective | Bounded single-writer scheduling, trust/revision barriers, internal receipts and safe worker lifetime. |
| B. Requirements | RES-004, PERS-004/005/007/009, NFR-001; coordinator parts PERS-001, TIME-003/006, DEL-001/002/004, ERR-001/003/004, SEC-005. |
| C. Exact expected files | New `src/services/clipboard_persistence.zig`, `src/clipboard_persistence_tests.zig`; extend model/clock/store as interfaces require; `build.zig`, `scripts/test-suites.json`. |
| D. Interfaces | One Thread, mailbox Mutex/Condition, eventfd completion, ClockLease, L/P/J/E/B, exact projection identity, fixed receipt ring, beginShutdown/isDrained/deinitDrained. |
| E. Tests first | UT/FT-PERS-005, UT-PERS-004/007, FT-PERS-009, FT-DEL-001/002/004, FT-ERR-001/003/004, UT-RES-004, UT-NFR-001; deterministic worker blocks and allocation identity measurements. |
| F. Expected initial failures | No worker/coalescer, receipts or stale-result handling; no ownership hold during blocked I/O. |
| G. Minimal steps | Preallocate slots; reserve candidate refs before model commit; serial loop/completion mailbox; exact revision tracking; FIFO removal barriers; failure fences/latest-state repair; checked token/counter limits; drain/join API; checkpoint requests per approved policy. |
| H. Edges | 32/33 outstanding, 64/65 terminal, timeout/lost waiter, trust revoke before/after admission, Clear/new equal copy, older result, notification failure, blocked fsync/stop, worker-pruned descriptor. |
| I. Security | No GTK/model pointer in worker; never lock across I/O/zeroing; release frozen refs after fence; no stale snapshot replay or callback into freed service. |
| J. Regressions | C3 plus new M3 private store and M1/M2 tests; C4 if eventfd main-context adapter uses GIO test driver. |
| K. Commands | C0/C3/C4 as applicable; newly registered coordinator/store commands verified before execution. |
| L. Evidence | Deterministic schedules, max active I/O=1, bounded slots/metadata/allocations, distinct blob accounting, repaired latest projection, no post-barrier old publication, stopped thread before frees. |
| M. Acceptance | All 15 properties in section 5 hold at component level; budget decision recorded; no unbounded queue, false durable state or leak. |
| N. Rollback | Keep worker adapter unwired; drain test-owned worker before reverting; preserve failure images/traces. |
| O. Out of scope | Public CLI/UI receipts, production startup wiring, unapproved debounce/coalesced removal/journal. |
| P. Human approval | Exact resource/stack sizes, write policy/budgets and phase outcomes; approval before M5. |

### M5 — Wayland clipboard integration

| Item | Milestone contract |
| --- | --- |
| A. Objective | Transactional external/internal copy adapters preserving independent source/transfer semantics. |
| B. Requirements | HIST-001..005, RES-002/003/004, TIME-002, PERS-001, DEL-003, SEC-004; later lifecycle wiring required for full acceptance. |
| C. Exact expected files | `src/services/clipboard.zig`, `clipboard_policy.zig`, `capture.zig`; `tests/fixtures/clipboard.zig`, `tests/integration/test_clipboard_capture.py`, `test_launcher_calculator.py`; `build.zig` for instrumented adapter fixture only if needed. |
| D. Interfaces | Prepared model/source request, publication adapter, sanitizer bounded callback sink, receive/send epochs, calculator copyText and screenshot single-copy entry point. |
| E. Tests first | UT/IT-HIST-001/002/003/004, IT-HIST-005, UT/IT-RES-002/003/004, IT-TIME-002, IT-PERS-001, IT-DEL-003, IT-SEC-004. Fault source allocation and marshalling before model commit. |
| F. Expected initial failures | Baseline retains before local publication, front duplicate does nothing, screenshot add-then-select splits one logical action, sanitizer output unbounded until after encode. |
| G. Minimal steps | Audit pinned generated Wayland calls; prepare all fallible bytes/source/metadata; queue then nonfallible model commit; exact receive validation/dedup; callback-bounded PNG sanitation; cap transfer capacity and full wipe; keep adapter isolated from ordinary startup until M6. |
| H. Edges | Primary/null first, mixed MIME order and all sensitive hints, failed/partial EOF, source cancel/EPIPE, four old transfers, fresh equal copy after removal, oversized screenshot still Save-able. |
| I. Security | Never receive sensitive-hinted offer; no PNG metadata re-export, no new connection reader alongside GTK, no external-owner selection clearing. |
| J. Regressions | C3, C6 clipboard/calculator/capture-master; retain actual private paste and PNG pixel/metadata checks. |
| K. Commands | C0/C3; selected existing runner suite commands from C6 against instrumented private adapter only after verified hookup. |
| L. Evidence | Publication event vs persistence traces, old source survives preflight failure, one event per local action, private receiver bytes, PNG limits/stripping, no unintended desktop endpoints. |
| M. Acceptance | No allocation failure can partially evict/history-refresh; queue success is not paste success; H/transfer bounds preserved; production hookup remains gated on M6. |
| N. Rollback | Drain fixture adapter and disable hookup; revert only this milestone's reviewed source/test diff. |
| O. Out of scope | Live clipboard, synthetic paste, new PNG worker architecture, general screenshot Save limits. |
| P. Human approval | Stop if generated marshalling defeats preflight; review necessary adapter scope change; approve before M6. |

### M6 — Lock, unlock and lifecycle integration

| Item | Milestone contract |
| --- | --- |
| A. Objective | Hidden retained history with safe startup, suspension/resume, clock expiry and asynchronous application teardown. |
| B. Requirements | LOCK-001..004, PERS-002/008/009, TIME-003/006, NFR-001; privacy parts CLI-004, ERR-004, DEL-002. |
| C. Exact expected files | `src/services/clipboard.zig`, `clipboard_persistence.zig`, `src/ui/surfaces/manager.zig`, `src/core/application.zig`; `src/services/lifecycle.zig` and `capture.zig` only where notification/cancellation adapter requires change; `tests/integration/test_clipboard_capture.py`, `test_security.py`, `test_lifecycle.py`, new `tests/integration/test_clipboard_persistence.py`; `build.zig`, `scripts/test-suites.json`. |
| D. Interfaces | Full privacy predicate, suspension vs explicit Clear, async load/deferred locked startup, app hold and begin/final-stop split, service/control epochs, preserved private restart state. |
| E. Tests first | IT-PERS-002/008/009, FT-PERS-009, IT-LOCK-001..004, IT-TIME-003/006, IT-NFR-001, IT-ERR-004. Pause worker then invoke both application stop and final cleanup; dispatch a late result. |
| F. Expected initial failures | Lock/device loss clears rows; locked startup has no load gate; immediate manager deinit destroys state before persistence completion. |
| G. Minimal steps | Compose every gate, hide/revoke/cancel synchronously, retain/prune model, initial skip on reconnect, defer unsafe load; integrate worker source; stop admission first and defer final manager/application cleanup until drained; make repeated stop/cleanup idempotent. |
| H. Edges | Overlapping Polkit/inactive/lock/preparing gates, second seat process lifetime, IPC loss, dead device, sleep elapsed time, ClockUntrusted retry, blocked stop, unloaded exit. |
| I. Security | No loaded content/metadata before gate; no unlock/restore publication; no stale capture completion; no callback to destroyed manager despite app still alive. |
| J. Regressions | C3/C4/C6 including lifecycle/security/lock/capture/calculator; private model/store/coordinator suites. |
| K. Commands | C0/C3/C6; register and verify new persistence integration command before use. |
| L. Evidence | Per-reason gate traces, private restart images and fresh IDs, source revocation/initial skip, pending save during lock, blocked-worker responsiveness, lifetime/zero observer. |
| M. Acceptance | History survives suspension but cannot expose/replay; text-only restart eligible; stop never writes teardown empty or frees worker-owned state. Public feature remains unavailable until M7/M8 contracts complete. |
| N. Rollback | Stop fixture sessions via drain; remove startup hookup while retaining pure modules; never use lock as a rollback Clear. |
| O. Out of scope | Host session/PAM/logind configuration, physical sleep/reboot, real KDE or Devario. |
| P. Human approval | Application teardown diff review and any lifecycle contract expansion; approval before M7. |

### M7 — Delete, Clear and asynchronous operation receipts

| Item | Milestone contract |
| --- | --- |
| A. Objective | End-to-end durable destructive operations with queryable bounded receipts and privacy-safe deferred replies. |
| B. Requirements | DEL-001..004, PERS-005/006/007, ERR-001/003/004, CLI-004/005, UI-002; public health/pagination finalization in M8. |
| C. Exact expected files | `src/services/clipboard.zig`, `clipboard_persistence.zig`, `src/ui/surfaces/manager.zig`, `src/cli/server.zig`, `protocol.zig`, `options.zig`, `src/pearlctl.zig`, `src/aqueous/transport.zig`; new `src/clipboard_protocol_tests.zig`; extend new persistence integration, clipboard/security integrations; `build.zig`, `scripts/test-suites.json`. |
| D. Interfaces | Deferred handler union/WaiterKey, copied correlation ID, slot epoch, operation token ring/result/retry, gate-aware queued send, receipt-aware exit status. |
| E. Tests first | UT/IT-PERS-007, FT/IT-DEL-001/002, IT-DEL-003, FT-DEL-004, UT/IT-CLI-005, IT-CLI-004, FT/IT-ERR-001/004, FT-ERR-003. Unknown/failed receipt must not be success; lock unsent and partially sent replies. |
| F. Expected initial failures | Current handler replies immediately, clear/delete report success before disk, no token/query, no copied deferred lifetime, client exits zero for envelope-ok failed operation. |
| G. Minimal steps | Add scoped fields/commands and errors; reserve removal before logical mutation; connect barrier/receipt; detach waiters on timeout/socket/privacy; recheck full gate before each send; zero or close queued sensitive frames; new-token latest-state repair. |
| H. Edges | Three-second deadline vs older five-second socket deadline, disconnect/reused slot, 33rd request, 65th terminal receipt, missing/prior instance, Clear corrupt/future file, concurrent later copy, partially cleaned temps. |
| I. Security | Locked before membership lookup; no token/count/path details under suspension; no request-arena retention; Clear cannot bypass path/lock, Delete cannot bypass clock. |
| J. Regressions | C3/C4, relevant C6 suites plus new store/coordinator/protocol driver; unrelated transport consumers must retain their behavior. |
| K. Commands | C0/C3/C4/C6; new protocol driver command only after registration verification. |
| L. Evidence | Red/green wire fixtures, receipt state schedules, partial-send privacy trace, fsync-before-ack, restart after durable removals, client exit codes/full JSON. |
| M. Acceptance | Hidden != durable; acknowledged removals cannot resurrect from old jobs; failed removals remain hidden; all async ownership bounded and epoch-safe. |
| N. Rollback | Stop private clients, drain worker and detach waiters; disable public destructive routes before reverting integration; preserve private crash evidence. |
| O. Out of scope | Durable receipt journal across restart, indiscriminate barrier coalescing, live deletion/clear. |
| P. Human approval | Wire/error/exit compatibility review, transport callback API review; approval before M8. |

### M8 — CLI pagination and UI integration

| Item | Milestone contract |
| --- | --- |
| A. Objective | Complete bounded status/navigation and truthful persistence/removal UI for all 100 rows. |
| B. Requirements | CLI-001..005, UI-001/002, COMP-001, SEC-005; outcome portions PERS-004/007 and DEL-004. |
| C. Exact expected files | New `src/cli/clipboard_status.zig`; `src/cli/protocol.zig`, `options.zig`, `server.zig`, `src/pearlctl.zig`, `src/desktop/clipboard_capture.zig`, `src/ui/surfaces/manager.zig`; `src/clipboard_protocol_tests.zig`, `src/tests.zig`, `tests/integration/test_clipboard_capture.py`, `test_clipboard_persistence.py`, `test_launcher_calculator.py`; affected `translations/pearl.pot` and `translations/de/pearl.po` after verifying their domain inventory; `build.zig`, `scripts/test-suites.json`. |
| D. Interfaces | Bounded status encoder, revision/instance pins, capability object, UI record/cursor identity, bounded filter/query, privacy rebuild and receipt feedback. |
| E. Tests first | UT/IT-CLI-001/002/005, UT-CLI-003, IT-CLI-004, IT-UI-001/002, UT/IT-COMP-001, UT/IT-SEC-005. Use max request ID/u64, worst escaped UTF-8 preview and every response/error family. |
| F. Expected initial failures | Baseline oversized all-entry status, no continuation/instance, newline off-by-one, ID-only refresh, 20-row expectations and clear-on-lock wording. |
| G. Minimal steps | Fixed complete-frame encoder <=8192 including LF; shrink returned count with >=1 progress; exact default/range/pins; health distinct from incoming pending; revision-driven rows; 100-row filter/navigation; pending/failed/uncertain/removal feedback, retry, safe Clear for blocked payload trust; update verified strings. |
| H. Edges | Offset=total/100, limits 0/21, expiry between pages, front duplicate unchanged IDs, no-match Delete, PNG thumbnails, quoted/control previews, legacy generation-only actions. |
| I. Security | No full payload/path; privacy redacts counts/revisions/instances/tokens; wipe query/folds/labels/thumbnails and unsent output; generic errors must remain bounded. |
| J. Regressions | C3/C7 and clipboard/calculator/security C6 selections, transport/protocol tests and new persistence suite. |
| K. Commands | C0/C3/C6/C7; confirm catalog update tooling from current repo before generating catalogs. |
| L. Evidence | Byte-measured complete JSON+LF, stable 100-row traversal without duplicates, stale-pin errors, correct UI targeting/screenshots, exact strings/catalog inventory, marker absence. |
| M. Acceptance | All frames fit, all rows reachable, no-match preserves data, no metadata leak, stages accurately described; full feature integration can now be reviewed. |
| N. Rollback | Disable full feature hookup; revert reviewed UI/protocol/catalog changes together to avoid mixed identity versions; preserve disk state, never migrate backwards automatically. |
| O. Out of scope | UI redesign, new MIME kinds, full-payload export, unrelated translation edits. |
| P. Human approval | Compatibility/wire/UI wording and final catalog file inventory; authorize M9 after reviewing complete integration. |

### M9 — Complete integration and regression tests

| Item | Milestone contract |
| --- | --- |
| A. Objective | Execute every proposed ID with meaningful boundary/failure parameterization and full private integration regression. |
| B. Requirements | All 52, completing all 80 IDs in section 8; no new functional scope. |
| C. Exact expected files | `tests/integration/test_clipboard_persistence.py`, `test_clipboard_capture.py`, `test_launcher_calculator.py`, `test_security.py`, `test_lifecycle.py`; `tests/fixtures/clipboard.zig`, `scripts/pearl_session.py` for explicitly preserved private state only; `src/clipboard_store_tests.zig`, `clipboard_persistence_tests.zig`, `clipboard_protocol_tests.zig`, affected module inline tests; `build.zig`, `scripts/test-suites.json`. |
| D. Interfaces | Existing runner evidence, private restart/crash driver, clock/fault controls, artifact isolation assertions, current production/test binaries. |
| E. Tests first | Fill any unimplemented parameter sets in all 80 rows; cross-cut privacy and durability negative schedules from section 8.1. Add a regression case before each discovered fix. |
| F. Expected initial failures | Missing native restart/fault/clock orchestration or uncovered semantic assertions; do not assert in advance that implementation will pass. |
| G. Minimal steps | Audit mapping against actual test case names; register suites; generate only synthetic data; run targeted ID groups, then relevant regressions; review production hook rejection; record all failures/approved exceptions. |
| H. Edges | Restart with different instance/equal IDs, producer exit, lost receipt, seven-day exact boundary, locked startup, two sessions/one store, malformed/unsupported file, storage stalls and late callbacks. |
| I. Security | Fail closed before child creation on any live endpoint/root; never scan real clipboard artifacts; synthetic secret markers only. |
| J. Regressions | C3/C4/C6/C7 and newly registered feature suites; changed baseline expectations justified explicitly, retained privacy/paste/PNG/cancel coverage checked. |
| K. Commands | C0/C3/C4/C6/C7 plus verified new registered suite commands, recorded exactly in evidence. |
| L. Evidence | Per-ID result table, parameters/seeds, exact commands, JUnit/results/logs/screenshots, source/fixture hashes and failure dispositions. |
| M. Acceptance | 52/52 requirements and 80/80 proposed IDs have actual evidence or explicit approved exceptions; no hidden skip, unregistered test or weakened unchanged regression. |
| N. Rollback | Revert only reviewed harness/fix changes; preserve failing evidence; stop fixture-owned processes and leave real desktop untouched. |
| O. Out of scope | Performance acceptance by anecdote, deployment, unapproved broad refactoring. |
| P. Human approval | Any exception/changed acceptance assertion, additional suite dependencies and approval before M10. |

### M10 — Security, fault-injection and performance validation

| Item | Milestone contract |
| --- | --- |
| A. Objective | Prove failure boundaries/resource bounds and measure approved operational budgets on CachyOS. |
| B. Requirements | RES-001..004, TIME-004..006, PERS-003..009, DEL-001..004, SEC-001..006, CLI-003/004, ERR-001..004, NFR-001/002; revalidate all cross-cutting invariants. |
| C. Exact expected files | Extend `src/clipboard_store_tests.zig`, `clipboard_persistence_tests.zig`, `clipboard_protocol_tests.zig`, new `tests/integration/test_clipboard_persistence_performance.py`; `tests/integration/test_clipboard_persistence.py`, `build.zig`, `scripts/test-suites.json`. Evidence under `.cache/test-runs/**`; budget/signoff records in this plan after approval. |
| D. Interfaces | Syscall phase faults/durable images, allocator observer, scheduler trace, private performance driver, process RSS/host write observations separate from logical writes. |
| E. Tests first | Every FT ID and resource/security/NFR UT/IT cases; workloads A–H, disjoint-barrier memory saturation, allocation failure paths, malformed-input bounded corpus, production hook rejection and support-marker scan. |
| F. Expected initial failures | Missing instrumentation or violation of selected numerical budget; do not retroactively relabel a failing budget as report-only. |
| G. Minimal steps | Run deterministic phase matrix; repeat only nondeterministic native races as justified; benchmark empty/small/full models and blocked disk; measure active/pending/ref counts, logical bytes/fsyncs, status/privacy dispatch order and observed RSS/latencies; review findings. |
| H. Edges | 32 barriers with near-disjoint full payload, temp clutter batches, ENOSPC/EIO/fsync uncertainty, worker notification failure, applied-then-error, main shutdown/reused client slot, PNG external workspace. |
| I. Security | No marker in logs/support/closed-gate output; validate sentinels/modes/locks/path identities and unmodified invalid files; tests have bounded CPU/disk and approved private roots. |
| J. Regressions | C3/C4/C6/C7 plus all new feature suites after any fix; no redundant full reruns once evidence remains valid. |
| K. Commands | Existing C0/C3/C4/C6/C7; verify/register performance/fault commands before running. No unverified perf/fuzz flags are prescribed. |
| L. Evidence | Owned-allocation vs RSS charts/tables, workload input/rate/duration, p50/p95/p99 and maxima where measured, logical/host bytes, fsync counts, seeds, phase coverage and zero/leak results. |
| M. Acceptance | Selected preapproved budgets met; one active/no growth; deterministic privacy progress before worker release; every applicable negative/failure path passes; filesystem guarantees qualified honestly. |
| N. Rollback | Stop synthetic workload and drain fixtures; preserve images/results; any architecture amendment returns to review, not an ad-hoc optimization. |
| O. Out of scope | SSD lifetime certification, root/same-UID isolation promises, physical power-loss or universal filesystem certification. |
| P. Human approval | Numerical budget ratification before execution, stress disk/memory allowance, proposed architecture change, exceptions; approval before M11. |

### M11 — CachyOS acceptance and documentation finalization

| Item | Milestone contract |
| --- | --- |
| A. Objective | Reviewed CachyOS feature acceptance with accurate plaintext/privacy documentation and requirement signoff. |
| B. Requirements | All 52, especially UI-001/002, COMP-001 and NFR-002; no unreviewed new behavior. |
| C. Exact expected files | `docs/CLIPBOARD_CAPTURE.md`, `docs/TESTING.md`, this plan's acceptance/evidence record; existing affected translations from verified M8 inventory only. Spec/design stay unchanged unless a separately approved amendment explicitly authorizes their edits. |
| D. Interfaces | Complete feature in isolated CachyOS native session, runner reports, signoff matrix and user-facing help/wording. |
| E. Tests first | Recheck every section 9 criterion against actual evidence; private manual visual/keyboard review of restored 100-row history, pending removal/retry and lock/unlock; automate any newly found reproducible bug before fixing. |
| F. Expected initial failures | Missing signoffs/evidence and obsolete memory-only/clear-on-lock documentation; actual visual issues unknown. |
| G. Minimal steps | Review complete diff/results/limitations, update affected docs, re-run only affected checks, complete all 52 signoffs, report CachyOS acceptance status and stop. |
| H. Edges | Plaintext/unmarked secrets, data copied elsewhere, unknown pre-ack crash result, unsupported store recovery, external libraries and offline clock limitations. |
| I. Security | Never collect live status/real payload into documentation/screenshots/support reports; review synthetic artifact privacy. |
| J. Regressions | C3/C6/C7 as relevant to final changes; preserve M9/M10 evidence for unchanged source and rerun affected suites after fixes. |
| K. Commands | C0 and applicable verified runner commands; documentation content-aware whitespace check includes untracked files. |
| L. Evidence | Final per-requirement signatures/links, accepted exceptions, commands/source hashes, private visual evidence, exact final git status. |
| M. Acceptance | Every definition-of-done criterion met; no unknown mandatory result; approved budgets satisfied; accurate storage/privacy claims. |
| N. Rollback | Withhold acceptance/release; revert only reviewed wording/integration as approved. Never erase private stores or downgrade binary format as a documentation rollback. |
| O. Out of scope | Live desktop use, automatic commit/push/package deployment, Devario execution. |
| P. Human approval | Final CachyOS acceptance and explicit separate permission to author/review M12; no automatic next milestone. |

### M12 — Devario acceptance plan (no deployment)

| Item | Milestone contract |
| --- | --- |
| A. Objective | Produce a concrete later Devario validation proposal only after CachyOS signoff. |
| B. Requirements | All 52 carried forward as platform acceptance obligations, especially PERS-006/008, SEC-001..003, COMP-001, NFR-002. No claim they pass on Devario. |
| C. Exact expected files | This plan's Devario appendix only; read `packaging/Devario/pearl/PKGBUILD` and `packaging/Devario/pearl-git/PKGBUILD` without modifying them. No new deployment files. |
| D. Interfaces | Approved source/format, packaging expectations, proposed private state roots/filesystem, exact toolchain/native fixtures and platform evidence template. |
| E. Tests first | Carry the 80-ID matrix and approved CachyOS workloads forward; define environment/permissions/fsync/flock/clock/PNG/CLI compatibility checks before any future run. Execute none. |
| F. Expected initial failures | All Devario prerequisites/results initially unverified; a plan has no test pass. |
| G. Minimal steps | Review packaging/platform assumptions read-only; list required versions and safe fixture destinations; propose separate dependency/baseline/execution approvals; document stop/rollback/evidence rules. |
| H. Edges | Different filesystem/UID/XDG setup, Wayland/native versions, clock after reboot, packaging paths and lock competition. |
| I. Security | No SSH, remote copy, state transfer, live clipboard, service/system configuration or deployment authorized. |
| J. Regressions | Specify future private core/native suites and all feature IDs; do not run them here or during this planning milestone. |
| K. Commands | C0 for local source identity only; no unverified Devario command is offered as runnable. |
| L. Evidence | Reviewable platform checklist, missing-prerequisite inventory, separate approval boundaries and evidence schema. |
| M. Acceptance | Complete proposed validation scope with no Devario testing/deployment started; CachyOS already accepted. |
| N. Rollback | Revise/withdraw proposal; there is no deployed state to undo. |
| O. Out of scope | All Devario execution, package publication, installation and rollout. |
| P. Human approval | Approval of the plan is distinct from later preparation/testing/deployment; stop after reporting. |

## 8. Complete requirement and proposed-test traceability

One row per requirement below includes its acceptance scenario and every proposed
test ID exactly once. A slash between types/milestones follows the same order as
the test IDs. Cross-cutting parameter sets in section 8.1 are part of these IDs,
not invented replacement IDs. Milestones list first component implementation and
native completion; M9 reconciles evidence for all rows, M10 stress/fault checks
supplement them, M11 signs off every row.

Test-type key: Z=pure Zig; F=temporary local filesystem; C=deterministic fake
clock; S=storage/syscall fault injection; W=private Aqueous/Wayland integration;
R=process restart; K=crash/forced termination; V=manual verification adjunct.
Combinations are required capabilities. FT cases use Zig fake/table drivers plus
real private-FS cases as appropriate. IT cases use Python orchestration and Zig
fixtures; no test category implies use of a live desktop.

| Requirement | Acceptance scenario | Proposed test ID(s) | Required test type(s) | Milestone(s), same order | Expected evidence |
| --- | --- | --- | --- | --- | --- |
| HIST-001 | AC-HIST-001 | UT-HIST-001, IT-HIST-001 | Z+C / W+C | M5 / M5+M9 | Completed regular eligible offers only; MIME precedence and sensitive exclusion before receive. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| HIST-002 | AC-HIST-002 | UT-HIST-002, IT-HIST-002 | Z+C / W+C | M1 / M5+M9 | Exact canonical match, live ID preserved, preview collisions distinct. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| HIST-003 | AC-HIST-003 | UT-HIST-003, IT-HIST-003 | Z+C / W+C | M1+M5 / M5+M9 | Fallible preflight before publication/model commit; old selection preserved on failure. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| HIST-004 | AC-HIST-004 | UT-HIST-004, IT-HIST-004 | Z+C / W+C+F+R | M1 / M5+M9 | Sequence ordering, expiry first, transactional tail eviction and text projection removal. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| HIST-005 | AC-HIST-005 | IT-HIST-005 | W+C+F+R | M5+M9 | Calculator/screenshot same transaction and owner-independent payload. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| RES-001 | AC-RES-001 | UT-RES-001, IT-RES-001 | Z+C / W+C | M1 / M5+M9 | Count<=100 and payload<=16777216 at every commit. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| RES-002 | AC-RES-002 | UT-RES-002, IT-RES-002 | Z / W | M1+M2 / M5+M9 | Nonempty UTF-8 without NUL, length<=262144 before allocation. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| RES-003 | AC-RES-003 | UT-RES-003, IT-RES-003 | Z / W | M5 / M5+M9 | Existing PNG structure/filter/decode/pixel/encoded caps retained. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| RES-004 | AC-RES-004 | UT-RES-004, IT-RES-004 | Z+C / W | M4+M5 / M5+M9 | 1/4/8 transfers/offers, 5 seconds, 65536 dispatch, finite writer queue. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| TIME-001 | AC-TIME-001 | UT-TIME-001, IT-TIME-001 | Z+C / W+C | M1 / M6+M9 | Inclusive exact 604800 expiry; independent selection preserved. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| TIME-002 | AC-TIME-002 | UT-TIME-002, IT-TIME-002 | Z+C / W+C | M1 / M5+M9 | Front recopy changes time/sequence/L/P without new ID. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| TIME-003 | AC-TIME-003 | UT-TIME-003, IT-TIME-003 | Z+C / W+C | M1+M4 / M6+M9 | Timer and operation pruning before every exposure, including suspension/resume. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| TIME-004 | AC-TIME-004 | UT-TIME-004 | Z+C | M1 | Nanosecond carry and injected nondecreasing effective time; reset fails. Invariant/sample/codec assertions; failure parameters in 8.1. |
| TIME-005 | AC-TIME-005 | UT-TIME-005 | Z+C | M1+M2 | Floor/order integrity and exact provisional 299/300/301 behavior. Invariant/sample/codec assertions; failure parameters in 8.1. |
| TIME-006 | AC-TIME-006 | UT-TIME-006, IT-TIME-006 | Z+C / W+C | M1+M4 / M6+M9 | Hide/disable/no automatic overwrite; Delete blocked, safe Clear allowed. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-001 | AC-PERS-001 | UT-PERS-001, IT-PERS-001 | Z+C / W+C+F+R | M1+M4 / M5+M9 | Complete surviving text projection after text changes or PNG eviction. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-002 | AC-PERS-002 | IT-PERS-002 | W+C+F+R | M6+M9 | Locked load deferred; restore no publication or initial import. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-003 | AC-PERS-003 | UT-PERS-003 | Z | M2 | Fully bounded raw UTF-8 v1 with all-or-nothing decode/EOF. Invariant/sample/codec assertions; failure parameters in 8.1. |
| PERS-004 | AC-PERS-004 | UT-PERS-004 | Z+C | M4 | L/requested P/confirmed descriptor separated; old completion not current success. Invariant/sample/codec assertions; failure parameters in 8.1. |
| PERS-005 | AC-PERS-005 | UT-PERS-005, FT-PERS-005 | Z+C / Z+F+S+C | M4 / M4 | One writer, immutable ownership, FIFO removal barriers and trust admission. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-006 | AC-PERS-006 | FT-PERS-006 | Z+F+S+R | M3 | File sync, pinned-directory sync and new-parent link sync required. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-007 | AC-PERS-007 | UT-PERS-007, IT-PERS-007 | Z+C / W+C+F+S | M4+M7 / M7+M9 | 32 outstanding/64 terminal, token query, 3-second unknown and privacy override. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-008 | AC-PERS-008 | IT-PERS-008 | W+C+F+R | M6+M9 | Stable nonblocking writer lock, loser disables both kinds and preserves external traffic. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| PERS-009 | AC-PERS-009 | FT-PERS-009, IT-PERS-009 | Z+F+S+C+K / W+C+F+R+K | M4+M6 / M6+M9 | Drain before free, forced pending unknown, no teardown-empty overwrite. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| LOCK-001 | AC-LOCK-001 | IT-LOCK-001 | W+C | M6+M9 | Every authoritative gate composes and blocks metadata/actions. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| LOCK-002 | AC-LOCK-002 | IT-LOCK-002 | W+C | M6+M9 | Retain model, revoke source/transfers, no suspension Clear. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| LOCK-003 | AC-LOCK-003 | IT-LOCK-003 | W+C | M6+M9 | Every reconnect skips first regular including null, never primary or auto-publication. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| LOCK-004 | AC-LOCK-004 | IT-LOCK-004 | W+C | M6+M9 | Capture preview cleanup/generation remains separate from retained PNG. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| DEL-001 | AC-DEL-001 | FT-DEL-001, IT-DEL-001 | Z+F+S+C+R / W+C+F+R | M3+M4+M7 / M7+M9 | Logical removal plus ordered durable projection; final text unlink. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| DEL-002 | AC-DEL-002 | FT-DEL-002, IT-DEL-002 | Z+F+S+C+R / W+C+F+R | M3+M4+M7 / M7+M9 | Clear unlinks main/validated temps after older work and revokes only Pearl source. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| DEL-003 | AC-DEL-003 | IT-DEL-003 | W+C+F | M5+M9 | Independent paste survives Delete/expiry/eviction without reinsertion. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| DEL-004 | AC-DEL-004 | FT-DEL-004 | Z+F+S+C+R+K | M3+M4+M7 | No permanent-removal claim before sync; no rollback of hidden rows. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-001 | AC-SEC-001 | UT-SEC-001, FT-SEC-001 | Z / Z+F+S | M3 / M3 | Absolute XDG/fallback only, no alternate path or test root escape. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-002 | AC-SEC-002 | FT-SEC-002 | Z+F+S | M3 | Exact modes/UID/type/nlink and no existing-object repair. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-003 | AC-SEC-003 | FT-SEC-003 | Z+F+S | M3 | Pinned descriptor identity, no ancestor redirection or false success. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-004 | AC-SEC-004 | IT-SEC-004 | W | M5+M9 | Each exact sensitive MIME excludes whole offer with no refresh. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-005 | AC-SEC-005 | UT-SEC-005, IT-SEC-005 | Z / W+F | M1+M2+M8 / M8+M9 | Owned final buffers zeroed, no content/derived-query diagnostics. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| SEC-006 | AC-SEC-006 | FT-SEC-006 | Z+F+S | M3 | Only main restores; incremental 128-entry temp cleanup and safe refusal. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| CLI-001 | AC-CLI-001 | UT-CLI-001, IT-CLI-001 | Z / W+F+S | M8 / M8+M9 | Legacy field meanings plus truthful separate health. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| CLI-002 | AC-CLI-002 | UT-CLI-002, IT-CLI-002 | Z+C / W+C | M8 / M8+M9 | Offset/limit defaults and exact instance/revision traversal. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| CLI-003 | AC-CLI-003 | UT-CLI-003 | Z | M8 | Complete JSON+LF<=8192, UTF-8 preview and progressive page shrink. Invariant/sample/codec assertions; failure parameters in 8.1. |
| CLI-004 | AC-CLI-004 | IT-CLI-004 | W | M8+M9 | Closed-gate metadata redaction, callback/send-time gate and queued-output cancellation. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| CLI-005 | AC-CLI-005 | UT-CLI-005, IT-CLI-005 | Z+C / W+C+F+R | M1+M7+M8 / M8+M9 | New instance, nonreused IDs/tokens, explicit missing/stale failures. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| UI-001 | AC-UI-001 | IT-UI-001 | W+F+R+V | M8+M9 | 100-row navigation/filter, restored rows, revision refresh and corrected wording. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| UI-002 | AC-UI-002 | IT-UI-002 | W+S+V | M8+M9 | Copy/publication/save/removal stages named truthfully with query/retry. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| ERR-001 | AC-ERR-001 | FT-ERR-001, IT-ERR-001 | Z+F+S+C / W+C+F+R+S | M4+M7 / M7+M9 | Accepted live result kept unsaved; retry latest state without recopy. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| ERR-002 | AC-ERR-002 | FT-ERR-002 | Z+F+S+C+R | M3 | Invalid bytes preserved, no automatic backup/overwrite/collection. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| ERR-003 | AC-ERR-003 | FT-ERR-003 | Z+F+S+C+R+K | M3+M4+M7 | Phase-aware old/new/absent crash outcomes and no invented receipt. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| ERR-004 | AC-ERR-004 | FT-ERR-004, IT-ERR-004 | Z+F+S+C / W+C+F+R+S | M3+M4+M7 / M7+M9 | Explicit complete revalidation and fresh initial-selection skip. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| COMP-001 | AC-COMP-001 | UT-COMP-001, IT-COMP-001 | Z / W | M8 / M8+M9 | Legacy first page parses; unsafe old mutations fail explicitly. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| NFR-001 | AC-NFR-001 | UT-NFR-001, IT-NFR-001 | Z+C / W+C+S | M4 / M6+M9 | Paused storage cannot block main-context privacy/status or free worker data. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |
| NFR-002 | AC-NFR-002 | UT-NFR-002, IT-NFR-002 | Z+C / W+C+F+R+K | M1+M9 / M9 | Injected clocks/filesystems and private endpoints; no production hooks. Per-ID assertions and private trace/image/report; failure parameters in 8.1. |

### 8.1 Required negative and failure parameterization

| Area | Parameters required within the mapped IDs |
| --- | --- |
| Privacy/lifecycle | IT-LOCK-001/002/003/004, IT-CLI-004, IT-SEC-004/005, IT-NFR-001/002: each full gate independently and overlapping; pre-load lock; lock during read/send/deferred/queued output; known IDs/tokens; empty/nonempty redaction equality; stale screenshot completion; every sensitive hint/order; no post-event output; production hook rejection. |
| Durable removal | UT/FT-PERS-005, UT/IT-PERS-007, FT/IT-DEL-001/002, FT-DEL-004, FT-ERR-003: old snapshot paused at every irreversible phase; Delete A/Delete B/recopy A/Clear/later copy; temp unlink/sync failure; PNG/final-text/absent removal; three-second unknown, socket loss, stale slot; post-ack restart absent, pre-ack honestly unknown. |
| Filesystem safety | UT/FT-SEC-001, FT-SEC-002/003/006, FT-PERS-006, IT-PERS-008: absolute/fallback/error roots, every component/leaf swap, mode/UID/type/nlink/umask, stable directory+file locks, loser no reads, root sentinels unchanged, 128/129 cleanup and unsafe matching temp. |
| Invalid/time state | UT-TIME-001..006, UT-PERS-003, FT-ERR-002/004, IT-ERR-004: 299/300/301, exact age, fractional carry/reset/overflow/forward/reverse, corrupt/unsupported preserved, no startup-empty overwrite, clock blocks Delete but safe Clear works, correction without retry remains blocked. |
| Ownership/failures | UT-SEC-005, UT/IT-RES-004, FT-PERS-009, FT/IT-ERR-001, UT/IT-NFR-001: allocation failure at each owned allocation, short/zero/EINTR/EPIPE, notification failure, blocked I/O and shutdown, refs survive logical removal, all final capacities zeroed, bounded queue/memory after saturation. |
| Protocol/compatibility | UT-CLI-001/002/003/005, UT-COMP-001, IT-UI-001/002: duplicate/null/extra/overflow fields, max numeric identity, complete LF-bound frames for success/error/deferred/query, progressive shrink, stale revision/instance, exact exit codes, no-match Delete, truthful copy/save/removal wording. |

## 9. Standard coding workflow and definition of done

For each separately authorized coding milestone:

1. Verify branch, HEAD/base and complete working tree; preserve user/untracked
   documents. Stop on unexpected production changes before touching them.
2. Read applicable project instructions and approved unchanged spec/design/plan,
   including approved decisions and baseline evidence. Confirm M0 accepted.
3. Inspect affected source/build/runner and exact generated bindings as needed.
4. Write the milestone's meaningful tests before behavior implementation.
5. Demonstrate expected failures and record the failing assertion/cause; a
   missing module compile error alone does not prove behavioral test sensitivity.
6. Implement the smallest correct change within the milestone boundary.
7. Run targeted tests; diagnose/fix and repeat only affected failing checks.
8. Run relevant existing regressions and record exact outcomes/source identity.
9. Check failure paths, privacy, ownership, durability and resource accounting.
10. Review the complete diff, including untracked test/doc additions and generated
    catalog changes; perform content-aware whitespace validation.
11. Update requirement/test evidence and accepted limitations; do not mark a
    proposed ID passed merely because a suite compiled or a nearby case passed.
12. Report files/behavior/tests/failures/risks and **stop for human approval**.
    Do not automatically commit, push, publish, deploy, or begin the next milestone.

The feature is complete on CachyOS only when:

- All normative requirements below are implemented and every required case passes
  or has an explicit approved documented exception with remaining risk and owner.
- Every committed mixed model is <=100 entries and <=16777216 payload bytes;
  all individual/transfer/queue/parser/preview bounds hold without capacity leaks.
- Text expires at 604800 effective seconds and every successful recopy refreshes
  age/order, including index zero and same-second events. Restore/retry/paste do not.
- Valid text survives private process restart/new elapsed origin; reboot semantics
  are simulated deterministically; PNG/preview/runtime identities never persist.
- Lock and every other privacy gate retain eligible history, expose no retained
  content/metadata, cancel transfers/revoke Pearl source, and unlock/reconnect
  never republish/import an initial selection. Screenshot preview cleanup remains.
- Sensitive MIME offers are excluded before receive and cannot refresh duplicates.
- Delete/Clear acknowledge only required synchronized state; stale jobs/retries
  cannot resurrect removed data; independent Delete/expiry/eviction paste semantics
  and genuinely later copy semantics remain correct.
- Exact permissions, ownership, links, private paths, pinned identities, stable
  nonblocking writer exclusion and explicit StoreBusy behavior are validated.
- CLI accesses all 100 rows through truthful pagination with complete frames
  <=8192 bytes, fresh instance identity, exact errors and bounded operation receipts.
- Malformed/unsupported/future snapshots never partially restore or automatically
  overwrite; temporary files never restore; explicit recovery is gated and safe.
- One disk operation/worker and bounded snapshots/receipts/completions exist;
  failure/uncertainty/shutdown never free live ownership or fabricate success.
- Approved performance/write/memory budgets are met with owned and external RSS
  costs distinguished; no unbounded growth; security/fault/regression evidence passes.
- Documentation/help/translations accurately explain plaintext storage, unmarked
  secrets, seven-day effective retention, memory-only PNG, hidden-on-lock behavior,
  conditional durability, unknown pre-ack outcomes and non-forensic deletion.
- No Devario tests or deployment began before CachyOS approval; M12 remains a
  proposal until separately authorized. No automatic commit/push or rollout occurs.

### 9.1 Final requirement-by-requirement signoff

Each checkbox requires implemented behavior, the section 8 evidence for all
mapped IDs and boundary/failure parameters, final source hash, reviewer/date,
and any explicitly approved exception. None is checked by this planning task.

- [ ] **HIST-001** — Eligible capture. Evidence / reviewer / date / exception: pending.
- [ ] **HIST-002** — Canonical deduplication. Evidence / reviewer / date / exception: pending.
- [ ] **HIST-003** — Publication success and failure. Evidence / reviewer / date / exception: pending.
- [ ] **HIST-004** — Most-recently-copied eviction. Evidence / reviewer / date / exception: pending.
- [ ] **HIST-005** — Internal producers and owner independence. Evidence / reviewer / date / exception: pending.
- [ ] **RES-001** — Count and aggregate payload. Evidence / reviewer / date / exception: pending.
- [ ] **RES-002** — Text validation. Evidence / reviewer / date / exception: pending.
- [ ] **RES-003** — Existing PNG security bounds. Evidence / reviewer / date / exception: pending.
- [ ] **RES-004** — Transfer and persistence-work bounds. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-001** — Exact seven-day expiration. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-002** — Refresh every successful recopy. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-003** — Runtime, startup and resume enforcement. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-004** — Nondecreasing injected clock. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-005** — Persisted clock and future timestamps. Evidence / reviewer / date / exception: pending.
- [ ] **TIME-006** — Untrusted-clock recovery. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-001** — Automatic text projection. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-002** — Restore without automatic copy. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-003** — Bounded versioned raw-UTF-8 binary state. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-004** — Logical, pending and durable revisions. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-005** — Serialized worker and coalescing. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-006** — Required synchronization for acknowledgement. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-007** — Bounded queryable removal outcomes. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-008** — Single user-wide writer and StoreBusy. Evidence / reviewer / date / exception: pending.
- [ ] **PERS-009** — Safe shutdown with outstanding writes. Evidence / reviewer / date / exception: pending.
- [ ] **LOCK-001** — Preserve every privacy/session gate. Evidence / reviewer / date / exception: pending.
- [ ] **LOCK-002** — Retain history during suspension. Evidence / reviewer / date / exception: pending.
- [ ] **LOCK-003** — Skip initial selection on every reconnect. Evidence / reviewer / date / exception: pending.
- [ ] **LOCK-004** — Unchanged screenshot-preview cleanup. Evidence / reviewer / date / exception: pending.
- [ ] **DEL-001** — Durable individual deletion. Evidence / reviewer / date / exception: pending.
- [ ] **DEL-002** — Durable Clear barrier. Evidence / reviewer / date / exception: pending.
- [ ] **DEL-003** — Independent selection survives history removal. Evidence / reviewer / date / exception: pending.
- [ ] **DEL-004** — No false permanent-removal claim. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-001** — XDG storage location. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-002** — Exact permissions and object validation. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-003** — Identity-safe filesystem operations. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-004** — Advisory sensitive MIME exclusions. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-005** — Plaintext ownership and no content logging. Evidence / reviewer / date / exception: pending.
- [ ] **SEC-006** — Never restore temporary snapshots. Evidence / reviewer / date / exception: pending.
- [ ] **CLI-001** — Compatible status and truthful health. Evidence / reviewer / date / exception: pending.
- [ ] **CLI-002** — Bounded pagination and stable traversal. Evidence / reviewer / date / exception: pending.
- [ ] **CLI-003** — Complete response and preview bounds. Evidence / reviewer / date / exception: pending.
- [ ] **CLI-004** — Suspended content and metadata redaction. Evidence / reviewer / date / exception: pending.
- [ ] **CLI-005** — Fresh instance-scoped identities. Evidence / reviewer / date / exception: pending.
- [ ] **UI-001** — Full model navigation and restored rows. Evidence / reviewer / date / exception: pending.
- [ ] **UI-002** — Observable operation outcomes. Evidence / reviewer / date / exception: pending.
- [ ] **ERR-001** — Ordinary-save and timestamp-save failure. Evidence / reviewer / date / exception: pending.
- [ ] **ERR-002** — No automatic overwrite of invalid state. Evidence / reviewer / date / exception: pending.
- [ ] **ERR-003** — Crash and synchronization outcomes. Evidence / reviewer / date / exception: pending.
- [ ] **ERR-004** — Explicit revalidation after failure. Evidence / reviewer / date / exception: pending.
- [ ] **COMP-001** — Deliberate compatibility boundaries. Evidence / reviewer / date / exception: pending.
- [ ] **NFR-001** — Storage-independent main-context progress. Evidence / reviewer / date / exception: pending.
- [ ] **NFR-002** — Deterministic private verification. Evidence / reviewer / date / exception: pending.

## 10. Planning-task validation and decisions still requiring approval

This task is documentation-only. Content verification is distinct from running
the project tests. Direct checks of all three documents, including untracked
files, found no trailing whitespace, tabs, CR/control characters, missing final
newlines or extra blank EOF lines. `git diff --no-index --check /dev/null FILE`
returned 1 with no diagnostics for each: different content, no whitespace finding.
Tracked and staged `git diff --check` checks passed without diagnostics. The two
input hashes still match section 1. Final status contains only the original
untracked spec/design and this new untracked plan; no production/test file changed.
The plan has 13 milestones with all 16 A–P fields, a 52-row/80-unique-ID matrix
equal to both input documents, and 52 unchecked requirement signoffs.

Decisions requiring approval before their dependent work:

1. Ratify the inclusive provisional 300-second clock tolerance and its limitations.
2. Approve v1 binary/wire/API decisions and accept FIFO resource cost, or review
   a proof-preserving alternative before freezing fixtures.
3. Choose the operational write policy and numerical memory/write/latency budgets;
   current v1 cannot meet a <=1 GiB/day idle-full-text budget without a reviewed
   checkpoint/format change. No such budget is silently adopted or waived here.
4. Approve A/B/C/D separately, including exact downloads, offline graph readiness,
   previously unseen upstream preparation scripts, private smoke scope and disk
   reservations. Then review/accept unchanged-source CachyOS baseline explicitly.
5. Authorize each M1–M11 coding/validation boundary separately, any required
   exception/expanded scope, and final CachyOS signoff; authorize M12 planning
   separately. Plan approval never implies Devario execution/deployment.

The architecture can proceed to staged work after these gates; performance and
platform acceptance remain unproven. This task ends after reporting the plan,
traceability, whitespace and working-tree results. No preparation, dependency
fetch, build, project test, production/test-code edit, compositor/Pearl launch,
live clipboard access, commit/push, system change or implementation is authorized
or performed by this plan.
