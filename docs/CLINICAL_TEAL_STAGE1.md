# Clinical Teal UI V2.0 — Stage 1

Baseline: V1.3 commit 849de0204e1b0d070499be143b0d29634f9af582.
Branch: feat/clinical-teal-ui-v2, isolated worktree /workspace/akys-clinical-teal.
The source V1.3 worktree contained an untracked acceptance plan; it was left
untouched. This UI worktree started clean from the specified commit.

## Shared system

Import core/design/akys_design_system.dart. It exports module-independent semantic
color/spacing/radius/elevation/breakpoint tokens, ClinicalTealTheme.light, common
components and adaptive navigation. No clinical data model is imported.

Palette: primary #006B68, navy #123047, background #F5F8FA, selected #DDF3EF,
warning surface #E7A34C with dark #513000 text. Success/error/info/disabled pairs
have separate foreground/surface tokens. All status text pairs meet tested WCAG
AA 4.5:1 contrast. Borders meet 3:1 against white. Rank/personnel colors remain in
the legacy module palette and are not used as semantic statuses.

Components: AkysAppScaffold, AkysPageHeader, AkysSectionHeader, AkysCard,
AkysStatCard, AkysPrimaryButton, AkysSecondaryButton, AkysStatusChip,
AkysEmptyState, AkysErrorState, AkysLoadingState, AkysFormField,
AkysConfirmDialog. States use text and icons. Native Material focus/actions,
form validation, semantics headings/live regions, scrollable dialogs and padded
48dp button targets are retained. Heights adapt to content rather than clipping
scaled text. Empty/error/loading components can be embedded in any module.

## Navigation preparation

AkysAdaptiveNavigation accepts destinations, selected index, callback and body.
Mobile overflow uses four direct destinations plus a scrollable More sheet when
there are more than five destinations. For Work Schedule the proposed ordered
list is Overview/Duty/Tasks/Personnel/History/Settings; the last two appear under
More. Tablet/desktop show a scrollable side menu (720/1100 breakpoints). This shell
is prepared only; current Work Schedule navigation is unchanged.

## First application

Only the authorized home page uses ClinicalTealTheme locally. MaterialApp's legacy
theme, login/AuthGate, private routes, Work Schedule and public-share pages retain
their prior behavior/theme. Home shows AKYS branding, description, working schedule
card, disabled coming-soon operative-notes card and a future-modules notice.
Wide screens use two module columns; narrow or large-text screens use one. The
working card retains /work_schedule navigation. No operative-notes feature exists.

## Validation and limits

Design tests cover 320/768/1440 widths at 100/200% text size, all common components,
contrast, keyboard activation, form/confirm behavior and adaptive navigation at
320/800/1440 widths with 200% text size. Existing auth tests cover denied users,
private routes, logout and revoked authority. Full V1.2/V1.3 suite and builds are
required before commit. An initial tablet navigation test needed a layout pump
after scrolling; the corrected interaction passes without suppressing errors.

Local widget captures used test fonts and validate geometry only; they are not
production-font screenshots or golden baselines. Physical device, screen reader
and full-browser visual acceptance remain future checks. No theme changes were
applied to the other clinical modules, and dark mode is not introduced here.
No solver/repository/model/Firebase/rules/feature-flag changes are included.

Final validation: flutter analyze clean; 197/197 tests passed (13 new design
acceptance tests); Flutter Web release build passed; Android debug APK build
passed. No dependency lockfile or unrelated source changes. Existing compiler
notices about fonts/Kotlin/unchecked plugin operations did not fail the builds.
