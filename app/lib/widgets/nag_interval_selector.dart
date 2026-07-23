import 'package:flutter/material.dart';

import '../state/settings_store.dart';

/// "Tamamlanmazsa kaç saatte bir tekrar hatırlat" seçimi.
///
/// Hem sihirbazda hem düzenleme formunda kullanılır; seçenek listesi tek
/// yerden ([SettingsStore.nagIntervalOptions]) gelir.
class NagIntervalSelector extends StatelessWidget {
  const NagIntervalSelector({
    super.key,
    required this.valueHours,
    required this.onChanged,
  });

  /// 0 = tekrar hatırlatma kapalı.
  final int valueHours;
  final ValueChanged<int> onChanged;

  static String labelFor(int hours) =>
      hours == 0 ? 'Kapalı' : '$hours saatte bir';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in SettingsStore.nagIntervalOptions)
          ChoiceChip(
            label: Text(labelFor(option)),
            selected: valueHours == option,
            onSelected: (_) => onChanged(option),
            labelStyle: TextStyle(
              fontSize: 15,
              fontWeight: valueHours == option
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
            // Dokunma hedefini HIG alt sınırına yaklaştırır; varsayılan chip
            // yüksekliği 32pt'de kalıyor.
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            side: BorderSide(color: scheme.outlineVariant),
          ),
      ],
    );
  }
}
