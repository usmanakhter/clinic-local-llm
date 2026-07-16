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
  List<GuidelineChunk> _results = [];
  bool _loading = false;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _search(value));
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final hits = await widget.repository.searchGuidelines(q);
    await widget.repository.logSession(
      queryType: 'guideline_search',
      inputSummary: q,
      outputSummary: hits.isEmpty
          ? 'no hits'
          : hits.take(3).map((g) => g.id).join(','),
    );
    if (!mounted) return;
    setState(() {
      _results = hits;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Search guidelines (EN / नेपाली)…',
              prefixIcon: Icon(Icons.menu_book_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _controller.text.trim().isEmpty
                ? 'Try: typhoid, dengue, TB, snakebite, diarrhea'
                : (_loading
                    ? 'Searching…'
                    : '${_results.length} citation(s) — source + excerpt'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.slate500,
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _controller.text.trim().isEmpty
                          ? 'Enter a keyword to search local guideline chunks.'
                          : 'No matching guidelines.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.slate500),
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => CitationCard(
                      chunk: _results[i],
                      initiallyExpanded: i == 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
