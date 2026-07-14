import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/disclaimer_banner.dart';

class DrugDetailScreen extends StatefulWidget {
  const DrugDetailScreen({
    super.key,
    required this.repository,
    required this.drugId,
    this.initialDrug,
  });

  final ClinicalRepository repository;
  final String drugId;
  final Drug? initialDrug;

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  Drug? _drug;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _drug = widget.initialDrug;
    _load();
  }

  Future<void> _load() async {
    try {
      final drug = await widget.repository.getDrug(widget.drugId);
      if (!mounted) return;
      setState(() {
        _drug = drug;
        _loading = false;
        _error = drug == null ? 'Drug not found in local DB.' : null;
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
    final drug = _drug;
    return ScreenScaffold(
      title: drug?.genericName ?? 'Drug detail',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && drug == null
              ? Center(child: Text(_error!))
              : _DrugBody(drug: drug!),
    );
  }
}

class _DrugBody extends StatelessWidget {
  const _DrugBody({required this.drug});

  final Drug drug;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (drug.genericNameNe != null)
          Text(
            drug.genericNameNe!,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.slate700,
                ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (drug.category != null) _MetaChip(label: drug.category!),
            if (drug.nelmTier != null)
              _MetaChip(label: 'NNLEM ${drug.nelmTier!}'),
            if (drug.pregnancyCategory != null)
              _MetaChip(label: 'Pregnancy ${drug.pregnancyCategory!}'),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Dosage forms',
          child: Text(drug.dosageForms.join(', ')),
        ),
        _Section(
          title: 'Strengths',
          child: Text(drug.strengths.join(', ')),
        ),
        _Section(
          title: 'Brand names (pilot)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: drug.brandNames
                .map(
                  (b) => Text(
                    b.manufacturer == null
                        ? b.name
                        : '${b.name} (${b.manufacturer})',
                  ),
                )
                .toList(),
          ),
        ),
        _Section(
          title: 'Indications',
          child: Text(drug.indications.join('; ')),
        ),
        _Section(
          title: 'Contraindications',
          child: Text(drug.contraindications.join('; ')),
        ),
        _Section(
          title: 'Adult dose',
          child: Text(drug.adultDose ?? '—'),
        ),
        _Section(
          title: 'Pediatric dose',
          child: Text(drug.pediatricDose ?? '—'),
        ),
        _Section(
          title: 'Reference note',
          child: Text(drug.ragText),
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: AppColors.tealSoft,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.tealDark,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: AppColors.slate700,
                  height: 1.45,
                ),
            child: child,
          ),
        ],
      ),
    );
  }
}
