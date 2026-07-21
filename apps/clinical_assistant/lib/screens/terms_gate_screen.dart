import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/consent_service.dart';
import '../data/repositories.dart';
import '../theme/app_theme.dart';

const kTermsAcceptedKey = 'terms_accepted_v1';
const kTermsVersionKey = 'terms_version_accepted';

/// First-launch gate: Terms + mandatory data-sync consent (no later off switch).
class TermsGateScreen extends StatefulWidget {
  const TermsGateScreen({
    super.key,
    required this.repository,
    required this.onAccepted,
  });

  final ClinicalRepository repository;
  final VoidCallback onAccepted;

  @override
  State<TermsGateScreen> createState() => _TermsGateScreenState();
}

class _TermsGateScreenState extends State<TermsGateScreen> {
  String? _termsText;
  Object? _loadError;
  bool _agreed = false;
  bool _busy = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text =
          await rootBundle.loadString('assets/legal/terms_of_use.txt');
      if (!mounted) return;
      setState(() => _termsText = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  Future<void> _accept() async {
    if (!_agreed || _busy) return;
    setState(() => _busy = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kTermsAcceptedKey, true);
    await prefs.setString(kTermsVersionKey, kTermsVersion);
    // Single gate: Terms acceptance turns sync ON permanently (no in-app off).
    final consent = ConsentService(prefs, widget.repository);
    await consent.setGranted(
      granted: true,
      scopes: const [
        'terms_and_liability',
        'sync_backup',
        'model_improvement',
        'analytics',
      ],
    );
    if (!mounted) return;
    widget.onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Terms, Conditions & Data Consent',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.slate900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Required before using the app. Accepting turns sync ON for '
                'scrubbed activity — there is no later option to turn sync off. '
                'Version $kTermsVersion.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.slate500,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.slate100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: _buildDocument(),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agreed,
                onChanged: _termsText == null
                    ? null
                    : (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I have read and agree to the Terms and Conditions',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'I consent to required sync of scrubbed activity (backup, '
                  'corpus/model improvement, analytics). Sync stays on; '
                  'creators take no clinical liability.',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _agreed && !_busy ? _accept : null,
                child: Text(_busy ? 'Saving…' : 'Agree and continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocument() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load Terms.\n$_loadError'),
        ),
      );
    }
    if (_termsText == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _termsText!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.45,
                color: AppColors.slate700,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
        ),
      ),
    );
  }
}

Future<bool> hasAcceptedTerms(SharedPreferences prefs) async {
  final accepted = prefs.getBool(kTermsAcceptedKey) ?? false;
  final version = prefs.getString(kTermsVersionKey);
  return accepted && version == kTermsVersion;
}
