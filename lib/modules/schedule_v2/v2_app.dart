import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../core/design/clinical_teal_theme.dart';
import 'schedule_page.dart';
import 'workspace.dart';

/// Explicit, local-only entry point. Does not modify the authenticated V1 app.
class V2App extends StatelessWidget {
  const V2App({super.key, this.workspace});
  final ScheduleWorkspace? workspace;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AKYS V2',
    debugShowCheckedModeBanner: false,
    theme: ClinicalTealTheme.light,
    locale: const Locale('tr'),
    supportedLocales: const [Locale('tr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: V2SchedulePage(workspace: workspace),
  );
}
