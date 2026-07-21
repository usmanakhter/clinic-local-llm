import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/db.dart';
import 'data/patient_store.dart';
import 'data/repositories.dart';
import 'data/session_store.dart';
import 'screens/home_shell.dart';
import 'screens/terms_gate_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  runApp(const _BootApp());
}

class _BootApp extends StatefulWidget {
  const _BootApp();

  @override
  State<_BootApp> createState() => _BootAppState();
}

class _BootAppState extends State<_BootApp> {
  Object? _error;
  ClinicalAssistantApp? _ready;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await AppDatabase.init();
      final prefs = await SharedPreferences.getInstance();
      await SessionStore.initWebPersistence(prefs);
      await PatientStore.initWebPersistence(prefs);
      final repo = ClinicalRepository();
      final termsOk = await hasAcceptedTerms(prefs);
      if (!mounted) return;
      setState(() {
        _ready = ClinicalAssistantApp(
          repository: repo,
          termsAccepted: termsOk,
        );
      });
    } catch (e, st) {
      debugPrint('Startup failed: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'App failed to start.\n\n$_error\n\n'
              'Try: flutter run -d chrome\n'
              'Then hard-refresh (Ctrl+Shift+R).',
            ),
          ),
        ),
      );
    }
    if (_ready != null) return _ready!;
    return MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading Nepal clinical data…'),
            ],
          ),
        ),
      ),
    );
  }
}

class ClinicalAssistantApp extends StatefulWidget {
  const ClinicalAssistantApp({
    super.key,
    required this.repository,
    required this.termsAccepted,
  });

  final ClinicalRepository repository;
  final bool termsAccepted;

  @override
  State<ClinicalAssistantApp> createState() => _ClinicalAssistantAppState();
}

class _ClinicalAssistantAppState extends State<ClinicalAssistantApp> {
  late bool _termsAccepted;

  @override
  void initState() {
    super.initState();
    _termsAccepted = widget.termsAccepted;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nepal Clinical Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: _termsAccepted
          ? HomeShell(repository: widget.repository)
          : TermsGateScreen(
              repository: widget.repository,
              onAccepted: () => setState(() => _termsAccepted = true),
            ),
    );
  }
}
