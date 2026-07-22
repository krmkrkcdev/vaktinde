/// Bir hatırlatmanın son tarihi geçtiğinde otomatik olarak ne kadar
/// ileri taşınacağını belirler.
enum RepeatInterval {
  none('none', 'Tekrar yok'),
  monthly('monthly', 'Her ay'),
  quarterly('quarterly', 'Üç ayda bir'),
  yearly('yearly', 'Her yıl');

  const RepeatInterval(this.id, this.label);

  final String id;
  final String label;

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
      case RepeatInterval.monthly:
        return _addMonths(from, 1);
      case RepeatInterval.quarterly:
        return _addMonths(from, 3);
      case RepeatInterval.yearly:
        return _addMonths(from, 12);
    }
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
