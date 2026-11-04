# Clinical Teal UI V2.0 — Aşama 3

Başlangıç commit: `2e42123a671c368a2f379e08d9bfb05fb488d203`
Geliştirme branch'i: `feat/clinical-teal-ui-v2`

## Değişiklikler

- `schedule_page.dart`: mevcut Clinical Teal teması kalan modül sayfalarına
  uygulandı. Masaüstü içerik genişliği ortak `maxContent` token'ıyla sınırlandı.
  Personel kartlarında ad, K sırası, grup, aktiflik, isim düzenleme ve sıralama
  tutamacı kapalı durumda görünür. Grup/aktiflik ve personel ayrıntıları açılır.
  Seçili ayın kısıt sayıları ve mevcut Nöbet ekranına erişim sunulur. Personel
  başlığı listeyle kayar; %200 metinde liste alanını tüketmez.
- Aylık asıl/yedek görev kartları ortak responsive grid ve `AkysCard` kullanır.
  Mevcut atama ve override dialogları, kayıt callback'leri ve doğrulama korunur.
- `combined_day_cards.dart`: Görev Dağılımı ve Birleşik Görünüm tarafından
  paylaşılan günlük görünüm. Tarih filtresi, mobilde açılır kartlar, masaüstünde
  çok sütun; nöbet, klinik görev ve nöbet sonrası izin ayrı bölümler. Explicit
  senior/junior bilgisi mevcut `CompactDutyCard` ile gösterilir; eski kayıtlarda
  pozisyon tahmin edilmez. Nöbet hard constraint ihlalleri hata, görev motorunun
  uyarıları uyarı olarak gösterilir. Pasif görevlerde edit işlemi gösterilmez.
- `difficulty_widgets.dart`: modelden okunan puanlar responsive ortak kartlarda;
  1–10 tam sayı seçimi, varsayılanlara dönüş, kaydetme korunur. Yerel değişiklikten
  vazgeçme ve kayıt sonucunu açıklayan durum etiketi eklendi. Ana controller'ın
  başarı/hata mesajları da korunur.
- `remaining_teal_test.dart`: 12 kabul testi; diğer iki widget test dosyasında
  açılır ayrıntı ve scroll animasyonu için etkileşim uyarlamaları.

## İşlevsel sınırlar

V1.2/V1.3 solver, görev algoritması, veri modeli, repository/controller,
Firebase/auth, Rules, feature flag, kesinleştirme ve paylaşım izinleri değişmedi.
Nöbet kısıtlarını değiştirme işlemi mevcut ay ekranında ve mevcut onay akışıyla
kalır. Sıralama/grup değişikliği geçmiş snapshot'ları dönüştürmez.

Görev aktifliği yalnız mevcut `dailyTasks` sonucundan okunur. Yeni iş günü
snapshot'larında hafta sonu/tam tatil pasif, yarım tatil 13.00 öncesi aktiftir.
**Mevcut eski ay davranışı:** `taskWorkdaySchemaVersion == 0` kayıtları hafta
sonunda da görev gösterebilir. Bu yeni UI hatası değildir; mevcut geriye dönük
uyumluluk davranışıdır ve sessizce düzeltilmedi. Görev ekranındaki eski ay uyarısı
ve yalnız taslak ay için mevcut onaylı yeniden hesaplama işlemi korundu.

## Kabul kapsamı

320/800/1440px, %200 metin, uzun personel adları; açılır personel, grup değişikliği,
sıralama callback'inin kalıcı kaydı, isim düzenleme; asıl/yedek doğrulaması ve
kaydı, manuel görev override; nöbet sonrası izin; hafta sonu, tam/yarım tatil;
ayar iptal/hata durumu ve mevcut puan persistence testleri. Mevcut V1.2/V1.3
algoritma testleri değiştirilmedi.

## Sınırlamalar

Fiziksel Android cihaz, gerçek ekran okuyucu ve canlı production verisiyle test
yapılmadı. Android kontrolü build doğrulamasıdır. Alt navigasyonun mevcut yatay
kaydırma davranışı korundu. Geniş ekranda birleşik görünüm tablo yerine çok
sütunlu açılır kartlar kullanır. Görsel değişiklikler production'a yayımlanmadı.

## Doğrulama sonuçları

- Flutter analyze: bulgu yok.
- Tam Flutter test paketi: 219 test (207 mevcut + 12 yeni).
- Chromium: 12 yeni UI kabul testi ve 20 mevcut grup/puanlama/V1.3 entegrasyon
  testi; mevcut testler ilk 30 testlik koşuda, yeni testlerin son hali ayrı
  12 testlik koşuda doğrulandı.
- Web release ve Android debug APK build doğrulandı. Mevcut Cupertino font ve
  Kotlin geçiş uyarıları build'i engellemedi.
- `git diff --check` temiz. Korunan domain/engine/data/application/auth/Firebase
  ve workflow yollarında fark yok.
- Push, main merge, deploy ve production veri işlemi yapılmadı.
