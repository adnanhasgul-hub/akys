# Clinical Teal UI V2.0 — Aşama 4

Başlangıç: `227cc9f24b1cb3c3f97bef626fe183239b02ac63`
Branch: `feat/clinical-teal-ui-v2`. Başlangıç çalışma ağacı temizdi.

## Navigasyon ve ekran yapısı

Mevcut `AkysAdaptiveNavigation` gerçek Çalışma Çizelgesi ekranına bağlandı.
Mobilde Genel Bakış, Nöbet, Görevler, Personel ve Diğer vardır. Diğer menüsü
Birleşik Görünüm, Geçmiş Aylar ve Ayarlar'ı açar. Ek sayfa seçildiğinde Diğer
seçili gösterilir. Geniş ekranlarda aynı hedefler Clinical Teal yan menüdedir.

Breakpoint'ler mevcut merkezi `AkysTokens.tablet` (720) ve `desktop` (1100)
değerleridir. Yeni tema oluşturulmadı. Yan menü %200 metinde dikey kaydırılabilir;
yalnız yedi öğe bulunduğundan hedefler klavye/erişilebilirlik için birlikte
oluşturulur. Mobilde yatay kaydırmalı sekme satırı kaldırıldı. Kontroller mevcut
48px minimum dokunma alanı, etiket ve seçili durum semantiğini korur.

Ekranlar IndexedStack içinde tutulur. Ayarların henüz kaydedilmemiş yerel
seçimleri, sayfa kaydırması ve V1.3 panel durumu sekme değişiminde korunur.
Sayfa scroll controller'ları ortak primary controller'ı paylaşmaz. Repository
revizyonu/ay değişimi mevcut anahtar davranışını korur. Kaydetme sırasında
navigasyon kilitlidir; açık menüden geç gelen seçimde de kilit kontrol edilir.
Modülden geri çıkış mevcut Navigator akışıdır; çıkıp yeniden açma yerel taslağın
kalıcı kayıt olduğu anlamına gelmez.

Ortak başlık, loading ve merkezi boşluklar korundu. Boş sayfalar ortak
AkysEmptyState kullanır; geçmiş aylar ortak kart ve boşluk token'larına geçti.
Masaüstü içerik genişliği mevcut maxContent sınırında kalır. Kısa mobil ekranda
ve büyük metinde başlık alanı gerektiğinde kayar; içerik için alan bırakılır.
Yükleme ve boş durumlar da dar yükseklikte taşmadan kaydırılabilir.

## İşlevsel sınır

Solver, görev algoritması, Firestore/model/repository/controller, kimlikler,
yetkilendirme, Firebase yapılandırması, Rules, workflow ve feature flag değişmedi.
V1.3 varsayılan kapalıdır; kesinleştirme ve paylaşım kısıtları korunur.

## Kabul kapsamı

- 320, 414, 800, 1440 piksel; %100 ve %200 metinle tüm navigasyon hedefleri.
  Dar ve büyük mobil senaryoları 750px ekran yüksekliğiyle de doğrulandı.
- Ay seçimi, uzun isimler, personel düzenleme/sıralama, görev atama ve override,
  manuel nöbet düzenleme mevcut regresyon paketinde.
- Kaydedilmemiş puan değerinin başka sekmeden geri dönünce korunması ve henüz
  Firestore'a kaydedilmemesi; modülden geri navigasyon.
- Klavyeyle Diğer açma, Escape ile kapama; V1.3 panel State kimliğinin korunması.
- V1.3 başlat/iptal, taslak önizleme/onaylı kaydetme ve yetkilendirme mevcut
  entegrasyon testleriyle korunur. Flag açık ek koşu production ayarı değildir.
- 1 Kasım 2026 eski/yeni görev şeması karşılaştırması yalnız yerel fixture ile.

Yeni menü sebebiyle eski UI testleri yeni navigasyon yardımcısına ve görünür
sayfanın kaydırma alanına uyarlandı; domain/solver testleri değiştirilmedi.

## Bilinen sorun ve production öncesi riskler

`NOVEMBER_2026_SUNDAY_TASK_REPORT.md` eski ayların Pazar günü görev hesaplamasını
ayrı inceler. İş kuralı bu aşamada değiştirilmedi; production ay belgesinin şema
sürümü incelenmedi. Bu bulgu sürüm onayında ayrıca değerlendirilmelidir.

Fiziksel cihaz ve gerçek ekran okuyucu testi yapılmadı. Chromium/widget testleri
layout ve etkileşim doğrulamasıdır; gerçek cihaz/gerçek yazı tipiyle insan görsel
kabulünün yerini tamamen almaz. Android kontrolü debug APK build seviyesindedir.
Bellekte korunan sayfaların düşük kapasiteli fiziksel cihazlardaki performansı
ayrıca ölçülmelidir. Production'a geçiş için ayrı onay ve yayın görevi gerekir.

Push, merge, deploy veya production veri işlemi yapılmadı.

## Doğrulama sonuçları

- `flutter analyze --no-pub`: temiz.
- `flutter test --no-pub`: 231/231 başarılı (219 mevcut + 12 yeni).
- Chromium kabul paketi: 58/58 başarılı; ana sayfa, Aşama 2/3 ekranları,
  navigasyon, V1.3 entegrasyonu ve kısa mobil ekranlar dahil.
- `AKYS_V13_SOLVER=true` ile panel durumunu koruma testi: 1/1 başarılı.
  Varsayılan kapalı bayrak da normal test paketinde doğrulandı.
- `git diff --check`: temiz. Korunan iş mantığı/veri/güvenlik/workflow yollarında
  fark yok.
- Web release build: başarılı.
- Android debug APK build: başarılı. Cupertino font, Kotlin geçişi ve Android SDK
  XML sürüm uyumu uyarıları var; build'i engellemedi. Toolchain modernizasyonu
  bu UI görevinin kapsamı dışında bırakıldı.
