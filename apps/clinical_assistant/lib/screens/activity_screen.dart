import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Past Notes — clinician-readable note drafts only.
///
/// Chat, drug search, and interaction sessions remain in the local store and
/// sync_queue for backend ingest; they are not listed here.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<ClinicalSession> _notes = [];
  Map<String, Patient> _patientsById = {};
  int _pendingSync = 0;
  bool _loading = true;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final sessions = await widget.repository.listSessions(limit: 200);
    final patients = await widget.repository.listPatients();
    final pending = await widget.repository.pendingSyncCount();
    if (!mounted) return;
    setState(() {
      _notes = sessions.where((s) => s.queryType == 'note_draft').toList();
      _patientsById = {for (final p in patients) p.id: p};
      _pendingSync = pending;
      _loading = false;
    });
  }

  Future<void> _copyReadable() async {
    final buf = StringBuffer();
    for (final s in _notes) {
      buf.writeln(_readableExport(s));
      buf.writeln('---');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied past notes to clipboard')),
    );
  }

  String _readableExport(ClinicalSession s) {
    final patient = _patientLabel(s);
    final lines = <String>[
      'Note · ${_formatTime(s.createdAt)}',
      if (patient != null) 'Patient: $patient',
      if (s.inputSummary != null && s.inputSummary!.isNotEmpty)
        'Chief complaint: ${s.inputSummary}',
      ..._detailLines(s).map((e) => '${e.$1}: ${e.$2}'),
    ];
    return lines.join('\n');
  }

  String? _patientLabel(ClinicalSession s) {
    final id = s.patientId;
    if (id == null || id.isEmpty) return null;
    final p = _patientsById[id];
    if (p == null) return id;
    return '${p.displayName} ($id)';
  }

  List<(String, String)> _detailLines(ClinicalSession s) {
    final meta = s.payload;
    final out = <(String, String)>[];
    if (meta == null) {
      if (s.outputSummary != null &&
          s.outputSummary!.isNotEmpty &&
          s.outputSummary != 'saved_locally') {
        out.add(('Result', s.outputSummary!));
      }
      return out;
    }

    void add(String label, String key) {
      final v = meta[key];
      if (v is String && v.trim().isNotEmpty) out.add((label, v.trim()));
    }

    add('Chief complaint', 'chief_complaint');
    add('History', 'history');
    add('Examination', 'examination');
    add('Assessment', 'assessment');
    add('Plan', 'plan');
    add('Draft', 'draft_text');
    if (meta['action'] == 'generate') {
      final preview = meta['draft_preview'];
      if (preview is String && preview.isNotEmpty) {
        out.add(('Draft preview', preview));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Past Notes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Saved and generated note drafts on this device. '
            'Chat, drug search, and interactions stay in the sync queue for '
            'backend ingest but are not listed here. '
            '$_pendingSync item(s) queued for server sync '
            '(scrubbing applies only to that queue).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.slate500,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _notes.isEmpty ? null : _copyReadable,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy past notes'),
          ),
          const SizedBox(height: 16),
          if (_notes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'No past notes yet. Generate and Save a draft on the Notes tab.',
              ),
            )
          else
            ..._notes.map(_sessionCard),
        ],
      ),
    );
  }

  Widget _sessionCard(ClinicalSession s) {
    final expanded = _expandedId == s.id;
    final patient = _patientLabel(s);
    final details = _detailLines(s);
    final preview = details.isNotEmpty
        ? details.first.$2
        : (s.inputSummary ?? s.outputSummary ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() {
          _expandedId = expanded ? null : s.id;
        }),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Note',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.tealDark,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(s.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.slate500,
                        ),
                  ),
                ],
              ),
              if (patient != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.person_outline,
                        size: 16, color: AppColors.tealDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        patient,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.tealDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (!expanded && preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.slate500, fontSize: 13),
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: 10),
                if (details.isEmpty)
                  Text(
                    s.outputSummary ?? 'No further details.',
                    style: const TextStyle(color: AppColors.slate700),
                  )
                else
                  ...details.map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.$1,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: AppColors.slate500,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(d.$2),
                        ],
                      ),
                    ),
                  ),
                Text(
                  'Tap to collapse',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.slate500,
                      ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tap for details',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.slate500,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $h:$m';
  }
}
