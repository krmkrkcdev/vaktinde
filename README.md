# Vaktinde

Belge ve ödeme hatırlatıcısı. Araç muayenesi, sigorta, ehliyet/pasaport
yenileme, kira, fatura, aidat, dijital abonelik, kredi kartı, kredi taksiti,
garanti ve vergi tarihlerini kaydedin; uygulama yalnızca **belirlediğiniz
tarihten önce** bildirim gönderir.

| Klasör | İçerik |
|---|---|
| [`app/`](app) | Flutter mobil uygulaması (Android + iOS) |
| [`backend/`](backend) | FastAPI + PostgreSQL senkronizasyon sunucusu |

## Nasıl çalışır

Uygulama **çevrimdışı önceliklidir**. Telefondaki SQLite ana kaynaktır ve
bildirimler internet olmadan çalışır. Sunucu isteğe bağlı bir yedek ve aktarım
katmanıdır: kullanıcı giriş yapmadığı sürece hiçbir veri dışarı çıkmaz.

Giriş yapıldığında hatırlatmalar ve belge fotoğrafları hesaba yedeklenir;
kullanıcı telefon değiştirip giriş yaptığında geri gelir.

## Başlangıç

```bash
# Mobil uygulama
cd app
flutter pub get
flutter run

# Sunucu
cd backend
cp .env.example .env      # JWT_SECRET ve POSTGRES_PASSWORD üretin
docker compose up -d --build
```

Ayrıntılar için [`app/README.md`](app/README.md) ve
[`backend/README.md`](backend/README.md).

## Testler

```bash
cd app && flutter test                    # birim testleri
cd backend && docker compose run --rm --no-deps -v "$PWD:/src" -w /src api \
  sh -c "pip install -r requirements-dev.txt && python -m pytest -q"
```

İstemci ile sunucu arasındaki sözleşmeyi (alan adları, tarih biçimleri)
çalışan bir API'ye karşı sınayan ayrı bir test paketi vardır; bkz.
`app/test/api_contract_test.dart`.

## Yayına alma

Sunucu `vaktinde.devpos.com` adresinde nginx ters vekili arkasında çalışır.
Hazır yapılandırma: [`backend/nginx/`](backend/nginx).

Mobil uygulama sürüm derlemesinde sunucu adresi şöyle verilir:

```bash
flutter build apk --dart-define=API_BASE_URL=https://vaktinde.devpos.com
```
