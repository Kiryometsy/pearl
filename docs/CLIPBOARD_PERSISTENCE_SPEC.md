# Pearl Clipboard Persistence Functional Specification

- **Document version:** 0.1.0.
- **Status:** Draft for review; functional specification.
- **Implementation status:** Not implemented by this task. No proposed tests created or executed.
- **Source baseline:** `4b8097add7de09647382fc6ae88c467ea832d473`.
- **Review branch:** `feat/clipboard-persistence`.
- **Date:** 2026-11-01.
- **Authority:** Requirements/decisions supplied in Task 5; no authorization to implement or execute tests.

## 1. Version and implementation status

This document describes intended future behavior, not capabilities already present in the baseline. Every normative requirement has a stable ID, preconditions, observable outcome, boundary cases, an acceptance reference, and proposed test IDs. Given/When/Then scenarios are in section 17 and traceability in section 18.

MUST/MUST NOT express obligations; MAY permits the stated alternative subject to the same safety invariants. Requirement blocks and the definitions/tables they explicitly incorporate form the normative contract. Source observations, rationale, non-goals, limitations and review/deferred-design items are informative.

The document version is distinct from the eventual binary-format version, CLI capability version, entry age and process instance.

## 2. Purpose and scope

Provide automatic bounded text clipboard history across Pearl restart/reboot, with PNG history remaining memory-only. Normal lock and other privacy suspensions hide history rather than deleting it; explicit removal has durable confirmation.

Scope covers functional history/retention semantics, persistence/recovery, lifecycle, safe storage, observable UI/CLI/errors, resource constraints and acceptance criteria. This is implementation-independent except for the approved background-worker, private binary-store and identity constraints. It does not choose module names, APIs, binary byte offsets, memory representations, or implementation steps.

## 3. Terminology and definitions

| Term | Meaning |
| --- | --- |
| Entry | Canonical text/PNG plus runtime identity, last-copy time and copy order. |
| Canonical text | Full validated UTF-8 bytes without trimming or Unicode normalization. |
| Canonical PNG | Existing validated sanitization/re-encoding output. |
| Captured successfully | A completed eligible external offer is admitted to the bounded logical model. |
| Publication queued successfully | Pearl prepared and queued a source on its verified connection; not a paste acknowledgement. |
| Successful copy event | Successful capture or explicit local publication-queued event; not restore, query, retry or outgoing paste. Each logical event has one sequence update; separately received eligible offers are separate capture events. |
| Logical revision | Current accepted in-process model. |
| Pending revision | Latest projection requested for storage, not durable confirmation. |
| Durable revision | Projection whose required publication/removal and synchronization completed. |
| Text projection | Eligible retained text in relative copy order with last-copy timestamps; no PNG. |
| Accessible | All privacy gates pass, initial load is complete/missing, and store/time trust permits exposure. |
| Privacy suspension | Closed lifecycle/security gate, including normal lock, authentication, inactivity, mismatch or protocol loss. |
| Independent selection | Separately owned publication/paste payload, not the history allocation. |
| Removal pending | Entry hidden in memory but durable removal is not confirmed. |
| Clear barrier | Ordered separation of pre-Clear state from genuinely later copy events. |
| Authoritative file | Single named snapshot eligible for restore; temporary files are never authoritative. |
| Outcome unknown | Actual completion or acknowledgement delivery cannot be established. |
| Operation token | Bounded receipt identity scoped to process instance, separate from entry ID. |
| Reboot test | New process/elapsed-clock origin with preserved private state and injected wall time; no physical reboot. |

KiB = 1024 bytes; MiB = 1048576 bytes. The retained-history budget is not a total RSS limit. A removed history entry is ineligible even if independent selected bytes remain available elsewhere.

## 4. Assumptions and system boundaries

Before authoring, local checks confirmed the expected branch/commit, a clean working tree and absent destination document. `AGENTS.md` requires Zig production code and permits Python test harnesses. No baseline test pass is claimed.

Verified source evidence:

| Source at the baseline | Current behavior / relevance |
| --- | --- |
| [Clipboard contract](CLIPBOARD_CAPTURE.md), lines 34-109 | MIME/limits, independent selection, memory-only history and destructive suspension. |
| [Clipboard service](../src/services/clipboard.zig), lines 13-112, 122-267 | Ownership, transfer bounds, clear/lock, recopy/order, publication and connect/drop. |
| Same service, lines 269-440 | Registry/device loss, sensitive MIME, receive/send, hard-coded persistent=false, PNG sanitation. |
| [Policy](../src/services/clipboard_policy.zig), lines 3-18, 49-100 | Twenty-entry baseline, size constraints, PNG prefilter and preview. |
| [Manager](../src/ui/surfaces/manager.zig), lines 533-549, 1997-2027, 2148-2182 | Combined privacy gate and status/mutation routing. |
| [Lifecycle](../src/services/lifecycle.zig), lines 390-411 | Sleep preparation and privacy notifications. |
| [I/O](../src/config/io.zig), lines 20-92 | Bounded regular read, incomplete private validation, 128 KiB replacement read, private atomic publication and directory-sync caveat. |
| [Protocol](../src/cli/protocol.zig), line 6; [server](../src/cli/server.zig), lines 177-215 | 8192-byte framing, session/display checks and synchronous response baseline. |
| [View](../src/desktop/clipboard_capture.zig), lines 69-72, 308-334, 400-495 | Capacity-dependent arrays, navigation, rebuilding and obsolete lock-clear text. |

GTK dispatch, compositor behavior, external clipboard ownership and storage hardware remain separate boundaries. Successful synchronization is conditional on the kernel/filesystem/device honoring it. 0700/0600 do not exclude root, same-UID access, backups or external tampering.

Task 5 replaces the prior StoreBusy memory-only proposal: a losing process disables new history collection. This differs from an ordinary save failure after successful admission.

## 5. Functional requirements

Acceptance and publication are distinct from saving. This section incorporates the terminology above; it never equates queued publication with destination consumption.

### HIST-001 — Eligible capture

**Preconditions:** The verified session permits collection and initial-selection skipping is complete.

**Requirement:** Pearl MUST capture only completed validated regular selections: exact image/png wins over text; case-insensitive text/plain;charset=utf-8 wins over exact text/plain. Unsupported and primary selections MUST NOT enter history. SEC-004 applies before receiving payload bytes.

**Observable outcome:** One eligible accepted offer creates a capture event; rejection creates no entry or recopy event.

**Boundary cases:** Unsupported MIME; primary selection; empty or failed transfer; mixed MIME ordering. EOF does not prove a valid text prefix was the producer's entire intended message.

**Acceptance:** AC-HIST-001. **Proposed tests:** UT-HIST-001, IT-HIST-001.

### HIST-002 — Canonical deduplication

**Preconditions:** An eligible capture or local publication has canonical bytes.

**Requirement:** Pearl MUST deduplicate by kind and complete canonical payload: unchanged validated UTF-8 for text, existing sanitized/re-encoded bytes for PNG. A live duplicate MUST retain its runtime ID. Text MUST NOT be trimmed or normalized, and previews MUST NOT be used as identity.

**Observable outcome:** One matching record remains and TIME-002 refreshes its age/order.

**Boundary cases:** Front and lower duplicates; equal previews with differing suffixes; whitespace differences; equivalent canonical PNGs.

**Acceptance:** AC-HIST-002. **Proposed tests:** UT-HIST-002, IT-HIST-002.

### HIST-003 — Publication success and failure

**Preconditions:** A local copy request passes privacy, identity, payload, and device admission.

**Requirement:** Pearl MUST complete fallible publication preflight before recording successful-copy age/order. A queued Wayland source is publication-queued success, not proof of destination paste. Preflight failure MUST preserve the old selection and order; later cancellation or paste failure MUST NOT trigger replay or retroactive timestamp rollback.

**Observable outcome:** Copy and persistence outcomes are separately observable.

**Boundary cases:** Unavailable device; allocation/source failure; early receiver exit; later source cancellation; failed new-value copy.

**Acceptance:** AC-HIST-003. **Proposed tests:** UT-HIST-003, IT-HIST-003.

### HIST-004 — Most-recently-copied eviction

**Preconditions:** A copy or restore changes the logical model.

**Requirement:** Pearl MUST order entries by successful copy events, using increasing copy sequence for timestamp ties. It MUST expire first and evict the least-recently-copied tail until count and byte limits permit insertion. PNG-induced text eviction MUST remove the victim from the pending persistent projection. Query, restore, paste and save retry MUST NOT become copy events; sequence arithmetic MUST NOT wrap.

**Observable outcome:** The front is the latest successful copy and both resource bounds hold.

**Boundary cases:** Same-second events; text evicted by PNG; allocation failure; sequence exhaustion; newly restored text.

**Acceptance:** AC-HIST-004. **Proposed tests:** UT-HIST-004, IT-HIST-004.

### HIST-005 — Internal producers and owner independence

**Preconditions:** Calculator/screenshot copying or original-owner exit occurs.

**Requirement:** Pearl MUST apply the same validation, privacy, successful-copy, limits and persistence contract to internal calculator text and screenshot PNG. Completed history MUST survive original-owner exit and popup disposal. Only explicitly copied calculator results, not unelected expressions, enter calculator-produced history. History-unavailable errors MUST NOT alter another application's selection.

**Observable outcome:** Copied calculator text is restorable; screenshot PNG stays memory-only; retained values can be reselected after producer exit.

**Boundary cases:** Popup closure; external owner exits; oversized screenshot remains independently saveable; StoreBusy; preflight failure.

**Acceptance:** AC-HIST-005. **Proposed tests:** IT-HIST-005.

## 6. Resource constraints

Count/byte invariants apply at committed model boundaries. Input, selected data and immutable worker buffers have distinct bounded ownership; no total-process-memory ceiling is asserted.

### RES-001 — Count and aggregate payload

**Preconditions:** History is admitted, restored, recopied, or pruned.

**Requirement:** Every committed logical model MUST contain at most 100 entries and at most 16777216 retained payload bytes, text and PNG combined. Both bounds are inclusive. Independently selected data, transfers, decoder/UI copies and persistence buffers are outside this retained-history sum and separately bounded.

**Observable outcome:** No committed model exceeds either limit.

**Boundary cases:** 100 versus 101 entries; exactly 16 MiB and one byte over; both limits; mixed kinds.

**Acceptance:** AC-RES-001. **Proposed tests:** UT-RES-001, IT-RES-001.

### RES-002 — Text validation

**Preconditions:** Text arrives from a producer, internal copy, or storage.

**Requirement:** Pearl MUST accept only nonempty valid UTF-8 without NUL and no more than 262144 bytes. Storage lengths MUST be checked before allocation. Invalid text MUST NOT create an entry, age refresh, or persistent record.

**Observable outcome:** Input and restored payloads share the exact text contract.

**Boundary cases:** Lengths 0, 1, 262144, 262145; multibyte boundary; embedded NUL; invalid UTF-8.

**Acceptance:** AC-RES-002. **Proposed tests:** UT-RES-002, IT-RES-002.

### RES-003 — Existing PNG security bounds

**Preconditions:** PNG arrives from clipboard or capture.

**Requirement:** Pearl MUST preserve input and sanitized-output limits of 8388608 bytes each, positive dimensions at most 8192 per axis, and product at most 8388608 pixels. Existing chunk filtering, structural checks, explicit PNG decoding, and fresh-pixel re-encoding MUST remain: only IHDR/PLTE/tRNS/IDAT/IEND reach the decoder; malformed, unknown-critical, duplicate-header, missing/trailing-end and failed-decode data is rejected. Input text/profile/animation metadata MUST NOT be re-exported.

**Observable outcome:** Only bounded sanitized static PNG enters history.

**Boundary cases:** Truncation; CRC/decoder failure; chunk-length overflow; metadata; dimension and sanitized-size boundaries.

**Acceptance:** AC-RES-003. **Proposed tests:** UT-RES-003, IT-RES-003.

### RES-004 — Transfer and persistence-work bounds

**Preconditions:** Offers, transfers, or storage work accumulate.

**Requirement:** Pearl MUST preserve one incoming transfer, four outgoing transfers, eight offer records, five-second transfer deadlines, and 65536 bytes per pipe dispatch. New selection cancels the previous read. Persistence MUST have one active worker and one latest pending ordinary snapshot description; PERS-007 bounds removal receipts. Buffer ownership and explicit cancellation MUST close descriptors and release resources without unbounded queue growth.

**Observable outcome:** Clipboard pipes remain nonblocking and workload bookkeeping is bounded.

**Boundary cases:** Extra offer/write; stalled read; EPIPE; rapid copies while disk blocks; partial I/O.

**Acceptance:** AC-RES-004. **Proposed tests:** UT-RES-004, IT-RES-004.

## 7. Retention and clock semantics

The lifetime is 604800 seconds. Deterministic time inputs are independent of system-clock configuration. The startup skew value of 300 seconds is carried forward explicitly from the Task 4 proposal and remains a review item in section 20. It is not proof of real UTC accuracy.

A forward jump may expire history early. Under the nondecreasing runtime policy, reversing that jump does not revive already expired history.

### TIME-001 — Exact seven-day expiration

**Preconditions:** An entry has valid last-copy time and effective time is known.

**Requirement:** Text and PNG MUST be expired when effective_now minus last_copy is at least 604800 seconds, using checked arithmetic. Expired records MUST NOT be listed or selected even if durable cleanup is pending; independent active selection follows DEL-003.

**Observable outcome:** At the exact boundary accessible history excludes the entry.

**Boundary cases:** Age 604799, 604800, 604801; both kinds; active selection; pending rewrite.

**Acceptance:** AC-TIME-001. **Proposed tests:** UT-TIME-001, IT-TIME-001.

### TIME-002 — Refresh every successful recopy

**Preconditions:** A nonexpired canonical duplicate is captured or its explicit publication is queued.

**Requirement:** Pearl MUST set last_copy to the successful event's effective time and advance copy sequence/logical revision, including at index zero and within one second. Text refresh MUST request persistence. Failed preflight, restore, status, paste and storage retry MUST NOT refresh retention.

**Observable outcome:** A front duplicate extends lifetime without changing its entry ID.

**Boundary cases:** Front/lower duplicate; same-second event; failed publication; failed timestamp save.

**Acceptance:** AC-TIME-002. **Proposed tests:** UT-TIME-002, IT-TIME-002.

### TIME-003 — Runtime, startup and resume enforcement

**Preconditions:** Retained history exists, including during suspension.

**Requirement:** Expiration MUST be evaluated before admission, list/status, select, Delete lookup, restore exposure and resume/unlock exposure. Pearl MUST schedule the earliest known expiry and sample wall changes at least once per 60 elapsed seconds while dispatch runs. Due maintenance executes on the first eligible dispatch; no operation may expose expired content while waiting.

**Observable outcome:** No new copy is needed for expiry; suspended text is pruned from future snapshots.

**Boundary cases:** Idle process; delayed dispatch; sleep; forward adjustment; storage failure.

**Acceptance:** AC-TIME-003. **Proposed tests:** UT-TIME-003, IT-TIME-003.

### TIME-004 — Nondecreasing injected clock

**Preconditions:** Valid wall and elapsed-clock inputs are available.

**Requirement:** Retention MUST use injected integer epoch seconds and elapsed time including suspend. In-process effective_now MUST be max(wall_now, previous_effective plus nonnegative elapsed), carrying fractional elapsed time without repeated truncation loss. Clock reset, overflow or unavailable input MUST yield ClockUntrusted. No retention test may change system time.

**Observable outcome:** Rollback cannot decrease effective age and identical inputs yield identical outcomes.

**Boundary cases:** Fractional samples; suspend; forward jump then rollback; elapsed reset; arithmetic overflow.

**Acceptance:** AC-TIME-004. **Proposed tests:** UT-TIME-004.

### TIME-005 — Persisted clock and future timestamps

**Preconditions:** A structurally valid snapshot has last-copy times and a saved effective clock floor.

**Requirement:** Negative or inconsistent timestamps, a record later than its saved floor, or inconsistent copy ordering MUST be rejected as corrupt. A saved floor more than 300 seconds ahead of trustworthy startup wall time MUST cause ClockUntrusted without restore or overwrite. At skew up to and including 300 seconds, restore uses max(wall_now, saved_floor) and original entry times; restore never refreshes age.

**Observable outcome:** Unexpected future state is withheld and accepted skew cannot rewind the saved floor.

**Boundary cases:** Skew 299/300/301 seconds; future record beyond floor; corrected time; reboot expiration.

**Acceptance:** AC-TIME-005. **Proposed tests:** UT-TIME-005.

### TIME-006 — Untrusted-clock recovery

**Preconditions:** Clock validation fails at startup or runtime.

**Requirement:** Pearl MUST hide retained history content and metadata, disable new capture/recopy and restore exposure, and forbid automatic authoritative-file overwrite while ClockUntrusted. Explicit retry requires valid inputs. Individual Delete MUST return ClockUntrusted without mutation until time validation succeeds; safe explicit Clear can remove payload state without inventing timestamps and remains subject to privacy, path, lock and durability checks. No system-clock adjustment is performed.

**Observable outcome:** Clock failure cannot silently renew, expose or replace saved data.

**Boundary cases:** No wall sample; runtime reset; individual Delete refused; corrected clock; Clear of future state.

**Acceptance:** AC-TIME-006. **Proposed tests:** UT-TIME-006, IT-TIME-006.

## 8. Persistence and recovery contract

Capture/publication can precede durability. A valid newer file may survive an unacknowledged write, but finding that file does not invent knowledge that the old caller received success. Snapshots contain the complete eligible text projection. Byte layout and operating-system APIs belong to later technical design.

### PERS-001 — Automatic text projection

**Preconditions:** A valid owned store receives a relevant logical mutation.

**Requirement:** Pearl MUST automatically request the complete current text projection after accepted text, text recopy, text expiry, removal, or eviction, including text evicted by PNG. It MUST preserve relative text ordering/timestamps and never serialize PNG bytes, previews or cancelled transfer data. No manual Save is required.

**Observable outcome:** Durable state matches the acknowledged text projection, not the mixed memory model.

**Boundary cases:** PNG-only changes; last text removed; duplicate front; mixed eviction.

**Acceptance:** AC-PERS-001. **Proposed tests:** UT-PERS-001, IT-PERS-001.

### PERS-002 — Restore without automatic copy

**Preconditions:** Privacy, filesystem, writer and time validation permit initial load.

**Requirement:** Pearl MUST restore only complete valid unexpired text from the authoritative file, preserving age/order and assigning fresh runtime IDs. Missing state means empty history. It MUST NOT publish restored data, import the initial selection, or overwrite an unloaded store with an empty startup model. Startup while suspended defers payload loading/exposure until permitted.

**Observable outcome:** Restart/reboot restores eligible text without changing external clipboard ownership.

**Boundary cases:** Locked startup; missing/empty state; partial invalid load; current external selection.

**Acceptance:** AC-PERS-002. **Proposed tests:** IT-PERS-002.

### PERS-003 — Bounded versioned raw-UTF-8 binary state

**Preconditions:** Snapshots are encoded or decoded.

**Requirement:** The authoritative file MUST be unencrypted versioned binary containing raw UTF-8 text, bounded count/lengths, copy order/times and clock floor, no larger than 16842752 bytes. Parsing MUST enforce at most 100 records, 262144 bytes per text and 16777216 decoded payload bytes, check arithmetic and lengths before allocation, and reject truncation, invalid text, duplicate payload records, impossible metadata and unrecognized trailing data. Runtime IDs/instances and PNG MUST NOT be persisted.

**Observable outcome:** Valid supported models round-trip without forbidden data; invalid models never partially restore.

**Boundary cases:** Maximum size and one byte over; count >100; length overflow; unsupported version; duplicate/truncated/trailing records.

**Acceptance:** AC-PERS-003. **Proposed tests:** UT-PERS-003.

### PERS-004 — Logical, pending and durable revisions

**Preconditions:** History changes and worker completions interleave.

**Requirement:** Pearl MUST track logical state, latest requested projection and latest durably completed projection separately. An old completion MUST NOT mark a newer mutation durable. PNG-only logical changes need not advance the stored projection. Captured, publication-queued, pending, durable, failed and uncertain outcomes MUST remain distinct.

**Observable outcome:** Status can truthfully show successful copying and unsaved newer text.

**Boundary cases:** Old completion after new copy; coalescing; PNG-only change; failed timestamp refresh.

**Acceptance:** AC-PERS-004. **Proposed tests:** UT-PERS-004.

### PERS-005 — Serialized worker and coalescing

**Preconditions:** The process owns the store and storage work is queued.

**Requirement:** One background worker MUST serialize storage operations. Ordinary snapshots MAY be replaced by a later complete projection only when no removal proof is lost. Delete/Clear barriers MUST retain identities and wait behind older in-flight publication; no older snapshot may publish after their durable completion. Worker snapshots MUST have immutable valid ownership until release. Publication admission MUST recheck store/time trust; detected trust failure invalidates queued automatic writes. An operation already inside an irreversible publication step is classified as potentially uncertain and fenced before any subsequent write, not assumed cancellable or rolled back.

**Observable outcome:** Later durable barriers cannot be undone by stale queued work.

**Boundary cases:** Old write paused at rename; rapid front duplicates; Delete then genuine recopy; Clear then new copy.

**Acceptance:** AC-PERS-005. **Proposed tests:** UT-PERS-005, FT-PERS-005.

### PERS-006 — Required synchronization for acknowledgement

**Preconditions:** A validated store publishes or removes an authoritative snapshot.

**Requirement:** Durable completion MUST require content sync before atomic publication and successful sync of the pinned containing directory afterward, including necessary newly created directory links for first save. Final-file removal requires directory sync. Existing atomic functionality MUST be reused where safe, but helper success alone MUST NOT replace missing validation/synchronization checks.

**Observable outcome:** No required sync/open failure receives durable success.

**Boundary cases:** Directory open failure; file fsync error; post-rename dir fsync error; first save; final removal.

**Acceptance:** AC-PERS-006. **Proposed tests:** FT-PERS-006.

### PERS-007 — Bounded queryable removal outcomes

**Preconditions:** An admitted Delete/Clear has an operation token.

**Requirement:** Pearl MUST retain at most 32 outstanding operations and the latest 64 completed receipts; excess requests return Busy before mutation and outstanding receipts are not evicted. Result queries scoped by instance/token MUST distinguish pending, durable, failed and uncertain. Delete/Clear success waits for durability; at three elapsed seconds without a known result, a still privacy-authorized live request returns non-success DurabilityUnknown plus token before the five-second transport deadline. If privacy closes, CLI-004 takes precedence: return bounded Locked without token or operation details, while the worker's receipt remains subject to its actual outcome. Unknown/evicted/prior-instance tokens never imply success.

**Observable outcome:** Callers can resolve live uncertain operations without unbounded bookkeeping or false completion.

**Boundary cases:** 33rd pending operation; timeout; late completion; lost token; evicted receipt; restart; suspension before reply.

**Acceptance:** AC-PERS-007. **Proposed tests:** UT-PERS-007, IT-PERS-007.

### PERS-008 — Single user-wide writer and StoreBusy

**Preconditions:** A process requests the shared state store.

**Requirement:** Pearl MUST hold an exclusive nonblocking lock on one stable validated writer-lock inode before loading/writing. A losing process MUST report StoreBusy, disable new text and PNG history collection, avoid store reads/writes/takeover, and require explicit retry after release. It MUST NOT silently collect unsaved new history or change external application clipboard ownership.

**Observable outcome:** One writer owns persistence; external ordinary copy/paste works while history is unavailable.

**Boundary cases:** Second process; inactive owner; owner crash; unsafe/replaced lock inode.

**Acceptance:** AC-PERS-008. **Proposed tests:** IT-PERS-008.

### PERS-009 — Safe shutdown with outstanding writes

**Preconditions:** Shutdown begins, possibly before load or with worker ownership outstanding.

**Requirement:** Pearl MUST stop collection/publication, release its source and cancel transfers, drain outstanding work on graceful shutdown, and keep worker-owned objects alive until release. It MUST NOT persist empty teardown history or label failed/forced flushes durable. Forced exit promises only last confirmed durable state; indefinitely blocking storage has no guaranteed graceful-exit deadline.

**Observable outcome:** Saved history survives normal restart; teardown creates no dangling access or destructive overwrite.

**Boundary cases:** Unloaded locked startup; blocked worker; failed flush; SIGKILL; reboot.

**Acceptance:** AC-PERS-009. **Proposed tests:** FT-PERS-009, IT-PERS-009.

## 9. Lock and lifecycle state machine

LOCK-001/LOCK-002 incorporate this matrix. Overlapping reasons compose: every gate must pass before resumption. Maintenance is allowed only while store/format/time trust remains valid; explicit safe Clear is the destructive exception.

| Transition/state | Collection | History visibility | Memory history | Disk behavior | Pearl selection | Transfers |
| --- | --- | --- | --- | --- | --- | --- |
| Accessible active | Enabled | Visible | Retain | Persist text changes | Normal ownership | Normal bounds |
| Normal lock / lock requested | Disabled | Hidden | Retain subject to expiry | No lock-driven deletion; prior accepted maintenance may finish | Release local source | Cancel all |
| Unlock | Only after full validation | Eligible retained entries | Retain | Expiry/pending work | Never auto-publish | Never replay |
| Sleep preparation | Disabled | Hidden | Retain subject to expiry | Maintenance only | Release | Cancel all |
| Inactive/unavailable logind | Disabled | Hidden | Retain subject to expiry | Maintenance only | Release | Cancel all |
| Polkit/activity inhibition | Disabled | Hidden | Retain subject to expiry | Maintenance only | Release | Cancel all |
| Aqueous disconnect/identity mismatch | Disabled | Hidden | Retain until teardown | Maintenance if trust permits | Attempt release; destroy local ownership | Cancel all |
| Data-control device/manager/seat loss | Disabled | Hidden | Retain subject to expiry | Maintenance if trust permits | Attempt release; destroy local ownership | Cancel all |
| Multiple-seat ambiguity | Disabled for process | Hidden | Retain until teardown, subject to expiry | Maintenance only | Release | Cancel all |
| Startup locked/unverified | Disabled | Hidden/unloaded | No restored payload yet | Do not overwrite with empty model | No publication | None |
| Valid startup load | Disabled until validated | Expose only eligible text | Restore text only | Expiry cleanup | No publication | No replay |
| StoreBusy | Disabled for both kinds | Hidden/unloaded | No new entries | No losing-process I/O | Preserve external clipboard | No new history reads |
| Unsafe/corrupt/unsupported/clock-invalid store | Disabled until recovery | Hidden | Existing model may remain hidden | No automatic overwrite | No new history publication | Cancel collection/publication work |
| Shutdown | Disabled | Hidden | Release after workers drain | Flush latest eligible projection, never teardown-empty | Release | Cancel all |
| Explicit Delete | Full gate applies | Victim hidden; others visible | Remove victim | Durable removal barrier | Independent source preserved | Existing independent paste preserved |
| Explicit Clear | Full gate applies | Empty at logical Clear point | Remove all | Durably remove payload state | Revoke only Pearl source | Cancel all |

Ordinary save failure after admission is different from startup trust failure: ERR-001 permits the already accepted live model to remain accessible with unsaved health. No losing process collects a new unsaved model under StoreBusy.

### LOCK-001 — Preserve every privacy/session gate

**Preconditions:** A lifecycle, authentication, device or control event occurs.

**Requirement:** The section 9 matrix MUST govern access without weakening current UID/session/display, Aqueous readiness, active-logind, authoritative/requested/preparing lock, activity-inhibition and Polkit checks. Multiple-seat ambiguity disables clipboard access for the process lifetime. History mutation/result requests MUST use the full gate, not only the compositor locked flag.

**Observable outcome:** Each suspension blocks content access as soon as its event is processed.

**Boundary cases:** Polkit without lock flag; inactive/missing session; mismatch; overlapping reasons; second seat.

**Acceptance:** AC-LOCK-001. **Proposed tests:** IT-LOCK-001.

### LOCK-002 — Retain history during suspension

**Preconditions:** An active process enters a matrix privacy suspension.

**Requirement:** Pearl MUST retain text/PNG subject to expiry, hide content/metadata, disable collection, cancel all incoming/outgoing clipboard transfers, release its active source where possible, and destroy local publication ownership. Suspension MUST NOT request history deletion. Previously accepted saves/expiry maintenance MAY finish only under valid store/time trust.

**Observable outcome:** Unexpired history can return after resume without locked-period collection.

**Boundary cases:** In-flight read/paste; external owner; dead connection; repeat notification; suspension before load.

**Acceptance:** AC-LOCK-002. **Proposed tests:** IT-LOCK-002.

### LOCK-003 — Skip initial selection on every reconnect

**Preconditions:** Startup or recovery creates a new data-control device.

**Requirement:** Pearl MUST skip its first regular-selection event, including null, without letting a primary event consume the skip. Startup/unlock/reconnect MUST NOT publish retained/restored text, import pre-existing selection, or replay a cancelled request without a new explicit copy action.

**Observable outcome:** Only later eligible offers are collected; current external content is not replaced.

**Boundary cases:** Null first selection; primary first; locked-period copy; explicit copy after unlock.

**Acceptance:** AC-LOCK-003. **Proposed tests:** IT-LOCK-003.

### LOCK-004 — Unchanged screenshot-preview cleanup

**Preconditions:** Capture work or preview exists when the privacy gate closes.

**Requirement:** Retaining clipboard history MUST NOT change capture cleanup: pending capture/conversion is cancelled, separate screenshot preview/saved-path feedback is cleared under existing rules, and cancelled workers cannot expose/publish late results. A PNG already in history follows history retention rather than preview ownership.

**Observable outcome:** No screenshot preview survives suspension merely because a history PNG survives.

**Boundary cases:** Conversion finishes during lock; same PNG in history; stale generation.

**Acceptance:** AC-LOCK-004. **Proposed tests:** IT-LOCK-004.

## 10. Deletion and clearing semantics

Logical hiding is immediate; completed-removal language waits for durability. Clear is ordered relative to new events: intentionally copying equal text afterward creates new history, not stale resurrection. The empty directory/lock inode contain no retained clipboard payload and remain to preserve synchronization.

### DEL-001 — Durable individual deletion

**Preconditions:** An accessible current-instance caller identifies a live entry and owns a safe store.

**Requirement:** Delete MUST hide/remove the record logically, retain a distinct receipt and durably remove its text projection before success. Missing/expired IDs return Stale with no unrelated changes. PNG deletion writes no PNG but fences any older work relevant to the acknowledged state. Empty final text state requires authoritative-file removal plus sync. TIME-006 blocks individual Delete while time validation fails.

**Observable outcome:** An acknowledged deletion remains absent after restart unless a new copy reintroduces equal content.

**Boundary cases:** Last text; PNG; stale ID; older snapshot; new equal copy after Delete.

**Acceptance:** AC-DEL-001. **Proposed tests:** FT-DEL-001, IT-DEL-001.

### DEL-002 — Durable Clear barrier

**Preconditions:** A privacy-authorized caller owns the writer lock and a validated safe filesystem store. Unlike ordinary history exposure, explicit Clear does not require payload-format or time trust.

**Requirement:** Clear MUST create an ordered barrier, hide/remove all history, cancel transfers, revoke only Pearl's active selection, discard pre-Clear pending snapshots, and remove authoritative payload and validated owned temporary snapshots with required directory sync before success. The empty private directory and stable lock inode remain. Explicit Clear can remove corrupt/unsupported/clock-invalid payloads after filesystem validation; it is not automatic overwrite.

**Observable outcome:** No pre-Clear payload is authoritative after acknowledgement; later accepted copies are legitimate new history.

**Boundary cases:** Absent/empty file; corrupt file; unsafe path; contention; old in-flight write; copy arriving after Clear.

**Acceptance:** AC-DEL-002. **Proposed tests:** FT-DEL-002, IT-DEL-002.

### DEL-003 — Independent selection survives history removal

**Preconditions:** A removed history entry also has an independent selected payload or paste transfer.

**Requirement:** Delete, expiry and eviction MUST NOT revoke that independent source/transfer solely due to history removal. Serving it MUST NOT refresh/reinsert the removed record. Clear and privacy suspension remain explicit revocation/cancellation boundaries.

**Observable outcome:** History removal preserves existing paste semantics without renewing retained history.

**Boundary cases:** Original owner gone; PNG evicts selected text; expires mid-paste; source replaced externally.

**Acceptance:** AC-DEL-003. **Proposed tests:** IT-DEL-003.

### DEL-004 — No false permanent-removal claim

**Preconditions:** Removal is pending, failed or uncertain.

**Requirement:** Pearl MUST NOT report permanent Delete/Clear completion before durable confirmation. In-process hidden records MUST NOT reappear merely to roll back a save failure. An unacknowledged removal can restore old eligible state after crash/reboot; acknowledged removals MUST never be undone by older work from that writer. New intentional copies are not stale resurrection.

**Observable outcome:** The durability boundary, rather than a hidden row, defines guaranteed removal.

**Boundary cases:** Crash before acknowledgement; sync complete but reply lost; forced reboot; later recopy.

**Acceptance:** AC-DEL-004. **Proposed tests:** FT-DEL-004.

## 11. Filesystem and privacy requirements

This is plaintext persistence. Private modes, validation, identity-bound operations, bounded parsing and accurate errors define the security contract. Helper names and final-component checks alone do not establish race protection. Safe explicit Clear can remove invalid payload state without parsing its contents, but never bypasses filesystem ownership validation.

### SEC-001 — XDG storage location

**Preconditions:** The user-wide store is resolved.

**Requirement:** Pearl MUST use absolute XDG_STATE_HOME or an absolute HOME/.local/state fallback when XDG_STATE_HOME is unset/empty/relative, with pearl/clipboard/history.bin and pearl/clipboard/writer.lock below that base. Unsafe traversal or no usable absolute fallback MUST yield InvalidStatePath without current-directory or alternate-store fallback.

**Observable outcome:** Only the intended private state subtree is used.

**Boundary cases:** Unset/empty/relative base; invalid HOME; dot-dot traversal; excessive path length; private test root.

**Acceptance:** AC-SEC-001. **Proposed tests:** UT-SEC-001, FT-SEC-001.

### SEC-002 — Exact permissions and object validation

**Preconditions:** Store-controlled directories/files are created or opened.

**Requirement:** The clipboard directory MUST be current-user owned, an actual directory, with exact permission bits 0700. State, writer-lock and owned-temporary files MUST be current-user-owned regular files, exact 0600, with link count one. Symlinks, nonregular files, unexpected hard links and unsafe traversal MUST be rejected. Existing objects MUST NOT be repaired by chmod/chown or unrelated deletion.

**Observable outcome:** Unsafe storage blocks access/collection with a generic error rather than being read/replaced.

**Boundary cases:** Foreign UID; 0755/0700; 0640/0400/0600; FIFO/socket; dangling symlink; hard link; unsafe leaf.

**Acceptance:** AC-SEC-002. **Proposed tests:** FT-SEC-002.

### SEC-003 — Identity-safe filesystem operations

**Preconditions:** Validated state is read, published, synchronized or removed.

**Requirement:** Operations MUST stay bound to validated directory/file identities throughout use; pathname check followed by unprotected reopen is insufficient. Ancestor replacement MUST NOT redirect operations. Existing helpers are reusable only behind protection preserving identity and PERS-006 durability; a final NOFOLLOW flag alone is insufficient.

**Observable outcome:** A replaced pathname cannot redirect clipboard I/O or earn false acknowledgement.

**Boundary cases:** Ancestor/final swap; directory replacement between rename and sync; lock inode substitution.

**Acceptance:** AC-SEC-003. **Proposed tests:** FT-SEC-003.

### SEC-004 — Advisory sensitive MIME exclusions

**Preconditions:** An offer advertises MIME types.

**Requirement:** Any exact x-kde-passwordManagerHint, application/x-keepassxc or application/x-pearl-private hint MUST exclude the entire offer before payload receipt, independent of hint contents or ordering. Exclusion MUST NOT refresh an equal retained entry. Unmarked valid secrets remain ordinary text; no content-based secret-detection claim is allowed.

**Observable outcome:** Marked offers create no receive/history/persistence/preview/refresh event.

**Boundary cases:** Every hint independently; empty hint data; PNG plus hint; hint after text MIME.

**Acceptance:** AC-SEC-004. **Proposed tests:** IT-SEC-004.

### SEC-005 — Plaintext ownership and no content logging

**Preconditions:** Clipboard bytes or derived strings are held, saved, diagnosed or released.

**Requirement:** The store MUST be unencrypted raw UTF-8 under private permissions. Payloads, previews, clipboard-derived queries and snapshot contents MUST NOT enter logs/support artifacts, including error paths. Explicitly owned plaintext buffers MUST be zeroed before final release where ownership permits. No claim of erasing third-party, prior allocator, backup or physical-media copies is permitted.

**Observable outcome:** Diagnostics contain bounded codes instead of clipboard text; cleanup respects live worker ownership.

**Boundary cases:** Invalid data with marker secret; failed serialization; lock during work; allocation failure.

**Acceptance:** AC-SEC-005. **Proposed tests:** UT-SEC-005, IT-SEC-005.

### SEC-006 — Never restore temporary snapshots

**Preconditions:** A safe owned directory contains crash-left files.

**Requirement:** Only the authoritative file MUST be restorable. Cleanup MAY remove validated store-owned exact-pattern temporaries after writer ownership and owner/mode/type/link validation, without reading their payload. Directory enumeration MUST be incremental with at most 128 entries processed per worker batch and no unbounded in-memory name list. Unrelated/unsafe objects MUST remain untouched. A newer-looking temporary or missing authoritative file MUST NOT trigger promotion. Clear acknowledges only after its validated payload temporaries are removed and synchronized, even if multiple batches are required.

**Observable outcome:** Crash leftovers cannot resurrect history or authorize false completion.

**Boundary cases:** Absent/corrupt main file; newer valid-looking temporary; unrelated filename; malicious link; unlink failure; 128 versus 129 directory entries.

**Acceptance:** AC-SEC-006. **Proposed tests:** FT-SEC-006.

## 12. CLI and UI observable behavior

These requirements describe future interfaces, not currently implemented commands. The new result-query/recovery spellings and binary/wire layouts remain technical-design details; queryability, exact outcome distinctions, identity checks and byte/redaction limits are functional obligations.

Illustrative future pagination:

    pearlctl clipboard status
    pearlctl clipboard status --offset 20 --limit 20

Entry actions continue to identify a numeric entry but also require process instance. Capability-aware clients can use new pagination, while legacy status receives compatible existing fields and a first page.

### CLI-001 — Compatible status and truthful health

**Preconditions:** An authorized client requests clipboard status.

**Requirement:** Status MUST preserve available, locked, persistent, pending, message and entries wherever compatible. pending retains its incoming-transfer meaning; persistent describes enabled/owned text persistence, not latest-save acknowledgement. A separate bounded health object MUST distinguish unloaded, ready, pending, failed, uncertain, StoreBusy, corrupt, unsupported, ClockUntrusted and unsafe/unavailable states as applicable, using generic codes without payload/path disclosure.

**Observable outcome:** Copied-but-unsaved text is distinguishable from durable text and unavailable persistence.

**Boundary cases:** PNG-only model; front refresh; no device; save fails; lock contention; suspension.

**Acceptance:** AC-CLI-001. **Proposed tests:** UT-CLI-001, IT-CLI-001.

### CLI-002 — Bounded pagination and stable traversal

**Preconditions:** History is accessible.

**Requirement:** Status MUST support offset default 0 in 0..100 and limit default 20 in 1..20, returning total, offset, limit, returned, has_more, next_offset, revision, instance and entries. At/beyond total yields an empty page. Continuation advances by returned, not requested limit, and is null at completion. Supplied revision/instance mismatches MUST return a nonmutating stale error; accessible content/order changes invalidate a pinned traversal.

**Observable outcome:** A stable 100-entry model is enumerable without duplicates/omissions.

**Boundary cases:** Empty model; offsets 0/20/100; invalid limits 0/21; partial page; expiry/recopy between pages.

**Acceptance:** AC-CLI-002. **Proposed tests:** UT-CLI-002, IT-CLI-002.

### CLI-003 — Complete response and preview bounds

**Preconditions:** Any clipboard status, mutation, query or error is encoded.

**Requirement:** The complete response including envelope and newline MUST fit 8192 bytes. Text previews MUST preserve existing control substitution and be at most 120 original UTF-8 bytes on valid character boundaries. Full payload MUST NOT be returned. Measured encoded size MUST reduce returned entries if needed with truthful pagination; an impossible response becomes a bounded explicit error.

**Observable outcome:** No history size produces an oversized wire frame or broken UTF-8.

**Boundary cases:** Multibyte cutoff; quote/backslash escaping; 100 long previews; maximum request-ID overhead; health/error fields.

**Acceptance:** AC-CLI-003. **Proposed tests:** UT-CLI-003.

### CLI-004 — Suspended content and metadata redaction

**Preconditions:** Any privacy gate is closed.

**Requirement:** UI/status/query responses MUST suppress payload, previews, entry IDs, timestamps, counts, history revisions, instances, continuation tokens, operation identities and per-entry results. Status uses entries=[], total=null, has_more=false, next_offset=null with remaining history metadata null/omitted. Generic health MAY remain. Known-token queries and deferred callbacks MUST recheck privacy before reply and return Locked rather than disclose membership.

**Observable outcome:** Polling cannot distinguish retained empty/nonempty history through history metadata while suspended.

**Boundary cases:** Nonzero offset; known ID/token; lock between request and deferred reply; Polkit without lock flag.

**Acceptance:** AC-CLI-004. **Proposed tests:** IT-CLI-004.

### CLI-005 — Fresh instance-scoped identities

**Preconditions:** Entry select/Delete or result queries are requested.

**Requirement:** Every process MUST have a fresh opaque instance identity. Entry IDs MUST be nonzero and never reused within that instance; restored entries get fresh IDs. Entry/result operations MUST require current instance: mismatch returns StaleInstance, missing instance returns InstanceRequired, and missing current-instance entry returns Stale, all without mutation. Prior-process receipts MUST return unknown/stale, not fabricated success.

**Observable outcome:** Old operations cannot target unrelated new-process entries even when numeric IDs coincide.

**Boundary cases:** Forced equal numeric IDs across fake instances; missing-instance legacy client; expired/deleted ID; lost receipt.

**Acceptance:** AC-CLI-005. **Proposed tests:** UT-CLI-005, IT-CLI-005.

### UI-001 — Full model navigation and restored rows

**Preconditions:** Accessible history includes newly captured and restored entries.

**Requirement:** The existing filter, Up/Down, Enter/row Copy, Delete/row Delete and Clear interactions MUST support 100 entries. Filtering remains case-folded preview matching and no-match MUST NOT delete data. Restored text uses the same rows. Affected text/translation/documentation claims MUST describe text persistence, memory-only PNG, expiry and hidden-on-lock behavior rather than memory-only/clear-on-lock history.

**Observable outcome:** Restored and fresh entries share correct keyboard/pointer behavior and accurate privacy wording.

**Boundary cases:** 100 mixed entries; no matches; multibyte preview; selected row removed; reopen after lock.

**Acceptance:** AC-UI-001. **Proposed tests:** IT-UI-001.

### UI-002 — Observable operation outcomes

**Preconditions:** Copy or destructive work is pending, completed or failed.

**Requirement:** UI/CLI MUST distinguish captured successfully, publication queued, persistence pending, durable completion, failed persistence and uncertain outcome. Delete/Clear remains pending/failed/uncertain until durable confirmation; hiding a row MUST NOT be described as permanent removal. A bounded query/retry path MUST remain and recovery MUST NOT replay publication.

**Observable outcome:** Feedback does not equate capture, publication, paste and storage durability.

**Boundary cases:** Successful copy/failed save; timeout then completion; unavailable source; locked deferred reply.

**Acceptance:** AC-UI-002. **Proposed tests:** IT-UI-002.

## 13. Failure and recovery behavior

ERR-003 incorporates this matrix. Old/new states below still require complete format/time/expiry validation. Atomic visibility is not the same as durable acknowledgement.

| Failure point | Immediate outcome | Restart contract |
| --- | --- | --- |
| Automatic text/timestamp save fails before publication | Capture/publication successful; persistence failed/unsaved | Old authoritative state may remain; newer event not promised durable |
| Disk full / permission denial | Failed mutation persistence; no repair/system changes | Old state may remain |
| Corrupt/unsupported file | No restore or automatic overwrite/backup | Original bytes preserved until explicit safe reset/valid retry |
| Serialization crash / pre-publication interruption | No new durable completion | Old/absent authoritative file; never restore temp |
| Publication succeeded, directory sync incomplete | Pending/uncertain; no assumed rollback | Valid old/new/absent recovered directory outcome; no partial snapshot accepted |
| Required directory open/fsync fails | No durable acknowledgement; post-publication uncertain | Validate actual authoritative file only |
| Sync complete, crash before reply delivery | Caller result may remain unknown | New state can exist; restarted process does not invent a prior receipt |
| Delete interrupted before acknowledgement | Victim hidden; removal pending/failed/uncertain | Old eligible text can return |
| Clear interrupted before acknowledgement | Live model hidden; barrier pending/uncertain | Old eligible main state may remain; temp never promoted |
| Crash/reboot after acknowledged Delete/Clear | Removal completed | Older writer work cannot restore acknowledged removed records |
| Reboot before ordinary pending writes finish | Pending not durable | Last valid eligible authoritative text only; never PNG |
| Shutdown with outstanding work | Drain safely or explicit failure; forced exit may lose pending changes | No empty teardown overwrite or fabricated successful flush |
| Runtime wall rollback | Effective age continues nondecreasing | No same-process resurrection |
| Startup future floor / missing trustworthy time | ClockUntrusted, no overwrite/exposure | Withhold until explicit validated retry or Clear |
| Forward clock adjustment | Expire at next operation/eligible timer dispatch | Cleanup can be pending, but expired content stays inaccessible |
| Elapsed reset / overflow | ClockUntrusted | No invented time or automatic overwrite |
| Writer contention | StoreBusy; no new collection | Winning writer unaffected by loser |

Receipt absence is not evidence of success. A storage stack refusing every removal cannot be made to provide durable deletion by software acknowledgement.

### ERR-001 — Ordinary-save and timestamp-save failure

**Preconditions:** A capture/recopy was admitted before an automatic write failed.

**Requirement:** Pearl MUST preserve the bounded live logical result, mark affected projection failed/unsaved and retain its event timestamp. Explicit retry MUST use only the latest valid projection without recopy/reordering or undoing intervening removals. ENOSPC/permission failure MUST NOT cause system changes, permission repair, alternate storage or sensitive logging. StoreBusy follows PERS-008 instead of this post-admission behavior.

**Observable outcome:** Live success remains visible as unsaved rather than being falsely durable.

**Boundary cases:** Front refresh; ENOSPC; EACCES; older completion; later Delete/Clear; recovery.

**Acceptance:** AC-ERR-001. **Proposed tests:** FT-ERR-001, IT-ERR-001.

### ERR-002 — No automatic overwrite of invalid state

**Preconditions:** Loading or later revalidation detects corrupt, unsupported or clock-invalid state.

**Requirement:** Pearl MUST restore no invalid records and prohibit automatic overwrite or additional plaintext backup creation. Automatic collection/writes remain inhibited until explicit validated retry or safe explicit Clear. No unloaded empty startup model may replace the file; existing same-process history may remain retained but hidden. A previously admitted worker already inside an irreversible publication step at detection follows PERS-005/ERR-003 uncertainty rules; detecting invalidity cannot promise retroactive cancellation or recovery of overwritten bytes.

**Observable outcome:** Original invalid bytes remain unchanged under automatic operations.

**Boundary cases:** Oversized/truncated file; duplicate record; future timestamp; unsupported version; file changes later.

**Acceptance:** AC-ERR-002. **Proposed tests:** FT-ERR-002.

### ERR-003 — Crash and synchronization outcomes

**Preconditions:** Storage is interrupted at a section 13 failure-matrix boundary.

**Requirement:** Pearl MUST satisfy that matrix: pre-publication work is not durable; post-publication/pre-required-sync failures are potentially uncertain, not assumed rollback. Restore validates only the authoritative file, never promotes a temporary, and never invents delivery of a previous process's acknowledgement. Acknowledged removals remain protected from older writer work.

**Observable outcome:** Only documented old/new/absent filesystem outcomes are accepted, with no partial restore or false success.

**Boundary cases:** Serialization crash; before/after rename; directory-open/fsync failure; sync complete/reply lost; reboot before durability.

**Acceptance:** AC-ERR-003. **Proposed tests:** FT-ERR-003.

### ERR-004 — Explicit revalidation after failure

**Preconditions:** The user retries unavailable persistence or collection.

**Requirement:** Retry MUST revalidate privacy, ownership, safe paths, supported format and time before reopening collection/exposure/writes. A StoreBusy loser MUST NOT collect automatically after the owner exits. Recovery MUST skip the initial selection and never publish retained data or infer operation success from file absence.

**Observable outcome:** Recovery is gated and explicit, preserving external clipboard ownership.

**Boundary cases:** Owner crash; unsafe mode remains; corrected clock; external file deletion; stale token.

**Acceptance:** AC-ERR-004. **Proposed tests:** FT-ERR-004, IT-ERR-004.

## 14. Backward compatibility

The baseline has no clipboard snapshot format to migrate. Increasing 20 to 100 does not increase retained byte limits. Existing lock-clear assertions become retention plus redaction checks; sensitive MIME, real publication, transfer cancellation, initial-selection exclusion and screenshot cleanup stay covered.

Missing-instance entry operations deliberately fail rather than accept a stale-generation risk. This compatibility cost is explicit, not a silent weakening of the approved identity requirement.

### COMP-001 — Deliberate compatibility boundaries

**Preconditions:** Current or legacy clients interact with the changed feature.

**Requirement:** Existing status fields and normal capture/calculator/panel behavior MUST remain compatible where feasible. Default status returns a bounded first page and advertises continuation. Missing-instance entry mutations MUST fail explicitly. Pending durability MUST NOT be emitted as old unconditional success. Count/lock-purge expectations and obsolete strings/docs MUST be deliberately updated in a future authorized change.

**Observable outcome:** Legacy status remains parseable while changed mutation guarantees are explicit.

**Boundary cases:** Old entries-only client; generation-only select/Delete; immediate-success Clear expectation; 20-entry and lock-clear tests.

**Acceptance:** AC-COMP-001. **Proposed tests:** UT-COMP-001, IT-COMP-001.

## 15. Nonfunctional requirements

Persistence stalls must not prevent privacy dispatch. This is an event-ordering obligation, not an unverified GPU/disk benchmark. Existing PNG sanitization may still delay a bounded dispatch; no new PNG-worker design is prescribed.

Production implementation remains Zig under AGENTS.md; existing Python private-session testing remains permitted.

### NFR-001 — Storage-independent main-context progress

**Preconditions:** Serialization or filesystem I/O stalls.

**Requirement:** Persistence encoding/reading/writing/sync MUST run outside GTK dispatch. GTK/Wayland access and live-model mutation MUST remain on their owning context. Eligible status/privacy events MUST complete without waiting for the worker; destructive acknowledgement obeys PERS-007. Snapshots and callbacks MUST remain valid through removal and teardown.

**Observable outcome:** Slow disk cannot delay applying privacy solely by blocking the persistence worker.

**Boundary cases:** Indefinite fsync; lock arrives; referenced payload removed; completion after shutdown starts.

**Acceptance:** AC-NFR-001. **Proposed tests:** UT-NFR-001, IT-NFR-001.

### NFR-002 — Deterministic private verification

**Preconditions:** A future authorized validation checks this specification.

**Requirement:** Clock tests MUST inject wall/elapsed inputs without altering system time or waiting seven days. Filesystem tests MUST inject publication/sync/removal failures and inspect private images. Native tests MUST use private HOME/XDG, Wayland/Aqueous, buses, PAM and clipboard fixtures, never live desktop endpoints. Production artifacts MUST NOT expose private test hooks.

**Observable outcome:** Acceptance can be verified without changing the user's clipboard, compositor or system clock.

**Boundary cases:** Restart/reboot simulation; fault paths; test-root escape; production hook probe.

**Acceptance:** AC-NFR-002. **Proposed tests:** UT-NFR-002, IT-NFR-002.

## 16. Explicit non-goals

- Implementation, technical design, module/API choices or implementation sequencing in this authoring task.
- Dependencies, builds, baseline execution, new test code, commits or pushes.
- Encryption, key management, secret inference, or forensic secure erasure.
- PNG/preview/primary-selection persistence, other MIME kinds, export/import or cloud synchronization.
- Synthetic paste, global shortcut capture, new clipboard D-Bus service, portal ownership or compositor replacement.
- Real login/PAM changes, live clipboard use, system-clock or system-configuration changes.
- Multi-writer merging or cross-user history.
- Restoring cancelled jobs, preserving old runtime IDs or durable receipt journaling across process death.
- Guarantees before durable acknowledgement, against external backup restoration, or after storage hardware violates synchronization.

These exclusions do not remove live operation queryability, explicit stale/unknown outcomes, privacy gates or acceptance obligations.

## 17. Acceptance scenarios

All scenarios and test IDs are proposed, not implemented or executed. UT denotes compositor-free Zig policy/codec tests; FT denotes private filesystem/fault-injection cases; IT denotes private Wayland/Aqueous/UI integrations. Each requirement's boundary list is included in the parameterized proposed tests.

One stable scenario below corresponds to each requirement; cross-cutting coverage supplements rather than replaces that mapping.

### AC-HIST-001 — Eligible capture

- **Given** A private producer advertises supported, unsupported, primary, and mixed offers.
- **When** Offers complete or fail at controlled boundaries.
- **Then** Only valid regular selections enter history, PNG wins mixed supported offers, and rejection leaves history unchanged.

**Covers:** HIST-001. **Proposed tests:** UT-HIST-001, IT-HIST-001.

### AC-HIST-002 — Canonical deduplication

- **Given** History contains a duplicate and a distinct payload with the same preview.
- **When** Each matching payload is recopied, varying its initial position.
- **Then** Only the full canonical match deduplicates, retains its ID, and refreshes; the distinct payload stays separate.

**Covers:** HIST-002. **Proposed tests:** UT-HIST-002, IT-HIST-002.

### AC-HIST-003 — Publication success and failure

- **Given** Pearl has an old active selection and an older history entry.
- **When** Publication setup is first failed, then succeeds while the receiver exits early.
- **Then** Failure leaves the old source, age and order unchanged; queueing refreshes the entry without claiming a successful paste or replaying it.

**Covers:** HIST-003. **Proposed tests:** UT-HIST-003, IT-HIST-003.

### AC-HIST-004 — Most-recently-copied eviction

- **Given** A bounded mixed model receives A, B, A at one clock second and a new PNG at capacity.
- **When** Admission, eviction and later persistence complete.
- **Then** Ordering follows event sequence, the correct tail is removed from memory/text projection, and failed admission does not partially evict unrelated entries.

**Covers:** HIST-004. **Proposed tests:** UT-HIST-004, IT-HIST-004.

### AC-HIST-005 — Internal producers and owner independence

- **Given** Private calculator, screenshot, and external producers hold valid data.
- **When** Values are copied, popups close, and the original external producer exits.
- **Then** Valid retained values remain usable with correct text/PNG persistence behavior, while failed actions preserve external selection ownership.

**Covers:** HIST-005. **Proposed tests:** IT-HIST-005.

### AC-RES-001 — Count and aggregate payload

- **Given** Models are constructed at each count/byte boundary.
- **When** One distinct text or PNG copy is admitted.
- **Then** Only the necessary least-recent victims are removed and the committed model meets both limits.

**Covers:** RES-001. **Proposed tests:** UT-RES-001, IT-RES-001.

### AC-RES-002 — Text validation

- **Given** Fixtures span every text boundary and invalid encoding.
- **When** Admission and storage decoding process those fixtures.
- **Then** Only valid nonempty NUL-free payloads within the inclusive limit are accepted.

**Covers:** RES-002. **Proposed tests:** UT-RES-002, IT-RES-002.

### AC-RES-003 — Existing PNG security bounds

- **Given** Malformed, metadata-bearing, and boundary PNG fixtures are provided.
- **When** Each is admitted and accepted output is published privately.
- **Then** Invalid cases are rejected and accepted output retains pixels without input metadata or animation.

**Covers:** RES-003. **Proposed tests:** UT-RES-003, IT-RES-003.

### AC-RES-004 — Transfer and persistence-work bounds

- **Given** Private fixtures saturate transfer/offer slots and block storage.
- **When** More events arrive, a deadline expires, or suspension occurs.
- **Then** Excess work is refused/coalesced, cancellation reclaims resources, and the service remains responsive.

**Covers:** RES-004. **Proposed tests:** UT-RES-004, IT-RES-004.

### AC-TIME-001 — Exact seven-day expiration

- **Given** Text and PNG have last-copy time T under a fake clock.
- **When** List/select occurs immediately before and at T+604800.
- **Then** Both exist before the boundary and both are inaccessible at it without waiting for disk cleanup.

**Covers:** TIME-001. **Proposed tests:** UT-TIME-001, IT-TIME-001.

### AC-TIME-002 — Refresh every successful recopy

- **Given** A front text entry would expire at T+604800.
- **When** It is successfully recopied at T+10 and checked at both old/new expiry times.
- **Then** It survives its old deadline, expires at T+10+604800, and persistence progress is separate from recopy success.

**Covers:** TIME-002. **Proposed tests:** UT-TIME-002, IT-TIME-002.

### AC-TIME-003 — Runtime, startup and resume enforcement

- **Given** A fake clock crosses expiry without offers, both active and suspended.
- **When** A timer, history operation, or resume event runs.
- **Then** Expired entries are inaccessible before exposure and excluded from subsequent text projections.

**Covers:** TIME-003. **Proposed tests:** UT-TIME-003, IT-TIME-003.

### AC-TIME-004 — Nondecreasing injected clock

- **Given** Fake wall and elapsed clocks supply each discontinuity and repeated fractional intervals.
- **When** Policy evaluates the sequence twice.
- **Then** Results match, elapsed seconds are not lost, effective time never decreases, and invalid samples inhibit age mutation.

**Covers:** TIME-004. **Proposed tests:** UT-TIME-004.

### AC-TIME-005 — Persisted clock and future timestamps

- **Given** Snapshots exercise every skew boundary and one impossible entry timestamp.
- **When** Startup restore uses controlled wall inputs.
- **Then** Over-300 skew is withheld unchanged; allowed skew uses the saved floor; inconsistent records are rejected.

**Covers:** TIME-005. **Proposed tests:** UT-TIME-005.

### AC-TIME-006 — Untrusted-clock recovery

- **Given** A saved store and known in-process entries exist when clock validation fails.
- **When** Offers, automatic writes, selection, individual Delete, explicit retry and safe Clear are attempted separately.
- **Then** Age-dependent operations and individual Delete fail without mutation, saved bytes remain unchanged automatically, and only validated retry or safe explicit Clear proceeds.

**Covers:** TIME-006. **Proposed tests:** UT-TIME-006, IT-TIME-006.

### AC-PERS-001 — Automatic text projection

- **Given** Durable text is interleaved with PNG and a new PNG evicts text.
- **When** The latest storage work finishes and the process restarts.
- **Then** Only surviving unexpired text returns in its prior order and the PNG eviction victim stays absent.

**Covers:** PERS-001. **Proposed tests:** UT-PERS-001, IT-PERS-001.

### AC-PERS-002 — Restore without automatic copy

- **Given** Saved text and a separately owned external selection exist.
- **When** Pearl restarts locked, then becomes accessible.
- **Then** No saved payload is exposed while suspended; valid text restores with original times and the external selection is untouched.

**Covers:** PERS-002. **Proposed tests:** IT-PERS-002.

### AC-PERS-003 — Bounded versioned raw-UTF-8 binary state

- **Given** Valid maximum and malformed binary fixtures are supplied.
- **When** A pure codec processes each and serializes a valid model.
- **Then** Only valid supported state round-trips, preserving raw bytes/order/time within both payload and serialized bounds.

**Covers:** PERS-003. **Proposed tests:** UT-PERS-003.

### AC-PERS-004 — Logical, pending and durable revisions

- **Given** Projection A is saving while text revision B is accepted.
- **When** A completes while B fails or waits.
- **Then** B remains pending/failed and is not mislabeled durable by A's completion.

**Covers:** PERS-004. **Proposed tests:** UT-PERS-004.

### AC-PERS-005 — Serialized worker and coalescing

- **Given** An old snapshot is paused and removal barriers plus later copy events arrive.
- **When** All relevant worker interleavings are released deterministically.
- **Then** Barriers finish after old effects, stale state never returns after acknowledgement, and genuine later copies remain distinct.

**Covers:** PERS-005. **Proposed tests:** UT-PERS-005, FT-PERS-005.

### AC-PERS-006 — Required synchronization for acknowledgement

- **Given** Every publication/removal boundary has injected success/failure.
- **When** A mutation attempts acknowledgement.
- **Then** Only fully synchronized paths report durable completion; post-publication errors are potentially uncertain.

**Covers:** PERS-006. **Proposed tests:** FT-PERS-006.

### AC-PERS-007 — Bounded queryable removal outcomes

- **Given** A removal is blocked beyond three seconds and receipt limits are exercised.
- **When** The caller receives a token, polls, and storage finishes or the process restarts.
- **Then** Live receipts report actual outcomes; full queues reject before effects; lost/prior receipts return OutcomeUnknown/StaleInstance, never invented success.

**Covers:** PERS-007. **Proposed tests:** UT-PERS-007, IT-PERS-007.

### AC-PERS-008 — Single user-wide writer and StoreBusy

- **Given** Two processes target one private store, with external clipboard producer/receiver.
- **When** The second starts and ordinary external copy/paste proceeds.
- **Then** The loser collects nothing, reports StoreBusy and leaves store and external selection traffic untouched.

**Covers:** PERS-008. **Proposed tests:** IT-PERS-008.

### AC-PERS-009 — Safe shutdown with outstanding writes

- **Given** Pending/durable text exists and a worker is paused.
- **When** Graceful stop, injected failure or forced termination occurs.
- **Then** Safe completion drains ownership without an empty overwrite; forced restart restores only valid authoritative state without upgrading pending work to acknowledged success.

**Covers:** PERS-009. **Proposed tests:** FT-PERS-009, IT-PERS-009.

### AC-LOCK-001 — Preserve every privacy/session gate

- **Given** Each privacy condition is independently closed while history and requests exist.
- **When** Notifications and subsequent UI/CLI actions execute.
- **Then** No history action bypasses a closed gate or exposes content/metadata while another suspension reason remains.

**Covers:** LOCK-001. **Proposed tests:** IT-LOCK-001.

### AC-LOCK-002 — Retain history during suspension

- **Given** Mixed history and pending transfers exist.
- **When** Lock, sleep, inactivity, Polkit, IPC/device loss or ambiguity occurs.
- **Then** History remains retained but hidden, Pearl transfers/source are revoked, external ownership is not cleared, and disk is not purged by suspension.

**Covers:** LOCK-002. **Proposed tests:** IT-LOCK-002.

### AC-LOCK-003 — Skip initial selection on every reconnect

- **Given** An external selection exists before startup or changes during lock.
- **When** Pearl starts/unlocks/reconnects, then receives a new ordinary copy.
- **Then** The initial selection is skipped with no recopy refresh/publication, while the subsequent eligible event is captured.

**Covers:** LOCK-003. **Proposed tests:** IT-LOCK-003.

### AC-LOCK-004 — Unchanged screenshot-preview cleanup

- **Given** Preview, retained history PNG and a paused conversion exist.
- **When** Suspension happens and conversion subsequently finishes.
- **Then** Preview stays absent, late capture output is discarded, and history stays hidden until allowed.

**Covers:** LOCK-004. **Proposed tests:** IT-LOCK-004.

### AC-DEL-001 — Durable individual deletion

- **Given** A durable record is deleted while old storage work exists.
- **When** Its barrier completes and Pearl restarts.
- **Then** The victim cannot return through old work, and only a genuine later copy can create a new equal record.

**Covers:** DEL-001. **Proposed tests:** FT-DEL-001, IT-DEL-001.

### AC-DEL-002 — Durable Clear barrier

- **Given** Payload state, an owned temporary and stale queued work exist alongside an external or Pearl selection.
- **When** Clear completes with later copy events controlled separately.
- **Then** Old payload files are gone, stale work cannot undo Clear, external selection is untouched and legitimate later copies are treated separately.

**Covers:** DEL-002. **Proposed tests:** FT-DEL-002, IT-DEL-002.

### AC-DEL-003 — Independent selection survives history removal

- **Given** Pearl selects an entry and a private receiver starts reading.
- **When** History Delete/expiry/eviction occurs, then separately Clear/suspension is tested.
- **Then** Independent paste survives the first removal without reinsertion; Clear/suspension cancels/releases it.

**Covers:** DEL-003. **Proposed tests:** IT-DEL-003.

### AC-DEL-004 — No false permanent-removal claim

- **Given** Fault fixtures interrupt each removal phase before/after acknowledgement.
- **When** The process restarts from each filesystem image.
- **Then** Acknowledged removal stays absent through all stale-work interleavings; pre-ack outcomes remain explicitly unknown rather than falsely guaranteed.

**Covers:** DEL-004. **Proposed tests:** FT-DEL-004.

### AC-SEC-001 — XDG storage location

- **Given** Environment fixtures provide valid and invalid path bases.
- **When** Location resolution occurs.
- **Then** The intended absolute store is selected or a nonmutating path error occurs, with no writes elsewhere.

**Covers:** SEC-001. **Proposed tests:** UT-SEC-001, FT-SEC-001.

### AC-SEC-002 — Exact permissions and object validation

- **Given** Each object/mode/link boundary is installed in a private filesystem fixture.
- **When** Load/save/lock/Clear validation is attempted.
- **Then** Unsafe objects are refused before content access or replacement; unrelated sentinel objects remain unchanged.

**Covers:** SEC-002. **Proposed tests:** FT-SEC-002.

### AC-SEC-003 — Identity-safe filesystem operations

- **Given** A fixture swaps ancestors or leaves between validation and use.
- **When** Read, write, sync and removal attempt to continue.
- **Then** Operations stay within the validated store or fail; unrelated targets remain untouched and no false durable success occurs.

**Covers:** SEC-003. **Proposed tests:** FT-SEC-003.

### AC-SEC-004 — Advisory sensitive MIME exclusions

- **Given** Producers advertise each sensitive-hint permutation matching an existing entry.
- **When** The offer becomes the regular selection.
- **Then** No sensitive payload is requested or retained and the matching entry's age remains unchanged.

**Covers:** SEC-004. **Proposed tests:** IT-SEC-004.

### AC-SEC-005 — Plaintext ownership and no content logging

- **Given** Unique markers occur in payloads/queries and malformed snapshots.
- **When** Copy/save/error/lock/Clear/diagnostic paths execute privately.
- **Then** Markers never enter logs/support artifacts, owned-buffer cleanup is verified and UI states plaintext/non-forensic limits accurately.

**Covers:** SEC-005. **Proposed tests:** UT-SEC-005, IT-SEC-005.

### AC-SEC-006 — Never restore temporary snapshots

- **Given** Temporary candidates, optional main state and an unrelated sentinel exist.
- **When** Startup maintenance or Clear runs.
- **Then** Only valid authoritative text restores; temps are cleaned or failure reported, never promoted, and unrelated objects are preserved.

**Covers:** SEC-006. **Proposed tests:** FT-SEC-006.

### AC-CLI-001 — Compatible status and truthful health

- **Given** A successful copy is followed by save failure.
- **When** Status is queried before/after failure and during suspension.
- **Then** Original fields retain meaning, separate health reports failure and no latest-save durable success is invented.

**Covers:** CLI-001. **Proposed tests:** UT-CLI-001, IT-CLI-001.

### AC-CLI-002 — Bounded pagination and stable traversal

- **Given** A fixed 100-entry model is traversed, then changed between pinned pages.
- **When** The client follows continuation and retries an outdated revision.
- **Then** Stable traversal returns every entry once; invalid or stale requests fail explicitly without unrelated changes.

**Covers:** CLI-002. **Proposed tests:** UT-CLI-002, IT-CLI-002.

### AC-CLI-003 — Complete response and preview bounds

- **Given** Worst-case legal preview/request fixtures are encoded for every response kind.
- **When** Complete frames are measured.
- **Then** Each fits 8192 bytes, remains valid JSON/UTF-8 and either progresses enumeration or returns a bounded error.

**Covers:** CLI-003. **Proposed tests:** UT-CLI-003.

### AC-CLI-004 — Suspended content and metadata redaction

- **Given** A client knows identities from a previously accessible session.
- **When** Each suspension arrives before status/query/mutation/reply completes.
- **Then** Only redacted generic health or Locked appears, with no history/receipt membership information.

**Covers:** CLI-004. **Proposed tests:** IT-CLI-004.

### AC-CLI-005 — Fresh instance-scoped identities

- **Given** Two fake process instances assign the same numeric entry ID.
- **When** Old, missing and current-instance requests arrive.
- **Then** Only a complete current-instance live identity succeeds; stale or missing identities have no effects.

**Covers:** CLI-005. **Proposed tests:** UT-CLI-005, IT-CLI-005.

### AC-UI-001 — Full model navigation and restored rows

- **Given** A private view displays 100 entries including restored text.
- **When** Filtering/navigation/copy/removal/lock/reopen are exercised.
- **Then** Correct IDs are targeted, no-match preserves history and no obsolete persistence/lock claim remains in affected output.

**Covers:** UI-001. **Proposed tests:** IT-UI-001.

### AC-UI-002 — Observable operation outcomes

- **Given** Copy/Delete/Clear use an injected slow/failing store.
- **When** Publication and worker outcomes are released separately.
- **Then** Feedback names the actual stage and only confirmed removal is described as completed.

**Covers:** UI-002. **Proposed tests:** IT-UI-002.

### AC-ERR-001 — Ordinary-save and timestamp-save failure

- **Given** A text capture and front duplicate refresh precede injected write failures.
- **When** Status, intervening removal and explicit retry execute.
- **Then** Live state stays bounded, timestamps are not renewed by retry and only the latest removal-respecting projection can become durable.

**Covers:** ERR-001. **Proposed tests:** FT-ERR-001, IT-ERR-001.

### AC-ERR-002 — No automatic overwrite of invalid state

- **Given** Each invalid snapshot has a recorded digest.
- **When** Startup, incoming offers and recovery operations are attempted.
- **Then** No records are exposed, no automatic mutation changes the invalid file, and only valid recovery or safe Clear releases the blocked state.

**Covers:** ERR-002. **Proposed tests:** FT-ERR-002.

### AC-ERR-003 — Crash and synchronization outcomes

- **Given** A deterministic filesystem records each crash/error boundary image.
- **When** A new process restores each image under a fake clock.
- **Then** Only eligible valid authoritative data restores and prior pending/unknown receipts are not upgraded to success.

**Covers:** ERR-003. **Proposed tests:** FT-ERR-003.

### AC-ERR-004 — Explicit revalidation after failure

- **Given** A process is blocked by StoreBusy, unsafe state or invalid time, with an external selection present.
- **When** The condition is corrected first without retry, then with explicit retry.
- **Then** Collection stays disabled until validated retry; initial selection is skipped, no old value is published and unknown operations stay unknown.

**Covers:** ERR-004. **Proposed tests:** FT-ERR-004, IT-ERR-004.

### AC-COMP-001 — Deliberate compatibility boundaries

- **Given** Legacy requests and existing relevant integration assertions are replayed.
- **When** Future service responses and compatibility documentation are inspected.
- **Then** Old status fields work, full traversal requires pagination, unsafe mutations fail and semantic changes are documented rather than hidden.

**Covers:** COMP-001. **Proposed tests:** UT-COMP-001, IT-COMP-001.

### AC-NFR-001 — Storage-independent main-context progress

- **Given** A fake worker blocks while main-context events are runnable.
- **When** Status and suspension are dispatched before worker release.
- **Then** Trace ordering proves bounded/redacted responses and revocation before worker release, without cross-thread GTK or invalid ownership.

**Covers:** NFR-001. **Proposed tests:** UT-NFR-001, IT-NFR-001.

### AC-NFR-002 — Deterministic private verification

- **Given** Fake clocks/filesystems and private-session harnesses are configured.
- **When** The proposed cases run in a future separately approved task.
- **Then** Outcomes are deterministic and private, live endpoints remain unused and production test-control requests are unavailable.

**Covers:** NFR-002. **Proposed tests:** UT-NFR-002, IT-NFR-002.

## 18. Requirement-to-test traceability matrix

All proposed case names are specification identifiers, not claims about existing functions or passed suites.

Existing extension anchors:

- `src/services/clipboard_policy.zig` via `src/tests.zig:38`: payload/PNG/preview policy.
- `tests/integration/test_clipboard_capture.py` and `build.zig:824-839`: history, native publication, privacy and screenshot behavior.
- `tests/integration/test_launcher_calculator.py` and `build.zig:840-846`: internal copy and pending-action cancellation.
- `tests/integration/test_security.py` and `build.zig:814-823`: lifecycle/session/Polkit/PAM foundation.
- `scripts/pearl_session.py`: private XDG roots, compositor, buses and children.
- `scripts/test.py` / `scripts/test-suites.json`: official discovery, registration and evidence.

Future pure-model/codec and filesystem targets can extend these anchors. No runner or doctor was executed to author this document.

| Requirement | Acceptance scenario | Proposed test cases |
| --- | --- | --- |
| HIST-001 | AC-HIST-001 | UT-HIST-001, IT-HIST-001 |
| HIST-002 | AC-HIST-002 | UT-HIST-002, IT-HIST-002 |
| HIST-003 | AC-HIST-003 | UT-HIST-003, IT-HIST-003 |
| HIST-004 | AC-HIST-004 | UT-HIST-004, IT-HIST-004 |
| HIST-005 | AC-HIST-005 | IT-HIST-005 |
| RES-001 | AC-RES-001 | UT-RES-001, IT-RES-001 |
| RES-002 | AC-RES-002 | UT-RES-002, IT-RES-002 |
| RES-003 | AC-RES-003 | UT-RES-003, IT-RES-003 |
| RES-004 | AC-RES-004 | UT-RES-004, IT-RES-004 |
| TIME-001 | AC-TIME-001 | UT-TIME-001, IT-TIME-001 |
| TIME-002 | AC-TIME-002 | UT-TIME-002, IT-TIME-002 |
| TIME-003 | AC-TIME-003 | UT-TIME-003, IT-TIME-003 |
| TIME-004 | AC-TIME-004 | UT-TIME-004 |
| TIME-005 | AC-TIME-005 | UT-TIME-005 |
| TIME-006 | AC-TIME-006 | UT-TIME-006, IT-TIME-006 |
| PERS-001 | AC-PERS-001 | UT-PERS-001, IT-PERS-001 |
| PERS-002 | AC-PERS-002 | IT-PERS-002 |
| PERS-003 | AC-PERS-003 | UT-PERS-003 |
| PERS-004 | AC-PERS-004 | UT-PERS-004 |
| PERS-005 | AC-PERS-005 | UT-PERS-005, FT-PERS-005 |
| PERS-006 | AC-PERS-006 | FT-PERS-006 |
| PERS-007 | AC-PERS-007 | UT-PERS-007, IT-PERS-007 |
| PERS-008 | AC-PERS-008 | IT-PERS-008 |
| PERS-009 | AC-PERS-009 | FT-PERS-009, IT-PERS-009 |
| LOCK-001 | AC-LOCK-001 | IT-LOCK-001 |
| LOCK-002 | AC-LOCK-002 | IT-LOCK-002 |
| LOCK-003 | AC-LOCK-003 | IT-LOCK-003 |
| LOCK-004 | AC-LOCK-004 | IT-LOCK-004 |
| DEL-001 | AC-DEL-001 | FT-DEL-001, IT-DEL-001 |
| DEL-002 | AC-DEL-002 | FT-DEL-002, IT-DEL-002 |
| DEL-003 | AC-DEL-003 | IT-DEL-003 |
| DEL-004 | AC-DEL-004 | FT-DEL-004 |
| SEC-001 | AC-SEC-001 | UT-SEC-001, FT-SEC-001 |
| SEC-002 | AC-SEC-002 | FT-SEC-002 |
| SEC-003 | AC-SEC-003 | FT-SEC-003 |
| SEC-004 | AC-SEC-004 | IT-SEC-004 |
| SEC-005 | AC-SEC-005 | UT-SEC-005, IT-SEC-005 |
| SEC-006 | AC-SEC-006 | FT-SEC-006 |
| CLI-001 | AC-CLI-001 | UT-CLI-001, IT-CLI-001 |
| CLI-002 | AC-CLI-002 | UT-CLI-002, IT-CLI-002 |
| CLI-003 | AC-CLI-003 | UT-CLI-003 |
| CLI-004 | AC-CLI-004 | IT-CLI-004 |
| CLI-005 | AC-CLI-005 | UT-CLI-005, IT-CLI-005 |
| UI-001 | AC-UI-001 | IT-UI-001 |
| UI-002 | AC-UI-002 | IT-UI-002 |
| ERR-001 | AC-ERR-001 | FT-ERR-001, IT-ERR-001 |
| ERR-002 | AC-ERR-002 | FT-ERR-002 |
| ERR-003 | AC-ERR-003 | FT-ERR-003 |
| ERR-004 | AC-ERR-004 | FT-ERR-004, IT-ERR-004 |
| COMP-001 | AC-COMP-001 | UT-COMP-001, IT-COMP-001 |
| NFR-001 | AC-NFR-001 | UT-NFR-001, IT-NFR-001 |
| NFR-002 | AC-NFR-002 | UT-NFR-002, IT-NFR-002 |

**Coverage inventory:** 52 normative requirement IDs; 52 Given/When/Then scenarios; 80 distinct proposed test IDs; zero requirements without an acceptance scenario or proposed test. This is document traceability, not implemented coverage or executed test evidence.

## 19. Known limitations

- Durability depends on the filesystem/device honoring successful synchronization.
- Acknowledged removal protects against older serialized-writer work, not external tampering, media corruption or restored backups.
- A crash before acknowledgement can restore old eligible text. A hidden row is not proof of durable deletion.
- A copied-but-unsaved value can be absent after restart; a failed timestamp refresh may restore an older age/order.
- UTC elapsed while powered off cannot be proven from an untrusted wall clock. The bounded-skew policy is not an external trusted-time source.
- Large rollback can withhold legitimate history; forward adjustment can expire it early.
- Unmarked secrets can enter plaintext history. Hints are advisory.
- Lock retains RAM payloads, replacing baseline destruction with access suppression and source/transfer revocation.
- Delete/expiry/eviction do not remove independent selected bytes or data already received elsewhere.
- Modes do not isolate against root, the same UID, backups or third-party copies.
- Graceful shutdown may wait indefinitely on blocking storage; forced exit sacrifices uncompleted persistence.
- Offline readiness, pinned Pillow compatibility, Vulkan operation and native baseline passes remain unverified.
- Legacy clients need updates for instance-qualified mutations and complete pagination.

## 20. Unresolved issues and review decisions

This draft gives every normative requirement a scenario and proposed test. It is not implementation approval.

| Item | Status | Consequence |
| --- | --- | --- |
| Startup future-clock allowance of 300 seconds | Explicit review decision carried forward from Task 4 | Ratify or revise TIME-005 before freezing the functional specification; no clock configuration change proposed. |
| Exact binary layout, byte order, format tag and integrity representation | Deferred technical design | Raw UTF-8, versioning, bounds, validation and round-trip behavior are fixed; interoperable byte fixtures await layout selection. |
| Result-query/recovery CLI syntax and capability discovery encoding | Deferred technical design | Queryability, identity, redaction, outcomes and framing are fixed; no claim those commands exist today. |
| Descriptor APIs, snapshot memory representation and asynchronous reply integration | Deferred technical design | Race/lifetime/response tests constrain the later design; no implementation plan is created here. |
| Receipt knowledge after process death | Defined limitation | Cross-restart receipt journaling is excluded; unknown/stale is returned rather than invented success. |

The next activity is review of this single specification. Technical design, implementation planning, dependency preparation and execution each require later authorization.
