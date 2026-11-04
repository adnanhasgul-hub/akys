import '../core/design/clinical_teal_theme.dart';
import '../core/design/akys_components.dart';

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
  Widget build(BuildContext context) => Theme(
    data: ClinicalTealTheme.light,
    child: Builder(
      builder: (context) => AkysAppScaffold(
        actions: [LogoutButton(auth: auth)],
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AkysTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: AkysTokens.selected,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(AkysTokens.spaceMd),
                  child: Icon(
                    Icons.local_hospital_outlined,
                    size: 36,
                    color: AkysTokens.primary,
                  ),
                ),
              ),
              const SizedBox(height: AkysTokens.spaceLg),
              const AkysPageHeader(
                title: 'AKYS',
                description: 'A Klinik Yönetim Sistemi',
              ),
              const SizedBox(height: AkysTokens.spaceXl),
              const AkysSectionHeader(
                title: 'Klinik çalışma alanınız',
                description: 'Günlük işlerinizi tek bir yerden yönetin.',
              ),
              const SizedBox(height: AkysTokens.spaceLg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 720 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24;
                  final cards = [
                    _module(
                      context,
                      title: workScheduleModule.title,
                      description: 'Nöbet planlaması, görev dağılımı ve personel yönetimi.',
                      icon: Icons.calendar_month_outlined,
                      available: true,
                    ),
                    _module(
                      context,
                      title: operativeNotesModule.title,
                      description: 'Ameliyat kayıtları için yeni çalışma alanı hazırlanıyor.',
                      icon: Icons.description_outlined,
                      available: false,
                    ),
                  ];
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: AkysTokens.spaceLg),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            cards[0],
                            const SizedBox(height: AkysTokens.spaceMd),
                            cards[1],
                          ],
                        );
                },
              ),
              const SizedBox(height: AkysTokens.spaceLg),
              const AkysStatusChip(
                label: 'Yeni klinik modüller yakında',
                status: AkysStatus.info,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _module(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required bool available,
  }) => AkysCard(
    semanticLabel: available ? '$title modülünü aç' : null,
    onTap: available
        ? () => Navigator.of(context).pushNamed('/work_schedule')
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 32,
          color: available ? AkysTokens.primary : AkysTokens.muted,
        ),
        const SizedBox(height: AkysTokens.spaceMd),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AkysTokens.spaceSm),
        Text(description),
        const SizedBox(height: AkysTokens.spaceLg),
        AkysStatusChip(
          label: available ? 'Kullanıma hazır' : 'Yakında',
          status: available ? AkysStatus.success : AkysStatus.disabled,
        ),
        if (available) ...[
          const SizedBox(height: AkysTokens.spaceMd),
          const Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Modülü aç',
                style: TextStyle(
                  color: AkysTokens.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(Icons.arrow_forward, color: AkysTokens.primary, size: 20),
            ],
          ),
        ],
      ],
    ),
  );
}
