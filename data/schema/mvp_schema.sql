-- MVP local schema (SQLCipher-compatible SQLite)
-- Region: Nepal pilot | EMR-ready stubs included

PRAGMA foreign_keys = ON;

-- ─── Core drug reference ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS drugs (
    id              TEXT PRIMARY KEY,
    generic_name    TEXT NOT NULL,
    generic_name_ne TEXT,
    category        TEXT,
    nelm_tier       TEXT CHECK (nelm_tier IN ('core', 'complementary', 'supplementary')),
    dosage_forms    TEXT NOT NULL,  -- JSON array
    strengths       TEXT NOT NULL,  -- JSON array
    brand_names     TEXT NOT NULL,  -- JSON array of {name, manufacturer}
    indications     TEXT,           -- JSON array
    contraindications TEXT,         -- JSON array
    adult_dose      TEXT,
    pediatric_dose  TEXT,
    pregnancy_category TEXT,
    rag_text        TEXT NOT NULL,
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS drugs_fts USING fts5(
    generic_name,
    generic_name_ne,
    brand_names,
    rag_text,
    content='drugs',
    content_rowid='rowid'
);

CREATE VIRTUAL TABLE IF NOT EXISTS guidelines_fts USING fts5(
    title,
    title_ne,
    topic,
    chunk_text,
    chunk_text_ne,
    source,
    content='guideline_chunks',
    content_rowid='rowid'
);

CREATE TABLE IF NOT EXISTS interactions (
    id              TEXT PRIMARY KEY,
    drug_a_id       TEXT NOT NULL REFERENCES drugs(id),
    drug_b_id       TEXT NOT NULL REFERENCES drugs(id),
    severity        TEXT NOT NULL CHECK (severity IN ('contraindicated', 'major', 'moderate', 'minor')),
    mechanism       TEXT,
    clinical_effect TEXT,
    recommendation  TEXT NOT NULL,
    source          TEXT,
    UNIQUE (drug_a_id, drug_b_id)
);

CREATE TABLE IF NOT EXISTS guideline_chunks (
    id              TEXT PRIMARY KEY,
    title           TEXT NOT NULL,
    title_ne        TEXT,
    source          TEXT NOT NULL,
    topic           TEXT,
    chunk_text      TEXT NOT NULL,
    chunk_text_ne   TEXT,
    priority        INTEGER DEFAULT 0
);

-- ─── Sessions & privacy ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS clinical_sessions (
    id              TEXT PRIMARY KEY,
    created_at      TEXT NOT NULL,
    query_type      TEXT NOT NULL CHECK (query_type IN ('drug_lookup', 'interaction_check', 'note_draft', 'guideline_search', 'chat')),
    input_summary   TEXT,
    output_summary  TEXT,
    payload_json    TEXT,
    sync_status     TEXT NOT NULL DEFAULT 'pending_sync',
    feedback        TEXT CHECK (feedback IN ('up', 'down', NULL)),
    feedback_reason TEXT,
    patient_id      TEXT,  -- nullable until EMR Phase 2
    device_id       TEXT
);

CREATE TABLE IF NOT EXISTS consent_records (
    id              TEXT PRIMARY KEY,
    clinician_id    TEXT,
    scope           TEXT NOT NULL,  -- JSON: ["model_improvement", "analytics"]
    granted         INTEGER NOT NULL DEFAULT 0,
    consent_version TEXT NOT NULL,
    granted_at      TEXT,
    revoked_at      TEXT
);

CREATE TABLE IF NOT EXISTS sync_queue (
    id              TEXT PRIMARY KEY,
    session_id      TEXT REFERENCES clinical_sessions(id),
    payload_json    TEXT NOT NULL,
    scrubbed_at     TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN (
                        'pending',
                        'synced',
                        'failed',
                        'blocked_residual_pii'
                    )),
    scrub_note      TEXT,
    created_at      TEXT DEFAULT (datetime('now'))
);

-- ─── EMR stubs (empty in MVP) ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS patients (
    id              TEXT PRIMARY KEY,
    local_id        TEXT UNIQUE,
    display_name_enc TEXT,
    age_decade      TEXT,
    sex             TEXT CHECK (sex IN ('M', 'F', 'O', NULL)),
    phone_enc       TEXT,
    district        TEXT,
    created_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS visits (
    id              TEXT PRIMARY KEY,
    patient_id      TEXT REFERENCES patients(id),
    session_id      TEXT REFERENCES clinical_sessions(id),
    visit_date      TEXT,
    vitals_json     TEXT,
    note_enc        TEXT
);

CREATE TABLE IF NOT EXISTS prescriptions (
    id              TEXT PRIMARY KEY,
    visit_id        TEXT REFERENCES visits(id),
    drugs_json      TEXT NOT NULL,
    created_at      TEXT DEFAULT (datetime('now'))
);

-- ─── Pilot tracking (dev / staging only) ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS pilot_clinicians (
    id              TEXT PRIMARY KEY,
    display_name    TEXT NOT NULL,
    specialty       TEXT,
    district        TEXT,
    facility_name   TEXT,
    onboarding_status TEXT CHECK (onboarding_status IN ('invited', 'installed', 'active', 'churned')),
    opt_in_data     INTEGER DEFAULT 0,
    invited_at      TEXT,
    activated_at    TEXT
);

CREATE INDEX IF NOT EXISTS idx_drugs_generic ON drugs(generic_name);
CREATE INDEX IF NOT EXISTS idx_interactions_drugs ON interactions(drug_a_id, drug_b_id);
CREATE INDEX IF NOT EXISTS idx_sessions_type ON clinical_sessions(query_type);
CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_queue(status);
