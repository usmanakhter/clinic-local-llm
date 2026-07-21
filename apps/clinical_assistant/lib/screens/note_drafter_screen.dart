import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repositories.dart';
import '../llm/gguf_runtime_factory.dart';
import '../llm/local_llm_client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/llm_status_banner.dart';

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
  final _patientIdManual = TextEditingController();

  /// Notes: GGUF when present, else in-app SOAP assembler (Chat is GGUF-only).
  final _client = LocalLlmClient(gguf: createNativeGgufRuntime());
  List<_SampleNote> _samples = [];
  List<Patient> _patients = [];
  Patient? _selectedPatient;
  bool _loading = false;
  String? _status;
  bool _fromModel = false;
  bool _saving = false;
  String? _saveMessage;
  LlmStatus? _llmStatus;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _loadSamples();
    _loadPatients();
    _probeLlm();
  }

  Future<void> _probeLlm() async {
    setState(() => _probing = true);
    final s = await _client.probeNotes();
    if (!mounted) return;
    setState(() {
      _llmStatus = s;
      _probing = false;
    });
  }

  @override
  void dispose() {
    _cc.dispose();
    _hx.dispose();
    _exam.dispose();
    _assess.dispose();
    _plan.dispose();
    _draft.dispose();
    _patientIdManual.dispose();
    super.dispose();
  }

  Future<void> _loadPatients() async {
    final list = await widget.repository.listPatients();
    if (!mounted) return;
    setState(() => _patients = list);
  }

  String? get _resolvedPatientId {
    if (_selectedPatient != null) return _selectedPatient!.id;
    final manual = _patientIdManual.text.trim();
    return manual.isEmpty ? null : manual;
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
      _status = 'Sample ${s.id} loaded — tap Generate draft';
      _fromModel = false;
    });
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _status = 'Drafting in-app…';
    });
    try {
      final text = await _client.draftNote(
        chiefComplaint: _cc.text,
        history: _hx.text,
        examination: _exam.text,
        assessment: _assess.text,
        plan: _plan.text,
      );
      _draft.text = text;
      final status = await _client.probe();
      await widget.repository.logSession(
        queryType: 'note_draft',
        inputSummary: _cc.text,
        outputSummary: 'generated',
        patientId: _resolvedPatientId,
        metadata: {
          'action': 'generate',
          'from_model': true,
          'backend': status.backend.name,
          'model': status.model,
          'patient_id': _resolvedPatientId,
          'draft_preview':
              text.length > 300 ? '${text.substring(0, 300)}…' : text,
        },
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fromModel = true;
        _llmStatus = status;
        _status =
            'Draft from ${status.shortLabel}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fromModel = false;
        _status = 'Draft failed: $e';
      });
    }
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
        patientId: _resolvedPatientId,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = 'Saved locally — view in Past Notes.';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LlmStatusBanner(
          status: _llmStatus,
          checking: _probing,
          onRefresh: _probeLlm,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Note draft (in-app or GGUF)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Uses on-device GGUF when present; otherwise the in-app SOAP '
                'assembler. Draft only; interaction severity is never invented. '
                'Chat still requires a local GGUF (no rules fallback).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.slate500,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Patient?>(
                // ignore: deprecated_member_use
                value: _selectedPatient,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Patient (from local registry)',
                ),
                items: [
                  const DropdownMenuItem<Patient?>(
                    value: null,
                    child: Text('None / enter ID below'),
                  ),
                  ..._patients.map(
                    (p) => DropdownMenuItem<Patient?>(
                      value: p,
                      child: Text(
                        '${p.displayName} (${p.id})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (p) => setState(() {
                  _selectedPatient = p;
                  if (p != null) _patientIdManual.text = p.id;
                }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _patientIdManual,
                enabled: _selectedPatient == null,
                decoration: const InputDecoration(
                  labelText: 'Patient ID',
                  hintText: 'Required for linked notes — e.g. OPD-1042',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (_samples.isNotEmpty)
                DropdownButtonFormField<_SampleNote>(
                  // ignore: deprecated_member_use
                  value: null,
                  decoration:
                      const InputDecoration(labelText: 'Load synthetic sample'),
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
                    color:
                        _fromModel ? AppColors.tealDark : AppColors.warningText,
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
          ),
        ),
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
