# Stage 1.9E implementation boundaries

## Encrypted local recovery

Web uses AES-256-GCM with a fresh 96-bit IV and a newly generated non-extractable
CryptoKey per entry. IndexedDB atomically stores key handle, IV and ciphertext.
A SHA-256 owner identifier is authenticated as AAD. Reads are explicitly scoped to
the authenticated UID. No physician or schedule plaintext is persistently stored.
Non-extractable does not mean inaccessible to malicious same-origin JavaScript:
XSS, a compromised origin/profile, privileged browser extensions and an unlocked
shared browser are outside this confidentiality boundary. Browser clearing may
remove both key and ciphertext. No guaranteed recovery is promised.

Android uses AndroidKeyStore AES-256-GCM and private noBackupFilesDir ciphertext,
fsync + atomic rename, with file/key identity derived from UID. Crypto/file work is
on a serial executor, not the Android UI thread. Hardware-backed key protection is
device-dependent and is not claimed. Rooted/unlocked-device threats remain. No
physical device is available; Android crypto behavior is build-verified only.

DraftSession observes actual draft changes, writes after a 300ms debounce and
retains exact retry operation IDs before sending uncertain server saves. Recovery
is offered explicitly, with fresh server version/status check when a base record
exists. A conflict keeps the local candidate and does not overwrite workspace or
server. Successful clean saves clear recovery; edits made during a save preserve
a recovery entry based on the acknowledged version. New UIDs never load previous
UID entries. Failed decryption blocks automatic overwrite until explicit deletion.
Several tabs for the SAME user share the latest recovery entry; cross-tab recovery
history is not implemented. Crash before debounce/storage completion can lose the
latest change. Server version concurrency protections remain authoritative.

## History payload separation

New heads carry historySchema=2. Each save atomically writes head, full immutable
versions/N, payload-free version_metadata/N and event (four writes versus three).
Rules require metadata equal the transaction's head; clients cannot mutate/delete
metadata. UI history queries order by numeric version then document ID, using a
cursor and pageSize+1 (max 51 docs). Only opening a version downloads payload.
The first page checks the head once; subsequent cursors pin collection identity.
Default single-field Firestore indexes cover these queries; no composite index is
required. The emulator verifies real queries.

Legacy heads without historySchema keep the old full-payload history path. No
migration runs automatically. This avoids hiding old versions. A separately
reviewed admin migration would have to validate every legacy version, backfill
metadata, then atomically mark the head; it is NOT included or run here. This
legacy path retains the old bandwidth cost until such a migration is approved.

## UI hot path

ScheduleEditor.current previously re-evaluated all constraints and quality for
EVERY getter. Without localEvidence, both Problem and EditedSchedule are immutable;
all accepted edits/undo/redo already compute and validate their replacement. That
case now returns the evaluated revision. With mutable TransitionSession evidence,
current STILL rechecks authorization every time. No DFS or quality rule changed.
Workspace caches encoded draft against problem/revision/preview identity and a
copy of names, avoiding repeated JSON and validation on unchanged progress events.
Saving/restoring still validates independently. Dirty-check and actual Chromium
before/after measurements are retained separately; no single-run device guarantee.
