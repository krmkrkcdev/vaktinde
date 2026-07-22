@Tags(['contract'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaktinde/models/reminder.dart';
import 'package:vaktinde/models/repeat_interval.dart';
import 'package:vaktinde/services/api_client.dart';

/// İstemci ile sunucu arasındaki sözleşmeyi çalışan bir API'ye karşı sınar.
///
/// Buradaki asıl risk mantık değil, **uyuşmazlıktır**: alan adlarının,
/// tarih biçimlerinin ve tiplerin iki tarafta aynı olduğunu yalnızca gerçek
/// bir sunucuya konuşarak doğrulayabiliriz. Birim testleri bunu yakalayamaz.
///
/// Çalıştırmak için backend ayakta olmalı:
///   cd ../vaktinde-backend && docker compose up -d
///   flutter test test/api_contract_test.dart \
///     --dart-define=CONTRACT_API_URL=http://127.0.0.1:8100
///
/// Adres verilmezse testler atlanır; normal `flutter test` çalışması
/// sunucuya bağımlı olmaz.
const _baseUrl = String.fromEnvironment('CONTRACT_API_URL');

void main() {
  if (_baseUrl.isEmpty) {
    test('sözleşme testleri atlandı (CONTRACT_API_URL tanımlı değil)', () {}, skip: true);
    return;
  }

  late ApiClient api;
  late String email;

  setUp(() async {
    api = ApiClient(baseUrl: _baseUrl);
    // Her test kendi hesabıyla çalışır; testler birbirinin verisini görmez.
    email = 'sozlesme-${DateTime.now().microsecondsSinceEpoch}@ornek.com';
    await api.register(email, 'SozlesmeTesti123');
  });

  test('kayıt sonrası oturum açılır ve /me doğru e-postayı döner', () async {
    final me = await api.me();
    expect(me['email'], email);
  });

  test('hatırlatma gönderilip aynı değerlerle geri alınır', () async {
    final gonderilen = Reminder.create(
      categoryId: 'subscription',
      title: 'Netflix',
      note: 'Aile paketi',
      dueDate: DateTime(2026, 8, 21),
      leadDays: const [30, 7, 1],
      notifyHour: 20,
      notifyMinute: 30,
      repeat: RepeatInterval.monthly,
      amount: 149.99,
    );

    final pushResult = await api.push([gonderilen.toApi()]);
    expect(pushResult['rejected_ids'], isEmpty);

    final changes = await api.fetchChanges(0);
    final donenler = (changes['reminders'] as List).cast<Map<String, Object?>>();
    expect(donenler, hasLength(1));

    final donen = Reminder.fromApi(donenler.first);
    expect(donen.uuid, gonderilen.uuid);
    expect(donen.title, 'Netflix');
    expect(donen.note, 'Aile paketi');
    expect(donen.categoryId, 'subscription');
    expect(donen.leadDays, [30, 7, 1]);
    expect(donen.notifyHour, 20);
    expect(donen.notifyMinute, 30);
    expect(donen.repeat, RepeatInterval.monthly);
    expect(donen.amount, 149.99);
    // Tarih saat dilimi dönüşümünden sağ çıkmalı.
    expect(donen.dueDate.year, 2026);
    expect(donen.dueDate.month, 8);
    expect(donen.dueDate.day, 21);
    // Sunucudan gelen kayıt temizdir.
    expect(donen.isDirty, isFalse);
  });

  test('imleç yalnızca yeni değişiklikleri döner', () async {
    await api.push([_ornek('Birinci').toApi()]);
    final cursor = (await api.fetchChanges(0))['cursor'] as int;

    final bos = await api.fetchChanges(cursor);
    expect(bos['reminders'], isEmpty);

    await api.push([_ornek('İkinci').toApi()]);
    final yeni = await api.fetchChanges(cursor);
    final basliklar = (yeni['reminders'] as List)
        .cast<Map<String, Object?>>()
        .map((r) => r['title']);
    expect(basliklar, ['İkinci']);
  });

  test('eski düzenleme reddedilir, yeni düzenleme uygulanır', () async {
    final ilk = _ornek('İlk hâli');
    await api.push([ilk.toApi()]);

    // Geçmiş zamanlı düzenleme yok sayılmalı.
    final eski = ilk.copyWith(title: 'Eski hâli').toApi()
      ..['client_updated_at'] =
          ilk.updatedAt.subtract(const Duration(hours: 1)).toUtc().toIso8601String();
    final redSonucu = await api.push([eski]);
    expect(redSonucu['rejected_ids'], [ilk.uuid]);

    // Daha yeni düzenleme kabul edilmeli.
    final yeni = ilk.copyWith(title: 'Yeni hâli').toApi()
      ..['client_updated_at'] =
          ilk.updatedAt.add(const Duration(hours: 1)).toUtc().toIso8601String();
    final kabulSonucu = await api.push([yeni]);
    expect(kabulSonucu['rejected_ids'], isEmpty);

    final changes = await api.fetchChanges(0);
    final donen = (changes['reminders'] as List).cast<Map<String, Object?>>().first;
    expect(donen['title'], 'Yeni hâli');
  });

  test('silinen hatırlatma mezar taşı olarak döner', () async {
    final reminder = _ornek('Silinecek');
    await api.push([reminder.toApi()]);
    await api.push([reminder.copyWith(isDeleted: true).toApi()]);

    final changes = await api.fetchChanges(0);
    final donen = (changes['reminders'] as List).cast<Map<String, Object?>>().first;
    expect(Reminder.fromApi(donen).isDeleted, isTrue);
  });

  test('fotoğraf yüklenip aynı baytlarla indirilir', () async {
    final reminder = _ornek('Faturalı');
    await api.push([reminder.toApi()]);

    // Geçerli bir JPEG imzası; sunucu içeriğe bakarak tür doğruluyor.
    final bytes = <int>[0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(256, 7)];
    final temp = File(
      '${Directory.systemTemp.path}/sozlesme-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await temp.writeAsBytes(bytes);
    addTearDown(() => temp.delete());

    const photoId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await api.uploadPhoto(
      photoId: photoId,
      reminderId: reminder.uuid,
      file: temp,
    );

    expect(await api.downloadPhoto(photoId), bytes);

    final changes = await api.fetchChanges(0);
    final photos = (changes['photos'] as List).cast<Map<String, Object?>>();
    expect(photos, hasLength(1));
    expect(photos.first['id'], photoId);
    expect(photos.first['reminder_id'], reminder.uuid);
    expect(photos.first['has_content'], isTrue);
  });

  test('geçersiz kimlik bilgisi ApiException fırlatır', () async {
    final temiz = ApiClient(baseUrl: _baseUrl);
    expect(
      () => temiz.login(email, 'YanlisSifre'),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
    );
  });

  test('oturumsuz istek reddedilir', () async {
    final temiz = ApiClient(baseUrl: _baseUrl);
    expect(() => temiz.fetchChanges(0), throwsA(isA<ApiException>()));
  });
}

Reminder _ornek(String title) => Reminder.create(
      categoryId: 'bill',
      title: title,
      dueDate: DateTime(2026, 9, 15),
      leadDays: const [7, 1],
      notifyHour: 9,
      notifyMinute: 0,
      repeat: RepeatInterval.none,
    );
