import 'package:flutter/material.dart';

import 'data/draft_session.dart';

class PersistencePanel extends StatefulWidget {
  const PersistencePanel({super.key, required this.session});
  final DraftSession session;
  @override
  State<PersistencePanel> createState() => _PersistencePanelState();
}

class _PersistencePanelState extends State<PersistencePanel> {
  DraftSession get s => widget.session;
  String? error;
  Future<void> perform(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<bool> discard() async =>
      !s.dirty ||
      await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Kaydedilmemiş değişiklikler'),
              content: const Text(
                'Yerel değişiklikler kaybolacak. Devam edilsin mi?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Değişiklikleri bırak'),
                ),
              ],
            ),
          ) ==
          true;
  Future<void> browse({bool history = false}) async {
    final rows = history
        ? await s.repository.history(s.record!.scheduleId)
        : await s.repository.list();
    if (!mounted) return;
    final selected = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(
          history ? 'Sürüm geçmişi' : 'Kaydedilmiş taslaklar (son 100)',
        ),
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kayıt bulunamadı.'),
            ),
          for (var i = 0; i < rows.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, i),
              child: Text(
                '${rows[i].snapshot.problem.startDate!.month}/${rows[i].snapshot.problem.startDate!.year} • v${rows[i].version} • ${rows[i].status}\n${rows[i].summary}\n${rows[i].actor} • ${rows[i].updatedAt}\nKaynak: ${rows[i].sourceId ?? "—"} / ${rows[i].sourceVersion ?? "—"}',
              ),
            ),
        ],
      ),
    );
    if (selected != null && await discard()) {
      await s.open(rows[selected].scheduleId, version: rows[selected].version);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (c, _) => ExpansionTile(
      title: Text(
        s.saving
            ? 'Kaydediliyor…'
            : s.dirty
            ? 'Kaydedilmemiş değişiklikler'
            : 'Kaydedildi • v${s.record?.version}',
      ),
      subtitle: Text(
        s.record == null
            ? 'Yeni taslak • Kalıcı onay kapalı'
            : '${s.record!.status} • ${s.record!.updatedAt ?? "Sunucu zamanı bekleniyor"}',
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('save-draft'),
              onPressed:
                  s.saving ||
                      s.workspace.pending ||
                      s.record?.status == 'archived'
                  ? null
                  : () => s.save(),
              child: Text(
                s.retry == null ? 'Kaydet' : 'Aynı kaydı yeniden dene',
              ),
            ),
            OutlinedButton(
              onPressed: s.saving || s.workspace.pending
                  ? null
                  : () => perform(() => browse()),
              child: const Text('Taslakları aç'),
            ),
            OutlinedButton(
              onPressed: s.saving || s.workspace.pending
                  ? null
                  : () => perform(() async {
                      if (await discard()) s.newDraft();
                    }),
              child: const Text('Yeni taslak'),
            ),
            OutlinedButton(
              onPressed: s.saving || s.workspace.pending || s.record == null
                  ? null
                  : () => perform(() async {
                      s.revision();
                    }),
              child: const Text('Revizyon oluştur'),
            ),
            OutlinedButton(
              onPressed: s.saving || s.workspace.pending || s.record == null
                  ? null
                  : () => perform(() => browse(history: true)),
              child: const Text('Sürüm geçmişi'),
            ),
            OutlinedButton(
              onPressed:
                  s.saving ||
                      s.workspace.pending ||
                      s.record == null ||
                      s.record!.status != 'draft'
                  ? null
                  : () => s.save(archive: true),
              child: const Text('Arşivle'),
            ),
            if (s.workspace.pending && s.workspace.previewOnly)
              OutlinedButton(
                onPressed: s.saving ? null : () => s.save(preview: true),
                child: const Text('B önizlemesini taslak kaydet'),
              ),
            const FilledButton(
              onPressed: null,
              child: Text('Kalıcı onay kapalı'),
            ),
            TextButton(
              onPressed: s.record == null || s.saving
                  ? null
                  : () => perform(s.approval),
              child: const Text('Onay neden kapalı?'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Sunucuda klinik doğrulama bulunmadığından A ve B çizelgeleri onaylanamaz. Kaydedilmiş kalite ve kanıt iddiaları yetki sağlamaz.',
          ),
        ),
        if (s.error != null || error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              s.error ?? error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
