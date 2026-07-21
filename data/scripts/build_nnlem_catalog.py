#!/usr/bin/env python3
"""Build NNLEM 2021 molecule catalog (398 target) from official PDF text."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "nepal" / "nnlem_2021_molecules.json"
PDF_TEXT = ROOT / "data" / "sources" / "nnlem2021.txt"

# Junk lines from PDF column extraction (replaced by canonical names below)
JUNK_NAMES = {
    "* to be used in combination with sulfadoxine pyrimethamine",
    "5 mg/ ml",
    "ampoule",
    "carbonate)",
    "citrate)",
    "combination with direct acting anti-viral",
    "compound",
    "compound solution",
    "devices",
    "in ampoule",
    "tablet (heat stable): 100 mg + 25 mg, 200mg",
    "+ pyrazinamide",
    "(lignocaine) epinephrine",
    "diphtheria, tetanus,",
}

ALIASES: dict[str, str] = {
    "acetylsalicylic acid (aspirin)": "Acetylsalicylic Acid (Aspirin)",
    "acetylsalicylic acid": "Acetylsalicylic Acid (Aspirin)",
    "acetylsalicylic": "Acetylsalicylic Acid (Aspirin)",
    "acid (aspirin)": "Acetylsalicylic Acid (Aspirin)",
    "paracetamol": "Paracetamol",
    "epinephrine (adrenaline)": "Adrenaline (Epinephrine)",
    "adrenaline (epinephrine)": "Adrenaline (Epinephrine)",
    "benzylpenicillin (penicillin g)": "Benzylpenicillin (Penicillin G)",
    "benzylpenicillin": "Benzylpenicillin (Penicillin G)",
    "penicillin v": "Penicillin V",
    "penicillin g": "Benzylpenicillin (Penicillin G)",
    "lidocaine (lignocaine)": "Lidocaine (Lignocaine)",
    "lignocaine": "Lidocaine (Lignocaine)",
    "lidocaine (lignocaine) + epinephrine (adrenaline)": "Lidocaine + Epinephrine",
    "lidocaine + epinephrine": "Lidocaine + Epinephrine",
    "methylthioninium chloride (methylene blue)": "Methylene Blue",
    "methylene blue": "Methylene Blue",
    "potassium ferric hexacyanoferrate (ii).2h2o (prussian blue)": "Prussian Blue",
    "charcoal, activated": "Activated Charcoal",
    "activated charcoal": "Activated Charcoal",
    "valproic acid": "Sodium Valproate",
    "phenobarbital": "Phenobarbitone",
    "artemether + lumefantrine": "Artemether-Lumefantrine",
    "artemether-lumefantrine": "Artemether-Lumefantrine",
    "amoxicillin + clavulanic acid": "Amoxicillin-Clavulanate",
    "amoxicillin clavulanic acid": "Amoxicillin-Clavulanate",
    "amoxicillin-clavulanate": "Amoxicillin-Clavulanate",
    "amoxicillin + clavulanic acid": "Amoxicillin-Clavulanate",
    "amoxicillin clavulanate": "Amoxicillin-Clavulanate",
    "sulfamethoxazole + trimethoprim": "Trimethoprim-Sulfamethoxazole",
    "trimethoprim + sulfamethoxazole": "Trimethoprim-Sulfamethoxazole",
    "co-trimoxazole": "Trimethoprim-Sulfamethoxazole",
    "ethinylestradiol + levonorgestrel": "Ethinylestradiol-Levonorgestrel",
    "ethinylestradiol + norethisterone": "Ethinylestradiol-Norethisterone",
    "ferrous salt": "Ferrous Sulfate",
    "ferrous salt+ folic acid": "Ferrous Sulfate + Folic Acid",
    "ferrous sulphate": "Ferrous Sulfate",
    "colecalciferol": "Vitamin D3 (Cholecalciferol)",
    "cyanocobalmin": "Vitamin B12 (Cyanocobalamin)",
    "oral rehydration salts": "Oral Rehydration Salts",
    "compound solution of sodium lactate": "Ringer's Lactate",
    "zinc sulfate": "Zinc Sulfate",
    "zinc sulphate": "Zinc Sulfate",
    "enalpril": "Enalapril",
    "cephalexin": "Cephalexin",
    "dolutegravir + lamivudine + tenofovir": "Dolutegravir-Lamivudine-Tenofovir",
    "efavirenz + lamivudine + tenofovir": "Efavirenz-Lamivudine-Tenofovir",
    "dihydroartemisinin + piperaquine phosphate": "Dihydroartemisinin-Piperaquine",
    "dihydroartemisinin": "Dihydroartemisinin-Piperaquine",
    "sulfadoxine + pyrimethamine": "Sulfadoxine-Pyrimethamine",
    "amlodipine+ losartan": "Amlodipine-Losartan",
    "amlodipine + losartan": "Amlodipine-Losartan",
    "levodopa+ cabidopa": "Levodopa-Carbidopa",
    "levodopa + carbidopa": "Levodopa-Carbidopa",
    "aluminum hydroxide gel + magnesium hydroxide": "Aluminium Hydroxide + Magnesium Hydroxide",
    "benzoic acid + salicylic acid": "Benzoic Acid + Salicylic Acid",
    "benzoic acid salicylic acid": "Benzoic Acid + Salicylic Acid",
    "piperacillin + tazobactam": "Piperacillin-Tazobactam",
    "atazanavir + ritonavir": "Atazanavir-Ritonavir",
    "atazanavir-ritonavir": "Atazanavir-Ritonavir",
    "atovaquone + proguanil": "Atovaquone-Proguanil",
    "atovaquone proguanil": "Atovaquone-Proguanil",
    "procaine benzylpenicillin": "Procaine Benzylpenicillin",
    "benzathine benzylpenicillin": "Benzathine Benzylpenicillin",
    "benzathine": "Benzathine Benzylpenicillin",
    "albumin, human": "Albumin (Human)",
    "albumin (human)": "Albumin (Human)",
    "phytomenadione": "Vitamin K1 (Phytomenadione)",
    "retinol": "Vitamin A",
    "ascorbic acid": "Vitamin C (Ascorbic Acid)",
    "pyridoxine": "Vitamin B6 (Pyridoxine)",
    "riboflavin": "Vitamin B2 (Riboflavin)",
    "thiamine": "Vitamin B1 (Thiamine)",
    "aciclovir": "Acyclovir",
    "acetylcysteine": "N-Acetylcysteine",
    "bicalitumide": "Bicalutamide",
    "verampil": "Verapamil",
    "amiodaron": "Amiodarone",
    "nicotine replacement therapy (nrt)": "Nicotine Replacement Therapy",
    "polyvenom anti-snake serum": "Snake Antivenom (Polyvalent)",
    "water for injection": "Water for Injection",
    "glucose": "Dextrose (Glucose)",
    "glucose with sodium chloride": "Dextrose-Sodium Chloride",
    "lamivudine (3tc)": "Lamivudine",
    "zidovudine (zdv or azt)": "Zidovudine",
    "nevirapine (nvp)": "Nevirapine",
    "trihexyphenidyl (benzhexol)": "Trihexyphenidyl",
    "alcohol based hand rub": "Alcohol-Based Hand Rub",
    "alcohol-based hand rub": "Alcohol-Based Hand Rub",
    "chlorine based hand rub": "Chlorine-Based Hand Rub",
    "chlorine based": "Chlorine-Based Hand Rub",
    "permethrin": "Permethrin 5%",
    "timolol": "Timolol Eye Drops",
    "insulin": "Insulin Regular (Soluble)",
    "diethylcarbamazine": "Diethylcarbamazine",
    "diethylcarba-mazine": "Diethylcarbamazine",
    "ethambutol + isoniazid + pyrazinamide + rifampicin": "HRZE (Fixed-Dose Combo)",
    "isoniazid + pyrazinamide + rifampicin": "Isoniazid-Pyrazinamide-Rifampicin",
    "isoniazid + rifampicin": "Isoniazid-Rifampicin",
    "ethinylestradiol-levonorgestrel": "Ethinylestradiol-Levonorgestrel",
    "condoms": "Male Condom",
    "copper-containing devices": "Copper IUD",
    "copper-containing": "Copper IUD",
    "cetirizine": "Cetirizine",
    "all-trans retinoid acid": "All-Trans Retinoic Acid",
}

# Ensure high-priority Nepal OPD molecules present even if PDF parse misses them
MUST_HAVE: list[tuple[str, str, str]] = [
    ("Lisinopril", "Antihypertensive (ACE-I)", "core"),
    ("Hydrochlorothiazide", "Diuretic (thiazide)", "core"),
    ("Simvastatin", "Statin", "complementary"),
    ("Rosuvastatin", "Statin", "complementary"),
    ("Pravastatin", "Statin", "complementary"),
    ("Ramipril", "Antihypertensive (ACE-I)", "complementary"),
    ("Captopril", "Antihypertensive (ACE-I)", "core"),
    ("Telmisartan", "Antihypertensive (ARB)", "complementary"),
    ("Olmesartan", "Antihypertensive (ARB)", "complementary"),
    ("Spironolactone", "Diuretic", "complementary"),
    ("Chlorthalidone", "Diuretic", "complementary"),
    ("Metoprolol", "Beta-blocker", "complementary"),
    ("Carvedilol", "Beta-blocker", "complementary"),
    ("Cefpodoxime", "Antibiotic", "complementary"),
    ("Levofloxacin", "Antibiotic", "complementary"),
    ("Clarithromycin", "Antibiotic", "complementary"),
    ("Sertraline", "SSRI", "complementary"),
    ("Montelukast", "Antiasthmatic", "complementary"),
    ("Budesonide", "Inhaled corticosteroid", "complementary"),
    ("Salmeterol", "LABA", "complementary"),
    ("Pregabalin", "Neuropathic pain", "complementary"),
    ("Gliclazide", "Antidiabetic", "complementary"),
    ("Insulin Glargine", "Insulin basal", "complementary"),
    ("Ivermectin", "Antiparasitic", "core"),
    ("Praziquantel", "Anthelmintic", "core"),
    ("Naproxen", "NSAID", "complementary"),
    ("Enoxaparin", "Anticoagulant", "complementary"),
    ("Apixaban", "DOAC", "complementary"),
    ("Isosorbide Mononitrate", "Antianginal", "complementary"),
    ("Glyceryl Trinitrate", "Antianginal", "core"),
    ("Digoxin", "Cardiac glycoside", "complementary"),
    ("Labetalol", "Antihypertensive", "complementary"),
    ("Hydralazine", "Vasodilator", "complementary"),
    ("Methyldopa", "Antihypertensive", "core"),
    ("Clindamycin", "Antibiotic", "complementary"),
    ("Fluconazole", "Antifungal", "complementary"),
    ("Clotrimazole Vaginal", "Antifungal", "core"),
    ("Sodium Valproate", "Antiepileptic", "complementary"),
    ("Lamotrigine", "Antiepileptic", "complementary"),
    ("Haloperidol", "Antipsychotic", "complementary"),
    ("Risperidone", "Antipsychotic", "complementary"),
    ("Trimethoprim-Sulfamethoxazole", "Antibiotic", "core"),
    ("Lidocaine + Epinephrine", "Local anaesthetic", "complementary"),
    ("Male Condom", "Contraceptive", "core"),
    ("Copper IUD", "Contraceptive", "core"),
    ("Sulfadoxine-Pyrimethamine", "Antimalarial", "complementary"),
    ("Chlorine-Based Hand Rub", "Disinfectant", "core"),
    ("All-Trans Retinoic Acid", "Antineoplastic", "complementary"),
]

JUNK_SUBSTR = (
    "where ", "should ", " who ", "patient", "hospital", "based on",
    "during delivery", "post-operative", "facilities", "pharmacology",
    "widely available", "nutritional supplement", "genotype", "per dose",
    "in vial", "ml ampoule", "ml vial", "human papiloma", "for use during",
    "aspergillosis", "be widely", "selected ", "could be", "may be",
    "are essential", "are recommended", "if ", "when ", "cannot be safely",
    "guidelines recommend", "haemorrhage where", "watch group", "access group",
)


def _title(s: str) -> str:
    key = re.sub(r"\s+", " ", s.strip().lower())
    key = re.sub(r"\[[a-z]\]|\*", "", key).strip()
    if key in JUNK_NAMES:
        return ""
    if key in ALIASES:
        return ALIASES[key]
    out = []
    for w in s.strip().split():
        if w in {"+", "and", "or", "with", "de", "of"}:
            out.append(w)
        elif w.isupper() and len(w) <= 4:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:].lower() if w else w)
    name = " ".join(out)
    return ALIASES.get(name.lower(), name)


def _from_pdf(text: str) -> set[str]:
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if "1.1 General anaesthetics and oxygen" in l)
    end = next(i for i, l in enumerate(lines) if i > start + 500 and l.strip() == "ANNEX I")
    raw: set[str] = set()
    for i in range(start, end):
        s = lines[i].strip()
        if not s or "N AT I O N A L" in s or len(s) > 50:
            continue
        if re.search(
            r"\d+\s*mg|\d+\s*ml|\d+\s*%|Injection:|Tablet:|Powder for|Oral liquid|Inhalation|FIRST|SECOND|WHO ",
            s,
            re.I,
        ):
            continue
        if re.match(r"^\d+$", s) or (s.isupper() and len(s) > 10):
            continue
        if not re.match(r"^[a-z][a-z0-9 \+\-\(\)\.,/'*\[\]]*$", s):
            continue
        s2 = re.sub(r"\[[a-z]\]|\*", "", s, flags=re.I).strip()
        if len(s2) < 4:
            continue
        if any(j in s2 for j in JUNK_SUBSTR):
            continue
        raw.add(s2)

    line_list = [lines[i].strip() for i in range(start, end)]
    merged: set[str] = set()
    i = 0
    while i < len(line_list):
        s = line_list[i]
        if s.endswith(" +") or s.endswith("+"):
            parts = [s.rstrip("+").strip()]
            j = i + 1
            while j < len(line_list) and j < i + 4:
                nxt = line_list[j].strip()
                if re.match(r"^[a-z][a-z0-9 \+\-\(\)\.,/']*$", nxt) and len(nxt) < 30:
                    parts.append(nxt)
                    j += 1
                    if "acid" in nxt or len(parts) >= 3:
                        break
                else:
                    break
            merged.add(" ".join(parts))
            i = j
            continue
        if s in raw:
            merged.add(s)
        i += 1

    out: set[str] = set()
    for s in merged:
        name = _title(s)
        if name and len(name) >= 4 and name.lower() not in JUNK_NAMES:
            if any(j in name.lower() for j in ("Mg/", "Ampoule", "Tablet (heat", "Combination with Direct")):
                continue
            out.add(name)
    return out


def _norm_key(name: str) -> str:
    return re.sub(r"[^a-z0-9+]", "", name.lower().replace("-", "").replace(" ", ""))


def build_catalog(pdf_text_path: Path) -> list[dict]:
    from_pdf = _from_pdf(pdf_text_path.read_text(encoding="utf-8", errors="replace")) if pdf_text_path.is_file() else set()
    by_key: dict[str, dict] = {}
    for name in from_pdf:
        key = _norm_key(name)
        if not key:
            continue
        row = {
            "generic_name": name,
            "category": "NNLEM 2021",
            "nelm_tier": "core",
            "nnlem_source": "NNLEM 2021 PDF (DDA/MoHP)",
        }
        if key not in by_key or len(name) < len(by_key[key]["generic_name"]):
            by_key[key] = row
    for name, cat, tier in MUST_HAVE:
        key = _norm_key(name)
        by_key[key] = {
            "generic_name": name,
            "category": cat,
            "nelm_tier": tier,
            "nnlem_source": "NNLEM 2021 curated supplement",
        }
    return sorted(by_key.values(), key=lambda x: x["generic_name"].lower())


def main() -> int:
    pdf = PDF_TEXT
    if not pdf.is_file():
        print(f"Missing {pdf}; run pdftotext on official NNLEM PDF first.", file=sys.stderr)
        return 1
    molecules = build_catalog(pdf)
    out = {
        "version": "2021.6",
        "region": "NP",
        "molecule_count": len(molecules),
        "target_count": 398,
        "source": "National List of Essential Medicines Nepal, Sixth revision (2021), DDA/MoHP",
        "source_url": "https://cdn.who.int/media/docs/default-source/nepal-documents/hss_nepal/national-list-of-essential-medicines-nepal-sixth-revision-2021.pdf",
        "molecules": molecules,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(molecules)} molecules (target 398) -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
