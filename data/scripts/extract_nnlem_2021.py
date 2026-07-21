#!/usr/bin/env python3
"""Extract NNLEM 2021 molecules from official PDF text (dosage-form anchored).

The NNLEM PDF lists each molecule immediately before its dosage-form lines.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "nepal" / "nnlem_2021_molecules.json"
FOOTER = "N AT I O N A L L I S T O F E S S E N T I A L M E D I C I N E S N E PA L"

DOSAGE_START = re.compile(
    r"^(Injection|Tablet|Capsule|Oral liquid|Oral solution|Oral powder|Powder for|"
    r"Solid oral|Inhalation|Topical|Cream|Solution|Suppository|Lotion|Ointment|"
    r"Eye drops|Ear drops|Nasal|Vaginal|Patch|Implant|Dispersible|Chewable|"
    r"Effervescent|Granules|Enema|Infusion|Gas|Aerosol|MDI|Lozenge|Gum|"
    r"Film|Spray|Gel|Paste|Foam|Emulsion|Paint|Pessary|Rod|Strip|Device|"
    r"Pre-filled|Pen|Cartridge|Bag|Bottle|Sachet|Tube|Liquid|Syrup|"
    r"Suspension|Drops|Shampoo|Soap|Gargle|Mouthwash|Swab|Tincture|"
    r"Concentrate|Premix|Kit|Pack|Blister|Unit dose|Chewable tablet|"
    r"Modified-release|Prolonged-release|Immediate release|Metered-dose|"
    r"Powder \(|Oral \(|Rectal|Subcutaneous|Intramuscular|Intravenous|"
    r"Transdermal|Buccal|Sublingual|Inhaler|Nebulizer|Spacer|Mask)",
    re.I,
)

SKIP_NAME = re.compile(
    r"^(Complementary list|FIRST CHOICE|SECOND CHOICE|\*|Disclaimer|Bibliography|"
    r"WATCH GROUP|ACCESS GROUP|RESERVE GROUP|\d+$|\[a\]|For use |Also used|"
    r"Not recommended|Selected |This group|World Health|License:|Oral Powder for "
    r"reconstitution|Injection for spinal|Topical \(sterile\)|in vial|in ampoule)",
    re.I,
)

ALIASES = {
    "acetylsalicylic acid (aspirin)": "Acetylsalicylic Acid (Aspirin)",
    "acetylsalicylic acid": "Acetylsalicylic Acid (Aspirin)",
    "paracetamol": "Paracetamol",
    "epinephrine (adrenaline)": "Adrenaline (Epinephrine)",
    "adrenaline (epinephrine)": "Adrenaline (Epinephrine)",
    "benzylpenicillin (penicillin g)": "Benzylpenicillin (Penicillin G)",
    "penicillin v": "Penicillin V",
    "lidocaine (lignocaine)": "Lidocaine (Lignocaine)",
    "lidocaine (lignocaine) + epinephrine (adrenaline)": "Lidocaine + Epinephrine",
    "methylthioninium chloride (methylene blue)": "Methylene Blue",
    "potassium ferric hexacyanoferrate (ii).2h2o (prussian blue)": "Prussian Blue",
    "charcoal, activated": "Activated Charcoal",
    "valproic acid": "Sodium Valproate",
    "phenobarbital": "Phenobarbitone",
    "artemether + lumefantrine": "Artemether-Lumefantrine",
    "amoxicillin + clavulanic acid": "Amoxicillin-Clavulanate",
    "sulfamethoxazole + trimethoprim": "Trimethoprim-Sulfamethoxazole",
    "ethinylestradiol + levonorgestrel": "Ethinylestradiol-Levonorgestrel",
    "ethinylestradiol + norethisterone": "Ethinylestradiol-Norethisterone",
    "ferrous salt": "Ferrous Sulfate",
    "ferrous salt+ folic acid": "Ferrous Sulfate + Folic Acid",
    "colecalciferol": "Vitamin D3 (Cholecalciferol)",
    "cyanocobalmin": "Vitamin B12 (Cyanocobalamin)",
    "oral rehydration salts": "Oral Rehydration Salts",
    "compound solution of sodium lactate": "Ringer's Lactate",
    "zinc sulfate": "Zinc Sulfate",
    "zinc sulphate": "Zinc Sulfate",
    "enalpril": "Enalapril",
    "cephalexin": "Cephalexin",
    "glibenclamide": "Glibenclamide",
    "dolutegravir + lamivudine + tenofovir": "Dolutegravir-Lamivudine-Tenofovir",
    "efavirenz + lamivudine + tenofovir": "Efavirenz-Lamivudine-Tenofovir",
    "ethambutol + isoniazid + pyrazinamide + rifampicin": "HRZE (Fixed-Dose Combo)",
    "isoniazid + pyrazinamide +rifampicin": "Isoniazid-Pyrazinamide-Rifampicin",
    "isoniazid + rifampicin": "Isoniazid-Rifampicin",
    "isoniazid + pyrazinamide + rifampicin": "Isoniazid-Pyrazinamide-Rifampicin",
    "dihydroartemisinin + piperaquine phosphate": "Dihydroartemisinin-Piperaquine",
    "sulfadoxine + pyrimethamine": "Sulfadoxine-Pyrimethamine",
    "amlodipine+ losartan": "Amlodipine-Losartan",
    "levodopa+ cabidopa": "Levodopa-Carbidopa",
    "aluminum hydroxide gel + magnesium hydroxide": "Aluminium Hydroxide + Magnesium Hydroxide",
    "benzoic acid + salicylic acid": "Benzoic Acid + Salicylic Acid",
    "sodium bicarbonate + glycerin": "Sodium Bicarbonate + Glycerin",
    "piperacillin + tazobactam": "Piperacillin-Tazobactam",
    "amoxicillin+ clavulanic acid": "Amoxicillin-Clavulanate",
    "potassium chloride": "Potassium Chloride",
    "water for injection": "Water for Injection",
    "normal saline": "Normal Saline (0.9% NaCl)",
    "sodium chloride": "Normal Saline (0.9% NaCl)",
    "glucose": "Dextrose (Glucose)",
    "dextrose (glucose)": "Dextrose (Glucose)",
    "anti-d immunoglobulin": "Anti-D Immunoglobulin",
    "anti-rabies hyperimmune serum": "Anti-Rabies Hyperimmune Serum",
    "anti-tetanus immunoglobulin": "Anti-Tetanus Immunoglobulin",
    "snake antivenom (polyvalent)": "Snake Antivenom (Polyvalent)",
    "polyvenom anti-snake serum": "Snake Antivenom (Polyvalent)",
    "nicotine replacement therapy (nrt)": "Nicotine Replacement Therapy",
    "insulin, intermediate-acting insulin (nph)": "Insulin Human (NPH)",
    "insulin regular (soluble)": "Insulin Regular (Soluble)",
    "insulin glargine": "Insulin Glargine",
    "lugol's iodine": "Potassium Iodide",
    "phytomenadione": "Vitamin K1 (Phytomenadione)",
    "retinol": "Vitamin A",
    "ascorbic acid": "Vitamin C (Ascorbic Acid)",
    "pyridoxine": "Vitamin B6 (Pyridoxine)",
    "riboflavin": "Vitamin B2 (Riboflavin)",
    "thiamine": "Vitamin B1 (Thiamine)",
    "pethidine": "Pethidine",
    "codeine": "Codeine",
    "fentanyl": "Fentanyl",
    "morphine": "Morphine",
    "halothane": "Halothane",
    "isoflurane": "Isoflurane",
    "nitrous oxide": "Nitrous Oxide",
    "oxygen": "Oxygen",
    "sevoflurane": "Sevoflurane",
    "ketamine": "Ketamine",
    "propofol": "Propofol",
    "bupivacaine": "Bupivacaine",
    "midazolam": "Midazolam",
    "glycopyrrolate": "Glycopyrrolate",
    "levocetirizine": "Levocetirizine",
    "fexofenadine": "Fexofenadine",
    "pheniramine": "Pheniramine",
    "naloxone": "Naloxone",
    "deferoxamine": "Deferoxamine",
    "dimercaprol": "Dimercaprol",
    "fomipezole": "Fomipezole",
    "sodium calcium edetate": "Sodium Calcium Edetate",
    "niclosamide": "Niclosamide",
    "nalidixic acid": "Nalidixic Acid",
    "cefazolin": "Cefazolin",
    "cefotaxime": "Cefotaxime",
    "meropenem": "Meropenem",
    "polymyxin b": "Polymyxin B",
    "vancomycin": "Vancomycin",
    "clofazimine": "Clofazimine",
    "rifabutin": "Rifabutin",
    "bedaquiline": "Bedaquiline",
    "cycloserine": "Cycloserine",
    "delamanid": "Delamanid",
    "ethionamide": "Ethionamide",
    "amphotericin b": "Amphotericin B",
    "flucytosine": "Flucytosine",
    "itraconazole": "Itraconazole",
    "nystatin": "Nystatin",
    "natamycin": "Natamycin",
    "lamivudine (3tc)": "Lamivudine",
    "zidovudine (zdv or azt)": "Zidovudine",
    "nevirapine (nvp)": "Nevirapine",
    "atazanavir + ritonavir": "Atazanavir-Ritonavir",
    "dolutegravir": "Dolutegravir",
    "efavirenz": "Efavirenz",
    "tenofovir": "Tenofovir",
    "artemether": "Artemether",
    "chloroquine": "Chloroquine",
    "hydroxychloroquine": "Hydroxychloroquine",
    "methotrexate": "Methotrexate",
    "azathioprine": "Azathioprine",
    "ciclosporin": "Ciclosporin",
    "chlorambucil": "Chlorambucil",
    "cisplatin": "Cisplatin",
    "cyclophosphamide": "Cyclophosphamide",
    "doxorubicin": "Doxorubicin",
    "paclitaxel": "Paclitaxel",
    "tamoxifen": "Tamoxifen",
    "levodopa-carbidopa": "Levodopa-Carbidopa",
    "trihexyphenidyl (benzhexol)": "Trihexyphenidyl",
    "iron dextran": "Iron Dextran",
    "heparin sodium": "Heparin Sodium",
    "clomifene": "Clomifene",
    "methylergometrine": "Methylergometrine",
    "mifepristone": "Mifepristone",
    "terbutaline": "Terbutaline",
    "caffeine citrate": "Caffeine Citrate",
    "surfactant": "Surfactant (Neonatal)",
    "mannitol": "Mannitol",
    "metoclopramide": "Metoclopramide",
    "promethazine": "Promethazine",
    "hyoscine butylbromide": "Hyoscine Butylbromide",
    "drotaverine hydrochloride": "Drotaverine",
    "hyoscine hydrobromide": "Hyoscine Hydrobromide",
    "ispaghula husk": "Ispaghula Husk",
    "magnesium sulfate": "Magnesium Sulfate",
    "sulfasalazine": "Sulfasalazine",
    "fludrocortisone": "Fludrocortisone",
    "testosterone": "Testosterone",
    "ethinylestradiol": "Ethinylestradiol",
    "norethisterone": "Norethisterone",
    "medroxyprogesterone acetate": "Medroxyprogesterone Acetate",
    "desmopressin": "Desmopressin",
    "carbimazole": "Carbimazole",
    "neostigmine": "Neostigmine",
    "suxamethonium": "Suxamethonium",
    "vecuronium": "Vecuronium",
    "atracurium": "Atracurium",
    "aciclovir": "Acyclovir",
    "ofloxacin": "Ofloxacin",
    "tetracycline": "Tetracycline",
    "proparacaine": "Proparacaine",
    "tetracaine": "Tetracaine",
    "pilocarpine": "Pilocarpine",
    "tropicamide": "Tropamide",
    "betamethasone": "Betamethasone",
    "benzocaine": "Benzocaine",
    "zinc oxide": "Zinc Oxide",
    "oxymetazoline": "Oxymetazoline",
    "clove oil": "Clove Oil",
    "gentian violet": "Gentian Violet",
    "neomycin": "Neomycin",
    "silver sulfadiazine": "Silver Sulfadiazine",
    "povidone iodine": "Povidone Iodine",
    "chlorhexidine": "Chlorhexidine",
    "ethanol": "Ethanol",
    "glutaraldehyde": "Glutaraldehyde",
    "calamine": "Calamine",
    "benzyl benzoate": "Benzyl Benzoate",
    "fluorescein": "Fluorescein",
    "amidotrizoate": "Amidotrizoate",
    "barium sulfate": "Barium Sulfate",
    "iohexol": "Iohexol",
    "isoprenaline": "Isoprenaline",
    "amiodaron": "Amiodarone",
    "verampil": "Verapamil",
    "prazosin": "Prazosin",
    "fenofibrate": "Fenofibrate",
    "isosorbide dinitrate": "Isosorbide Dinitrate",
    "verapamil": "Verapamil",
    "coagulation factor viii": "Coagulation Factor VIII",
    "coagulation factor ix": "Coagulation Factor IX",
    "albumin": "Albumin",
    "polygeline": "Polygeline",
    "tuberculin, purified protein derivative (ppd)": "Tuberculin PPD",
    "diphtheria antitoxin": "Diphtheria Antitoxin",
    "tetanus antitoxin": "Tetanus Antitoxin",
    "bcg": "BCG Vaccine",
    "pentavalent": "Pentavalent Vaccine",
    "hepatitis b": "Hepatitis B Vaccine",
    "hepatitis a": "Hepatitis A Vaccine",
    "human papillomavirus (hpv)": "HPV Vaccine",
    "influenza": "Influenza Vaccine",
    "meningococcal meningitis": "Meningococcal Vaccine",
    "measles": "Measles Vaccine",
    "mumps": "Mumps Vaccine",
    "rubella": "Rubella Vaccine",
    "typhoid": "Typhoid Vaccine",
    "yellow fever": "Yellow Fever Vaccine",
    "rabies": "Rabies Vaccine (PVRV)",
    "chlordiazepoxide": "Chlordiazepoxide",
    "lorazepam": "Lorazepam",
    "lithium carbonate": "Lithium Carbonate",
    "methadone": "Methadone",
    "buprenorphine": "Buprenorphine",
    "disulfiram": "Disulfiram",
    "chlorpromazine": "Chlorpromazine",
    "fluphenazine": "Fluphenazine",
    "olanzapine": "Olanzapine",
    "aminophylline": "Aminophylline",
    "sodium bicarbonate": "Sodium Bicarbonate",
    "intraperitoneal dialysis solution": "Intraperitoneal Dialysis Solution",
    "thiopental": "Thiopental",
    "ephedrine": "Ephedrine",
    "enalapril": "Enalapril",
    "lisinopril": "Lisinopril",
    "atorvastatin": "Atorvastatin",
    "simvastatin": "Simvastatin",
    "rosuvastatin": "Rosuvastatin",
}


def _normalize(raw: str) -> str:
    s = re.sub(r"\s+", " ", raw.strip())
    s = re.sub(r"\[[a-z]\]", "", s, flags=re.I).strip()
    s = re.sub(r"\*+$", "", s).strip()
    key = s.lower()
    if key in ALIASES:
        return ALIASES[key]
    # title case preserving symbols
    out = []
    for w in s.replace("+", " + ").split():
        if w in {"+", "and", "or", "with", "de"}:
            out.append(w)
        elif w.isupper() and len(w) <= 4:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:].lower() if w else w)
    name = " ".join(out)
    return ALIASES.get(name.lower(), name)


def _collect_name(lines: list[str], idx: int) -> str | None:
    parts: list[str] = []
    j = idx
    while j >= 0:
        s = lines[j].strip()
        if not s or FOOTER in s:
            break
        if DOSAGE_START.match(s):
            j -= 1
            continue
        if SKIP_NAME.match(s):
            break
        if re.match(r"^\d+(\.\d+)*(\s+[A-Za-z])", s) and len(s) > 20:
            break
        if s.isupper() and len(s) > 12:
            break
        if re.search(r"\d+\s*mg|\d+\s*ml|\d+\s*%", s, re.I):
            break
        if _is_name_fragment(s):
            parts.insert(0, s)
            j -= 1
            if len(parts) >= 3:
                break
        else:
            break
    if not parts:
        return None
    name = _normalize(" ".join(parts))
    if len(name) < 3 or len(name) > 80:
        return None
    if any(x in name.lower() for x in ("medicine", "antibiotic", "group", "choice", "who ", "stewardship")):
        return None
    return name


def _is_name_fragment(s: str) -> bool:
    if SKIP_NAME.match(s):
        return False
    if DOSAGE_START.match(s):
        return False
    if re.match(r"^\d+$", s):
        return False
    if FOOTER in s:
        return False
    return bool(re.match(r"^[A-Za-z0-9][A-Za-z0-9 \+\-\(\)\.,/']*$", s))


def _parse_text(text: str) -> list[dict]:
    lines = text.splitlines()
    start = next(i for i, l in enumerate(lines) if "1.1 General anaesthetics and oxygen" in l)
    end = next(i for i, l in enumerate(lines) if i > start + 500 and l.strip() == "ANNEX I")

    tier = "core"
    category = "General"
    seen: set[str] = set()
    molecules: list[dict] = []

    for i in range(start, end):
        s = lines[i].strip()
        if FOOTER in s:
            continue
        if s.lower() == "complementary list":
            tier = "complementary"
            continue
        if re.match(r"^\d+\s+[A-Z].*MEDICINE", s):
            category = re.sub(r"^\d+\.?\s*", "", s).title()
            tier = "core"
            continue
        if not DOSAGE_START.match(s):
            continue
        name = _collect_name(lines, i - 1)
        if not name:
            continue
        key = name.lower()
        if key in seen:
            continue
        seen.add(key)
        molecules.append(
            {
                "generic_name": name,
                "category": category,
                "nelm_tier": tier,
                "nnlem_source": "NNLEM 2021 6th revision (DDA/MoHP)",
            }
        )

    return molecules


def main(argv: list[str]) -> int:
    src = Path(argv[1] if len(argv) > 1 else "/tmp/nnlem2021.txt")
    text = src.read_text(encoding="utf-8", errors="replace")
    molecules = _parse_text(text)
    out = {
        "version": "2021.6",
        "region": "NP",
        "molecule_count": len(molecules),
        "target_count": 398,
        "source": "National List of Essential Medicines Nepal, Sixth revision (2021), DDA/MoHP",
        "source_url": "https://cdn.who.int/media/docs/default-source/nepal-documents/hss_nepal/national-list-of-essential-medicines-nepal-sixth-revision-2021.pdf",
        "molecules": sorted(molecules, key=lambda x: x["generic_name"].lower()),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(molecules)} molecules -> {OUT}")
    return 0 if len(molecules) >= 350 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
