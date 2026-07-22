import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../models/repeat_interval.dart';
import '../theme/app_theme.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onTap,
    required this.onComplete,
  });

  final Reminder reminder;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = reminder.category;
    final days = reminder.daysRemaining;
    final accent = urgencyColor(scheme, days);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(category.icon, color: category.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          label: urgencyLabel(days),
                          color: accent,
                          filled: true,
                        ),
                        _Pill(
                          label: DateFormat('d MMM yyyy', 'tr_TR')
                              .format(reminder.dueDate),
                          color: scheme.onSurfaceVariant,
                        ),
                        if (reminder.amount != null)
                          _Pill(
                            label: NumberFormat.currency(
                              locale: 'tr_TR',
                              symbol: '₺',
                              decimalDigits: 0,
                            ).format(reminder.amount),
                            color: scheme.onSurfaceVariant,
                          ),
                        if (reminder.repeat != RepeatInterval.none)
                          _Pill(
                            label: reminder.repeat.label,
                            color: scheme.onSurfaceVariant,
                            icon: Icons.repeat,
                          ),
                        if (reminder.photoPaths.isNotEmpty)
                          _Pill(
                            label: '${reminder.photoPaths.length} belge',
                            color: scheme.onSurfaceVariant,
                            icon: Icons.photo_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onComplete,
                tooltip: reminder.repeat == RepeatInterval.none
                    ? 'Tamamlandı olarak işaretle'
                    : 'Ödendi, sonraki döneme taşı',
                icon: const Icon(Icons.check_circle_outline),
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    this.filled = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
