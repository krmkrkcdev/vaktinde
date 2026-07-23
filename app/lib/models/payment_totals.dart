import 'reminder.dart';
import 'repeat_interval.dart';

/// Düzenli ödemelerin iki ayrı görünümü.
///
/// **Kendi aralığında toplam** ([byInterval]): aynı sıklıktaki ödemeler
/// birbiriyle toplanır. "Her ay 3 ödemem var, toplamı 600" bilgisi budur ve
/// kullanıcının kafasındaki gerçek rakamdır.
///
/// **Normalize toplam** ([daily], [weekly], [monthly], [yearly]): farklı
/// sıklıktaki ödemelerin tek ölçüye indirilmiş hâli. "Toplamda ayda ne kadar
/// gidiyor?" sorusunun cevabıdır; her tutar önce yıllık karşılığına çevrilip
/// istenen döneme bölünür.
///
/// Tekrar etmeyen (tek seferlik) kayıtlar hiçbirine katılmaz — düzenli bir
/// gider değildir ve ortalamayı yanıltır.
class PaymentTotals {
  const PaymentTotals({
    required this.byInterval,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.yearly,
    required this.countedReminders,
  });

  /// Sıklığına göre gruplanmış toplamlar. Yalnızca ödemesi olan aralıklar
  /// bulunur; sıralama [RepeatInterval] tanım sırasını (sıktan seyreğe) izler.
  final Map<RepeatInterval, double> byInterval;

  final double daily;
  final double weekly;
  final double monthly;
  final double yearly;

  /// Toplama dahil edilen hatırlatma sayısı.
  final int countedReminders;

  bool get isEmpty => countedReminders == 0;

  factory PaymentTotals.from(Iterable<Reminder> reminders) {
    final grouped = <RepeatInterval, double>{};
    var yearlyTotal = 0.0;
    var counted = 0;

    for (final reminder in reminders) {
      final amount = reminder.amount;
      if (amount == null || amount <= 0) continue;

      final perYear = _occurrencesPerYear(reminder.repeat);
      if (perYear == null) continue;

      grouped.update(
        reminder.repeat,
        (existing) => existing + amount,
        ifAbsent: () => amount,
      );
      yearlyTotal += amount * perYear;
      counted++;
    }

    // Enum tanım sırasına göre sırala: sık olandan seyrek olana.
    final ordered = <RepeatInterval, double>{
      for (final interval in RepeatInterval.values)
        if (grouped.containsKey(interval)) interval: grouped[interval]!,
    };

    return PaymentTotals(
      byInterval: ordered,
      daily: yearlyTotal / 365,
      weekly: yearlyTotal / 52,
      monthly: yearlyTotal / 12,
      yearly: yearlyTotal,
      countedReminders: counted,
    );
  }

  /// Bir tekrar aralığının yılda kaç kez gerçekleştiği.
  ///
  /// Tek seferlik kayıtlar ve saat başı tekrar `null` döner: ilki düzenli bir
  /// gider değildir, ikincisi ise ödeme değil hatırlatma amaçlıdır (ilaç gibi)
  /// ve yılda 8.760 kez sayılması toplamı anlamsız kılar.
  static double? _occurrencesPerYear(RepeatInterval repeat) {
    switch (repeat) {
      case RepeatInterval.none:
      case RepeatInterval.hourly:
        return null;
      case RepeatInterval.daily:
        return 365;
      case RepeatInterval.weekly:
        return 52;
      case RepeatInterval.monthly:
        return 12;
      case RepeatInterval.quarterly:
        return 4;
      case RepeatInterval.semiannual:
        return 2;
      case RepeatInterval.yearly:
        return 1;
    }
  }
}
