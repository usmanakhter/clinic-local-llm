import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/consent_service.dart';
import 'data/db.dart';
import 'data/repositories.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.init();
  final prefs = await SharedPreferences.getInstance();
  final repo = ClinicalRepository();
  final consent = ConsentService(prefs, repo);
  runApp(ClinicalAssistantApp(consent: consent, repository: repo));
}

class ClinicalAssistantApp extends StatefulWidget {
  const ClinicalAssistantApp({
    super.key,
    required this.consent,
    required this.repository,
  });

  final ConsentService consent;
  final ClinicalRepository repository;

  @override
  State<ClinicalAssistantApp> createState() => _ClinicalAssistantAppState();
}

class _ClinicalAssistantAppState extends State<ClinicalAssistantApp> {
  late ConsentService _consent;

  @override
  void initState() {
    super.initState();
    _consent = widget.consent;
  }

  Future<void> _refreshConsent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _consent = ConsentService(prefs, widget.repository);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nepal Clinical Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeShell(
        repository: widget.repository,
        consentGranted: _consent.granted,
        syncStatusText: _consent.syncStatusText,
        onOpenConsent: _refreshConsent,
      ),
    );
  }
}
