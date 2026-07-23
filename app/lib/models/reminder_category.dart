import 'package:flutter/material.dart';

import 'repeat_interval.dart';

/// Hatırlatma kategorileri. Kategoriler sabittir; her biri kendi varsayılan
/// tekrar aralığını ve "kaç gün önce" önerisini taşır.
class ReminderCategory {
  const ReminderCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.defaultRepeat,
    required this.defaultLeadDays,
    required this.hint,
    this.suggestions = const [],
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final RepeatInterval defaultRepeat;
  final List<int> defaultLeadDays;

  /// Başlık alanının örnek metni.
  final String hint;

  /// Tek dokunuşla seçilebilen hazır başlıklar. Sihirbazda klavye açmadan
  /// ilerlemeyi mümkün kılar — yazması zor olan kullanıcılar için önemli.
  final List<String> suggestions;

  static const List<ReminderCategory> all = [
    ReminderCategory(
      id: 'vehicle_inspection',
      label: 'Araç Muayenesi',
      icon: Icons.directions_car_filled_outlined,
      color: Color(0xFF2F6FED),
      defaultRepeat: RepeatInterval.yearly,
      defaultLeadDays: [30, 7, 1],
      hint: 'Örn. 34 ABC 123 muayene',
      suggestions: ['Araç muayenesi', 'İkinci araç muayenesi'],
    ),
    ReminderCategory(
      id: 'traffic_insurance',
      label: 'Trafik Sigortası',
      icon: Icons.shield_outlined,
      color: Color(0xFF1AA179),
      defaultRepeat: RepeatInterval.yearly,
      defaultLeadDays: [30, 7, 1],
      hint: 'Örn. Trafik poliçesi yenileme',
      suggestions: ['Trafik sigortası', 'Poliçe yenileme'],
    ),
    ReminderCategory(
      id: 'kasko',
      label: 'Kasko',
      icon: Icons.car_crash_outlined,
      color: Color(0xFF12897A),
      defaultRepeat: RepeatInterval.yearly,
      defaultLeadDays: [30, 7, 1],
      hint: 'Örn. Kasko yenileme',
      suggestions: ['Kasko', 'Kasko yenileme'],
    ),
    ReminderCategory(
      id: 'identity',
      label: 'Ehliyet / Kimlik / Pasaport',
      icon: Icons.badge_outlined,
      color: Color(0xFF7A4FD1),
      defaultRepeat: RepeatInterval.none,
      defaultLeadDays: [60, 30, 7],
      hint: 'Örn. Pasaport son geçerlilik',
      suggestions: ['Ehliyet', 'Kimlik kartı', 'Pasaport'],
    ),
    ReminderCategory(
      id: 'rent',
      label: 'Kira Ödemesi',
      icon: Icons.home_work_outlined,
      color: Color(0xFFD1663F),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [3, 1],
      hint: 'Örn. Ev kirası',
      suggestions: ['Ev kirası', 'Dükkân kirası'],
    ),
    ReminderCategory(
      id: 'bill',
      label: 'Fatura',
      icon: Icons.receipt_long_outlined,
      color: Color(0xFFC94F7C),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [3, 1],
      hint: 'Örn. Elektrik faturası',
      suggestions: [
        'Elektrik faturası',
        'Su faturası',
        'Doğalgaz faturası',
        'İnternet faturası',
        'Telefon faturası',
      ],
    ),
    ReminderCategory(
      id: 'dues',
      label: 'Aidat',
      icon: Icons.apartment_outlined,
      color: Color(0xFF5B6B8C),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [3, 1],
      hint: 'Örn. Apartman aidatı',
      suggestions: ['Apartman aidatı', 'Site aidatı'],
    ),
    ReminderCategory(
      id: 'subscription',
      label: 'Dijital Abonelik',
      icon: Icons.play_circle_outline,
      color: Color(0xFF8A6BD1),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [3, 1],
      hint: 'Örn. Netflix üyeliği',
      suggestions: [
        'Netflix',
        'YouTube Premium',
        'Spotify',
        'Amazon Prime',
        'Disney+',
        'iCloud / Google One',
      ],
    ),
    ReminderCategory(
      id: 'credit_card',
      label: 'Kredi Kartı Ödemesi',
      icon: Icons.credit_card,
      color: Color(0xFF2E7D8A),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [5, 2, 1],
      hint: 'Örn. Bankamatik kartı ekstresi',
      suggestions: ['Kredi kartı ekstresi', 'İkinci kart ekstresi'],
    ),
    ReminderCategory(
      id: 'loan',
      label: 'Kredi / Taksit Ödemesi',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFFB5562E),
      defaultRepeat: RepeatInterval.monthly,
      defaultLeadDays: [5, 2, 1],
      hint: 'Örn. Konut kredisi taksiti',
      suggestions: [
        'Konut kredisi',
        'Taşıt kredisi',
        'İhtiyaç kredisi',
        'Alışveriş taksiti',
      ],
    ),
    ReminderCategory(
      id: 'warranty',
      label: 'Garanti Bitişi',
      icon: Icons.verified_outlined,
      color: Color(0xFF3F8AD1),
      defaultRepeat: RepeatInterval.none,
      defaultLeadDays: [30, 7],
      hint: 'Örn. Buzdolabı garantisi',
      suggestions: [
        'Buzdolabı garantisi',
        'Çamaşır makinesi garantisi',
        'Televizyon garantisi',
        'Telefon garantisi',
      ],
    ),
    ReminderCategory(
      id: 'tax',
      label: 'Vergi ve Harç',
      icon: Icons.account_balance_outlined,
      color: Color(0xFF9C7A2E),
      defaultRepeat: RepeatInterval.yearly,
      defaultLeadDays: [15, 7, 1],
      hint: 'Örn. MTV 2. taksit',
      suggestions: [
        'Motorlu taşıtlar vergisi',
        'Emlak vergisi',
        'Gelir vergisi',
      ],
    ),
    ReminderCategory(
      id: 'other',
      label: 'Diğer',
      icon: Icons.event_note_outlined,
      color: Color(0xFF6B7280),
      defaultRepeat: RepeatInterval.none,
      defaultLeadDays: [7, 1],
      hint: 'Neyi hatırlatalım?',
    ),
  ];

  static ReminderCategory byId(String id) {
    return all.firstWhere((c) => c.id == id, orElse: () => all.last);
  }
}
