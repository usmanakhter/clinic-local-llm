import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Local activity history — all interactions saved on-device until consent-gated sync.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<ClinicalSession> _sessions = [];
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
    final pending = await widget.repository.pendingSyncCount();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _pendingSync = pending;
      _loading = false;
    });
  }

  Future<void> _copyExport() async {
    final payload = _sessions.map((s) => s.toMap()).toList();
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied local activity JSON to clipboard')),
    );
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
            'Local activity',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Every search, interaction check, guideline lookup, chat turn, and '
            'saved note is stored on this device (PII scrubbed). '
            '$_pendingSync item(s) queued for backup when you opt in to sync.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.slate500,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _sessions.isEmpty ? null : _copyExport,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Export JSON (clipboard)'),
          ),
          const SizedBox(height: 16),
          if (_sessions.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'No activity yet. Use Search, Interact, Guidelines, Chat, or '
                'save a note — entries appear here and survive refresh on web.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.slate700,
                    ),
              ),
            )
          else
            ..._sessions.map(_sessionTile),
        ],
      ),
    );
  }

  Widget _sessionTile(ClinicalSession s) {
    final expanded = _expandedId == s.id;
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
                  _TypeChip(label: s.typeLabel),
                  const Spacer(),
                  Text(
                    _formatTime(s.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.slate500,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (s.inputSummary != null && s.inputSummary!.isNotEmpty)
                Text(
                  s.inputSummary!,
                  maxLines: expanded ? null : 2,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              if (s.outputSummary != null && s.outputSummary!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  s.outputSummary!,
                  maxLines: expanded ? null : 1,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.slate500, fontSize: 13),
                ),
              ],
              if (expanded && s.payloadJson != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _prettyJson(s.payloadJson!),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
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

  String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.tealDark,
        ),
      ),
    );
  }
}
