import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'drug_detail_screen.dart';

class DrugSearchScreen extends StatefulWidget {
  const DrugSearchScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<DrugSearchScreen> createState() => _DrugSearchScreenState();
}

class _DrugSearchScreenState extends State<DrugSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Drug> _results = [];
  List<Drug> _featured = [];
  int _corpusCount = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeatured();
  }

  Future<void> _loadFeatured() async {
    try {
      final drugs = await widget.repository.listDrugs(limit: 20);
      if (mounted) {
        setState(() {
          _featured = drugs;
          _corpusCount = widget.repository.drugCorpusCount;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(value));
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final hits = await widget.repository.searchDrugs(q);
      await widget.repository.logSession(
        queryType: 'drug_lookup',
        inputSummary: q,
        outputSummary: hits.isEmpty
            ? 'no hits'
            : hits.take(3).map((d) => d.genericName).join(', '),
        metadata: {
          'hit_count': hits.length,
          'top_drug_ids': hits.take(5).map((d) => d.id).toList(),
          'top_drug_names': hits.take(5).map((d) => d.genericName).toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _results = hits;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openDrug(Drug drug) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrugDetailScreen(
          repository: widget.repository,
          drugId: drug.id,
          initialDrug: drug,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showingSearch = _controller.text.trim().isNotEmpty;
    final list = showingSearch ? _results : _featured;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            decoration: const InputDecoration(
              hintText: 'Search generic, नेपाली नाम, or brand…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            showingSearch
                ? (_loading
                    ? 'Searching…'
                    : '${_results.length} result${_results.length == 1 ? '' : 's'}')
                : _corpusCount > 0
                    ? '$_corpusCount medicines loaded — search any generic (e.g. Lisinopril, Simvastatin)'
                    : 'Search generic, नेपाली नाम, or brand…',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.slate500,
                ),
          ),
          if (!showingSearch && _corpusCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Showing ${_featured.length} of $_corpusCount (A–Z)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.slate500,
                  ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty && showingSearch && !_loading
                ? const Center(child: Text('No drugs matched.'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final drug = list[i];
                      final brands = drug.brandNames
                          .map((b) => b.name)
                          .take(3)
                          .join(', ');
                      return Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.slate200),
                        ),
                        child: ListTile(
                          title: Text(drug.genericName),
                          subtitle: Text(
                            [
                              if (drug.genericNameNe != null)
                                drug.genericNameNe!,
                              if (drug.category != null) drug.category!,
                              if (brands.isNotEmpty) brands,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: drug.nelmTier == null
                              ? null
                              : Chip(
                                  label: Text(
                                    drug.nelmTier!,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: AppColors.tealSoft,
                                  side: BorderSide.none,
                                ),
                          onTap: () => _openDrug(drug),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
