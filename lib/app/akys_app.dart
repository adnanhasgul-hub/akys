import 'package:flutter/material.dart';

import '../modules/operative_notes/operative_notes_module.dart';
import '../modules/work_schedule/work_schedule_module.dart';

class AkysApp extends StatelessWidget {
  const AkysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AKYS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B65)),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
      ),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
