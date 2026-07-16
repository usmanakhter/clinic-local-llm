import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Local OpenAI-compatible sidecar (Ollama / llama.cpp). Never sends traffic
/// outside localhost for this POC.
class LocalLlmClient {
  LocalLlmClient({
    String? baseUrl,
    this.model = 'qwen2.5:1.5b',
    this.timeout = const Duration(seconds: 90),
  }) : baseUrl = baseUrl ??
            (kIsWeb
                // Web needs CORS proxy (tools/ollama_cors_proxy.py) on :8765
                ? 'http://127.0.0.1:8765'
                : 'http://127.0.0.1:11434');

  final String baseUrl;
  final String model;
  final Duration timeout;

  static const systemPrompt = '''
You are a clinical note drafting assistant for a Nepal pilot demo.
Write a concise SOAP-style clinical note from structured fields.
Rules:
- Draft only — not a diagnosis or prescription authority.
- Do not invent drug-drug interaction severity.
- Do not invent lab values or findings not provided.
- Prefer English. Keep synthetic / training tone.
- End with: "Draft only — clinician must review. Not for clinical use."
''';

  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/api/tags');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      try {
        final uri = Uri.parse('$baseUrl/v1/models');
        final res = await http.get(uri).timeout(const Duration(seconds: 3));
        return res.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  Future<String> draftNote({
    required String chiefComplaint,
    required String history,
    required String examination,
    required String assessment,
    required String plan,
  }) async {
    final user = '''
Chief complaint: $chiefComplaint
History: $history
Examination: $examination
Assessment: $assessment
Plan: $plan

Write the draft clinical note now.
''';

    final uri = Uri.parse('$baseUrl/v1/chat/completions');
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.2,
      'stream': false,
    });

    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('LLM HTTP ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw StateError('LLM returned no choices');
    }
    final msg = choices.first as Map<String, dynamic>;
    final content = (msg['message'] as Map<String, dynamic>?)?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw StateError('LLM returned empty content');
    }
    return content.trim();
  }
}

class NoteDraftResult {
  const NoteDraftResult({
    required this.text,
    required this.fromLocalModel,
    this.statusMessage,
  });

  final String text;
  final bool fromLocalModel;
  final String? statusMessage;
}
