# Six-screen reference acceptance

Baseline: cf321a290b109df706f32e708694c31955748f23.
The user-supplied reference.jpg is the visual acceptance source. The small
clinical-team photograph is extracted from that reference; no external asset,
patient image, credential or production data was downloaded.

## Visual comparison

Real Flutter renders: mobile/ at 414×736; desktop/ at 1440×736. Each of the six
mobile PNGs was inspected against the corresponding reference panel. A second
layout pass reduced duty gaps, task rows and personnel row heights; enlarged-text
calendar legend and day-strip overflows were corrected before final acceptance.

| Panel | Reference treatment applied | Data/behavior retained |
| --- | --- | --- |
| Overview | Teal brand header, greeting/photo, 2-column icon metrics, primary action, summary card | Active count, days, planned days, explicit junior vacancies, total/average points calculated from selected snapshot |
| Duty list | Compact date tile, K/Ç role rows, difficulty badge, expanded details | Persisted roles only; legacy unknown roles stay unknown; preview edit shortcut retained |
| Duty calendar | Month grid, list/calendar segment, role status dots, legend | Read-only projection; tap opens existing day details, no assignment writes |
| Personnel | Group filters, compact K1–K7 identity blocks, group/count/average subtitle | Existing edit, active/group controls and drag reorder; reorder disabled while filtered |
| Tasks | Day strip, duty summary, compact clinical rows | Existing dailyTasks supplies work period, backup, warning and override behavior |
| Settings | Compact weekday rows, ± and direct numeric selection, other-settings foldout | Integer 1–10 limits, existing save/cancel/defaults and holiday settings |

Dark teal headers, subtle card shadows, rounded active mobile tab, spacing and
hierarchy are consistent across the six screens. Desktop keeps the existing
sidebar and multi-column duty layout. No material visual blocker remains.

Intentional differences from the mock:
- Real names, month values and assignments are never replaced with the mock data.
  The local sample uses the real deterministic V1.3 November solve (4 senior,
  3 junior, 10,000 states); it is not production Firestore data.
- AuthState does not expose a display name: greeting is “Merhaba”, not a hard-coded
  doctor's name. Calendar/menu actions remain functional; no dummy notification
  or search action is invented. Native accessible icons replace some mock glyphs.
- Sunday is not an error. Only actual hard errors use the error surface. Old
  position-less documents and old task-workday snapshots are explicitly preserved.
- Tools, statistics and monthly task controls remain in expandable sections;
  settings save/cancel remain available. Existing V1.3 finalization/share blocks
  remain enforced. Readable text, real long names and larger touch targets take
  precedence over matching mock pixels exactly.

## Validation and reproduction

Use the existing toolchain. The fixture uses FakeFirebaseFirestore and in-memory
Auth only; the browser capture explicitly blocks Firebase API calls.

```
flutter build web --debug --no-pub --dart-define=AKYS_V13_SOLVER=true \
  --target test/render/clinical_theme_preview.dart --output /tmp/akys-reference-render
python -m http.server 8767 --bind 127.0.0.1 --directory /tmp/akys-reference-render
# Separate terminal with Playwright and /usr/bin/chromium:
node test/render/capture_reference.cjs
RENDER_WIDTH=1440 node test/render/capture_reference.cjs
```

Fake platform interfaces require debug mode. Production remains lib/main.dart,
release mode, AKYS_V13_SOLVER=true. The older docs/clinical-teal-theme captures
are historical; this folder records the current acceptance.

Analyze clean. Production release build passed. Widget coverage includes
320/414/800/1440 widths, 200% text, long names, old records, task editing,
personnel editing/reordering, default-off and explicit-on feature flag paths.
New tests cover calendar read-only behavior and ± score bounds/persistence.
The full Flutter suite and CI must pass before Hosting release; the existing
workflow also runs the Firestore security emulator suite. No Android build or
physical-device/screen-reader acceptance was performed for this UI release.

No changes to solver algorithms, controller/repository/domain, Auth, Firebase
configuration, security rules or CI workflow are part of this patch.
