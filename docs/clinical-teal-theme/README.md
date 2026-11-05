# Clinical Teal root theme correction

## Cause and scope

The production `AkysApp` MaterialApp used the legacy `AkysColors.theme`
(seed #176B65, background #F8FAFC). Home and SchedulePage applied a local
Clinical Teal Theme, but root Navigator dialogs and the login route inherited
the old theme. SchedulePage also read some text styles above its local Theme.
The login gradient and legacy schedule color constants reinforced the mismatch.

MaterialApp now owns the existing ClinicalTealTheme.light. Redundant local
wrappers are removed. Legacy brand/status aliases delegate to shared tokens;
normal/weekend backgrounds no longer imply errors. Rank and clinic task palettes
are unchanged. Login changes are styling only. No solver, repository, Auth
behavior, permissions, feature flags, Firebase configuration or workflows changed.
The spreadsheet export's separate CSS palette is outside this screen-theme fix.

## Validation

- `flutter analyze --no-pub`: no issues.
- Relevant Flutter tests: 71 passed (design, widget_test, schedule/group/difficulty widgets).
- Chromium tests: 27 passed (root_theme, clinical_teal, navigation_acceptance).
- New regression tests use the real AkysApp root, signed-out route, every schedule
  destination, and the root Navigator personnel dialog instead of injecting a test theme.
- Real Chromium render at 414x1000 and 1440x1000: login, home, overview, duty,
  tasks, personnel, combined, history, settings and personnel dialog captured.
- Pixel inspection confirms primary #006B68, heading #123047, background #F5F8FA
  and selected #DDF3EF. Neither old primary nor old background appears in these
  captures. Hover/pressed overlays and dialog scrims intentionally blend colors.
- Existing warning token #E7A34C remains unchanged; warning text uses the existing
  accessible darker warning foreground. These viewport captures do not exercise
  every warning state. See pixel-counts.txt and representative PNGs.
- No full suite or Android rebuild repeated; no production deploy performed.

## Reproduce the isolated render

The fixture uses in-memory auth and FakeFirebaseFirestore only. It does not
initialize Firebase or access production data. Seeded November assignments are
visual fixtures, not solver acceptance evidence or clinical schedules.

```
flutter build web --debug --no-pub --dart-define=AKYS_V13_SOLVER=true \
  --target test/render/clinical_theme_preview.dart --output /tmp/akys-theme-render
python -m http.server 8765 --bind 127.0.0.1 --directory /tmp/akys-theme-render
# Separate terminal, with Playwright and /usr/bin/chromium available:
node test/render/capture_theme.cjs
```

Screenshots go to /tmp/akys-theme-shots. Debug is required by the fake platform
interface; it explicitly rejects release builds. Production still builds
lib/main.dart. This fixture is never a deployment target. Physical-device and
live authenticated production acceptance were not performed.
