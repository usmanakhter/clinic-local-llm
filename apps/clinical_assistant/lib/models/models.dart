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

/// OPD condition coverage row (Nepal checklist — Guide browse catalogue).
class OpdCondition {
  const OpdCondition({
    required this.id,
    required this.name,
    this.weight = 0,
    this.searchQuery,
    this.expectedDrugIds = const [],
    this.expectedGuidelineIds = const [],
    this.covered = false,
  });

  final String id;
  final String name;
  final int weight;
  final String? searchQuery;
  final List<String> expectedDrugIds;
  final List<String> expectedGuidelineIds;
  final bool covered;

  factory OpdCondition.fromMap(Map<String, dynamic> map) {
    return OpdCondition(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      weight: (map['weight'] as num?)?.toInt() ?? 0,
      searchQuery: map['search_query'] as String?,
      expectedDrugIds: (map['expected_drug_ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      expectedGuidelineIds:
          (map['expected_guideline_ids'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      covered: map['covered'] as bool? ?? false,
    );
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

/// Lightweight local patient card — not a full EMR chart.
class Patient {
  const Patient({
    required this.id,
    required this.displayName,
    this.age,
    this.sex,
    this.phone,
    this.whatsapp,
    this.email,
    this.clinicalCondition,
    this.relevantNotes,
    this.history,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String displayName;
  final String? age;
  final String? sex;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? clinicalCondition;
  final String? relevantNotes;
  final String? history;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'] as String,
      displayName: map['display_name'] as String? ?? '',
      age: map['age'] as String?,
      sex: map['sex'] as String?,
      phone: map['phone'] as String?,
      whatsapp: map['whatsapp'] as String?,
      email: map['email'] as String?,
      clinicalCondition: map['clinical_condition'] as String?,
      relevantNotes: map['relevant_notes'] as String?,
      history: map['history'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'display_name': displayName,
      'age': age,
      'sex': sex,
      'phone': phone,
      'whatsapp': whatsapp,
      'email': email,
      'clinical_condition': clinicalCondition,
      'relevant_notes': relevantNotes,
      'history': history,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get subtitle {
    final parts = <String>[
      if (age != null && age!.trim().isNotEmpty) 'Age $age',
      if (sex != null && sex!.trim().isNotEmpty) sex!,
      if (phone != null && phone!.trim().isNotEmpty) 'Tel $phone',
      if (whatsapp != null && whatsapp!.trim().isNotEmpty) 'WA $whatsapp',
      if (clinicalCondition != null && clinicalCondition!.trim().isNotEmpty)
        clinicalCondition!,
    ];
    return parts.isEmpty ? 'No condition listed' : parts.join(' · ');
  }

  /// Case-insensitive match across id, name, contacts, and clinical text.
  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      id,
      displayName,
      age,
      sex,
      phone,
      whatsapp,
      email,
      clinicalCondition,
      relevantNotes,
      history,
    ].whereType<String>().map((s) => s.toLowerCase()).join(' ');
    return hay.contains(q);
  }
}

/// Local activity log row — unredacted on device; sync queue is scrubbed separately.
class ClinicalSession {
  const ClinicalSession({
    required this.id,
    required this.createdAt,
    required this.queryType,
    this.inputSummary,
    this.outputSummary,
    this.payloadJson,
    this.syncStatus = 'local_only',
    this.deviceId = 'local',
    this.patientId,
    this.feedback,
    this.feedbackReason,
  });

  final String id;
  final DateTime createdAt;
  final String queryType;
  final String? inputSummary;
  final String? outputSummary;
  final String? payloadJson;
  final String syncStatus;
  final String? deviceId;
  final String? patientId;
  final String? feedback;
  final String? feedbackReason;

  factory ClinicalSession.fromMap(Map<String, dynamic> map) {
    return ClinicalSession(
      id: map['id'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      queryType: map['query_type'] as String? ?? 'unknown',
      inputSummary: map['input_summary'] as String?,
      outputSummary: map['output_summary'] as String?,
      payloadJson: map['payload_json'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'local_only',
      deviceId: map['device_id'] as String?,
      patientId: map['patient_id'] as String?,
      feedback: map['feedback'] as String?,
      feedbackReason: map['feedback_reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'query_type': queryType,
      'input_summary': inputSummary,
      'output_summary': outputSummary,
      'payload_json': payloadJson,
      'sync_status': syncStatus,
      'device_id': deviceId,
      'feedback': feedback,
      'feedback_reason': feedbackReason,
      'patient_id': patientId,
    };
  }

  Map<String, dynamic>? get payload {
    if (payloadJson == null || payloadJson!.isEmpty) return null;
    try {
      final decoded = jsonDecode(payloadJson!);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String get typeLabel {
    switch (queryType) {
      case 'drug_lookup':
        return 'Drug search';
      case 'interaction_check':
        return 'Interaction';
      case 'guideline_search':
        return 'Guideline';
      case 'note_draft':
        return 'Note';
      case 'chat':
        return 'Chat';
      default:
        return queryType;
    }
  }
}
