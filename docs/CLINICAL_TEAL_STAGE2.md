# Clinical Teal UI V2.0 — Aşama 2

Başlangıç: `bc4444370e4db02079d531bbc5d9388d336c7ced`
Branch: `feat/clinical-teal-ui-v2`

## Kapsam

Mevcut Clinical Teal token ve bileşenleri kullanıldı; yeni tema oluşturulmadı.
Genel Bakış ve Nöbet sayfalarına yerel tema uygulandı. Diğer sayfaların teması ve
mevcut navigasyon davranışı korundu.

- Ortak `AkysMonthSelector`: ay/yıl, ayrı durum etiketi, loading/empty durumları;
  mevcut controller ay seçimi callback'ini kullanır.
- Ortak `AkysResponsiveTiles`: doğal yükseklikli grid, dar ekran ve büyük metinde
  tek sütun; uygun mobil genişlikte iki, geniş ekranda daha fazla sütun.
- `AkysCard` isteğe bağlı padding ve `AkysStatCard` compact görünüm desteği.
- Genel Bakış: aktif personel, kayıtlı/kesinleşmiş-paylaşılmış aylar, seçili ay
  durumu ve uyarı sayısı; uzun yönergeler açılır yardım bölümünde.
- `CompactDutyCard`: kapalı durumda tarih, hekimler, açık pozisyonlar, zorluk,
  tatil ve uyarılar; açılınca tam adlar, kalıcı grup, kıdem, geçici senior,
  junior boşluk gerekçesi ve mevcut düzenleme işlemleri.
- Eski V1.2 kayıtlarında pozisyon tahmin edilmez; eksik bilgi açıkça belirtilir.
- Hafta sonları hafif nötr vurgu kullanır. Hata rengi yalnız doğrulama hatasında
  kullanılır; tatil, geçici atama ve optimizasyon bilgileri ayrı etiketlidir.
- `SolverStatusSummary`: geçerlilik, hiyerarşi kanıtı, genel optimumluk ve arama
  sınırını ayrı gösterir. Geçerli önizleme ve mevcut arama/iptal/düzenleme/onaylı
  taslak kaydetme işlemleri korunur.

Solver, domain, repository, Firebase, yetkilendirme, Rules ve feature flag
mantığı değiştirilmedi. V1.3 varsayılan kapalıdır; kesinleştirme/paylaşım izinleri
aynıdır. V1.3 panelindeki değişiklikler sunum katmanıyla sınırlıdır.

## Doğrulama

- `flutter analyze --no-pub`: başarılı, bulgu yok.
- `flutter test --no-pub`: 207/207 başarılı.
- Chromium: yeni tasarım ve mevcut V1.3 entegrasyon testleri 20/20;
  ayrıca 320px / %200 V1.3 panel testi 1/1 başarılı.
- Web release build: başarılı.
- Android debug APK: başarılı.
- Yeni 10 test: 28/30/31 gün, 320/800/1440px, %200 metin, uzun isim,
  junior boşluğu, geçici senior, tatil/hata ayrımı, eski kayıt, ay seçici,
  arama sınırı/kanıt durumları ve V1.3 açık panel.
- Mevcut V1.3 solver testleri değiştirilmedi. Eski UI testindeki sabit piksel
  kaydırma, yeni kompakt düzende hedef widget'a kaydırmayla değiştirildi.
- `git diff --check`: başarılı.

## Sınırlamalar

Geniş mevcut adalet tabloları yatay kaydırılabilir. Alt navigasyon davranışı bu
kapsamda değiştirilmedi. Fiziksel Android cihaz, ekran okuyucu ve production
verisiyle kabul testi yapılmadı. Web build Cupertino font uyarısı ve Android
build Kotlin geçiş uyarısı veriyor; iki build de başarıyla tamamlandı.

Push, main merge, Firebase/Hosting deploy veya production veri işlemi yapılmadı.
