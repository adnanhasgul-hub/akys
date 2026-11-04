import 'package:flutter/material.dart';

import '../../../core/design/akys_design_system.dart';

/// View-only: no proof inference from a zero observed violation count.
class SolverStatusSummary extends StatelessWidget {
  const SolverStatusSummary({
    required this.valid,
    required this.hierarchyProven,
    required this.optimal,
    required this.searchLimited,
    this.finished = false,
    super.key,
  });
  final bool? valid;
  final bool hierarchyProven, optimal, searchLimited, finished;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (valid != null) ...[
        AkysStatusChip(
          label: 'Hard constraint: ${valid! ? 'GEÇERLİ' : 'GEÇERSİZ'}',
          status: valid! ? AkysStatus.success : AkysStatus.error,
        ),
        AkysStatusChip(
          label:
              'Kıdem hiyerarşisi: ${hierarchyProven ? 'kanıtlandı' : 'kanıtlanmadı; istisna kesin kabul edilmez'}',
          status: hierarchyProven ? AkysStatus.success : AkysStatus.info,
        ),
        AkysStatusChip(
          label:
              'Genel optimizasyon: ${optimal ? 'tamamlandı' : 'tamamlanmadı; geçici taslak'}',
          status: optimal ? AkysStatus.success : AkysStatus.info,
        ),
      ] else if (finished)
        const AkysStatusChip(
          label: 'Geçerli çizelge bulunamadı',
          status: AkysStatus.info,
        ),
      if (searchLimited)
        const AkysStatusChip(
          label: 'Arama sınırına ulaşıldı. Bu, imkânsızlık anlamına gelmez; geçerli önizleme korunur.',
          status: AkysStatus.info,
        ),
    ],
  );
}
