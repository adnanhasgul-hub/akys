import 'package:flutter/material.dart';

import 'data/draft_session.dart';
import 'data/draft_repository.dart';

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
    final selected = await showDialog<DraftSummary>(
      context: context,
      builder: (_) => DraftBrowser(
        repository: s.repository,
        scheduleId: history ? s.record!.scheduleId : null,
      ),
    );
    if (selected != null && mounted && await discard()) {
      await s.open(selected.id, version: selected.version);
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
        if (s.recoveryCandidate != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Şifreli yerel taslak kurtarılabilir'),
              const Text(
                'Kurtarmadan önce sunucudaki sürüm kontrol edilir. Çakışma varsa kurtarma durdurulur.',
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => perform(s.recover),
                    child: const Text('Kurtar'),
                  ),
                  TextButton(
                    onPressed: () => perform(s.discardRecovery),
                    child: const Text('Yerel kopyayı sil'),
                  ),
                ],
              ),
            ],
          ),
        if (s.recoveryError != null) ...[
          Text(s.recoveryError!),
          TextButton(onPressed: () => perform(s.discardRecovery), child: const Text('Okunamayan yerel kopyayı sil')),
        ],
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

/// Cursor-based browsing: 20 metadata rows, no N+1 payload reads for the draft list.
class DraftBrowser extends StatefulWidget {
  const DraftBrowser({super.key, required this.repository, this.scheduleId});
  final DraftRepository repository;
  final String? scheduleId;
  @override
  State<DraftBrowser> createState() => _DraftBrowserState();
}

class _DraftBrowserState extends State<DraftBrowser> {
  final rows = <DraftSummary>[];
  DraftPage? page;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.repository.page(
        scheduleId: widget.scheduleId,
        after: page?.cursor,
      );
      if (!mounted) return;
      setState(() {
        for (final row in next.items) {
          if (!rows.any(
            (old) => old.id == row.id && old.version == row.version,
          )) {
            rows.add(row);
          }
        }
        page = next;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.scheduleId == null ? 'Kaydedilmiş taslaklar' : 'Sürüm geçmişi',
    ),
    content: SizedBox(
      width: 600,
      height: 440,
      child: ListView(
        children: [
          for (final row in rows)
            TextButton(
              onPressed: () => Navigator.pop(context, row),
              child: Text(
                '${row.month}/${row.year} • v${row.version} • ${row.status}\n${row.summary}\n${row.actor} • ${row.at}\nKaynak: ${row.sourceId ?? "—"} / ${row.sourceVersion ?? "—"}',
              ),
            ),
          if (rows.isEmpty && !loading && error == null)
            const Text('Kayıt bulunamadı.'),
          if (error != null) Text(error!),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (!loading && (page == null || page!.hasMore || error != null))
            TextButton(
              onPressed: load,
              child: Text(error == null ? 'Daha fazla yükle' : 'Yeniden dene'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
