import 'package:flutter/material.dart';

import '../data/chat_memory.dart';
import '../data/session_store.dart';
import '../data/repositories.dart';
import '../data/retriever.dart';
import '../llm/gguf_runtime.dart';
import '../llm/gguf_runtime_factory.dart';
import '../llm/local_llm_client.dart';
import '../llm/model_download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/citation_card.dart';
import '../widgets/llm_status_banner.dart';
import '../widgets/model_download_card.dart';
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

  ChatMemoryMessage toMemory() => ChatMemoryMessage(
        role: role,
        text: text,
        fromModel: fromModel,
        isError: isError,
        sessionId: sessionId,
        feedback: feedback,
      );

  factory _ChatMessage.fromMemory(ChatMemoryMessage m) => _ChatMessage(
        role: m.role,
        text: m.text,
        fromModel: m.fromModel,
        isError: m.isError,
        sessionId: m.sessionId,
        feedback: m.feedback,
      );
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <_ChatMessage>[];
  late final ClinicalRetriever _retriever;
  final _llm = LocalLlmClient(gguf: createNativeGgufRuntime());
  late final ModelDownloadManager _modelDownload;
  bool _busy = false;
  LlmStatus? _llmStatus;
  bool _probing = false;
  bool _modelReadyOnDisk = false;

  static _ChatMessage get _welcome => _ChatMessage(
        role: 'assistant',
        text:
            'I search local notes, history, chats, drugs, and guidelines on this '
            'device, then answer with the on-device Qwen GGUF only. If no model '
            'is installed yet, use Download clinical model (~1.1 GB, Wi‑Fi '
            'recommended) — there is no rules-engine fallback. I will not invent '
            'interaction severity. Not for clinical use.\n\n'
            '$kGgufLatencyNote',
      );

  @override
  void initState() {
    super.initState();
    _retriever = ClinicalRetriever(widget.repository);
    _modelDownload = createModelDownloadManager();
    _restoreMessages();
    _probeLlm();
  }

  Future<void> _restoreMessages() async {
    await ChatMemory.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(
          ChatMemory.instance.messages.map(_ChatMessage.fromMemory),
        );
      if (_messages.isEmpty) {
        _messages.add(_welcome);
        _persistMessages();
      }
    });
  }

  void _persistMessages() {
    ChatMemory.instance.replaceAll(_messages.map((m) => m.toMemory()).toList());
  }

  Future<void> _clearChat() async {
    await ChatMemory.instance.clear();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..add(_welcome);
      _busy = false;
    });
    _persistMessages();
  }

  Future<void> _probeLlm() async {
    setState(() => _probing = true);
    final readyOnDisk = await _modelDownload.isModelReady();
    final s = await _llm.probe();
    if (!mounted) return;
    setState(() {
      _modelReadyOnDisk = readyOnDisk || s.reachable;
      _llmStatus = s;
      _probing = false;
    });
  }

  Future<void> _onModelDownloaded() async {
    await _probeLlm();
  }

  @override
  void dispose() {
    _controller.dispose();
    _modelDownload.dispose();
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

    // Compact retrieve → shorter prompt eval on CPU.
    final bundle = await _retriever.retrieve(
      q,
      drugLimit: 3,
      guidelineLimit: 3,
      sessionLimit: 4,
    );

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
      _persistMessages();
      return;
    }

    String answer;
    var fromModel = false;
    var isError = false;
    final streamingIndex = _messages.length;
    try {
      if (!_llm.gguf.isReady) {
        final status = await _llm.probe();
        if (mounted) setState(() => _llmStatus = status);
        if (!status.reachable || status.backend != LlmBackend.gguf) {
          throw LocalModelNotFoundException(status.message);
        }
      } else if (mounted && _llmStatus?.reachable != true) {
        setState(() {
          _llmStatus = LlmStatus(
            reachable: true,
            backend: LlmBackend.gguf,
            model: _llm.gguf.modelLabel,
            models: _llm.gguf.modelLabel != null
                ? [_llm.gguf.modelLabel!]
                : const [],
          );
        });
      }

      // Placeholder bubble — stream tokens into it for perceived speed.
      if (mounted) {
        setState(() {
          _messages.add(
            _ChatMessage(
              role: 'assistant',
              text: '',
              bundle: bundle,
              fromModel: true,
            ),
          );
        });
      }

      answer = await _llm.groundedChatAnswer(
        question: q,
        retrievedContext: _retriever.formatContext(bundle, compact: true),
        modelOverride: _llmStatus?.model,
        onToken: (tok) {
          if (!mounted) return;
          setState(() {
            final cur = _messages[streamingIndex];
            _messages[streamingIndex] = _ChatMessage(
              role: cur.role,
              text: cur.text + tok,
              bundle: cur.bundle,
              fromModel: true,
              isError: false,
              sessionId: cur.sessionId,
              feedback: cur.feedback,
            );
          });
        },
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
      // Replace streaming placeholder (if any) with error text.
      if (mounted &&
          streamingIndex < _messages.length &&
          _messages[streamingIndex].role == 'assistant' &&
          _messages[streamingIndex].fromModel) {
        setState(() {
          _messages[streamingIndex] = _ChatMessage(
            role: 'assistant',
            text: answer,
            isError: true,
          );
        });
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
      if (streamingIndex < _messages.length &&
          _messages[streamingIndex].role == 'assistant') {
        final cur = _messages[streamingIndex];
        _messages[streamingIndex] = _ChatMessage(
          role: 'assistant',
          text: answer,
          bundle: isError ? null : bundle,
          fromModel: fromModel,
          isError: isError,
          sessionId: sess.id,
          feedback: cur.feedback,
        );
      } else {
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
      }
      _busy = false;
    });
    _persistMessages();
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
    _persistMessages();
  }

  @override
  Widget build(BuildContext context) {
    final showDownload = !_probing &&
        _llmStatus != null &&
        !_llmStatus!.reachable &&
        !_modelReadyOnDisk;

    return Column(
      children: [
        LlmStatusBanner(
          status: _llmStatus,
          checking: _probing,
          onRefresh: _probeLlm,
        ),
        if (showDownload)
          ModelDownloadCard(
            manager: _modelDownload,
            onComplete: _onModelDownloaded,
          ),
        Material(
          color: AppColors.slate100,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Retrieve → on-device GGUF. $kGgufLatencyNote',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.slate700,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _clearChat,
                  child: const Text('Clear'),
                ),
              ],
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
