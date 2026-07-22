import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Tappable field that opens a searchable full-drug picker sheet.
class DrugPickerField extends StatelessWidget {
  const DrugPickerField({
    super.key,
    required this.label,
    required this.repository,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final ClinicalRepository repository;
  final Drug? value;
  final ValueChanged<Drug?> onChanged;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Drug>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _DrugPickerSheet(
        repository: repository,
        title: label,
        selectedId: value?.id,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = value == null
        ? 'Tap to search medicines…'
        : [
            if (value!.genericNameNe != null) value!.genericNameNe!,
            if (value!.category != null) value!.category!,
          ].join(' · ');

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
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
                    const SizedBox(height: 4),
                    Text(
                      value?.genericName ?? 'Select drug',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: value == null
                                ? AppColors.slate500
                                : AppColors.slate700,
                          ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.slate500,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null)
                IconButton(
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear, size: 20),
                ),
              const Icon(Icons.search, color: AppColors.slate500),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrugPickerSheet extends StatefulWidget {
  const _DrugPickerSheet({
    required this.repository,
    required this.title,
    this.selectedId,
  });

  final ClinicalRepository repository;
  final String title;
  final String? selectedId;

  @override
  State<_DrugPickerSheet> createState() => _DrugPickerSheetState();
}

class _DrugPickerSheetState extends State<_DrugPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Drug> _all = [];
  List<Drug> _visible = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drugs = await widget.repository.listDrugs();
    if (!mounted) return;
    setState(() {
      _all = drugs;
      _visible = drugs;
      _loading = false;
    });
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () async {
      final q = value.trim();
      if (q.isEmpty) {
        if (mounted) setState(() => _visible = _all);
        return;
      }
      final hits = await widget.repository.searchDrugs(q, limit: 500);
      if (!mounted) return;
      setState(() => _visible = hits);
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
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onQuery,
              decoration: const InputDecoration(
                hintText: 'Search generic, नेपाली नाम, or brand…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _loading
                  ? 'Loading…'
                  : '${_visible.length} medicine${_visible.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.slate500,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visible.isEmpty
                    ? const Center(child: Text('No drugs matched.'))
                    : ListView.separated(
                        itemCount: _visible.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.slate200),
                        itemBuilder: (context, i) {
                          final drug = _visible[i];
                          final selected = drug.id == widget.selectedId;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: AppColors.tealSoft,
                            title: Text(drug.genericName),
                            subtitle: Text(
                              [
                                if (drug.genericNameNe != null)
                                  drug.genericNameNe!,
                                if (drug.category != null) drug.category!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? const Icon(Icons.check, color: AppColors.teal)
                                : null,
                            onTap: () => Navigator.pop(context, drug),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
