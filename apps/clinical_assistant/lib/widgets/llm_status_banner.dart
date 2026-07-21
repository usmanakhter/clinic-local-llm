import 'package:flutter/material.dart';

import '../llm/local_llm_client.dart';
import '../theme/app_theme.dart';

/// Compact banner showing local LLM reachability for Notes / Chat demos.
class LlmStatusBanner extends StatelessWidget {
  const LlmStatusBanner({
    super.key,
    required this.status,
    this.onRefresh,
    this.checking = false,
  });

  final LlmStatus? status;
  final VoidCallback? onRefresh;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final online = s?.reachable == true;
    final bg = online ? AppColors.tealSoft : AppColors.warningStrip;
    final fg = online ? AppColors.tealDark : AppColors.warningText;
    final label = checking
        ? 'Checking local model…'
        : (s?.shortLabel ?? 'Local model status unknown');
    final detail = checking ? null : s?.message;

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              online ? Icons.memory : Icons.cloud_off_outlined,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (detail != null && detail.isNotEmpty)
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: fg,
                          ),
                    ),
                ],
              ),
            ),
            if (onRefresh != null)
              IconButton(
                tooltip: 'Refresh LLM status',
                onPressed: checking ? null : onRefresh,
                icon: Icon(Icons.refresh, size: 18, color: fg),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
