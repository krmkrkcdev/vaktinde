# Flutter Hızlı Yayınlama Aracı

Flutter uygulamalarınızı tek komutla build alıp App Store ve Google Play'e
yükleyen local otomasyon paketi. Fastlane üzerine kuruludur.

## Bu paket ne yapar?

- `flutter build` komutlarını otomatik çalıştırır
- Build/version numarasını otomatik artırır
- iOS için: arşivler, imzalar, TestFlight veya App Store'a yükler
- Android için: App Bundle üretir, Play Store'a yükler
- Tek komutla (`./deploy.sh ios beta` gibi) tüm süreci başlatır

## Bu paketin YAPAMADIĞI şeyler (Apple/Google'ın manuel gerektirdiği tek seferlik adımlar)

Bunlar otomasyona başlamadan önce **bir kez** elle yapılması gereken işlemler:

1. Apple Developer Portal'da App ID (bundle identifier) oluşturmak
2. App Store Connect'te uygulama kaydı açmak (isim, SKU, bundle id seçimi)
3. Google Play Console'da uygulama oluşturmak ve ilk mağaza girişini
   (açıklama, ekran görüntüleri, gizlilik politikası vb.) tamamlamak
4. **Apple Distribution sertifikası** oluşturmak: Xcode → Settings → Accounts →
   Manage Certificates → `+` → Apple Distribution. Bu sertifika olmadan arşiv
   geliştirme kimliğiyle imzalanır ve paketleme
   "no provisioning profile mapping was provided" ile durur — hata sebebi
   söylemediği için teşhisi zordur.
5. Apple/Google'ın yaptığı inceleme sürecinin kendisi (bu süre otomatikleştirilemez,
   sadece yükleme ve incelemeye gönderme otomatikleştirilir)

Bunlardan sonra tüm sonraki güncellemeler bu araçla otomatikleştirilebilir.

### Dikey yöne kilitlenmiş uygulamalar

Uygulama yalnızca dikey çalışıyorsa ve iPad'i de hedefliyorsa
(`TARGETED_DEVICE_FAMILY = "1,2"`), `Info.plist` içine şu anahtar gerekir:

```xml
<key>UIRequiresFullScreen</key>
<true/>
```

iPad'de çoklu görev destekleyen uygulamalar dört yönü de beyan etmek
zorundadır. Bu anahtar olmadan yükleme **90474** hatasıyla reddedilir — ve
bunu ancak derleme, imzalama ve yükleme turunu tamamen harcadıktan sonra
öğrenirsiniz.

## Ön Gereksinimler

- Flutter SDK kurulu ve `flutter doctor` temiz
- Xcode kurulu (iOS build'leri için, sadece Mac'te çalışır)
- Android Studio + Android SDK kurulu
- Ruby ve Bundler kurulu (`gem install bundler`)
- Projenizin köküne bu paketin içeriğini kopyalayın (deploy.sh, Gemfile, .env.example,
  ios/fastlane/, android/fastlane/ klasörleri Flutter projenizin kök dizinine gelecek)

## Kurulum (bir kere yapılır)

### 1) Bağımlılıkları kurun

```bash
bundle install
```

### 2) iOS - App Store Connect API Key oluşturun

App Store Connect > Users and Access > Integrations > App Store Connect API
üzerinden yeni bir API Key oluşturun (rol: App Manager yeterli).

- İndirdiğiniz `.p8` dosyasını `ios/fastlane/` klasörüne koyun
- Key ID, Issuer ID ve dosya yolunu birazdan `.env` dosyasına gireceksiniz
- Bu yöntem kullanıcı adı/şifre veya 2FA gerektirmez, otomasyona uygundur

### 3) Android - Google Play Service Account oluşturun

Google Play Console > Setup > API access üzerinden bir servis hesabı oluşturup
Google Cloud Console'dan JSON anahtarını indirin. Play Console'da bu hesaba
"Release Manager" yetkisi verin.

- İndirdiğiniz `.json` dosyasını `android/fastlane/play-store-credentials.json`
  olarak kaydedin

### 4) .env dosyasını oluşturun

```bash
cp .env.example .env
```

Ardından `.env` dosyasını açıp kendi Key ID, Issuer ID, Team ID, bundle
identifier ve package name bilgilerinizle doldurun.

### 5) iOS imzalama: fastlane match kurulumu (önerilir)

`match`, imzalama sertifikalarınızı **şifreli** olarak özel bir git deposunda
saklar. Faydası: imzalama her makinede aynı çalışır, sertifika süresi dolduğunda
tek komutla yenilenir ve ileride CI'a taşınabilir.

**a) Özel bir git deposu açın.** Uygulama kodunuzdan ayrı, **private** olmalı:
GitHub'da `ios-certificates` gibi boş ve private bir repo yeterli. İçine hiçbir
şey koymayın, match kendisi dolduracak.

**b) `.env` dosyasına ekleyin:**

```
MATCH_GIT_URL=git@github.com:kullaniciadi/ios-certificates.git
MATCH_PASSWORD=guclu-bir-parola
```

`MATCH_PASSWORD`'ü bir parola yöneticisinde saklayın — kaybederseniz depodaki
sertifikaları bir daha açamazsınız.

**c) Sertifikaları bir kez oluşturun:**

```bash
cd ios && bundle exec fastlane certs
```

Bu komut App Store Connect API anahtarınızla Apple'a bağlanır, sertifika ve
provisioning profile üretir, şifreleyip git deposuna yükler. Şifre girmeniz
veya 2FA kodu beklemeniz gerekmez.

> **match kurmak istemiyorsanız:** `MATCH_GIT_URL` satırını boş bırakın. Bu
> durumda Xcode'un otomatik imzalaması kullanılır — çalışır, ama yalnızca sizin
> Mac'inizde ve CI'a taşınamaz. Xcode'da `ios/Runner.xcworkspace` > Signing &
> Capabilities sekmesinde "Automatically manage signing" işaretli ve doğru Team
> seçili olmalıdır.

> **Not:** match açıkken deploy sırasında `ios/Runner.xcodeproj` dosyası manuel
> imzalamaya çevrilir, yani git'te değişmiş görünür. Bu beklenen davranıştır;
> bu değişikliği commit'leyebilirsiniz.

## Kullanım

```bash
# TestFlight'a hızlı yükleme
./deploy.sh ios beta

# App Store'a yükle ve incelemeye gönder
./deploy.sh ios release

# Play Store Beta kanalına yükle
./deploy.sh android beta

# Play Store Production'a yükle
./deploy.sh android release

# İkisini birden tek komutla
./deploy.sh all beta
./deploy.sh all release
```

İlk çalıştırmadan önce script'e çalıştırma izni verin:

```bash
chmod +x deploy.sh
```

### Bayraklar

| Bayrak | Ne yapar |
|---|---|
| `--dry-run` | Build alır ama mağazaya **yüklemez**. Kurulumu denemek için ideal. |
| `--no-bump` | Build numarasını artırmaz. Başarısız bir yüklemeyi tekrarlarken kullanın. |
| `--skip-clean` | `flutter clean` adımını atlar, tekrar build'i hızlandırır. |

```bash
# Her şey doğru kurulmuş mu, yükleme yapmadan dene:
./deploy.sh ios beta --dry-run

# Yükleme adımı patladı, aynı build numarasıyla tekrar dene:
./deploy.sh ios beta --no-bump --skip-clean
```

## Sürüm notları

- iOS için: `ios/fastlane/release_notes.txt` → TestFlight "What to Test" alanına girer.
- Android için: `android/fastlane/release_notes.txt` → Play Store changelog'una girer.

Dosya yoksa iOS'ta varsayılan bir metin kullanılır, Android'de changelog boş geçilir.
Örnekler için `release_notes.txt.example` dosyalarına bakın.

## Kademeli yayın (Android)

`.env` dosyasına `PLAY_ROLLOUT=0.1` eklerseniz `./deploy.sh android release`
sürümü kullanıcıların %10'una açar (Play Console'dan sonra %100'e çıkarabilirsiniz).
Değişken boşsa doğrudan %100 yayınlanır.

## Süreç her seferinde otomatik olarak

1. `.env` yüklenir, zorunlu değişkenler ve anahtar dosyaları **önceden doğrulanır**
2. `pubspec.yaml` içindeki build numarası 1 artırılır (yalnızca `version:` satırı)
3. `flutter clean` + `flutter pub get`
4. Platforma göre `flutter build ios` / `flutter build appbundle` çalıştırılır
5. Fastlane ile imzalanır ve ilgili mağazaya yüklenir
6. (release lane'de) incelemeye otomatik gönderilir
7. Herhangi bir adım hata verirse `pubspec.yaml` **eski build numarasına geri alınır**

Build numarası tek bir kaynaktan yönetilir: `pubspec.yaml`. `flutter build ios`
bu değeri Xcode'un `CURRENT_PROJECT_VERSION` alanına yazar; Fastlane tarafında
ayrıca artırılmaz.

## Notlar

- Metadata (açıklama, ekran görüntüsü) güncellemeleri bu pakette **kapalıdır**
  (`skip_metadata: true`). Bunları da yönetmek isterseniz `fastlane deliver init`
  ile `ios/fastlane/metadata/` klasörünü oluşturup ilgili ayarı açın — aksi halde
  deliver mevcut mağaza metninizi boşaltabilir.
- Sertifikanız dolduğunda veya yeni bir cihaz/makine eklediğinizde:
  `cd ios && bundle exec fastlane certs`. Normal deploy akışı sertifika
  **üretmez**, yalnızca indirir (`readonly`), böylece kazara sertifika iptali olmaz.
- `upload_to_app_store` ve `upload_to_play_store` adımları mağaza tarafındaki
  API'lere bağlıdır; Apple/Google tarafında ara sıra API değişiklikleri
  olabilir, hata alırsanız `bundle update fastlane` ile güncelleyin.
