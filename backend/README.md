# Vaktinde API

[Vaktinde](../app) mobil uygulamasının senkronizasyon sunucusu.
Kullanıcı hesabı, hatırlatmaların yedeklenmesi ve belge fotoğraflarının
saklanmasını sağlar; kullanıcı telefon değiştirdiğinde giriş yaptığında
verileri geri gelir.

FastAPI + PostgreSQL. Docker Compose ile tek komutta ayağa kalkar.

## Hızlı başlangıç

```bash
cp .env.example .env

# Zorunlu iki sırrı üretin ve .env içine yazın:
openssl rand -hex 32      # JWT_SECRET
openssl rand -base64 24   # POSTGRES_PASSWORD

docker compose up -d --build
curl http://127.0.0.1:8000/health     # {"status":"ok"}
```

API yalnızca `127.0.0.1` üzerinden dinler; dışarıya açılması nginx ile yapılır.
Sunucuda 8000 portu meşgulse `.env` içinde `API_PORT` değiştirilir (nginx
yapılandırmasındaki `proxy_pass` portu da güncellenmeli).

Etkileşimli API dökümanı: `http://127.0.0.1:8000/docs`

## Yayına alma

Sunucuda ters vekilin nasıl kurulu olduğuna göre iki yoldan biri izlenir.

### A) Nginx Proxy Manager (konteyner tabanlı, web arayüzlü)

Bu durumda `.conf` dosyası yazılmaz, `certbot` çalıştırılmaz — sertifikayı
NPM kendisi alır. Yalnızca API'nin vekil ile aynı ağda olması gerekir;
`docker-compose.yml` bunu `proxy` ağıyla zaten sağlar. Ağın adı farklıysa
`.env` içinde `PROXY_NETWORK` ile değiştirilir.

Ardından NPM arayüzünde (`http://SUNUCU:81`) bir Proxy Host eklenir:

| Alan | Değer |
|---|---|
| Domain Names | `vaktinde.devposs.com` |
| Forward Hostname | `vaktinde-api` |
| Forward Port | `8000` |
| Websockets Support | kapalı |
| SSL | Request a new SSL Certificate + Force SSL |

**Advanced** sekmesine şunu eklemek gerekir; yoksa fotoğraf yüklemeleri
varsayılan 1 MB sınırına takılıp 413 döner:

```
client_max_body_size 12M;
proxy_read_timeout 120s;
proxy_send_timeout 120s;
```

### B) Sistem nginx'i

`nginx/vaktinde.devposs.com.conf` hazır bir yapılandırma içerir:

```bash
sudo cp nginx/vaktinde.devposs.com.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/vaktinde.devposs.com.conf /etc/nginx/sites-enabled/
sudo certbot --nginx -d vaktinde.devposs.com
sudo nginx -t && sudo systemctl reload nginx
```

> `client_max_body_size 12M` satırı önemlidir. nginx'in varsayılan 1 MB sınırı
> fotoğraf yüklemelerini 413 ile reddeder.

## Testler

Testler gerçek PostgreSQL'e karşı çalışır (ayrı bir `vaktinde_test`
veritabanı oluşturulur). Yığın ayaktayken:

```bash
docker compose run --rm --no-deps -v "$PWD:/src" -w /src api \
  sh -c "pip install -r requirements-dev.txt && python -m pytest -q"
```

SQLite taklidi bilinçli olarak kullanılmadı: senkronizasyon dizisi, UUID
sütunları ve eşzamanlı yazma davranışı ancak gerçek veritabanında sınanabilir.

## Senkronizasyon nasıl çalışır

Uygulama **çevrimdışı önceliklidir**. Telefondaki SQLite ana kaynaktır;
bildirimler internet olmadan da çalışır. Sunucu bir yedek ve aktarım
katmanıdır.

**Kimlikler istemcide üretilir.** Kullanıcı uçakta bir hatırlatma
oluşturabilmeli ve o kayıt senkronize edildiğinde kimliği değişmemelidir. Bu
yüzden birincil anahtar sunucuda değil telefonda üretilen bir UUID'dir.

**İmleç sayaçtır, zaman damgası değil.** Her yazmada paylaşılan bir PostgreSQL
dizisinden monoton artan bir `sync_seq` alınır. İstemci "şu sayıdan
büyüklerini ver" der. Zaman damgası kullanılsaydı istemci saatlerinin yanlış
olması ve aynı milisaniyedeki iki yazmanın sıralanamaması kayıt kaybına yol
açardı.

**Çakışmada son yazan kazanır.** İstemci her kayıtla birlikte kendi
`client_updated_at` değerini gönderir; sunucudaki değerden eskiyse yazma
atlanır ve kimlik `rejected_ids` içinde döner. İstemci bir sonraki çekimde
sunucu sürümünü alır.

**Silme mezar taşı bırakır.** Kayıt fiziksel olarak silinmez, `is_deleted`
işaretlenir — aksi hâlde diğer cihazlar silmeyi hiç öğrenemez ve kayıt geri
gelirdi. Bir hatırlatma silindiğinde fotoğrafları da mezar taşına çevrilir.

### Tipik akış

```
1. GET  /sync/changes?since=<son imleç>   → sunucudaki yenilikleri al
2. POST /sync/push                        → yereldeki değişiklikleri gönder
3. PUT  /photos/{id}?reminder_id=...      → içeriği olmayan fotoğrafları yükle
4. GET  /photos/{id}                      → eksik fotoğrafları indir
```

## Uç noktalar

| Yöntem | Yol | Açıklama |
|---|---|---|
| POST | `/auth/register` | Kayıt, token çifti döner |
| POST | `/auth/login` | Giriş |
| POST | `/auth/refresh` | Access token yenileme |
| GET | `/auth/me` | Oturumdaki kullanıcı |
| POST | `/auth/change-password` | �?ifre değiştirir, diğer oturumları düşürür |
| GET | `/sync/changes?since=` | İmleçten sonraki değişiklikler |
| POST | `/sync/push` | Yerel değişiklikleri gönderir |
| PUT | `/photos/{id}?reminder_id=` | Fotoğraf yükler (idempotent) |
| GET | `/photos/{id}` | Fotoğraf indirir |
| DELETE | `/photos/{id}` | Fotoğrafı siler |
| GET | `/health` | Sağlık kontrolü |

## Güvenlik notları

- �?ifreler bcrypt ile saklanır. Access token 30 dakika, refresh token 180 gün
  (kullanıcı yılda birkaç kez giriş yapsın diye).
- �?ifre değişimi `token_version` değerini artırarak **tüm cihazlardaki**
  oturumları düşürür.
- Başarısız giriş denemeleri e-posta bazında sınırlanır (5 dakikada 10).
- Var olmayan hesap ile yanlış şifre **aynı** yanıtı verir; hangi e-postaların
  kayıtlı olduğu sızdırılmaz.
- Yüklenen dosyanın türü istemcinin bildirdiği `Content-Type`'a değil, dosyanın
  kendi imzasına bakılarak belirlenir. `.jpg` uzantılı bir kabuk betiği 415 alır.
- Fotoğraflar kimlik doğrulaması arkasındadır ve nginx tarafından statik olarak
  servis edilmez. Başkasına ait bir fotoğraf, var olmayan bir fotoğrafla aynı
  404 yanıtını alır.
- Uygulama container içinde root olarak çalışmaz.
- PostgreSQL portu dışarıya açılmaz.

## Yedekleme

Kalıcı veri iki Docker volume'undadır:

```bash
# Veritabanı
docker compose exec -T db pg_dump -U vaktinde vaktinde | gzip > yedek-$(date +%F).sql.gz

# Fotoğraflar
docker run --rm -v backend_photos:/data -v "$PWD:/yedek" \
  alpine tar czf /yedek/fotograflar-$(date +%F).tar.gz -C /data .
```

## �?ema değişikliği yaparken

Tablolar açılışta `Base.metadata.create_all` ile oluşturulur. Bu yalnızca
**eksik tabloları** ekler; mevcut bir tabloya sütun eklemez. İlk sürümden
sonra şema değiştirecekseniz önce Alembic ekleyin, yoksa üretimdeki tablo
sessizce eski hâlinde kalır.
