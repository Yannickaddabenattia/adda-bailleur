import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Badge visuel indiquant qu'un champ est figé définitivement.
class ImmutableBadge extends StatelessWidget {
  const ImmutableBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 12, color: AppColors.accent),
          SizedBox(width: 4),
          Text(
            'FIGÉ',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
