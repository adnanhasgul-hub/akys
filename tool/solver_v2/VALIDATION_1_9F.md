# AKYS V2 — 1.9F yerel yayın hazırlığı

16 Kasım 2026. Başlangıç `4f1d9caafb6d275315d6bebaa5a8612d75fe9a19`,
`feature/akys-v2-solver-core`; başlangıç ağacı temiz. Production okunmadı veya
 değiştirilmedi; push, merge, deploy, ücretli kaynak veya kullanıcı işlemi yapılmadı.

## Sonuç ve güven sınırı

Yerel klinik onay prototipi güçlendirildi, migration provası ve platform testleri
çalıştırıldı. **Production onayı hazır/açık değildir.** Gerçek Firebase Google key
rotation/revocation doğrulaması, kimlik gateway'i, imzalı kullanıcı zarfı, ADC
Firestore adapter ve Cloud Run IAM entegrasyonu uygulanıp doğrulanmadı. A ve B
istemci onayı kapalı kalır. B kalıcı onayı yasaktır. Bu eksikler nedeniyle bütün
production kabul kriterleri karşılandı denemez; bu commit güvenli hazırlık çıktısıdır.

Dart HTTP servisinde gerçek bağımsız validator çalışır. Yerel test issuer'ına ait
RS256 imzalar kontrol edilir; Google tarafından verilmiş gerçek token testi değildir.
Servis yalnız loopback/demo-akys emülatörünü kabul eder. Firebase Emulator'daki
`Bearer owner` production kimliği değildir. Production'a bu binary yönlendirilemez.

Head/version metadata eşitliği (depolama göstergesi historySchema hariç), tam payload
SHA-256 bağı, immutable sürüm, atomik audit ve idempotency güçlendirildi. İki farklı
admin yarışında yalnız bir onay oluşur; diğer admin aynı operasyonla başarı alamaz.
Onaylı payload değişmişse tekrar isteği digest kontrolünde reddedilir. A fizibilitesi
optimumluk kanıtı değildir. İstemci proof/quality/onay alanları yetki oluşturmaz.
Başarısız klinik doğrulama yazma oluşturmaz. Commit gönderildikten sonra yanıt kaybı
olursa sonuç belirsiz olabilir: aynı operation ID ile tekrar sorgulanır; timeout
hiç yazma olmadığının genel kanıtı değildir. Yerel timeout testi commit ÖNCESİ
bekleyen okuma içindir (5.077 sn, 0 commit isteği).

## IAM, Rules ve yayın dosyaları

`deployment/approval/SECURITY_AND_RELEASE.md` güven sınırlarını, servis hesabını,
Rules/index/Hosting/Android dağıtım sırasını, rollback ve maliyetleri açıklar.
`cloud-run.template.yaml` review-only placeholder içerir; çalışır production imajı
veya uygulanmış kaynak değildir. `runtime-role.json` önerilen en küçük işlem
allowlist'idir. Statik kontrol 5 PASS; **gerçek IAM yetki testi yapılmadı**.
Firestore IAM collection izolasyonu sağlamaz; Admin erişim Rules'ı atlar. Sunucuda
kimlik, sabit yol, snapshot ve transaction kontrolleri ayrıca gereklidir.
Rules değiştirilmedi; istemci onayı, audit yazımı ve immutable sürüm değişikliği
negatif emülatör testleri korunuyor. Deploy workflow'ları değiştirilmedi.

## Test ve platform sonuçları

| Kontrol | Sonuç |
|---|---|
| Tam Flutter paketi (Dart solver/oracle/kalite dahil) | 277 PASS |
| Gerçek Chromium regresyon paketi | 68 PASS |
| Gerçek Web Worker | 18/18 PASS |
| WebCrypto/IndexedDB kurtarma | 5 kontrol grubu PASS |
| Dart HTTP onay / Firestore emülatörü | 19 kontrol grubu PASS |
| Servis okuma timeout | PASS, 0 commit isteği |
| V2 Firestore Rules | 55 PASS |
| Eski veri koleksiyonlarının erişim sınırı | PASS |
| Migration emülatör kabulü | 9 kontrol grubu PASS |
| Önerilen IAM/template statik politika kontrolü | 5 PASS; gerçek IAM değil |
| Flutter analyze ve Dart analyze | Temiz |
| Android debug APK | Başarılı, 44.9 sn |
| Standart Web release + Worker | Başarılı, 46.0 sn + Worker 2.32 sn |
| Auth/Firestore gerçek Flutter tarayıcı akışı | 8 kontrol grubu PASS, production API isteği 0 |

Bu satırlar aynı kapsamı farklı platformlarda tekrar doğrular; sayılar tek bir
benzersiz test toplamı olarak toplanmamalı. 1.9E'deki 276 VM ve 67 Chromium testine
31 günlük ayda son slota kaydırma testi eklendi. Mevcut DFS/A-B/19 bileşen/strateji
ve forward-checking kaynakları değiştirilmedi. `lib/` ve Android kaynak farkı yok.

ADB cihaz listesi boş; uygun emülatör system image yok. Android giriş/admin,
Keystore kurtarma, dokunmatik taşıma ve hesap değişimi cihazda çalıştırılmadı.
APK başarısı bu testlerin yerine geçmez. Derlemede mevcut Kotlin/SDK XML uyumluluk
uyarıları var. Web build Cupertino font ailesi uyarısı veriyor; yeni ikon/tema
veya bağımlılık değişikliği yapılmadı.

## Flutter profil ölçümleri

Linux container; Flutter 3.47.9, Dart 3.13.7, Chromium 154.0.8037.57; release Flutter.
Aynı deterministik `20-open`, 20 hekim/31 gün, 414 ve 1440 px, her biri üç tekrar.
600 ms ısınma sonrası 4 sekme tıklaması ve 18 kaydırma. CDP timeline + rAF + longtask.
Aynı benchmark zincirinde koşular ardışık; paylaşımlı host yükü sabitlenemiyor.
Profil enstrümantasyonu ek maliyet getirir; kapalı profil kontrolü yapılmadığı için
bu maliyet yüzdesi ölçülmüş değildir. rAF değerleri Flutter raster frame süresi değildir.

| Sürüm | Mobil rAF p95 (3 tekrar) ms | Masaüstü rAF p95 ms | En kötü aralık mobil / masaüstü ms |
|---|---|---|---|
| Önce | 33.4 / 33.4 / 33.4 | 50 / 50 / 50.1 | 200 / 233.3 |
| Son, kaynak geri alınmış | 50 / 33.4 / 33.4 | 83.2 / 50.1 / 50 | 249.9 / 316.6 |

İki lazy-list denemesi yapıldı: varsayılan cache ve 2000 px cache. Masaüstü p95
66.7–83.4 ms bandına kötüleşti; tutarlı kazanç göstermedi. **Her iki deney geri
alındı. Son arayüz kodu başlangıçla aynıdır.** Önce/sonra değişkenliği ölçüm ortamı
riskini gösterir; hızlanma iddia edilmez. Ham deneyler silinmedi:
`results/stage_1_9f_profile_{before,after,lazy_default_cache,lazy_large_cache}.json`.

Ölçülen son long-task en kötüsü mobil256 / masaüstü320 ms. Son FunctionCall p95
mobil12.5–18.1 / masaüstü27.8–30.5 ms; browser Layout/Paint daha küçüktür. Bu CDP
ölçümü Flutter widget rebuild/raster dağılımını tek tek açıklamaz. CanvasKit/semantics
ve Dart callback içi tablo oluşturma aday darboğazlardır; kesin widget kök nedeni
olarak sunulmaz. Tab ölçümleri 100 ms kasıtlı bekleme içerir. Sonraki ölçüm Flutter
profile/DevTools frame ve rebuild verisiyle, sabit yük altında olmalıdır.

## Migration ve maliyet

`tool/firestore_migration` yalnız demo emülatörü kabul eder. Varsayılan dry-run,
50 belgeli cursor sorguları, 25 payload'lık Dart decoder grupları, source digest,
create-only metadata, en son updateTime CAS ile head cutover. Checkpoint geçici
 dosya + fsync + rename; bozuk checkpoint yazmadan reddedilir. Kaynak sürüm/payload
silinmez veya değiştirilmez. Tamamlanan metadata tekrar yazılmaz. Kaynak okumaları
tekrar doğrulanır; checkpoint sunucu kanıtı değildir. Bir hatadan önceki metadata
kalabilir; legacy head cutover olmadan bunları kullanmaz. Hash/numara raporu geçmiş
uzunluğuyla büyür. Production için ayrı backup/canary/rate-limit/yetki süreci gerekir.

İki sentetik çizelge, 125+2 sürüm; 3 yazma sonrası kesinti ve devam test edildi.

| Koşu | Dönen belgeler | Bulunmayan point read | Tahmini belge okuması* | Yazma |
|---|---:|---:|---:|---:|
| Dry-run | 129 | 127 | 256 | 0 |
| Kesinti sonrası devam | 132 | 124 | 256 | 126 |
| Tamamlanmış tekrar | 2 | 0 | 2 | 0 |

*Index/Rules bağımlı okumalar dahil değil; emülatör sayaçlarından hesap, gerçek fatura
değil. İlk üç metadata yazmasıyla toplam127 metadata+2 head yazılır. 127 orijinal
sürümün alanları/baytları aynı kaldı. CAS yarışı, bozuk metadata, rollback ve corrupt
checkpoint negatif testleri geçti. Ham kaynak: `results/stage_1_9f_migration.json`.

Örnek tam sürüm JSON4231 byte, metadata538 byte (%87.3 azalma). Bu fixture boyutudur,
genel tasarruf garantisi değil. 25 sürümlük sayfa yine25 belge okur; sadece payload
byte azalır; açılan sürüm ek1 payload read gerektirir. Legacy yol migration öncesi
tam payload okumayı sürdürür. version/at + documentId sorguları için yeni composite
index yok; production index exemption durumu okunmadı. Listener sorguları bu aşamada
değiştirilmedi; canlı fatura/traffic ölçülmedi.

## Kalan yayın engelleri ve öneri

- Gerçek Firebase token/gateway/ADC ve Cloud Run IAM zincirini güvenlik incelemesi
  ve izinli ortam testi olmadan açma. A/B uygulama onayı kapalı kalsın.
- Fiziksel Android/emülatör Auth, Keystore, oturum izolasyonu kabulü eksik.
- UI uzun frame aralıkları sürüyor; ölçümden bağımsız hız iddiası yok.
- Production migration çalıştırılmadı; yerel dry-run üretim veri kalitesini kanıtlamaz.
- Yerel şifreli kurtarma XSS veya ele geçirilmiş aynı-origin koduna karşı tam koruma
  değildir; browser/OS verisi silinince kesin kurtarma garantisi yok.
- IAM ve onay altyapısı tamamlanmadan production-ready PASS verilmiyor. Güvenli
  kapalı davranış ve mevcut klinik doğruluk korunuyor.

Değişen dosyalar: `CHANGES_1_9F.txt`. Yerel commit SHA son teslim mesajında verilir;
raporu içeren commit'in kendi SHA'sı rapora gömülmez.
