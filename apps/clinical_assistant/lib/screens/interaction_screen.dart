import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/citation_card.dart';

class InteractionScreen extends StatefulWidget {
  const InteractionScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<InteractionScreen> createState() => _InteractionScreenState();
}

class _InteractionScreenState extends State<InteractionScreen> {
  List<Drug> _drugs = [];
  Drug? _drugA;
  Drug? _drugB;
  Interaction? _result;
  List<GuidelineChunk> _suggestions = [];
  bool _checked = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDrugs();
  }

  Future<void> _loadDrugs() async {
    final drugs = await widget.repository.listDrugs(limit: 200);
    if (mounted) setState(() => _drugs = drugs);
  }

  Future<void> _check() async {
    if (_drugA == null || _drugB == null) return;
    if (_drugA!.id == _drugB!.id) {
      setState(() {
        _error = 'Select two different drugs.';
        _checked = false;
        _result = null;
        _suggestions = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ix = await widget.repository.checkInteraction(
        _drugA!.id,
        _drugB!.id,
      );
      var suggestions = <GuidelineChunk>[];
      if (ix == null) {
        final q =
            '${_drugA!.genericName} ${_drugB!.genericName} interaction safety';
        suggestions = await widget.repository.searchGuidelines(q, limit: 3);
      }
      await widget.repository.logSession(
        queryType: 'interaction_check',
        inputSummary: '${_drugA!.id}+${_drugB!.id}',
        outputSummary: ix?.id ?? 'none',
      );
      if (!mounted) return;
      setState(() {
        _result = ix;
        _suggestions = suggestions;
        _checked = true;
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Two-drug interaction check',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Lookup uses the local interaction table in both orderings. '
          'Severity is never invented.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.slate500,
              ),
        ),
        const SizedBox(height: 16),
        _DrugDropdown(
          label: 'Drug A',
          value: _drugA,
          drugs: _drugs,
          onChanged: (d) => setState(() {
            _drugA = d;
            _checked = false;
            _result = null;
            _suggestions = [];
          }),
        ),
        const SizedBox(height: 12),
        _DrugDropdown(
          label: 'Drug B',
          value: _drugB,
          drugs: _drugs,
          onChanged: (d) => setState(() {
            _drugB = d;
            _checked = false;
            _result = null;
            _suggestions = [];
          }),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_drugA != null && _drugB != null && !_loading)
              ? _check
              : null,
          icon: const Icon(Icons.science_outlined),
          label: Text(_loading ? 'Checking…' : 'Check interaction'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        if (_checked) ...[
          const SizedBox(height: 20),
          if (_result == null)
            _NullResultCard(
              a: _drugA!.genericName,
              b: _drugB!.genericName,
              suggestions: _suggestions,
            )
          else
            _InteractionCard(interaction: _result!),
        ],
      ],
    );
  }
}

class _DrugDropdown extends StatelessWidget {
  const _DrugDropdown({
    required this.label,
    required this.value,
    required this.drugs,
    required this.onChanged,
  });

  final String label;
  final Drug? value;
  final List<Drug> drugs;
  final ValueChanged<Drug?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Drug>(
      // ignore: deprecated_member_use — value still valid across Flutter SDKs
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: drugs
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(
                d.genericNameNe == null
                    ? d.genericName
                    : '${d.genericName} (${d.genericNameNe})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _NullResultCard extends StatelessWidget {
  const _NullResultCard({
    required this.a,
    required this.b,
    required this.suggestions,
  });

  final String a;
  final String b;
  final List<GuidelineChunk> suggestions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.slate100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.slate200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No known interaction in local DB',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'No curated row for $a ↔ $b. This is not an all-clear — '
                'absence of data must not be treated as safety. '
                'No severity is invented.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.slate700,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Related guideline citations (retrieval only)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...suggestions.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CitationCard(chunk: g),
              )),
        ],
      ],
    );
  }
}

class _InteractionCard extends StatelessWidget {
  const _InteractionCard({required this.interaction});

  final Interaction interaction;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.severityColor(interaction.severity);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              interaction.severity.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Field(label: 'Mechanism', value: interaction.mechanism),
          _Field(label: 'Clinical effect', value: interaction.clinicalEffect),
          _Field(label: 'Recommendation', value: interaction.recommendation),
          _Field(label: 'Source', value: interaction.source),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.slate500,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(value!),
        ],
      ),
    );
  }
}
