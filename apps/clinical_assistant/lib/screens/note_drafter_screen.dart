import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repositories.dart';
import '../llm/gguf_runtime_factory.dart';
import '../llm/local_llm_client.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/llm_status_banner.dart';

/// Notes: draft editor + saved past notes in one place.
class NoteDrafterScreen extends StatefulWidget {
  const NoteDrafterScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<NoteDrafterScreen> createState() => _NoteDrafterScreenState();
}

enum _NotesSegment { draft, past }

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
  List<ClinicalSession> _pastNotes = [];
  Map<String, Patient> _patientsById = {};
  /// Dropdown value must be an id string — Patient object identity breaks after reload.
  String? _selectedPatientId;
  bool _loading = false;
  String? _status;
  bool _fromModel = false;
  bool _saving = false;
  String? _saveMessage;
  LlmStatus? _llmStatus;
  bool _probing = false;
  _NotesSegment _segment = _NotesSegment.draft;
  String? _editingSessionId;
  String? _expandedId;
  bool _pastLoading = false;
  int _pendingSync = 0;

  @override
  void initState() {
    super.initState();
    _loadSamples();
    _loadPatients();
    _probeLlm();
    _reloadPastNotes();
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
    setState(() {
      _patients = list;
      _patientsById = {for (final p in list) p.id: p};
    });
  }

  Future<void> _reloadPastNotes() async {
    setState(() => _pastLoading = true);
    final sessions = await widget.repository.listSessions(limit: 200);
    final patients = await widget.repository.listPatients();
    final pending = await widget.repository.pendingSyncCount();
    if (!mounted) return;
    setState(() {
      // Explicit saves only — generate no longer writes local history.
      _pastNotes = sessions
          .where(
            (s) =>
                s.queryType == 'note_draft' &&
                (s.outputSummary == 'saved_locally' ||
                    s.payload?['action'] == 'save'),
          )
          .toList();
      _patientsById = {for (final p in patients) p.id: p};
      _patients = patients;
      _pendingSync = pending;
      _pastLoading = false;
    });
  }

  String? get _resolvedPatientId {
    final selectedId = _selectedPatientId;
    if (selectedId != null && selectedId.isNotEmpty) return selectedId;
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
      _editingSessionId = null;
      _status = 'Sample ${s.id} loaded — tap Generate draft';
      _fromModel = false;
      _saveMessage = null;
    });
  }

  void _clearEditor({bool keepPatient = false}) {
    _cc.clear();
    _hx.clear();
    _exam.clear();
    _assess.clear();
    _plan.clear();
    _draft.clear();
    if (!keepPatient) {
      _selectedPatientId = null;
      _patientIdManual.clear();
    }
    setState(() {
      _editingSessionId = null;
      _fromModel = false;
      _status = null;
      _saveMessage = null;
    });
  }

  void _loadNoteForEdit(ClinicalSession s) {
    final meta = s.payload ?? {};
    String field(String key) {
      final v = meta[key];
      return v is String ? v : '';
    }

    _cc.text = field('chief_complaint').isNotEmpty
        ? field('chief_complaint')
        : (s.inputSummary ?? '');
    _hx.text = field('history');
    _exam.text = field('examination');
    _assess.text = field('assessment');
    _plan.text = field('plan');
    _draft.text = field('draft_text');
    final pid = s.patientId ?? field('patient_id');
    if (pid.isNotEmpty) {
      _patientIdManual.text = pid;
      _selectedPatientId = _patientsById.containsKey(pid) ? pid : null;
    } else {
      _patientIdManual.clear();
      _selectedPatientId = null;
    }
    setState(() {
      _editingSessionId = s.id;
      _fromModel = meta['from_model'] == true;
      _segment = _NotesSegment.draft;
      _status = 'Editing saved note — Save to update';
      _saveMessage = null;
    });
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _status = 'Drafting… $kGgufLatencyNote';
      _saveMessage = null;
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
      final status = await _client.probeNotes();
      // Intentionally do NOT persist on generate — only explicit Save.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fromModel = true;
        _llmStatus = status;
        _status =
            'Draft from ${status.shortLabel} — not saved until you tap Save';
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
        sessionId: _editingSessionId,
      );
      if (!mounted) return;
      final edited = _editingSessionId != null;
      setState(() {
        _saving = false;
        _saveMessage = edited
            ? 'Updated locally.'
            : 'Saved locally — see Saved notes.';
        if (!edited) _editingSessionId = null;
      });
      await _reloadPastNotes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMessage = 'Save failed: $e';
      });
    }
  }

  Future<void> _copyPastNotes() async {
    final buf = StringBuffer();
    for (final s in _pastNotes) {
      buf.writeln(_readableExport(s));
      buf.writeln('---');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied saved notes to clipboard')),
    );
  }

  String _readableExport(ClinicalSession s) {
    final patient = _patientLabel(s);
    final lines = <String>[
      'Note · ${_formatTime(s.createdAt)}',
      if (patient != null) 'Patient: $patient',
      if (s.inputSummary != null && s.inputSummary!.isNotEmpty)
        'Chief complaint: ${s.inputSummary}',
      ..._detailLines(s).map((e) => '${e.$1}: ${e.$2}'),
    ];
    return lines.join('\n');
  }

  String? _patientLabel(ClinicalSession s) {
    final id = s.patientId;
    if (id == null || id.isEmpty) return null;
    final p = _patientsById[id];
    if (p == null) return id;
    return '${p.displayName} ($id)';
  }

  List<(String, String)> _detailLines(ClinicalSession s) {
    final meta = s.payload;
    final out = <(String, String)>[];
    if (meta == null) {
      if (s.outputSummary != null &&
          s.outputSummary!.isNotEmpty &&
          s.outputSummary != 'saved_locally') {
        out.add(('Result', s.outputSummary!));
      }
      return out;
    }

    void add(String label, String key) {
      final v = meta[key];
      if (v is String && v.trim().isNotEmpty) out.add((label, v.trim()));
    }

    add('Chief complaint', 'chief_complaint');
    add('History', 'history');
    add('Examination', 'examination');
    add('Assessment', 'assessment');
    add('Plan', 'plan');
    add('Draft', 'draft_text');
    return out;
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_NotesSegment>(
            segments: const [
              ButtonSegment(
                value: _NotesSegment.draft,
                label: Text('Draft'),
                icon: Icon(Icons.edit_note, size: 18),
              ),
              ButtonSegment(
                value: _NotesSegment.past,
                label: Text('Saved notes'),
                icon: Icon(Icons.history, size: 18),
              ),
            ],
            selected: {_segment},
            onSelectionChanged: (s) {
              setState(() => _segment = s.first);
              if (s.first == _NotesSegment.past) _reloadPastNotes();
            },
          ),
        ),
        Expanded(
          child: _segment == _NotesSegment.draft
              ? _buildDraftPane()
              : _buildPastPane(),
        ),
      ],
    );
  }

  Widget _buildDraftPane() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _editingSessionId == null ? 'New note draft' : 'Edit saved note',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Generate fills the draft on screen only. Tap Save locally to store '
          'it on this device. Interaction severity is never invented.\n'
          '$kGgufLatencyNote '
          'Without a GGUF, Notes fall back to the fast in-app assembler.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.slate500,
                height: 1.35,
              ),
        ),
        if (_editingSessionId != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _clearEditor(),
            icon: const Icon(Icons.add),
            label: const Text('Start new note'),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          // ignore: deprecated_member_use
          value: _patientsById.containsKey(_selectedPatientId)
              ? _selectedPatientId
              : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Patient (from local registry)',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('None / enter ID below'),
            ),
            ..._patients.map(
              (p) => DropdownMenuItem<String?>(
                value: p.id,
                child: Text(
                  '${p.displayName} (${p.id})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (id) => setState(() {
            _selectedPatientId = id;
            if (id != null) _patientIdManual.text = id;
          }),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _patientIdManual,
          enabled: _selectedPatientId == null,
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
          label: Text(
            _saving
                ? 'Saving…'
                : (_editingSessionId != null
                    ? 'Update saved note'
                    : 'Save locally'),
          ),
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

  Widget _buildPastPane() {
    if (_pastLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _reloadPastNotes,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Saved notes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Notes you explicitly saved on this device. Generate does not '
            'auto-save. $_pendingSync item(s) queued for server sync.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.slate500,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pastNotes.isEmpty ? null : _copyPastNotes,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy saved notes'),
          ),
          const SizedBox(height: 16),
          if (_pastNotes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'No saved notes yet. Generate a draft, then tap Save locally.',
              ),
            )
          else
            ..._pastNotes.map(_pastNoteCard),
        ],
      ),
    );
  }

  Widget _pastNoteCard(ClinicalSession s) {
    final expanded = _expandedId == s.id;
    final patient = _patientLabel(s);
    final details = _detailLines(s);
    final preview = details.isNotEmpty
        ? details.first.$2
        : (s.inputSummary ?? s.outputSummary ?? '');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() {
                _expandedId = expanded ? null : s.id;
              }),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.tealSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Note',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.tealDark,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatTime(s.createdAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.slate500,
                            ),
                      ),
                    ],
                  ),
                  if (patient != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: AppColors.tealDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            patient,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.tealDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!expanded && preview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.slate500, fontSize: 13),
                    ),
                  ],
                  if (expanded) ...[
                    const SizedBox(height: 10),
                    if (details.isEmpty)
                      Text(
                        s.outputSummary ?? 'No further details.',
                        style: const TextStyle(color: AppColors.slate700),
                      )
                    else
                      ...details.map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.$1,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: AppColors.slate500,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(d.$2),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _loadNoteForEdit(s),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                Text(
                  expanded ? 'Tap card to collapse' : 'Tap card for details',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.slate500,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
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

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $h:$m';
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
