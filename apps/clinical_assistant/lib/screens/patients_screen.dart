import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Local patient registry — lightweight cards, not a full EMR.
class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  List<Patient> _patients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.listPatients();
      if (!mounted) return;
      setState(() {
        _patients = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openEditor({Patient? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _PatientEditorSheet(
        repository: widget.repository,
        existing: existing,
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _confirmDelete(Patient p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete patient?'),
        content: Text(
          'Remove local record for ${p.displayName} (${p.id})? '
          'Linked activity entries are kept but will show the ID only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.repository.deletePatient(p.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Patients (local registry)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Store ID, name, age, condition, notes, and history on this device. '
            'This is not a full EMR — use your facility record as source of truth.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.slate500,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add patient'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          if (_patients.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.slate100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'No patients yet. Add a local card, then attach the patient '
                'when saving a clinical note.',
              ),
            )
          else
            ..._patients.map(
              (p) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _openEditor(existing: p),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(p),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      Text(
                        'ID: ${p.id}',
                        style: TextStyle(
                          color: AppColors.slate500,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(p.subtitle),
                      if (p.relevantNotes != null &&
                          p.relevantNotes!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppColors.slate500,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(p.relevantNotes!),
                      ],
                      if (p.history != null && p.history!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'History',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppColors.slate500,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(p.history!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PatientEditorSheet extends StatefulWidget {
  const _PatientEditorSheet({
    required this.repository,
    this.existing,
  });

  final ClinicalRepository repository;
  final Patient? existing;

  @override
  State<_PatientEditorSheet> createState() => _PatientEditorSheetState();
}

class _PatientEditorSheetState extends State<_PatientEditorSheet> {
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _sex;
  late final TextEditingController _condition;
  late final TextEditingController _notes;
  late final TextEditingController _history;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(text: e?.id ?? '');
    _name = TextEditingController(text: e?.displayName ?? '');
    _age = TextEditingController(text: e?.age ?? '');
    _sex = TextEditingController(text: e?.sex ?? '');
    _condition = TextEditingController(text: e?.clinicalCondition ?? '');
    _notes = TextEditingController(text: e?.relevantNotes ?? '');
    _history = TextEditingController(text: e?.history ?? '');
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _age.dispose();
    _sex.dispose();
    _condition.dispose();
    _notes.dispose();
    _history.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customId = _id.text.trim();
      await widget.repository.upsertPatient(
        id: widget.existing?.id ??
            (customId.isEmpty ? null : customId),
        displayName: _name.text,
        age: _age.text,
        sex: _sex.text,
        clinicalCondition: _condition.text,
        relevantNotes: _notes.text,
        history: _history.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'Add patient' : 'Edit patient',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              enabled: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'Patient ID (optional — auto if blank)',
                hintText: 'e.g. OPD-1042',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _age,
                    decoration: const InputDecoration(labelText: 'Age'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sex,
                    decoration: const InputDecoration(labelText: 'Sex'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _condition,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Clinical condition',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Relevant notes'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _history,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'History',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save patient'),
            ),
          ],
        ),
      ),
    );
  }
}
