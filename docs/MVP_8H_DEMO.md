# MVP 8h Demo Runbook

## Run (web-server on :8080)

```powershell
$env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
flutter pub get
# Prefer web-server if Chrome device launch fails:
flutter run -d web-server --web-port=8080
# then open http://localhost:8080
# Or: flutter run -d windows
```

## Spot-check (CHECK-IN 3)

1. Banner shows not-for-clinical-use + offline.
2. Search: `Paracetamol`, `प्यारासिटामोल`, `Nepalol` → same drug.
3. Interact: Azithromycin + Ciprofloxacin → contraindicated (QT).
4. Interact: two unrelated drugs → “No known interaction in local DB”.
5. Consent tab: default OFF; sync blocked text visible.
6. Guidelines: search `diarrhea` or `TB` → chunk with source.
7. Consent tab: scrub sample with `+977-9801122334` / `NMC-2019-12345` → `[REDACTED]`; queue still blocked while consent OFF.

## Fixture automations

```powershell
cd c:\Users\UA4\Desktop\clinic-local-llm
python packages\clinical_core_py\smoke_test.py
python qa\run_fixture_evals.py
```

Dart unit check (optional):

```powershell
cd c:\Users\UA4\Desktop\clinic-local-llm\apps\clinical_assistant
flutter test test\pii_scrubber_test.dart
```

## Known limits

- Web uses in-memory DB (sqflite is native-only).
- Regex PII scrubber ~30% recall on names/places — NER deferred.
- No on-device LLM in this slice (RAG/DB first).
- No real network sync — consent gate is local UI + scrub demo only.
