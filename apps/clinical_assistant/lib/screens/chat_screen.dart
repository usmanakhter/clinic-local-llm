import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../data/retriever.dart';
import '../llm/local_llm_client.dart';
import '../theme/app_theme.dart';
import '../widgets/citation_card.dart';
import '../models/models.dart';

/// RAG-first chat: retrieve locally, then optional local LLM; refuse if empty.
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
  });

  final String role; // user | assistant
  final String text;
  final RetrieveBundle? bundle;
  final bool fromModel;
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <_ChatMessage>[];
  late final ClinicalRetriever _retriever;
  final _llm = LocalLlmClient();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _retriever = ClinicalRetriever(widget.repository);
    _messages.add(
      _ChatMessage(
        role: 'assistant',
        text:
            'Ask a clinical reference question. I retrieve from the local Nepal '
            'formulary and guidelines first. If nothing matches, I refuse — '
            'I will not invent interaction severity. Not for clinical use.',
      ),
    );
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
      await widget.repository.logSession(
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
            text:
                'I could not find matching local drugs or guidelines for that '
                'query.\n\n${bundle.refuseReason}\n\n'
                'Try a formulary name, brand, or topic like dengue, TB, scrub typhus.',
            bundle: bundle,
          ),
        );
        _busy = false;
      });
      return;
    }

    var answer = _deterministicAnswer(bundle);
    var fromModel = false;
    try {
      if (await _llm.isAvailable()) {
        final ctx = _retriever.formatContext(bundle);
        final drafted = await _llm.draftNote(
          chiefComplaint: q,
          history: ctx,
          examination: 'N/A — chat retrieve-then-answer',
          assessment:
              'Grounded assistant reply only from retrieved snippets; cite ids.',
          plan: 'Do not invent interaction severity. Draft only.',
        );
        answer = drafted;
        fromModel = true;
      }
    } catch (_) {
      // keep deterministic answer
    }

    await widget.repository.logSession(
      queryType: 'chat',
      inputSummary: q,
      outputSummary: answer.length > 200 ? '${answer.substring(0, 200)}…' : answer,
      metadata: {
        'refused': false,
        'from_model': fromModel,
        'drug_ids': bundle.drugs.map((d) => d.id).toList(),
        'guideline_ids': bundle.guidelines.map((g) => g.id).toList(),
      },
    );

    if (!mounted) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          role: 'assistant',
          text: answer,
          bundle: bundle,
          fromModel: fromModel,
        ),
      );
      _busy = false;
    });
  }

  String _deterministicAnswer(RetrieveBundle bundle) {
    final buf = StringBuffer(
      'Retrieved from local Nepal fixtures (no invented severity):\n\n',
    );
    if (bundle.drugs.isNotEmpty) {
      buf.writeln('**Drugs**');
      for (final d in bundle.drugs.take(3)) {
        buf.writeln('- ${d.genericName} (`${d.id}`): ${d.excerpt}');
      }
      buf.writeln();
    }
    if (bundle.guidelines.isNotEmpty) {
      buf.writeln('**Guidelines**');
      for (final g in bundle.guidelines.take(3)) {
        buf.writeln('- ${g.title} (`${g.id}`, ${g.source}): ${g.excerpt}');
      }
    }
    buf.writeln(
      '\n_Draft assist only — not for clinical use. Open citations below for full text._',
    );
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: AppColors.tealSoft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'RAG-first chat · local retrieve · LLM optional (PC/Ollama). '
              'Majority phones stay retrieve-only.',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.tealDark,
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
                    color: isUser ? AppColors.tealSoft : Colors.white,
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
                            'Local model reply',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppColors.tealDark),
                          ),
                        ),
                      if (m.bundle != null &&
                          !m.bundle!.refused &&
                          m.bundle!.guidelines.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Citations',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        ...m.bundle!.guidelines.take(3).map(
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
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_busy,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'e.g. scrub typhus doxycycline',
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
          ),
        ),
      ],
    );
  }
}
