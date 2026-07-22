import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/repositories.dart';
import '../models/models.dart';

const kConsentGrantedKey = 'consent_granted';
const kConsentScopesKey = 'consent_scopes';

/// Current Terms version — bump when legal text materially changes (forces re-gate).
const kTermsVersion = 'np-terms-1.2';

/// Records first-launch Terms acceptance as **mandatory** sync/data consent.
/// There is no separate Consent UI and no in-app sync off switch.
class ConsentService {
  ConsentService(this._prefs, this._repo);

  final SharedPreferences _prefs;
  final ClinicalRepository _repo;

  /// True after Terms acceptance — sync is always on for the life of this grant.
  bool get granted => _prefs.getBool(kConsentGrantedKey) ?? false;

  List<String> get scopes =>
      _prefs.getStringList(kConsentScopesKey) ?? const [];

  ConsentTemplate get template =>
      AppDatabase.consentTemplate ??
      const ConsentTemplate(consentVersion: 'np-pilot-1.0', templates: {});

  /// Only called from [TermsGateScreen] on Agree. Never expose a revoke UI.
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
      consentVersion: kTermsVersion,
    );
  }
}
