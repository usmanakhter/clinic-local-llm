# MVP 8h Demo Runbook

## Run (Chrome)

```powershell
$env:PATH = "C:\Users\UA4\flutter\bin;$env:PATH"
cd c:\Users\UA4\Desktop\usman\apps\clinical_assistant
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

## Fixture automations

```powershell
python c:\Users\UA4\Desktop\usman\packages\clinical_core_py\smoke_test.py
python c:\Users\UA4\Desktop\usman\qa\run_fixture_evals.py
```

## Known limits

- Web uses in-memory DB (sqflite is native-only).
- Regex PII scrubber ~30% recall — NER deferred.
- No on-device LLM in this slice (RAG/DB first).
