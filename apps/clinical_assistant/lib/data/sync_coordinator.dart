import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_worker.dart';

/// Background sync driver — no clinician-facing UI.
///
/// Starts after Terms → home: immediate flush, ~30s periodic, resume wake,
/// and enqueue-triggered [requestFlush] with debounce + single-flight.
class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator._();

  static final SyncCoordinator instance = SyncCoordinator._();

  static const _period = Duration(seconds: 30);
  static const _debounce = Duration(seconds: 1);

  Timer? _periodic;
  Timer? _debounceTimer;
  bool _started = false;
  bool _flushing = false;
  bool _flushAgain = false;

  /// Begin continuous silent sync (idempotent).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _periodic = Timer.periodic(_period, (_) => requestFlush());
    requestFlush();
  }

  /// Stop timers/observer (e.g. HomeShell dispose).
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _periodic?.cancel();
    _periodic = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Schedule a best-effort upload of pending scrubbed queue rows.
  void requestFlush() {
    if (!_started) {
      // Allow enqueue-before-start: flush once home mounts via start().
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(_runFlush());
    });
  }

  /// Wake flush even if [start] has not run yet (used from SessionStore enqueue).
  /// Queues a flush that [start] will pick up via immediate requestFlush, or
  /// runs immediately when already started.
  void notifyEnqueue() {
    if (_started) {
      requestFlush();
    }
    // If not started yet, HomeShell.start() will flush pending rows.
  }

  Future<void> _runFlush() async {
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        try {
          await SyncWorker.flushPending();
        } catch (_) {
          // Silent — leave pending/failed for next timer/resume.
        }
      } while (_flushAgain);
    } finally {
      _flushing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      requestFlush();
    }
  }
}
