import 'package:flutter/material.dart';

import '../data/session_store.dart';
import '../data/repositories.dart';
import '../data/retriever.dart';
import '../llm/gguf_runtime.dart';
import '../llm/gguf_runtime_factory.dart';
import '../llm/local_llm_client.dart';
import '../theme/app_theme.dart';
import '../widgets/citation_card.dart';
import '../widgets/llm_status_banner.dart';
import '../models/models.dart';

/// Unified local chat: notes + history + past chats + drugs + guidelines.
/// Answers only via on-device GGUF — no rules/Ollama fallback.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatMessage {
  _ChatMessage({
    required this.role,
    required this.text,
    this.bundle,
    this.fromModel = false,
    this.isError = false,
    this.sessionId,
    this.feedback,
  });

  final String role;
  final String text;
  final RetrieveBundle? bundle;
  final bool fromModel;
  final bool isError;
  final String? sessionId;
  final String? feedback;
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <_ChatMessage>[];
  late final ClinicalRetriever _retriever;
  final _llm = LocalLlmClient(gguf: createNativeGgufRuntime());
  bool _busy = false;
  LlmStatus? _llmStatus;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _retriever = ClinicalRetriever(widget.repository);
    _messages.add(
      _ChatMessage(
        role: 'assistant',
        text:
            'I search local notes, history, chats, drugs, and guidelines on this '
            'device, then answer with the on-device Qwen GGUF only. If no model '
            'file is present, you will see an error — there is no rules-engine '
            'fallback. I will not invent interaction severity. Not for clinical use.\n\n'
            '$kGgufLatencyNote',
      ),
    );
    _probeLlm();
  }

  Future<void> _probeLlm() async {
    setState(() => _probing = true);
    final s = await _llm.probe();
    if (!mounted) return;
    setState(() {
      _llmStatus = s;
      _probing = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _messages.add(_ChatMessage(role: 'user', text: q));
      _controller.clear();
    });

    final bundle = await _retriever.retrieve(q);

    if (bundle.refused) {
      final sess = await widget.repository.logSession(
        queryType: 'chat',
        inputSummary: q,
        outputSummary: 'refused',
        metadata: {
          'refused': true,
          'refuse_reason': bundle.refuseReason,
        },
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: '${bundle.refuseReason}\n\n'
                'Save a note, search a drug, or open a guideline first — '
                'then ask again.',
            bundle: bundle,
            sessionId: sess.id,
          ),
        );
        _busy = false;
      });
      return;
    }

    String answer;
    var fromModel = false;
    var isError = false;
    try {
      final status = await _llm.probe();
      if (mounted) setState(() => _llmStatus = status);
      if (!status.reachable || status.backend != LlmBackend.gguf) {
        throw LocalModelNotFoundException(status.message);
      }
      answer = await _llm.groundedChatAnswer(
        question: q,
        retrievedContext: _retriever.formatContext(bundle),
        modelOverride: status.model,
      );
      fromModel = true;
    } catch (e) {
      isError = true;
      fromModel = false;
      if (e is LocalModelNotFoundException) {
        answer = e.message;
      } else {
        answer = 'Local model error: $e';
      }
    }

    final sess = await widget.repository.logSession(
      queryType: 'chat',
      inputSummary: q,
      outputSummary:
          answer.length > 200 ? '${answer.substring(0, 200)}…' : answer,
      metadata: {
        'refused': false,
        'from_model': fromModel,
        'model_error': isError,
        'backend': _llmStatus?.backend.name,
        'drug_ids': bundle.drugs.map((d) => d.id).toList(),
        'guideline_ids': bundle.guidelines.map((g) => g.id).toList(),
        'session_ids': bundle.sessions.map((s) => s.sessionId).toList(),
      },
    );

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          role: 'assistant',
          text: answer,
          bundle: isError ? null : bundle,
          fromModel: fromModel,
          isError: isError,
          sessionId: sess.id,
        ),
      );
      _busy = false;
    });
  }

  Future<void> _submitFeedback(int index, String vote) async {
    final m = _messages[index];
    final sid = m.sessionId;
    if (sid == null || m.role != 'assistant' || m.isError) return;
    await SessionStore.updateFeedback(sessionId: sid, feedback: vote);
    if (!mounted) return;
    setState(() {
      _messages[index] = _ChatMessage(
        role: m.role,
        text: m.text,
        bundle: m.bundle,
        fromModel: m.fromModel,
        isError: m.isError,
        sessionId: m.sessionId,
        feedback: vote,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LlmStatusBanner(
          status: _llmStatus,
          checking: _probing,
          onRefresh: _probeLlm,
        ),
        Material(
          color: AppColors.slate100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              'Retrieve → on-device GGUF only (error if no local model). '
              'Expect ~30–60s per answer on CPU.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.slate700,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              final isUser = m.role == 'user';
              final b = m.bundle;
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.92,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppColors.tealSoft
                        : (m.isError ? AppColors.warningStrip : Colors.white),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.text),
                      if (m.fromModel)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'On-device GGUF',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.tealDark),
                          ),
                        ),
                      if (m.isError)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'No model fallback',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.warningText),
                          ),
                        ),
                      if (m.sessionId != null && !m.isError && m.role == 'assistant')
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  m.feedback == 'up'
                                      ? Icons.thumb_up
                                      : Icons.thumb_up_outlined,
                                  size: 18,
                                  color: m.feedback == 'up'
                                      ? AppColors.tealDark
                                      : AppColors.slate500,
                                ),
                                onPressed: m.feedback == null
                                    ? () => _submitFeedback(i, 'up')
                                    : null,
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  m.feedback == 'down'
                                      ? Icons.thumb_down
                                      : Icons.thumb_down_outlined,
                                  size: 18,
                                  color: m.feedback == 'down'
                                      ? AppColors.warningText
                                      : AppColors.slate500,
                                ),
                                onPressed: m.feedback == null
                                    ? () => _submitFeedback(i, 'down')
                                    : null,
                              ),
                              if (m.feedback != null)
                                Text(
                                  'Feedback recorded',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                            ],
                          ),
                        ),
                      if (b != null && !b.refused) ...[
                        if (b.notes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Notes used',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          ...b.notes.take(4).map(
                                (n) => Text(
                                  '• ${n.title} (${n.patientName ?? n.patientId ?? "no patient"})',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                        ],
                        if (b.guidelines.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Guideline citations',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          ...b.guidelines.take(3).map(
                                (g) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: CitationCard(
                                    chunk: GuidelineChunk(
                                      id: g.id,
                                      title: g.title,
                                      source: g.source,
                                      topic: g.topic,
                                      chunkText: g.excerpt,
                                      priority: g.score.round(),
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Generating on-device… $kGgufLatencyNote',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.slate500,
                          ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_busy,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. review my fever notes; or scrub typhus',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _busy ? null : _send,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
