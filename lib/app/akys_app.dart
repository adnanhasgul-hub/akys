import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../core/auth/auth_gate.dart';

import '../modules/operative_notes/operative_notes_module.dart';
import '../modules/work_schedule/work_schedule_module.dart';
import '../modules/work_schedule/data/schedule_repository.dart';
import '../modules/work_schedule/presentation/schedule_page.dart';
import '../modules/work_schedule/presentation/shared_schedule_page.dart';
import '../core/theme/akys_colors.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

class AkysApp extends StatelessWidget {
  const AkysApp({required this.auth, this.scheduleRepository, super.key});

  final AuthService auth;
  final ScheduleRepository? scheduleRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AKYS',
      debugShowCheckedModeBanner: false,
      theme: AkysColors.theme,
      locale: const Locale('tr'),
      supportedLocales: const [Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      onGenerateRoute: (settings) {
        final match = RegExp(r'^/shared/schedule/([a-f0-9]{48})$')
            .firstMatch(settings.name ?? '');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => match != null
              ? SharedSchedulePage(
                  token: match.group(1)!,
                  repository:
                      scheduleRepository ?? FirestoreScheduleRepository(),
                )
              : AuthGate(
                  auth: auth,
                  child: settings.name == '/work_schedule'
                      ? SchedulePage(
                          repository:
                              scheduleRepository ??
                              FirestoreScheduleRepository(),
                          logout: LogoutButton(auth: auth),
                        )
                      : _HomePage(auth: auth),
                ),
        );
      },
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.auth});
  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(actions: [LogoutButton(auth: auth)]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('AKYS', style: textTheme.headlineLarge),
                const SizedBox(height: 8),
                Text('A Klinik Yönetim Sistemi', style: textTheme.titleMedium),
                const SizedBox(height: 32),
                for (final module in [workScheduleModule, operativeNotesModule])
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: module == workScheduleModule
                          ? () =>
                                Navigator.of(context)
                                    .pushNamed('/work_schedule')
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(module.title, style: textTheme.titleMedium),
                            if (module.comingSoon) ...[
                              const SizedBox(height: 8),
                              const Text('Yakında'),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
