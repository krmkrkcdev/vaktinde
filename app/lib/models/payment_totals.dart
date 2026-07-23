import 'reminder.dart';
import 'repeat_interval.dart';

/// Tekrar eden ödemelerin haftalık / aylık / yıllık karşılıkları.
///
/// Farklı aralıklardaki tutarlar doğrudan toplanamaz: "her ay 700" ile
/// "her yıl 3.000" aynı ölçekte değildir. Her tutar önce **yıllık** karşılığına
/// çevrilir, sonra istenen döneme bölünür.
///
/// Tekrar etmeyen (tek seferlik) kayıtlar hesaba katılmaz — bunlar düzenli bir
/// gider değildir ve aylık ortalamayı yanıltır.
class PaymentTotals {
  const PaymentTotals({
    required this.weekly,
    required this.monthly,
    required this.yearly,
    required this.countedReminders,
  });

  final double weekly;
  final double monthly;
  final double yearly;

  /// Toplama dahil edilen hatırlatma sayısı. Sıfırsa gösterilecek bir şey
  /// yoktur (ne tutarı olan ne de tekrar eden kayıt var).
  final int countedReminders;

  bool get isEmpty => countedReminders == 0;

  factory PaymentTotals.from(Iterable<Reminder> reminders) {
    var yearlyTotal = 0.0;
    var counted = 0;

    for (final reminder in reminders) {
      final amount = reminder.amount;
      if (amount == null || amount <= 0) continue;

      final perYear = _occurrencesPerYear(reminder.repeat);
      if (perYear == null) continue;

      yearlyTotal += amount * perYear;
      counted++;
    }

    return PaymentTotals(
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
  /// ve yıllık 8.760 kez sayılması toplamı anlamsız kılar.
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
