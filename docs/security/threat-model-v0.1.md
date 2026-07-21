# Threat Model v0.1 — Nepal Clinical AI (8h MVP)

**Owner:** Security Agent A8  
**Date:** 2026-07-14  
**Scope:** Offline Flutter Android-first reference app (drug search, interaction checker, consent gate, regex PII scrubber).  
**Data:** Synthetic fixtures in `data/nepal/` only — **no real PHI**.

---

## 1. Assets (MVP)

| Asset | Location | Sensitivity (MVP) |
|---|---|---|
| Drug / interaction / guideline DB | On-device SQLite (`drugs`, `interactions`, `guideline_chunks`, FTS) | Public reference content; integrity matters |
| Session summaries | `clinical_sessions` (`input_summary`, `output_summary`) | May look like clinical notes; treat as sensitive even when synthetic |
| Consent records | `consent_records` (granted default `0`) | Privacy preference / audit truth |
| Sync queue payloads | `sync_queue` (deferred network) | Pre-scrub or blocked payloads; must not leave device without consent |
| App binary + seed assets | APK / bundled JSON | Integrity; no real patient fixtures in repo |

**Out of scope today:** cloud backend, EMR patient tables (schema stubs empty), ONNX NER, live OTA.

---

## 2. Trust boundaries

```
┌──────────────────── ON-DEVICE TRUST ZONE ────────────────────┐
│  Flutter UI  →  repositories  →  SQLite (+ FTS5)              │
│  Consent gatekeeper  →  sync_queue (local only)               │
│  Regex PII scrubber (local; ONNX later)                       │
└──────────────────────────────┬───────────────────────────────┘
                               │  BOUNDARY: network egress
                               │  (deferred; blocked unless consent ON)
                               ▼
                    [ Future sync API — not in 8h MVP ]
```

| Boundary | Rule for 8h |
|---|---|
| UI → DB | Read formulary/interactions; write sessions/consent only as designed |
| App → Network | **No clinical/session egress.** Consent default OFF; sync UI shows blocked |
| Repo → Device | Seed from synthetic `data/nepal/` only |
| Crash / logs | No PHI-like free text in logs (scrub or omit session bodies) |

---

## 3. Top threats (STRIDE-lite, MVP only)

| ID | STRIDE | Threat | MVP impact |
|---|---|---|---|
| T1 | Spoofing | Shared/lost device; another user opens app | Local sessions readable if device unlocked |
| T2 | Tampering | Altered seed DB / interactions on device | Wrong severity shown → clinical safety risk in any real use |
| T3 | Repudiation | Consent flip without audit | Sync could appear “authorized” without record |
| T4 | Info disclosure | Session text / scrubber failures leak via backup, screenshots, debug logs, or premature sync | Privacy / demo credibility |
| T5 | DoS | Corrupt DB or FTS index | Search/checker unavailable (demo fails) |
| T6 | Elevation | Bypass consent gate in code paths | Queue / future sync fires while `granted=0` |

**Explicit non-threats today:** remote RCE, server compromise, model prompt injection (no LLM), production PHI theft (fixtures are fictional).

---

## 4. Mitigations planned + residual risks

| Threat | Planned mitigation (8h / next) | Residual risk |
|---|---|---|
| T1 | App short-lived; no login; discourage real clinical text in demos | Unencrypted SQLite on unlocked phone (**SQLCipher soon**) |
| T2 | Ship read-only seed from known fixtures; interaction severity **only** from DB | No signed DB / integrity check yet |
| T3 | Versioned consent from `consent_templates.json`; persist `granted` + timestamps | No remote consent audit until backend |
| T4 | Consent default **OFF**; regex scrubber before any future sync; fixture eval on `pii_scrubber_test_cases.json` | Regex misses (code-mix names); no ONNX yet; Android backup may include DB |
| T5 | Seed script + QA smoke on 50/35/18 counts | Manual DB wipe not hardened |
| T6 | Single consent gatekeeper; sync UI blocked when OFF | Accidental future API wiring without gate |

---

## 5. Hard rules (non-negotiable)

1. **Consent default OFF** — no network send of clinical/session content unless clinician explicitly opts in.
2. **No invented interaction severity** — unknown pair → “no known interaction in local DB”; never LLM/heuristics for severity in MVP.
3. **Synthetic data only** — never commit or demo with real patient/clinician PHI; fixtures labeled fictional.
4. **Not for clinical use** — permanent disclaimer; medical content provisional until licensed advisor sign-off.
5. **No attack tooling** — this doc is defensive; do not produce exploits or PoCs against devices/backends.

---

## 6. Acceptance checks (A8 / QA)

- [ ] Fresh install: consent `granted = 0`
- [ ] Sync path / queue UI: blocked when consent OFF
- [ ] Interaction checker: DB severity only; unknown pair message present
- [ ] Scrubber passes +977 / name cases in `pii_scrubber_test_cases.json`
- [ ] Repo/fixtures contain no real PHI
- [ ] Disclaimer visible on clinical screens

**Next revision:** See [threat-model-v0.2.md](threat-model-v0.2.md) (MVP close — Terms, GGUF, scrub queue, transparency).
