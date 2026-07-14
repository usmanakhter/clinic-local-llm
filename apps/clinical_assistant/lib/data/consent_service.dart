import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/repositories.dart';
import '../models/models.dart';

const kConsentGrantedKey = 'consent_granted';
const kConsentScopesKey = 'consent_scopes';

/// Consent defaults OFF. Sync is blocked when false.
class ConsentService {
  ConsentService(this._prefs, this._repo);

  final SharedPreferences _prefs;
  final ClinicalRepository _repo;

  bool get granted => _prefs.getBool(kConsentGrantedKey) ?? false;

  List<String> get scopes =>
      _prefs.getStringList(kConsentScopesKey) ?? const [];

  ConsentTemplate get template =>
      AppDatabase.consentTemplate ??
      const ConsentTemplate(consentVersion: 'np-pilot-1.0', templates: {});

  String get syncStatusText =>
      granted ? 'Allowed — consent on' : 'Blocked — consent off';

  Future<void> setGranted({
    required bool granted,
    required List<String> scopes,
  }) async {
    await _prefs.setBool(kConsentGrantedKey, granted);
    await _prefs.setStringList(
      kConsentScopesKey,
      granted ? scopes : <String>[],
    );
    await _repo.upsertConsentRecord(
      granted: granted,
      scopes: granted ? scopes : const [],
      consentVersion: template.consentVersion,
    );
  }
}
