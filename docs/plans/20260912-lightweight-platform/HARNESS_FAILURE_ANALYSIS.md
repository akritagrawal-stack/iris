# H1 forensic analysis: Trial 21 repeat-copy failure

Date: 2026-09-12

This is a read-only analysis of one remaining complex failure. It uses the
retained Trial 21 result, its reduced reproducer, the historical power-user
artifacts, and the September 12 review package. No model call, build, target
app action, or edit to the historical lab was performed for this analysis.

## Finding

The next correction should be a contract-first transfer identity and
provenance receipt, carried into the existing bounded maker and reviewer
context. The merge must distinguish a source identity from a local instance,
semantic equality from identity, and a changed copy from an unchanged repeat.
It must match by indexed identity and semantic data, build parent mappings by
origin, and refuse missing or ambiguous provenance instead of selecting by
traversal order. This is one correction boundary. It does not require a new
model route, a larger context or call limit, a new telemetry service, or a
second retry campaign.

The reverse consumer selection and source-like `return false` / `throw new
Error` compaction fixes are already present in the current branch. They are
not the cause of this finding and are not repeated here. The static relative
import selection limit remains a disclosed bound.

## Lost requirement and submitted context

The frozen transfer contract requires that confirmed identical items are
skipped, while differing or uncertain matches remain separate, with no source
deletion or overwrite. It specifically requires importing the same file twice
to leave counts, bodies and memberships unchanged. Same name and equal
creation time are never identity proof. See
`/Users/akrit/Documents/iris-harness-lab/research/harness-v2/TRANSFER_ACCEPTANCE_CONTRACT.md`.

Trial 21 first rejected an origin fallback that consumed a later incoming
record's exact identity. A repair then added identity reservation and related
tests, and all 147 confined tests passed. The subsequent independent review
still rejected unchanged-repeat duplication when multiple retained copies
shared a source ID. The retained result is
`/Users/akrit/Documents/iris-harness-lab/research/harness-v2/TRIAL21_RESULT.md`.

The final review supplied 62,235 bytes and reported 10 omissions. It included
the changed tests, database and type files, the 17,046-byte Settings file,
transfer component/helper, app/export code and engine helpers. It omitted the
19,715-byte `Dashboard` consumer. A guessed `src/pages/Editor.tsx` did not
exist. Therefore the review could not verify the real listing/editor consumer
path from that context. The missing consumer evidence is a separate review
coverage defect. Raising the 24-file or 64 KiB limits is not justified.

## Submitted behavior and causal failure

The retained Trial 21 reproducer removes identity and view-only fields from a
content comparison. It first tries an exact ID, then retained copies, then
related origin candidates. When more than one candidate remains, it allocates
a random ID and appends a copy. The `used` set is local to one merge and is
reset for the next import. With one incoming folder, one unrelated destination
ID collision, and two equal retained copies, three unchanged imports grow the
folder count from 3 to 4 to 5 to 6 while leaving the unrelated destination
folder unchanged:

```text
node /Users/akrit/Documents/iris-harness-lab/research/harness-v2/trial21-ambiguous-copy-repro.mjs
{"reproduced":"unchanged repeated import keeps adding copies","folderCounts":[3,4,5,6]}
```

This is a reduced causal diagnostic, not a reconstruction of the complete
rolled-back candidate. It proves the independent review's remaining defect:
the algorithm treats ambiguity as permission to create another copy, so the
same unchanged input is not idempotent. Earlier evidence also found that a
parser discarded `transferOrigin`, which loses onward identity. A bare origin
ID would still be ambiguous across independent libraries, so preserving that
field alone is insufficient.

## Why the retained tests missed it and what review caught

The 147 passing confined tests establish that the repaired candidate fit its
local checks. They do not establish the multi-run state transition above. No
retained test evidence exercises two equivalent retained copies, a colliding
destination ID, three unchanged imports, a reopened note, and a restart as one
permutation-invariant case. The reduced reproducer supplied that missing
discriminator without relying on labels or array order.

Independent review caught three material facts before native checks could run:

1. The first repair did not solve the ambiguous retained-copy repeat. It still
   permitted a new folder and descendants on every unchanged import.
2. Final review context omitted the actual `Dashboard` consumer and included
   a nonexistent guessed editor path, so consumer behavior was unverified.
3. Native feature checks never ran, the candidate was not installed, and no
   complex feature was accepted. The truthful failure card preserved the
   existing app and the original transfer note.

The current review package records the disposition as an open transfer identity
blocker. It also records that the current bounded reverse-consumer selection
is a harness mechanism, not evidence of a successful transfer.

## Next correction boundary

Add a small versioned identity receipt to the transfer contract and protected
maker context before another real run. For each note or folder, the receipt
needs a source `libraryId`, an origin entity ID, a current local `instanceId`,
the parent origin where applicable, a canonical semantic hash, and a direct
copy lineage edge when the record is copied. The rules are:

- An exact origin plus semantic payload is idempotent across repeats, opening a
  note, array permutations and restart.
- A same-origin changed payload receives one new local instance, leaving the
  old instance unchanged. Repeating that changed receipt is idempotent too.
- Parent mappings resolve by origin before descendants are imported. Labels,
  timestamps, content alone, array position and a first candidate cannot map a
  parent.
- A missing, malformed or ambiguous receipt fails before writes, or is
  explicitly handled as an untrusted copy with no idempotence claim. It must
  never silently fall back to name, time or content heuristics.

Carry the seven cases in
`/Users/akrit/Documents/iris-harness-lab/research/harness-v2/TRANSFER_IDENTITY_CAUSAL_CHECKPOINT.md`
as a short deterministic reviewer obligation: equal-name/equal-time distinct
origins, exact repeat after opening and restart, changed same-origin content,
permuted arrays, destination ID collision with retained copies, onward export
and repeat, and malformed/dangling input. The reviewer must identify which
rows actually ran. Do not infer coverage from a function name, a mocked file
reader, a build pass or an unexecuted native source file.

## Frozen real UI journey and oracle

Run this only after the identity correction is implemented and admitted, using
the registered disposable NitroAI Iris Test app and its isolated profile. The
baseline currently has no transfer import control, so the positive journey is
unverified and remains a gate.

1. Through the app's ordinary data path, prepare a source library with two
   folders having equal names and equal creation times but distinct receipt
   origins, and notes visibly belonging to each. Export with the named library
   transfer control. Capture the exact file bytes at the file boundary.
2. Prepare the destination with an unrelated folder, a destination ID that
   collides with one incoming ID, and two retained copies sharing that incoming
   origin and identical semantic content. Use the actual Settings transfer
   controls, select the captured file, and import without overwriting.
3. Verify the two folder memberships and note bodies in the mounted UI. Open
   one imported note, quit and relaunch the target app, then import the exact
   same bytes twice. Revisit the affected folders and notes.
4. Independently snapshot the five requested records and relationships after
   each import. Record the Iris Test run ID, target app identity, source file
   digest and visible counts. Do not use hidden storage seeding as UI evidence.

The oracle is frozen as follows:

| Case | Required result |
| --- | --- |
| Equal-name/equal-time folders with distinct origins | Both folder identities and both memberships remain visible. |
| Exact repeat after opening a note and after restart | Zero semantic additions. A view timestamp may change. |
| Destination ID collision plus two equivalent retained copies | No overwrite and no repeated copies. A changed semantic version gets one fresh instance with provenance. |
| Reordered folder and note arrays | Same canonical origin-to-instance mapping and counts. |
| Same-origin changed body or source metadata | Old record stays unchanged; one new mapped instance is retained; repeating it adds zero. |
| Missing provenance, malformed input or dangling parent | Clear refusal before writes, with no partial records. |

Any count sequence 3, 4, 5, 6 for unchanged repeats is an immediate failure.
No native run, installed behavior, target restart or Iris restart Undo may be
reported as passed unless its actual controls and evidence are recorded.

## Measured denominators and limits

Trial 21's settled feature run had 15 physical calls, zero in flight,
1,543,541 submitted input bytes, 681,899 reported input tokens including
186,240 cached, 9,981 output tokens including 1,041 reasoning output tokens,
and 500.24 seconds including approval time. Dollar cost and provider-confirmed
model identity were unavailable. It produced zero accepted complex outcomes
and zero native feature checks. The two repair requests were admitted and
charged, so they must remain in the denominator.

The historical power-user directory is a separate earlier backup attempt and
must not be added to Trial 21. Its `feature.log` ends with a model-call failure
before review. Its `usage.json` records 10 calls, 664,584 submitted input
bytes, 376,911 input tokens including 123,008 cached, and 8,902 output tokens.
Those figures describe that earlier incomplete attempt, not Trial 21 and not a
model comparison.

For Terra, the retained V1 compile logs are
`/tmp/iris-harness-host-candidate-20260912/compiler.log` and
`/tmp/iris-harness-host-candidate-20260912/native-compiler.log`. The compile
completed with exit 0 for 176 sources, with 264 existing warnings. The
focused check executable and command were:

```text
/tmp/iris-harness-host-candidate-20260912/iris-harness-feature-host --checks
```

Its accepted-candidate checks passed in that run. These logs and the check result are
V1 evidence only and are not evidence for the H1 transfer journey.

## Evidence limits

No complete rejected Trial 21 feature tree was retained. The reduced script
proves the reviewed matching failure but cannot establish every detail of the
missing candidate. No positive native transfer run, target-app restart after a
transfer, Iris restart-selected Undo, provider-confirmed model identity or
dollar price is available. The source and existing note remaining intact after
rejection is recovery evidence, not transfer success.
