import 'gguf_runtime.dart';
import 'in_app_draft_engine.dart';

enum LlmBackend {
  /// On-device Qwen GGUF via llama.cpp (product Chat path).
  gguf,

  /// Structured SOAP assembler for Notes only — never used as Chat fallback.
  inApp,
}

/// Expected wall-clock for on-device Qwen GGUF on CPU (Chat / Notes generate).
const kGgufLatencyNote =
    'On-device Qwen may take ~30–60 seconds per reply on CPU (first answer can be longer).';

/// Health / reachability of the active draft / chat backend.
class LlmStatus {
  const LlmStatus({
    required this.reachable,
    required this.backend,
    this.model,
    this.models = const [],
    this.message,
    this.baseUrl,
  });

  final bool reachable;
  final LlmBackend backend;
  final String? model;
  final List<String> models;
  final String? message;
  final String? baseUrl;

  String get shortLabel {
    switch (backend) {
      case LlmBackend.gguf:
        if (!reachable) return 'No local model';
        return 'On-device · ${model ?? 'gguf'}';
      case LlmBackend.inApp:
        return 'In-app · ${model ?? InAppDraftEngine.modelId}';
    }
  }
}

/// Local draft / grounded-chat client.
///
/// **Chat:** [groundedChatAnswer] requires a loaded GGUF — throws
/// [LocalModelNotFoundException] otherwise (no rules / Ollama fallback).
/// **Notes:** [draftNote] uses GGUF when ready, else [InAppDraftEngine].
///
/// Pass [gguf] from [createNativeGgufRuntime] in product screens.
class LocalLlmClient {
  LocalLlmClient({
    GgufLlamaRuntime? gguf,
    this.inApp = const InAppDraftEngine(),
    this.requireGgufForChat = true,
  }) : gguf = gguf ?? UnloadedGgufRuntime();

  final GgufLlamaRuntime gguf;
  final InAppDraftEngine inApp;

  /// When true (product default), Chat never falls back to [inApp].
  final bool requireGgufForChat;

  Future<bool> isAvailable() async {
    final s = await probe();
    return s.reachable && s.backend == LlmBackend.gguf;
  }

  /// Prefer GGUF when loadable; otherwise report missing model for Chat.
  Future<LlmStatus> probe() async {
    final ready = await gguf.ensureLoaded();
    if (ready) {
      return LlmStatus(
        reachable: true,
        backend: LlmBackend.gguf,
        model: gguf.modelLabel,
        models: gguf.modelLabel != null ? [gguf.modelLabel!] : const [],
        message: null,
      );
    }

    return LlmStatus(
      reachable: false,
      backend: LlmBackend.gguf,
      message: gguf.lastError ?? LocalModelNotFoundException.defaultMessage,
    );
  }

  /// Notes-only status when GGUF is absent (in-app draft still works).
  Future<LlmStatus> probeNotes() async {
    final ggufStatus = await probe();
    if (ggufStatus.reachable && ggufStatus.backend == LlmBackend.gguf) {
      return ggufStatus;
    }
    return LlmStatus(
      reachable: true,
      backend: LlmBackend.inApp,
      model: InAppDraftEngine.modelId,
      message:
          'Notes use in-app draft (no GGUF). Chat still requires a local model.',
    );
  }

  Future<String> draftNote({
    required String chiefComplaint,
    required String history,
    required String examination,
    required String assessment,
    required String plan,
  }) async {
    final status = await probe();
    if (status.backend == LlmBackend.gguf && status.reachable) {
      try {
        return await gguf.complete(
          system: '''
You are a clinical note drafting assistant for a Nepal pilot demo.
Write a concise SOAP-style clinical note from structured fields.
Rules:
- Draft only — not a diagnosis or prescription authority.
- Do not invent drug-drug interaction severity.
- Do not invent lab values or findings not provided.
- Prefer English. Keep synthetic / training tone.
- End with: "Draft only — clinician must review. Not for clinical use."
''',
          user: '''
Chief complaint: $chiefComplaint
History: $history
Examination: $examination
Assessment: $assessment
Plan: $plan

Write the draft clinical note now.
''',
          maxTokens: 640,
          temperature: 0.2,
        );
      } catch (_) {
        // Notes may fall back to structured assembler.
      }
    }
    return inApp.draftNote(
      chiefComplaint: chiefComplaint,
      history: history,
      examination: examination,
      assessment: assessment,
      plan: plan,
    );
  }

  /// Paraphrase retrieved context with **GGUF only**.
  /// Caller must refuse if context empty. Never uses [InAppDraftEngine].
  Future<String> groundedChatAnswer({
    required String question,
    required String retrievedContext,
    String? modelOverride,
  }) async {
    if (retrievedContext.trim().isEmpty) {
      throw StateError('groundedChatAnswer requires non-empty retrieved context');
    }

    final status = await probe();
    if (requireGgufForChat &&
        (status.backend != LlmBackend.gguf || !status.reachable)) {
      throw LocalModelNotFoundException(status.message);
    }

    return gguf.complete(
      system: '''
You are a grounded clinical reference assistant for a Nepal pilot demo.
You may ONLY paraphrase or organize the retrieved local snippets provided.
Rules:
- Answer only from the RETRIEVED CONTEXT block. Do not add outside medical facts.
- Cite drug and guideline ids that appear in the context.
- Never invent drug-drug interaction severity.
- End with: "Draft only — not for clinical use."
''',
      user: '''
QUESTION:
$question

RETRIEVED CONTEXT:
$retrievedContext

Write a short grounded answer with citations to ids from context.
''',
      maxTokens: 512,
      temperature: 0.1,
    );
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
