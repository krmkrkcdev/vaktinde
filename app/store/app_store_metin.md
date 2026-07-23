# App Store mağaza metinleri — Vakitlice

App Store Connect → Vakitlice → Uygulama Bilgileri / Sürüm Bilgileri
bölümlerine girilecek metinler. Karakter sınırları Apple'ın koyduğu üst
sınırlardır; sayımlar bu dosyadaki metinlere aittir.

---

## Uygulama adı (30 karakter)

```
Vakitlice
```

## Alt başlık (30 karakter)

Ada eklenen kısa tanım; arama sonuçlarında adın altında görünür.

```
Fatura, kira, sigorta takibi
```
*(28 karakter)*

## Anahtar kelimeler (100 karakter)

Virgülle ayrılır, **boşluk bırakılmaz** — boşluk da karakter sayılır.
Uygulama adında ve alt başlıkta geçen kelimeleri tekrar yazmak gereksizdir;
Apple onları zaten indeksler.

```
kira,aidat,taksit,sigorta,muayene,abonelik,son ödeme,vade,takip,bütçe,gider,anımsatıcı
```
*(86 karakter)*

## Promosyon metni (170 karakter)

Sürüm güncellemesi gerektirmeden istediğiniz zaman değiştirilebilir.

```
Kira, fatura, aidat, sigorta ve muayene tarihlerini bir kez yazın; zamanı
gelince biz hatırlatalım. Çevrimdışı çalışır, internet gerektirmez.
```

## Açıklama (4000 karakter)

```
Kira ödemesini, aidat gününü, trafik sigortasının bitişini ya da araç
muayenesini kaçırmak pahalıya mal olur. Vakitlice bu tarihleri sizin
yerinize takip eder.

Bir kez yazarsınız, gerisini uygulama hatırlar.


NASIL ÇALIŞIR

• Hatırlatmayı adım adım eklersiniz: kategori, isim, tarih, tekrar aralığı
• Kaç gün önceden uyarılmak istediğinizi siz seçersiniz — 1 gün, 1 hafta,
  1 ay öncesinden, hepsi birden de olabilir
• Bildirim saatini belirlersiniz
• Ödediğinizde "tamamlandı" dersiniz, tarih kendiliğinden sonraki döneme
  geçer


NELERİ TAKİP EDEBİLİRSİNİZ

• Kira ve aidat
• Elektrik, su, doğalgaz, internet, telefon faturaları
• Trafik sigortası, kasko, araç muayenesi
• Kredi kartı ve kredi taksitleri
• Dijital abonelikler
• Ehliyet, kimlik, pasaport yenileme
• Garanti bitiş tarihleri
• Vergi ve harçlar


UNUTURSANIZ ISRAR EDER

Son gün geldiğinde bildirimi görüp "tamamlandı" demezseniz, belirlediğiniz
aralıkla tekrar hatırlatır. Saatte bir, üç saatte bir — siz seçersiniz.
İşaretlediğiniz anda tekrarlar durur.


ÖDEMELERİNİZİ TOPLU GÖRÜN

Düzenli ödemeleriniz sıklığına göre toplanır: aylık ödemeleriniz kendi
içinde, yıllık olanlar kendi içinde. Ayrıca hepsinin toplamını günlük,
haftalık, aylık ve yıllık karşılığıyla görürsünüz. "Ayda toplam ne kadar
gidiyor?" sorusunun cevabı bir bakışta.


BELGELERİNİZ YANINIZDA

Faturanın, poliçenin ya da garanti belgesinin fotoğrafını hatırlatmaya
ekleyebilirsiniz. Aradığınızda dosya karıştırmazsınız.


İNTERNET GEREKTİRMEZ

Uygulama çevrimdışı çalışır. Hatırlatmalarınız telefonunuzda saklanır,
bildirimler internet olmadan da gelir. Hesap açmadığınız sürece hiçbir
veriniz dışarı çıkmaz.

İsterseniz ücretsiz hesap açıp kayıtlarınızı yedekleyebilirsiniz; telefon
değiştirdiğinizde giriş yapmanız yeterli olur.


PREMIUM

Ücretsiz sürümde 20 hatırlatma ekleyebilirsiniz ve uygulamada reklam
gösterilir.

Premium abonelikle:
• Sınırsız hatırlatma
• Reklamsız kullanım

Abonelik yıllıktır ve dönem sonunda otomatik yenilenir. Dilediğiniz zaman
Ayarlar > Apple Kimliği > Abonelikler bölümünden iptal edebilirsiniz.

Gizlilik politikası: https://vaktinde.devposs.com/gizlilik
```

## Sürüm notları — 1.0.0 (What's New)

```
Vakitlice'nin ilk sürümü.

• Kira, fatura, aidat, sigorta, muayene ve abonelik takibi
• Kaç gün önceden ve saat kaçta hatırlatılacağını siz seçersiniz
• Tamamlamazsanız ısrarla tekrar hatırlatır
• Düzenli ödemelerinizin haftalık, aylık ve yıllık toplamı
• Belge fotoğrafı ekleme
• Çevrimdışı çalışır; isteğe bağlı bulut yedekleme
```

---

## Diğer alanlar

| Alan | Değer |
|---|---|
| Birincil kategori | Finans |
| İkincil kategori | Yaşam Tarzı *(isteğe bağlı)* |
| Gizlilik politikası URL | `https://vaktinde.devposs.com/gizlilik` |
| Destek URL | ⚠️ gerekli — aşağıya bakın |
| Pazarlama URL | isteğe bağlı, boş bırakılabilir |
| Telif hakkı | `2026 Kerem Karakoç` |

### Destek URL'i

App Store zorunlu tutuyor. Ayrı bir sayfa hazırlanabilir ya da geçici olarak
gizlilik politikası adresi verilebilir; iletişim e-postası orada yer alıyor.

### Yaş derecelendirmesi

Anket doldurulacak. Uygulamada şiddet, müstehcenlik, kumar, alkol/tütün
içeriği yok; tüm sorulara "Yok/Hayır" yanıtı verilir. Beklenen sonuç: **4+**

Dikkat: "Sınırsız Web Erişimi" sorusuna **Hayır** denmeli — uygulama
tarayıcı içermiyor. Reklam SDK'sı bunu değiştirmez.
