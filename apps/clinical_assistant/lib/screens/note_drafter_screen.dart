import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repositories.dart';
import '../llm/local_llm_client.dart';
import '../theme/app_theme.dart';

class NoteDrafterScreen extends StatefulWidget {
  const NoteDrafterScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<NoteDrafterScreen> createState() => _NoteDrafterScreenState();
}

class _NoteDrafterScreenState extends State<NoteDrafterScreen> {
  final _cc = TextEditingController();
  final _hx = TextEditingController();
  final _exam = TextEditingController();
  final _assess = TextEditingController();
  final _plan = TextEditingController();
  final _draft = TextEditingController();

  final _client = LocalLlmClient();
  List<_SampleNote> _samples = [];
  bool _loading = false;
  String? _status;
  bool _fromModel = false;
  bool _saving = false;
  String? _saveMessage;

  @override
  void initState() {
    super.initState();
    _loadSamples();
  }

  @override
  void dispose() {
    _cc.dispose();
    _hx.dispose();
    _exam.dispose();
    _assess.dispose();
    _plan.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _loadSamples() async {
    try {
      final raw =
          await rootBundle.loadString('assets/nepal/note_drafter_samples.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = (json['samples'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => _SampleNote.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (!mounted) return;
      setState(() => _samples = list);
      if (list.isNotEmpty) _applySample(list.first);
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not load samples: $e');
    }
  }

  void _applySample(_SampleNote s) {
    _cc.text = s.chiefComplaint;
    _hx.text = s.history;
    _exam.text = s.examination;
    _assess.text = s.assessment;
    _plan.text = s.plan;
    _draft.clear();
    setState(() {
      _status = 'Sample ${s.id} loaded — generate with local model or fallback';
      _fromModel = false;
    });
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _status = 'Contacting local model…';
    });
    try {
      final available = await _client.isAvailable();
      if (!available) {
        await _useFallback(
          kIsWeb
              ? 'Local model unavailable. On web: start Ollama + '
                  '`python tools/ollama_cors_proxy.py`, then retry. Using fixture draft.'
              : 'Local model unavailable — start Ollama (`ollama serve` + '
                  '`ollama pull qwen2.5:1.5b`). Using fixture draft.',
        );
        return;
      }
      final text = await _client.draftNote(
        chiefComplaint: _cc.text,
        history: _hx.text,
        examination: _exam.text,
        assessment: _assess.text,
        plan: _plan.text,
      );
      _draft.text = text;
      await widget.repository.logSession(
        queryType: 'note_draft',
        inputSummary: _cc.text,
        outputSummary: 'generated',
        metadata: {
          'action': 'generate',
          'from_model': true,
          'draft_preview':
              text.length > 300 ? '${text.substring(0, 300)}…' : text,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fromModel = true;
        _status = 'Draft from local model (${_client.model})';
      });
    } catch (e) {
      await _useFallback(
        'Local model error — using fixture draft. ($e)',
      );
    }
  }

  Future<void> _useFallback(String message) async {
    _SampleNote? match;
    for (final s in _samples) {
      if (s.chiefComplaint.trim().toLowerCase() ==
          _cc.text.trim().toLowerCase()) {
        match = s;
        break;
      }
    }
    match ??= _samples.isEmpty ? null : _samples.first;
    final text = match?.draftOutput ??
        'Draft only — clinician must review. Not for clinical use.\n'
            'CC: ${_cc.text}\nHPC: ${_hx.text}\nO/E: ${_exam.text}\n'
            'Impression: ${_assess.text}\nPlan: ${_plan.text}';
    _draft.text = text;
    await widget.repository.logSession(
      queryType: 'note_draft',
      inputSummary: _cc.text,
      outputSummary: 'fixture_fallback',
      metadata: const {'action': 'generate', 'from_model': false},
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _fromModel = false;
      _status = message;
    });
  }

  Future<void> _saveLocally() async {
    if (_draft.text.trim().isEmpty) {
      setState(() => _saveMessage = 'Generate or enter a draft before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      await widget.repository.saveNoteDraft(
        chiefComplaint: _cc.text,
        history: _hx.text,
        examination: _exam.text,
        assessment: _assess.text,
        plan: _plan.text,
        draftText: _draft.text,
        fromModel: _fromModel,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = 'Saved locally — view in Activity tab.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Note draft (local LLM POC)',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Draft only — not diagnosis or prescribing. Interaction severity is '
          'never invented by the model. Calls localhost only (Ollama).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.slate500,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 12),
        if (_samples.isNotEmpty)
          DropdownButtonFormField<_SampleNote>(
            // ignore: deprecated_member_use
            value: null,
            decoration: const InputDecoration(labelText: 'Load synthetic sample'),
            items: _samples
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s.id} · ${s.chiefComplaint}',
                        overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (s) {
              if (s != null) _applySample(s);
            },
          ),
        const SizedBox(height: 12),
        _field(_cc, 'Chief complaint'),
        _field(_hx, 'History'),
        _field(_exam, 'Examination'),
        _field(_assess, 'Assessment'),
        _field(_plan, 'Plan'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _loading ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_loading ? 'Drafting…' : 'Generate draft'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 10),
          Text(
            _status!,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _fromModel ? AppColors.tealDark : AppColors.warningText,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _draft,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Editable draft',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _saving ? null : _saveLocally,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving…' : 'Save locally'),
        ),
        if (_saveMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _saveMessage!,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: _saveMessage!.startsWith('Save failed')
                  ? AppColors.danger
                  : AppColors.tealDark,
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: 2,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _SampleNote {
  _SampleNote({
    required this.id,
    required this.chiefComplaint,
    required this.history,
    required this.examination,
    required this.assessment,
    required this.plan,
    required this.draftOutput,
  });

  final String id;
  final String chiefComplaint;
  final String history;
  final String examination;
  final String assessment;
  final String plan;
  final String draftOutput;

  factory _SampleNote.fromJson(Map<String, dynamic> json) {
    final input = json['structured_input'] as Map<String, dynamic>? ?? {};
    return _SampleNote(
      id: json['id'] as String? ?? '',
      chiefComplaint: input['chief_complaint'] as String? ?? '',
      history: input['history'] as String? ?? '',
      examination: input['examination'] as String? ?? '',
      assessment: input['assessment'] as String? ?? '',
      plan: input['plan'] as String? ?? '',
      draftOutput: json['draft_output'] as String? ?? '',
    );
  }
}
