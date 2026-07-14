import 'dart:convert';

class BrandName {
  const BrandName({required this.name, this.manufacturer});

  final String name;
  final String? manufacturer;

  factory BrandName.fromJson(Map<String, dynamic> json) {
    return BrandName(
      name: json['name'] as String? ?? '',
      manufacturer: json['manufacturer'] as String?,
    );
  }
}

class Drug {
  const Drug({
    required this.id,
    required this.genericName,
    this.genericNameNe,
    this.category,
    this.nelmTier,
    this.dosageForms = const [],
    this.strengths = const [],
    this.brandNames = const [],
    this.indications = const [],
    this.contraindications = const [],
    this.adultDose,
    this.pediatricDose,
    this.pregnancyCategory,
    required this.ragText,
    this.updatedAt,
  });

  final String id;
  final String genericName;
  final String? genericNameNe;
  final String? category;
  final String? nelmTier;
  final List<String> dosageForms;
  final List<String> strengths;
  final List<BrandName> brandNames;
  final List<String> indications;
  final List<String> contraindications;
  final String? adultDose;
  final String? pediatricDose;
  final String? pregnancyCategory;
  final String ragText;
  final String? updatedAt;

  factory Drug.fromMap(Map<String, dynamic> map) {
    List<String> stringList(dynamic raw) {
      if (raw == null) return const [];
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {
          return const [];
        }
      }
      return const [];
    }

    List<BrandName> brands(dynamic raw) {
      List<dynamic> list;
      if (raw is List) {
        list = raw;
      } else if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          list = decoded is List ? decoded : const [];
        } catch (_) {
          return const [];
        }
      } else {
        return const [];
      }
      return list
          .whereType<Map>()
          .map((e) => BrandName.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return Drug(
      id: map['id'] as String,
      genericName: map['generic_name'] as String? ?? '',
      genericNameNe: map['generic_name_ne'] as String?,
      category: map['category'] as String?,
      nelmTier: map['nelm_tier'] as String?,
      dosageForms: stringList(map['dosage_forms']),
      strengths: stringList(map['strengths']),
      brandNames: brands(map['brand_names']),
      indications: stringList(map['indications']),
      contraindications: stringList(map['contraindications']),
      adultDose: map['adult_dose'] as String?,
      pediatricDose: map['pediatric_dose'] as String?,
      pregnancyCategory: map['pregnancy_category'] as String?,
      ragText: map['rag_text'] as String? ?? '',
      updatedAt: map['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'generic_name': genericName,
      'generic_name_ne': genericNameNe,
      'category': category,
      'nelm_tier': nelmTier,
      'dosage_forms': jsonEncode(dosageForms),
      'strengths': jsonEncode(strengths),
      'brand_names': jsonEncode(
        brandNames
            .map((b) => {'name': b.name, 'manufacturer': b.manufacturer})
            .toList(),
      ),
      'indications': jsonEncode(indications),
      'contraindications': jsonEncode(contraindications),
      'adult_dose': adultDose,
      'pediatric_dose': pediatricDose,
      'pregnancy_category': pregnancyCategory,
      'rag_text': ragText,
    };
  }
}

class Interaction {
  const Interaction({
    required this.id,
    required this.drugAId,
    required this.drugBId,
    required this.severity,
    this.mechanism,
    this.clinicalEffect,
    required this.recommendation,
    this.source,
  });

  final String id;
  final String drugAId;
  final String drugBId;
  final String severity;
  final String? mechanism;
  final String? clinicalEffect;
  final String recommendation;
  final String? source;

  factory Interaction.fromMap(Map<String, dynamic> map) {
    return Interaction(
      id: map['id'] as String,
      drugAId: map['drug_a_id'] as String,
      drugBId: map['drug_b_id'] as String,
      severity: map['severity'] as String,
      mechanism: map['mechanism'] as String?,
      clinicalEffect: map['clinical_effect'] as String?,
      recommendation: map['recommendation'] as String? ?? '',
      source: map['source'] as String?,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'drug_a_id': drugAId,
      'drug_b_id': drugBId,
      'severity': severity,
      'mechanism': mechanism,
      'clinical_effect': clinicalEffect,
      'recommendation': recommendation,
      'source': source,
    };
  }
}

class GuidelineChunk {
  const GuidelineChunk({
    required this.id,
    required this.title,
    this.titleNe,
    required this.source,
    this.topic,
    required this.chunkText,
    this.chunkTextNe,
    this.priority = 0,
  });

  final String id;
  final String title;
  final String? titleNe;
  final String source;
  final String? topic;
  final String chunkText;
  final String? chunkTextNe;
  final int priority;

  factory GuidelineChunk.fromMap(Map<String, dynamic> map) {
    return GuidelineChunk(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      titleNe: map['title_ne'] as String?,
      source: map['source'] as String? ?? '',
      topic: map['topic'] as String?,
      chunkText: map['chunk_text'] as String? ?? '',
      chunkTextNe: map['chunk_text_ne'] as String?,
      priority: (map['priority'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toSqlMap() {
    return {
      'id': id,
      'title': title,
      'title_ne': titleNe,
      'source': source,
      'topic': topic,
      'chunk_text': chunkText,
      'chunk_text_ne': chunkTextNe,
      'priority': priority,
    };
  }
}

class ConsentTemplate {
  const ConsentTemplate({
    required this.consentVersion,
    required this.templates,
  });

  final String consentVersion;
  final Map<String, Map<String, String>> templates;

  factory ConsentTemplate.fromJson(Map<String, dynamic> json) {
    final raw = json['templates'] as Map<String, dynamic>? ?? {};
    final templates = <String, Map<String, String>>{};
    for (final entry in raw.entries) {
      final langs = entry.value;
      if (langs is Map) {
        templates[entry.key] = {
          for (final e in langs.entries) e.key.toString(): e.value.toString(),
        };
      }
    }
    return ConsentTemplate(
      consentVersion: json['consent_version'] as String? ?? 'np-pilot-1.0',
      templates: templates,
    );
  }

  String text(String key, String lang) {
    return templates[key]?[lang] ?? templates[key]?['en'] ?? key;
  }
}
