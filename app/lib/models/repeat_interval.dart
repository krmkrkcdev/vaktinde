/// Bir hatırlatmanın son tarihi geçtiğinde otomatik olarak ne kadar
/// ileri taşınacağını belirler.
enum RepeatInterval {
  none('none', 'Tekrar yok'),
  hourly('hourly', 'Saat başı'),
  daily('daily', 'Her gün'),
  weekly('weekly', 'Her hafta'),
  monthly('monthly', 'Her ay'),
  quarterly('quarterly', 'Üç ayda bir'),
  semiannual('semiannual', 'Altı ayda bir'),
  yearly('yearly', 'Her yıl');

  const RepeatInterval(this.id, this.label);

  final String id;
  final String label;

  /// Kendi kendine sürekli tekrarlayan bir hatırlatma mı?
  ///
  /// İki farklı kullanım var:
  ///
  /// * **Son tarihli** (aylık kira, yıllık sigorta): bir bitiş tarihi vardır,
  ///   kaç gün önceden uyarılacağı seçilir, kullanıcı "ödendi" dedikçe tarih
  ///   sonraki döneme taşınır.
  /// * **Sürekli** (saat başı ilaç, her gün egzersiz): bitiş tarihi yoktur,
  ///   "kaç gün önce" kavramı anlamsızdır; bildirim işletim sistemine
  ///   tekrarlayan olarak kurulur ve kullanıcı durdurana kadar sürer.
  ///
  /// Bu ayrım hem bildirim planlamasını hem de arayüzde hangi soruların
  /// sorulacağını belirler.
  bool get isContinuous =>
      this == RepeatInterval.hourly ||
      this == RepeatInterval.daily ||
      this == RepeatInterval.weekly;

  static RepeatInterval fromId(String id) {
    return RepeatInterval.values.firstWhere(
      (r) => r.id == id,
      orElse: () => RepeatInterval.none,
    );
  }

  /// [from] tarihini bir tekrar dönemi ileri taşır.
  ///
  /// Ay sonu taşmalarını kırpar: 31 Ocak + 1 ay = 28/29 Şubat.
  DateTime next(DateTime from) {
    switch (this) {
      case RepeatInterval.none:
        return from;
      case RepeatInterval.hourly:
        return from.add(const Duration(hours: 1));
      case RepeatInterval.daily:
        return _addDays(from, 1);
      case RepeatInterval.weekly:
        return _addDays(from, 7);
      case RepeatInterval.monthly:
        return _addMonths(from, 1);
      case RepeatInterval.quarterly:
        return _addMonths(from, 3);
      case RepeatInterval.semiannual:
        return _addMonths(from, 6);
      case RepeatInterval.yearly:
        return _addMonths(from, 12);
    }
  }

  /// Gün ekler.
  ///
  /// Duration yerine takvim aritmetiği kullanılır: yaz saati uygulanan
  /// bölgelerde `add(Duration(days: 1))` günü 23 ya da 25 saat kaydırıp
  /// bildirim saatini bozar.
  static DateTime _addDays(DateTime date, int days) {
    return DateTime(
      date.year,
      date.month,
      date.day + days,
      date.hour,
      date.minute,
    );
  }

  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      date.day > lastDayOfMonth ? lastDayOfMonth : date.day,
      date.hour,
      date.minute,
    );
  }
}
