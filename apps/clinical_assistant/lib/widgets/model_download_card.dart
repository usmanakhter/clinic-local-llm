import 'dart:async';

import 'package:flutter/material.dart';

import '../llm/model_download_manager.dart';
import '../theme/app_theme.dart';

/// CTA + progress for one-time Hugging Face GGUF install into app Documents.
class ModelDownloadCard extends StatefulWidget {
  const ModelDownloadCard({
    super.key,
    required this.manager,
    required this.onComplete,
  });

  final ModelDownloadManager manager;
  final VoidCallback onComplete;

  @override
  State<ModelDownloadCard> createState() => _ModelDownloadCardState();
}

class _ModelDownloadCardState extends State<ModelDownloadCard> {
  StreamSubscription<ModelDownloadProgress>? _sub;
  ModelDownloadProgress _progress = const ModelDownloadProgress(
    phase: ModelDownloadPhase.idle,
  );
  bool _busy = false;
  bool _allowMobileData = false;
  String? _hint;

  ModelManifest get _m => widget.manager.manifest;

  @override
  void initState() {
    super.initState();
    _progress = widget.manager.current;
    _sub = widget.manager.progress.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.phase == ModelDownloadPhase.complete) {
        widget.onComplete();
      }
    });
    _refreshHint();
  }

  Future<void> _refreshHint() async {
    final net = await widget.manager.detectNetwork();
    final free = await widget.manager.freeBytesAvailable();
    if (!mounted) return;
    String? hint;
    switch (net) {
      case NetworkKind.wifi:
        hint = 'Wi‑Fi detected — recommended for ${_m.sizeLabel} download.';
      case NetworkKind.mobile:
        hint =
            'Mobile data detected. Enable “use mobile data” or switch to Wi‑Fi.';
      case NetworkKind.none:
        hint = 'No network — connect to Wi‑Fi, then download.';
      case NetworkKind.other:
      case NetworkKind.unknown:
        hint =
            'Download ${_m.sizeLabel} once; Chat works offline afterward.';
    }
    if (free != null && free < _m.minFreeBytes) {
      final freeGb = free / (1024 * 1024 * 1024);
      hint =
          'Low storage (${freeGb.toStringAsFixed(1)} GB free). Need ~${(_m.minFreeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB.';
    }
    setState(() => _hint = hint);
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hint = null;
    });
    try {
      final net = await widget.manager.detectNetwork();
      if (net == NetworkKind.mobile && !_allowMobileData) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _hint =
              'Mobile data detected. Check “Use mobile data” or switch to Wi‑Fi.';
        });
        return;
      }
      await widget.manager.download(allowMobileData: _allowMobileData);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hint = e.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _progress.phase;
    final downloading = phase == ModelDownloadPhase.downloading ||
        phase == ModelDownloadPhase.verifying;
    final fraction = _progress.fraction;
    final err = _progress.error ?? _hint;

    return Material(
      color: AppColors.warningStrip,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'On-device clinical model required',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.warningText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Download ${_m.displayName} (${_m.sizeLabel}) from Hugging Face '
              'into this app. One-time; then Chat works offline. '
              'Search / Interact / Guidelines work without it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warningText,
                  ),
            ),
            if (err != null && err.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                err,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.warningText,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: phase == ModelDownloadPhase.verifying ? null : fraction,
                minHeight: 6,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                phase == ModelDownloadPhase.verifying
                    ? 'Verifying checksum…'
                    : _bytesLabel(_progress.receivedBytes, _progress.totalBytes),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.warningText,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _allowMobileData,
              onChanged: _busy || downloading
                  ? null
                  : (v) => setState(() => _allowMobileData = v ?? false),
              title: Text(
                'Use mobile data (${_m.sizeLabel})',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.warningText,
                    ),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: (_busy || downloading) ? null : _start,
                  icon: (_busy || downloading)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    downloading
                        ? (phase == ModelDownloadPhase.verifying
                            ? 'Verifying…'
                            : 'Downloading…')
                        : 'Download clinical model',
                  ),
                ),
                const SizedBox(width: 8),
                if (downloading)
                  TextButton(
                    onPressed: () => widget.manager.cancel(),
                    child: const Text('Cancel'),
                  )
                else
                  TextButton(
                    onPressed: _busy ? null : _refreshHint,
                    child: const Text('Check network'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _bytesLabel(int received, int total) {
    String fmt(int b) {
      if (b >= 1024 * 1024 * 1024) {
        return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
      return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    }

    if (total <= 0) return fmt(received);
    final pct = ((received / total) * 100).clamp(0, 100).toStringAsFixed(0);
    return '${fmt(received)} / ${fmt(total)} ($pct%)';
  }
}
