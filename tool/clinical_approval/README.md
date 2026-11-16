# Stage 1.9E: trusted approval prototype (LOCAL ONLY)

The executable accepts **only** `--emulator-only <trusted-test-jwks.json> <port>`.
It binds loopback and its Firestore REST target is fixed to `demo-akys` on
127.0.0.1:8080. It cannot be configured to write production. The Flutter approval
button and client Rules remain CLOSED for A and B. Do not deploy this harness.

## Actual implemented boundary

The HTTP client supplies only schedule ID, expected version and idempotency key.
An RS256 signature is verified against server-configured public keys before
issuer, audience, expiry, issued/auth times, subject and boolean admin claim are
accepted. Unsigned Auth Emulator JWTs are deliberately **not** trusted. Tests
create an ephemeral RSA issuer in a temporary directory, not a new application
identity system. Private keys are never committed. This is not a test of Google
Firebase token issuance, revocation, certificate rotation or Cloud Run IAM.

The service reads head and immutable version in one Firestore transaction,
checks expected version/month/operation linkage, decodes the exact stored payload,
rejects portable proof fields and B substitutions, and invokes the EXISTING Dart
SolutionValidator. Locks are checked on snapshot decoding. A valid, complete A
schedule does not require an optimum proof. Approval writes head + version +
metadata mirror + a server-owned success audit atomically with updateTime
preconditions. Repeated same-user/same-operation requests are idempotent; other
operations/conflicting versions fail closed. Client writes cannot alter an
approved version or fabricate the server audit collection.

Firestore emulator 1.22 GET-with-transaction query fails with BYTE_STRING parsing;
the working prototype uses POST batchGet inside the same transaction instead.

## Production remains blocked

Dart compiles and runs the same validator in a server process: there is no need to
rewrite the solver. But a production service additionally needs a reviewed Google
Secure Token key fetch/cache/rotation and revocation policy, workload identity/ADC
Firestore adapter with minimal IAM, operational timeouts/rate limits, deployment
and real identity acceptance testing. None was provisioned or claimed verified.
The custom RS256 verifier needs independent security review before production;
standard audited verification should be preferred if a suitable Dart library is
approved. Never enable approval merely because the local harness passes.

The prototype persists successful audit events; failures are server process logs,
not a guaranteed durable rejected-attempt audit archive. Cloud logging retention
and failure audit durability are still required. An HTTP timeout after an atomic
commit is an ambiguous acknowledgement, resolved by the same operation ID; it
cannot roll back a valid committed approval. A failed clinical validation never
creates approval. B approvals remain prohibited in every case.

## Reproduce

Activate the repository Dart toolchain, then run the Firebase Emulator command
used in `VALIDATION_1_9E.md`. `emulator_acceptance.py` starts and terminates the Dart
service, seeds synthetic data and verifies HTTP + transaction behavior. Tests use
only `demo-akys`, and no production credential is required.
