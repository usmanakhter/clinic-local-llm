import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/consent_service.dart';
import '../data/db.dart';
import '../data/repositories.dart';
import '../privacy/pii_scrubber.dart';
import '../theme/app_theme.dart';
import '../widgets/disclaimer_banner.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    this.embedded = false,
    this.onChanged,
  });

  /// When true, skip outer [ScreenScaffold] (used inside bottom nav).
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  ConsentService? _service;
  bool _granted = false;
  bool _modelImprovement = false;
  bool _analytics = false;
  bool _loading = true;
  final _scrubController = TextEditingController(
    text: 'Call +977-9801122334 or NMC-2019-12345 about ORS for diarrhea.',
  );
  SyncScrubResult? _scrubResult;

  @override
  void dispose() {
    _scrubController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final service = ConsentService(prefs, ClinicalRepository());
    if (!mounted) return;
    setState(() {
      _service = service;
      _granted = service.granted;
      final scopes = service.scopes;
      _modelImprovement = scopes.contains('model_improvement');
      _analytics = scopes.contains('analytics');
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final service = _service;
    if (service == null) return;
    final scopes = <String>[
      if (_modelImprovement) 'model_improvement',
      if (_analytics) 'analytics',
    ];
    await service.setGranted(granted: _granted, scopes: scopes);
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _buildBody(context);

    if (widget.embedded) return body;

    return ScreenScaffold(
      title: 'Consent',
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final t = _service!.template;
    final syncText = _service!.syncStatusText;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t.text('onboarding_title', 'en'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.slate900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          t.text('onboarding_title', 'ne'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.slate700,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          t.text('onboarding_body', 'en'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        const SizedBox(height: 8),
        Text(
          t.text('onboarding_body', 'ne'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: AppColors.slate700,
              ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _granted ? AppColors.tealSoft : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _granted ? AppColors.teal : AppColors.danger,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _granted ? Icons.sync : Icons.sync_disabled,
                color: _granted ? AppColors.tealDark : AppColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sync status: $syncText',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _granted ? AppColors.tealDark : AppColors.danger,
                      ),
                    ),
                    if (!_granted) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Sync queue is blocked. No clinical content leaves this device '
                        'until you explicitly grant consent. There is no network upload '
                        'in this MVP demo.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.danger,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Consent version: ${t.consentVersion} · Default OFF',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.slate500,
              ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Grant consent'),
          subtitle: const Text('Off by default — opt-in only'),
          value: _granted,
          activeThumbColor: AppColors.teal,
          onChanged: (v) async {
            setState(() {
              _granted = v;
              if (!v) {
                _modelImprovement = false;
                _analytics = false;
              }
            });
            await _persist();
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _modelImprovement,
          onChanged: !_granted
              ? null
              : (v) async {
                  setState(() => _modelImprovement = v ?? false);
                  await _persist();
                },
          title: Text(t.text('scope_model_improvement', 'en')),
          subtitle: Text(t.text('scope_model_improvement', 'ne')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _analytics,
          onChanged: !_granted
              ? null
              : (v) async {
                  setState(() => _analytics = v ?? false);
                  await _persist();
                },
          title: Text(t.text('scope_analytics', 'en')),
          subtitle: Text(t.text('scope_analytics', 'ne')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 12),
        Text(
          t.text('data_transparency', 'en'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          t.text('data_transparency', 'ne'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.slate700),
        ),
        const SizedBox(height: 10),
        Text(
          t.text('wifi_only_notice', 'en'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          t.text('wifi_only_notice', 'ne'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.slate700),
        ),
        const SizedBox(height: 10),
        Text(
          t.text('prohibited_uses', 'en'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          t.text('prohibited_uses', 'ne'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.slate700),
        ),
        const SizedBox(height: 24),
        Text(
          'PII scrubber (local demo)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Regex baseline only — phones, emails, NMC/HREG/passport-like IDs. '
          'Name/place recall is limited (~30%); NER deferred. No network call.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.slate500,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _scrubController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Sample sync payload',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () {
            setState(() {
              _scrubResult = PiiScrubber.evaluateForSync(_scrubController.text);
            });
          },
          icon: const Icon(Icons.policy_outlined),
          label: const Text('Scrub & evaluate for sync queue'),
        ),
        if (_scrubResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.slate100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scrubResult!.reason,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _scrubResult!.allowed
                        ? AppColors.tealDark
                        : AppColors.danger,
                  ),
                ),
                if (!_granted) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Even if scrubbed, queue stays blocked while consent is OFF.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Scrubbed text',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.slate500,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _scrubResult!.scrubbed,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Loaded from assets/nepal/consent_templates.json'
          '${AppDatabase.consentTemplate == null ? ' (fallback)' : ''}.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.slate500,
              ),
        ),
      ],
    );
  }
}
