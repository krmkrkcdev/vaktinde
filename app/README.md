# Vaktinde

Belge ve ödeme hatırlatıcısı. Araç muayenesi, sigorta, ehliyet/pasaport yenileme,
kira, fatura, aidat, abonelik, garanti ve vergi tarihlerini kaydedin; uygulama
yalnızca **belirlediğiniz tarihten önce** bildirim gönderir.

- **Paket adı:** `com.vaktinde.app` (Android + iOS)
- **Çevrimdışı önceliklidir.** Telefondaki SQLite (`vaktinde.db`) ana kaynaktır;
  bildirimler internet olmadan da çalışır.
- **Bildirimler yerel.** Push servisi kullanılmaz.
- **Bulut yedekleme isteğe bağlı.** Giriş yapılmadığı sürece sunucuya hiçbir
  bilgi gönderilmez. Sunucu ayrı bir projedir: [backend](../backend).

## Akış

Yeni kayıt, her ekranda tek soru soran altı adımlı bir sihirbazla eklenir:

```
1 Kategori → 2 Başlık → 3 Son tarih → 4 Tekrar → 5 Kaç gün önce → 6 İsteğe bağlı → Kaydet
```

Sihirbaz bilinçli olarak yaşlı kullanıcılara göre tasarlanmıştır: büyük yazı
(20–26sp), en az 72px yüksekliğinde dokunma alanları, adım göstergesi, her
kategori için klavye açmadan seçilebilen hazır başlıklar (Netflix, Elektrik
faturası, Konut kredisi…) ve kaydetmeden önce özet.

Mevcut bir kaydı **düzenlemek** tek sayfalık `ReminderFormScreen` ile yapılır —
küçük bir düzeltme için altı adım gezdirmemek adına.

## Çalıştırma

```bash
flutter pub get
flutter run              # bağlı cihaz/emülatörde
flutter test             # birim testleri
flutter build apk        # Android
flutter build ios        # iOS (macOS gerekir)
```

### Sunucu adresi

Varsayılan `https://vaktinde.devpos.com`. Değiştirmek için:

```bash
flutter build apk --dart-define=API_BASE_URL=https://baska-adres.com
```

Geliştirirken emülatörden ana makinedeki backend'e bağlanmak için
`http://10.0.2.2:8100` kullanılır. Düz HTTP yalnızca debug derlemesinde ve
yalnızca bu adres için açıktır
(`android/app/src/debug/res/xml/network_security_config.xml`); sürüm
derlemesinde tüm trafik HTTPS olmak zorundadır.

### Sözleşme testleri

İstemci–sunucu uyumunu (alan adları, tarih biçimleri) çalışan bir API'ye karşı
sınar. Normal `flutter test` çalışmasında atlanır:

```bash
cd ../backend && docker compose up -d && cd -
flutter test test/api_contract_test.dart \
  --dart-define=CONTRACT_API_URL=http://127.0.0.1:8100
```

> **Windows notu:** Proje yolu ASCII olmayan karakter içeremez. Örneğin
> `MobileUygulamalarım` gibi bir klasör altında Gradle ve shader derleyici
> (`impellerc`) başarısız olur. Proje bu yüzden `Documents\vaktinde\`
> altında tutulur.

## Yapı

```
lib/
  models/         Reminder, ReminderCategory (13 kategori), RepeatInterval
  data/           ReminderDatabase — sqflite deposu (şema v2)
  services/       NotificationService — yerel bildirim planlama
                  PhotoStore — belge fotoğrafı dosya deposu
  state/          ReminderStore, SettingsStore (provider / ChangeNotifier)
  screens/        home, reminder_wizard, reminder_form, premium, settings, archive
  widgets/        ReminderCard, PhotoGalleryField
  theme/          AppTheme + aciliyet renkleri
```

### Belge fotoğrafları

Fatura ve garanti belgelerinin fotoğrafı kameradan veya galeriden eklenebilir
(kayıt başına birden fazla). Dosyalar uygulamanın kendi dizinindeki
`belgeler/` klasörüne kopyalanır; veritabanında yalnızca **dosya adı** tutulur
ve tam yol çalışma zamanında çözülür — iOS'ta uygulama dizininin mutlak yolu
her güncellemede değiştiği için mutlak yol saklamak kayıpla sonuçlanırdı.

Fotoğraflar kayıttan çıkarıldığında veya kayıt silindiğinde diskten de silinir.
Sihirbaz yarıda bırakılırsa açılışta `pruneOrphans` sahipsiz dosyaları temizler.

### Bildirim mantığı

Her hatırlatma için seçilen "kaç gün önce" değerlerinin her biri ayrı bir
bildirim slotu alır (hatırlatma başına en fazla 8). Bildirim kimliği
`reminder.id * 8 + slot` olarak hesaplanır, böylece bir kaydın bildirimleri
tek tek iptal edilip yeniden kurulabilir.

Uygulama her açılışta `rescheduleAll` çağırır: saat dilimi değişikliği veya
cihazın planlanmış bildirimleri düşürmesi durumlarına karşı güvenlik ağıdır.

### Tekrar

`RepeatInterval` (yok / aylık / üç aylık / yıllık) bir kaydı "tamamlandı"
işaretlediğinizde son tarihi bir sonraki döneme taşır. Ay sonu taşmaları
kırpılır: 31 Ocak + 1 ay = 28 �?ubat.

## Bulut yedekleme

Hesap açmak isteğe bağlıdır; uygulama girişsiz de tam olarak çalışır. Giriş
yapıldığında hatırlatmalar ve belge fotoğrafları sunucuya yedeklenir; kullanıcı
telefon değiştirip giriş yaptığında geri gelir.

Senkronizasyonun nasıl çalıştığı (istemci üretimi UUID'ler, imleç sayacı,
son yazan kazanır, mezar taşları) [backend README'sinde](../backend/README.md)
ayrıntılı anlatılmıştır. İstemci tarafındaki karşılıkları:

| Dosya | Sorumluluk |
|---|---|
| `services/api_client.dart` | HTTP, token yenileme, hata çevirisi |
| `services/sync_service.dart` | Gönder → çek → fotoğraflar turu |
| `state/auth_store.dart` | Oturum, güvenli token saklama |
| `state/sync_controller.dart` | Senkronizasyonun ne zaman çalışacağı |

Tokenlar `shared_preferences` yerine güvenli depoda tutulur (Android Keystore
/ iOS Keychain), böylece cihaz yedeklerine düz metin olarak sızmazlar.

Fotoğraf dosya adları `belge_<uuid>.<uzantı>` biçimindedir ve içindeki UUID
aynı zamanda sunucudaki fotoğraf kimliğidir — ayrı bir eşleme tablosu tutmaya
gerek kalmaz.

## Para kazanma

| | Ücretsiz | Premium |
|---|---|---|
| Hatırlatma sayısı | 10 | Sınırsız |
| Bulut yedekleme | — | ✓ |
| Aileyle paylaşma | — | ✓ |
| Reklam | — | — |

Premium tek seferlik satın almadır. **İlk sürümde mağaza entegrasyonu yoktur:**
limit ve premium ekranı hazır, satın alma akışı `lib/screens/premium_screen.dart`
içindeki `TODO(iap)` işaretlerinde bekliyor. Satın alma doğrulandığında
çağrılacak tek nokta `SettingsStore.setPremium(true)`.

Debug derlemesinde premium'u test etmek için Premium ekranının altındaki
geliştirici anahtarını kullanın.

## Platform kurulumu

**Android** — `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`,
`RECEIVE_BOOT_COMPLETED` izinleri ve boot receiver `AndroidManifest.xml`
içinde tanımlı. `flutter_local_notifications` için core library desugaring
`android/app/build.gradle.kts` içinde açık.

**iOS** — Bildirim izinleri uygulama açılışında değil, kullanıcı ilk
hatırlatmayı kaydettiğinde istenir.

## Uygulama ikonu ve açılış ekranı

Kaynak görseller `assets/icon/` altında (`icon.png` tam ikon,
`icon_foreground.png` Android adaptif ön planı ve açılış ekranı logosu).
Değiştirdikten sonra yeniden üretmek için:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Veritabanı şeması

| Sürüm | Değişiklik |
|---|---|
| v1 | İlk şema |
| v2 | `photo_paths` sütunu eklendi (belge fotoğrafları) |
| v3 | Bulut senkronizasyonu: `uuid`, `updated_at`, `is_deleted`, `is_dirty` |

Yükseltme `ReminderDatabase.onUpgrade` içinde `ALTER TABLE` ile yapılır; mevcut
kayıtlar korunur.

## Yayın öncesi yapılacaklar

- [x] Uygulama ikonu
- [x] Açılış ekranı
- [ ] Android release imzalama yapılandırması (`android/app/build.gradle.kts`
      içindeki `signingConfig` şu an debug anahtarını kullanıyor)
- [ ] `in_app_purchase` ile tek seferlik premium ürünü
- [ ] Bulut yedekleme ve aile paylaşımı (premium özellikleri)
- [ ] Gizlilik politikası metni (veriler cihazda kalıyor — kısa olacak)
