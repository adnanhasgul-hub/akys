import 'package:flutter/material.dart';

import 'akys_components.dart';

class AkysMonthOption {
  const AkysMonthOption({
    required this.id,
    required this.title,
    required this.statusLabel,
    required this.status,
  });
  final String id, title, statusLabel;
  final AkysStatus status;
}

/// Presentation-only selector. The owner retains loading, selection and routing.
class AkysMonthSelector extends StatelessWidget {
  const AkysMonthSelector({
    required this.options,
    required this.selectedId,
    required this.onChanged,
    this.loading = false,
    super.key,
  });
  final List<AkysMonthOption> options;
  final String? selectedId;
  final ValueChanged<String>? onChanged;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [LinearProgressIndicator(), Text('Aylar yükleniyor')],
        ),
      );
    }
    if (options.isEmpty) {
      return const Text('Henüz kayıtlı ay yok. Nöbet Hazırla ile başlayın.');
    }
    final selection = options.where((m) => m.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('$selectedId-${options.length}'),
          initialValue: selection?.id,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
            labelText: 'Çalışılan ay',
            isDense: true,
          ),
          selectedItemBuilder: (context) => [
            for (final m in options)
              Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          items: [
            for (final m in options)
              DropdownMenuItem(
                value: m.id,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('${m.title} · ${m.statusLabel}'),
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (id) {
                  if (id != null) onChanged!(id);
                },
        ),
        if (selection != null) ...[
          const SizedBox(height: 8),
          AkysStatusChip(
            label: selection.statusLabel,
            status: selection.status,
          ),
        ],
      ],
    );
  }
}
