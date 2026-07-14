#!/usr/bin/env python3
"""Load Nepal MVP dummy data into SQLite for local dev/testing."""

import json
import sqlite3
import sys
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent
NEPAL_DIR = DATA_DIR / "nepal"
SCHEMA = DATA_DIR / "schema" / "mvp_schema.sql"
DEFAULT_DB = DATA_DIR / "nepal_mvp_dev.db"


def load_json(name: str) -> dict:
    with open(NEPAL_DIR / name, encoding="utf-8") as f:
        return json.load(f)


def main(db_path: Path = DEFAULT_DB) -> None:
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(db_path)
    conn.executescript(SCHEMA.read_text(encoding="utf-8"))

    drugs = load_json("drugs.json")["drugs"]
    for d in drugs:
        conn.execute(
            """INSERT INTO drugs (
                id, generic_name, generic_name_ne, category, nelm_tier,
                dosage_forms, strengths, brand_names, indications, contraindications,
                adult_dose, pediatric_dose, pregnancy_category, rag_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                d["id"], d["generic_name"], d.get("generic_name_ne"), d["category"],
                d["nelm_tier"], json.dumps(d["dosage_forms"]), json.dumps(d["strengths"]),
                json.dumps(d["brand_names"]), json.dumps(d.get("indications", [])),
                json.dumps(d.get("contraindications", [])), d.get("adult_dose"),
                d.get("pediatric_dose"), d.get("pregnancy_category"), d["rag_text"],
            ),
        )

    for i in load_json("interactions.json")["interactions"]:
        conn.execute(
            """INSERT INTO interactions (
                id, drug_a_id, drug_b_id, severity, mechanism,
                clinical_effect, recommendation, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                i["id"], i["drug_a_id"], i["drug_b_id"], i["severity"],
                i.get("mechanism"), i.get("clinical_effect"),
                i["recommendation"], i.get("source"),
            ),
        )

    for g in load_json("guideline_chunks.json")["chunks"]:
        conn.execute(
            """INSERT INTO guideline_chunks (
                id, title, title_ne, source, topic, chunk_text, chunk_text_ne, priority
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                g["id"], g["title"], g.get("title_ne"), g["source"], g.get("topic"),
                g["chunk_text"], g.get("chunk_text_ne"), g.get("priority", 0),
            ),
        )

    for s in load_json("clinical_sessions_dummy.json")["sessions"]:
        conn.execute(
            """INSERT INTO clinical_sessions (
                id, created_at, query_type, input_summary, output_summary, feedback
            ) VALUES (?, ?, ?, ?, ?, ?)""",
            (
                s["id"], s["created_at"], s["query_type"],
                s["input_summary"], s["output_summary"], s.get("feedback"),
            ),
        )

    for c in load_json("pilot_clinicians.json")["clinicians"]:
        conn.execute(
            """INSERT INTO pilot_clinicians (
                id, display_name, specialty, district, facility_name,
                onboarding_status, opt_in_data, invited_at, activated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                c["id"], c["display_name"], c.get("specialty"), c.get("district"),
                c.get("facility_name"), c["onboarding_status"], c.get("opt_in_data", 0),
                c.get("invited_at"), c.get("activated_at"),
            ),
        )

    consent = load_json("consent_templates.json")
    for r in consent.get("dummy_consent_records", []):
        conn.execute(
            """INSERT INTO consent_records (
                id, clinician_id, scope, granted, consent_version, granted_at
            ) VALUES (?, ?, ?, ?, ?, ?)""",
            (
                r["id"], r.get("clinician_id"), json.dumps(r.get("scope", [])),
                r["granted"], r["consent_version"], r.get("granted_at"),
            ),
        )

    for q in load_json("sync_queue_dummy.json")["items"]:
        conn.execute(
            """INSERT INTO sync_queue (id, session_id, payload_json, scrubbed_at, status)
               VALUES (?, ?, ?, ?, ?)""",
            (
                q["id"], q.get("session_id"), json.dumps(q["payload"]),
                q["scrubbed_at"], q["status"],
            ),
        )

    conn.commit()
    counts = {
        "drugs": conn.execute("SELECT COUNT(*) FROM drugs").fetchone()[0],
        "interactions": conn.execute("SELECT COUNT(*) FROM interactions").fetchone()[0],
        "guidelines": conn.execute("SELECT COUNT(*) FROM guideline_chunks").fetchone()[0],
        "sessions": conn.execute("SELECT COUNT(*) FROM clinical_sessions").fetchone()[0],
        "clinicians": conn.execute("SELECT COUNT(*) FROM pilot_clinicians").fetchone()[0],
    }
    conn.close()
    print(f"Loaded {db_path}")
    for k, v in counts.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB
    main(path)
