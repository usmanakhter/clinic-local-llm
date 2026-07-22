import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/citation_card.dart';

class GuidelinesScreen extends StatefulWidget {
  const GuidelinesScreen({super.key, required this.repository});

  final ClinicalRepository repository;

  @override
  State<GuidelinesScreen> createState() => _GuidelinesScreenState();
}

class _GuidelinesScreenState extends State<GuidelinesScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<OpdCondition> _allConditions = [];
  List<OpdCondition> _visibleConditions = [];
  List<GuidelineChunk> _guidelineHits = [];
  bool _loadingConditions = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConditions();
  }

  Future<void> _loadConditions() async {
    try {
      final conditions = await widget.repository.listOpdConditions();
      if (!mounted) return;
      setState(() {
        _allConditions = conditions;
        _visibleConditions = conditions;
        _loadingConditions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingConditions = false;
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _applyQuery(value));
  }

  Future<void> _applyQuery(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _visibleConditions = _allConditions;
        _guidelineHits = [];
        _searching = false;
      });
      return;
    }

    final lower = q.toLowerCase();
    final filtered = _allConditions
        .where((c) => c.name.toLowerCase().contains(lower))
        .toList();

    setState(() {
      _searching = true;
      _visibleConditions = filtered;
    });

    final hits = await widget.repository.searchGuidelines(q, limit: 100);
    await widget.repository.logSession(
      queryType: 'guideline_search',
      inputSummary: q,
      outputSummary: hits.isEmpty
          ? 'no hits'
          : hits.take(3).map((g) => g.title).join(', '),
      metadata: {
        'hit_count': hits.length,
        'condition_hit_count': filtered.length,
        'chunk_ids': hits.take(5).map((g) => g.id).toList(),
        'titles': hits.take(5).map((g) => g.title).toList(),
      },
    );
    if (!mounted) return;
    setState(() {
      _guidelineHits = hits;
      _searching = false;
    });
  }

  Future<void> _openCondition(OpdCondition condition) async {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _ConditionDetailDialog(
        repository: widget.repository,
        condition: condition,
      ),
    );
    await widget.repository.logSession(
      queryType: 'guideline_condition',
      inputSummary: condition.name,
      outputSummary: condition.id,
      metadata: {
        'condition_id': condition.id,
        'expected_guideline_ids': condition.expectedGuidelineIds,
      },
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
    final querying = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Filter conditions or search guidelines…',
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _loadingConditions
                ? 'Loading conditions…'
                : querying
                    ? (_searching
                        ? 'Searching…'
                        : '${_visibleConditions.length} condition(s) · ${_guidelineHits.length} citation(s)')
                    : '${_allConditions.length} OPD conditions (A–Z) — tap for guidelines',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.slate500,
                ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _loadingConditions
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      if (_visibleConditions.isEmpty && querying)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            'No matching conditions.',
                            style: TextStyle(color: AppColors.slate500),
                          ),
                        ),
                      ..._visibleConditions.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: AppColors.slate200),
                            ),
                            child: ListTile(
                              title: Text(c.name),
                              subtitle: Text(
                                c.covered
                                    ? 'Covered in local corpus'
                                    : 'Checklist entry',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openCondition(c),
                            ),
                          ),
                        ),
                      ),
                      if (querying && _guidelineHits.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Guideline citations',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        ..._guidelineHits.asMap().entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: CitationCard(
                                  chunk: e.value,
                                  initiallyExpanded: e.key == 0,
                                ),
                              ),
                            ),
                      ],
                      if (querying &&
                          _visibleConditions.isEmpty &&
                          _guidelineHits.isEmpty &&
                          !_searching)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Center(
                            child: Text(
                              'No matching guidelines.',
                              style: TextStyle(color: AppColors.slate500),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConditionDetailDialog extends StatefulWidget {
  const _ConditionDetailDialog({
    required this.repository,
    required this.condition,
  });

  final ClinicalRepository repository;
  final OpdCondition condition;

  @override
  State<_ConditionDetailDialog> createState() => _ConditionDetailDialogState();
}

class _ConditionDetailDialogState extends State<_ConditionDetailDialog> {
  List<GuidelineChunk> _chunks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final byId = await widget.repository
        .getGuidelinesByIds(widget.condition.expectedGuidelineIds);
    var chunks = byId;
    if (chunks.isEmpty) {
      chunks = await widget.repository.searchGuidelines(
        widget.condition.name,
        limit: 8,
      );
    }
    if (!mounted) return;
    setState(() {
      _chunks = chunks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.condition.name),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _chunks.isEmpty
                ? const Text(
                    'No local guideline chunks linked for this condition.',
                  )
                : SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _chunks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => CitationCard(
                        chunk: _chunks[i],
                        initiallyExpanded: i == 0,
                      ),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
