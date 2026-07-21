import 'package:flutter/material.dart';

import '../data/session_store.dart';
import '../data/sync_worker.dart';
import '../theme/app_theme.dart';

/// Transparency UI — scrubbed sync_queue status (sync is always on after Terms).
class SyncTransparencyScreen extends StatefulWidget {
  const SyncTransparencyScreen({super.key});

  @override
  State<SyncTransparencyScreen> createState() => _SyncTransparencyScreenState();
}

class _SyncTransparencyScreenState extends State<SyncTransparencyScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _flushMessage;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _attemptFlush();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final rows = await SessionStore.listSyncQueue(limit: 100);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _attemptFlush() async {
    if (_flushing) return;
    setState(() {
      _flushing = true;
      _flushMessage = 'Uploading pending items…';
    });
    final result = await SyncWorker.flushPending();
    if (!mounted) return;
    setState(() {
      _flushing = false;
      _flushMessage = result.message;
    });
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync transparency'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _attemptFlush();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Sync is ON (required by Terms — no off switch). '
                    'Scrubbed activity is queued automatically; local clinician '
                    'history stays unredacted on this device.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.slate500,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _flushing ? null : _attemptFlush,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      _flushing ? 'Uploading…' : 'Retry upload now',
                    ),
                  ),
                  if (_flushMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _flushMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_rows.isEmpty)
                    const Text('No sync_queue rows yet.')
                  else
                    ..._rows.map(_rowCard),
                ],
              ),
            ),
    );
  }

  Widget _rowCard(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'unknown';
    final created = row['created_at']?.toString() ?? '';
    final scrubbed = row['scrubbed_at']?.toString() ?? '';
    final note = row['scrub_note']?.toString() ?? '';
    final id = row['id']?.toString() ?? '';
    final color = switch (status) {
      'pending' => AppColors.tealDark,
      'synced' => Colors.green.shade700,
      'blocked_residual_pii' => AppColors.warningText,
      'failed' => Colors.red.shade700,
      _ => AppColors.slate500,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(id, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Created: $created',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Scrubbed: $scrubbed',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (note.isNotEmpty)
              Text(
                'Note: $note',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
