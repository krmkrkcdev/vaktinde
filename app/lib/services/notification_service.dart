import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import '../models/repeat_interval.dart' as model;

/// Yerel (cihaz üstü) bildirimleri planlar. Sunucu / push servisi kullanılmaz.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'vaktinde_reminders';
  static const _channelName = 'Hatırlatmalar';
  static const _channelDescription =
      'Belge ve ödeme son tarihleri için hatırlatma bildirimleri';

  /// Bir hatırlatma en fazla bu kadar bildirim slotu kullanabilir.
  /// Bildirim kimliği = reminder.id * _slotsPerReminder + slot.
  static const _slotsPerReminder = 8;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (e) {
      // Bilinmeyen saat dilimi: UTC'ye düş, bildirimler yine de planlanır.
      debugPrint('Saat dilimi belirlenemedi, UTC kullanılıyor: $e');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // İzinleri uygulama açılışında değil, kullanıcı ilk hatırlatmayı
          // kaydettiğinde isteriz.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDescription,
              importance: Importance.high,
            ),
          );
    }

    _initialized = true;
  }

  /// Bildirim izinlerini ister. Kullanıcı reddederse `false` döner.
  Future<bool> requestPermissions() async {
    await init();

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      // Tam zamanlı alarm izni ayrı bir izindir; reddedilse bile bildirimler
      // yaklaşık zamanla (inexact) gönderilmeye devam eder.
      await android?.requestExactAlarmsPermission();
      return granted;
    }

    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  /// Verilen hatırlatmanın tüm bildirimlerini iptal edip yeniden planlar.
  Future<void> schedule(Reminder reminder) async {
    await init();
    final id = reminder.id;
    if (id == null) return;

    await cancel(id);
    if (reminder.isArchived) return;

    // Sürekli hatırlatmalar (saat başı ilaç gibi) tek bir tekrarlayan
    // bildirimle kurulur: son tarih kavramı yoktur ve tek tek slot açmak
    // hem iOS'un uygulama başına 64 bekleyen bildirim sınırını tüketir hem
    // de belirli bir noktada biterdi.
    if (reminder.repeat.isContinuous) {
      await _scheduleContinuous(reminder, notificationId: _notificationId(id, 0));
      return;
    }

    final times = reminder.upcomingNotificationTimes();
    for (var slot = 0; slot < times.length && slot < _slotsPerReminder; slot++) {
      await _scheduleOne(
        notificationId: _notificationId(id, slot),
        at: times[slot],
        reminder: reminder,
      );
    }
  }

  /// Kullanıcı durdurana kadar süren tekrarlayan bildirim.
  Future<void> _scheduleContinuous(
    Reminder reminder, {
    required int notificationId,
  }) async {
    // Günlük ve haftalık tekrar seçilen saate sabitlenir; işletim sistemi
    // eşleşen bileşenleri (saat / haftanın günü + saat) tekrarlar.
    if (reminder.repeat == model.RepeatInterval.daily ||
        reminder.repeat == model.RepeatInterval.weekly) {
      await _plugin.zonedSchedule(
        id: notificationId,
        title: '${reminder.category.label}: ${reminder.title}',
        body: _bodyFor(reminder),
        scheduledDate: _nextOccurrence(reminder),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminder.id?.toString(),
        matchDateTimeComponents: reminder.repeat == model.RepeatInterval.daily
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
        notificationDetails: _details,
      );
      return;
    }

    // Saat başı: ilk bildirim bir saat sonra gelir, sonra her saat tekrarlar.
    // periodicallyShow belirli bir başlangıç saati almaz — saat başı tekrarda
    // önemli olan aralık olduğu için bu kabul edilebilir.
    await _plugin.periodicallyShow(
      id: notificationId,
      title: '${reminder.category.label}: ${reminder.title}',
      body: _bodyFor(reminder),
      repeatInterval: RepeatInterval.hourly,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: reminder.id?.toString(),
      notificationDetails: _details,
    );
  }

  /// Seçilen saatin bir sonraki gelişi. Bugünkü saat geçtiyse yarına kayar;
  /// aksi hâlde işletim sistemi geçmiş bir tarihe kurulmuş bildirimi atar.
  tz.TZDateTime _nextOccurrence(Reminder reminder) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.notifyHour,
      reminder.notifyMinute,
    );
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));

    // Haftalık tekrarda hatırlatmanın kendi gününe hizala.
    if (reminder.repeat == model.RepeatInterval.weekly) {
      while (next.weekday != reminder.dueDate.weekday) {
        next = next.add(const Duration(days: 1));
      }
    }
    return next;
  }

  Future<void> _scheduleOne({
    required int notificationId,
    required DateTime at,
    required Reminder reminder,
  }) async {
    final scheduled = tz.TZDateTime.from(at, tz.local);
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: notificationId,
      title: '${reminder.category.label}: ${reminder.title}',
      body: _bodyFor(reminder),
      scheduledDate: scheduled,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: reminder.id?.toString(),
      notificationDetails: _details,
    );
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  String _bodyFor(Reminder reminder) {
    // Sürekli hatırlatmanın son tarihi yoktur; "son gün" demek yanıltıcı olur.
    // Kullanıcının kendi notu varsa onu göster, yoksa tekrar aralığını.
    if (reminder.repeat.isContinuous) {
      final note = reminder.note?.trim();
      return (note == null || note.isEmpty) ? reminder.repeat.label : note;
    }

    final date = DateFormat('d MMMM yyyy', 'tr_TR').format(reminder.dueDate);
    final days = reminder.daysRemaining;
    final when = days <= 0 ? 'Son gün: $date' : '$date tarihinde ($days gün kaldı)';
    if (reminder.amount != null) {
      final amount = NumberFormat.currency(
        locale: 'tr_TR',
        symbol: '₺',
        decimalDigits: 2,
      ).format(reminder.amount);
      return '$when · $amount';
    }
    return when;
  }

  int _notificationId(int reminderId, int slot) {
    // 32-bit tamsayı sınırının altında kalmasını garanti eder.
    return (reminderId * _slotsPerReminder + slot) % 2147483647;
  }

  Future<void> cancel(int reminderId) async {
    await init();
    for (var slot = 0; slot < _slotsPerReminder; slot++) {
      await _plugin.cancel(id: _notificationId(reminderId, slot));
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Tüm hatırlatmaların bildirimlerini sıfırdan kurar.
  /// Uygulama her açıldığında çağrılır: saat dilimi değişikliği, cihazın
  /// bildirimleri düşürmesi gibi durumlara karşı güvenlik ağıdır.
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    await init();
    await _plugin.cancelAll();
    for (final reminder in reminders) {
      if (reminder.isArchived) continue;
      await schedule(reminder);
    }
  }

  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }
}
