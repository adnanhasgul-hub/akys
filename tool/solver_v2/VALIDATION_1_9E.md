# AKYS V2 — 1.9E yerel doğrulama raporu

Başlangıç: `24587e9c9ccd904ed8273c78e96efde14a2158bf`,
`feature/akys-v2-solver-core`, temiz çalışma ağacı. Tarih: 16 Kasım 2026.
Production/Firebase deploy, push, merge, kullanıcı veya canlı veri işlemi yapılmadı.

## Gerçek çalışma durumu

- Mevcut Dart validator ile çalışan **yerel HTTP onay prototipi** eklendi.
  Firestore emülatöründe A onayı, immutable sürüm, idempotent tekrar ve eşzamanlı
  transaction davranışı doğrulandı. B onayı yasak. İstemci proof alanı reddediliyor.
  Ayrıntı: `tool/clinical_approval/README.md`.
- Uygulamanın kalıcı onayı **A ve B için hâlâ kapalı**. Production Firebase token
  anahtar yenileme/revocation ve Cloud Run IAM/ADC bağlantısı kurulup doğrulanmadı.
  Yerel test issuer'ı, gerçek Firebase kimlik doğrulamasının yerine geçirilmedi.
  Dart motorunun sunucuda çalışması mümkün ve yerelde gösterildi; production
  operasyonel güven sınırı tamamlanmış değildir. Özel RS256 kodu bağımsız güvenlik
  incelemesi olmadan production'a taşınmamalı.
- Başarılı onayın sunucu audit belgesi atomik. Reddedilen servis istekleri süreç
  loglarıdır; kalıcı/değiştirilemez reddedilme arşivi iddia edilmiyor.
- Web kurtarma AES-GCM + dışa aktarılamayan CryptoKey/IndexedDB ile gerçek Chromium'da
  çalıştı. Android Keystore + noBackupFilesDir kanalı derlendi; cihaz yok.
- Yeni sürümlerin geçmişi payload-free metadata kullanıyor. Legacy kayıtlar uyumlu
  okunuyor ama geçmişteki tam-payload maliyeti otomatik migration olmadan sürüyor.
- DFS, klinik kurallar, 19 kalite tanımı, A/B protokolü, strateji/forward-checking
  varsayılanları değiştirilmedi. Editörün immutable revizyon okuması önbelleklendi;
  mutable oturum kanıtı varsa yeniden doğrulama aynen sürüyor.

## Doğrulamalar

| Kontrol | Sonuç |
|---|---|
| Tam Flutter paketi | 276 PASS |
| Chromium regresyonları | 67 farklı test PASS (66 testlik paket + güncellenmiş 4 kurtarma testi; 3 örtüşüyor) |
| Gerçek Worker kabulü | 18/18 PASS |
| Gerçek Auth/Firestore/Flutter akışı | 8 kontrol grubu PASS, production API isteği 0 |
| Gerçek WebCrypto/IndexedDB | 5 kontrol grubu PASS |
| Firestore V2 Rules | 55 PASS; mevcut eski veri erişim sınırı testi de PASS |
| Dart yerel onay HTTP/emülatör | 13 kontrol grubu PASS; imzalı olmayan/sahte/expired/yanlış issuer-audience/admin, B, bozuk snapshot, proof, version ve yarış kontrolleri |
| Onay deposu zaman aşımı | 5.079 saniyede timeout; commit isteği 0 |
| Flutter analyze / dart analyze | Temiz |
| Web release + Worker | Başarılı, yalnız yerel build |
| Android debug APK | Başarılı; ADB cihaz listesi boş |

Başarısız denemeler gizlenmedi: ilk Flutter testi sandbox soket iznine takıldı;
Android kanalında AAD String/ByteArray tip hatası düzeltildi; Firestore emülatörü
GET transaction query'de BYTE_STRING hatası verdi, transaction içi POST batchGet
ile giderildi. Sunucu fixture'ındaki `missing` kaydı Rules testinin yokluk
fixture'ıyla çakıştı; Rules testi kendi emülatör verisini temizleyerek yalıtıldı.
Sunucu policy testi tool dosyası import ettiği için Chromium test sunucusunda
derlenmedi; VM paketi ve gerçek HTTP emülatör testiyle doğrulanıyor. Tarayıcıya
uygun paket ayrı çalıştırıldı. Bir Web build komutu otomatik onay incelemesindeki
kullanım sınırı nedeniyle hiç başlamadı; devam talebi sonrasında çalıştırıldı.

## Ölçülen performans

Linux x86_64 container, Flutter 3.47.9 / Dart 3.13.7, Chromium 154.0.8037.57.
VM ölçümü JIT; tarayıcı Worker `dart compile js -O2`, Flutter UI release.
Tek benchmark zincirinde ardışık koşular; paylaşımlı host yükü sabitlenemedi.

### Serileştirme/doğrulama sıcak yolu

Aynı fixture, kaydedilmiş taslakta 1.000 dirty okuması, üç tekrar, VM test ortamı:

| Fixture | Önce medyan | Sonra medyan |
|---|---:|---:|
| 6 hekim / 30 gün | 219.177 ms | 5.820 ms |
| 15 hekim / 31 gün | 423.450 ms | 5.553 ms |

Bu sonuç yalnız ölçülen getter/serileştirme yoluna aittir. Tüm uygulamanın aynı
oranda hızlandığı anlamına gelmez. Kaynak bulgu: `ScheduleEditor.current` her getter
okumasında tüm doğrulama/kaliteyi yeniden hesaplıyordu; immutable revizyonda bunun
tekrarı gereksizdi. Dirty kontrolü ayrıca tam JSON+validator çağırıyordu.

Gerçek Flutter 414/1440 px Worker akışı:

| Ölçüm | Önce | Sonra | Sonra tekrar |
|---|---:|---:|---:|
| En büyük heartbeat aralığı | 158.3 ms | 119.2 ms | 135.3 ms |
| Kullanıcı tıklamasından iptal görünümü | 155.8 ms | 148.1 ms | 183.7 ms |
| Kaydırma gidiş/dönüş, 500ms kasıtlı bekleme dahil | 725.0 ms | 911.9 ms | 920.2 ms |

**Sınırlama:** Tüm UI gecikmeleri çözülmedi. Kaydırma sonucu iyileşmedi; iptal
etkileşiminde değişkenlik var. Bu değerler saf frame süresi değildir; Playwright,
semantics ve beklemeleri içerir. Genel performans PASS veya cihaz garantisi
çıkarılmadı. Sonraki adım tablo/semantics için frame timeline profili olmalı.

### Strateji karşılaştırması (varsayılan değiştirilmedi)

Seed 160600, `6-open` (30 gün), `15-open` (31 gün), her strateji/platform üç tekrar.
2 sn bütçe, 400ms sonra +2 sn uzatma, ardından 700ms sonra iptal. Yaklaşık 1.1 sn
arama penceresidir; 30/120 saniyelik optimum karşılaştırması değildir.

| Ortam | Fixture | Varsayılan ilk çözüm | Deneysel ilk çözüm medyanı |
|---|---|---|---:|
| VM isolate | 6-open | 3/3 bulunamadı | 3.527 ms |
| VM isolate | 15-open | 3/3 bulunamadı | 3.517 ms |
| Chromium Worker | 6-open | 3/3 bulunamadı | 47.500 ms |
| Chromium Worker | 15-open | 3/3 bulunamadı | 45.399 ms |

VM deneysel ilk soğuk tekrar 27.022ms. Deneysel sonuçların tamamı
`feasibleUnproven`; varsayılanın çözüm bulamaması imkânsızlık kanıtı değildir.
İptal VM 1.48–6.29ms, Worker 0.7–4.9ms. Bütün 24 koşuda run kimliği ve artan düğüm
sayısı korunarak süre uzatıldı. Tam 19 bileşen, düğümler, kanıt ve zamanlar raw JSON'da.
VM process max RSS 263,065,600 byte; tarayıcı süreçleri toplamı örneklenmiş tepe
490,397,696 byte (UI/GPU/Worker dahil, shared sayfalar çift sayılabilir; worker heap'i değil).
Bu kısa gözlemler varsayılan değişikliği için tek başına yeterli değildir.

## Veri ve maliyet

Yeni kayıt: 4 atomik yazma (head/version/metadata/event), önce 3.
Geçmiş: ilk sayfada 1 head okuması + en fazla pageSize+1 metadata; sonraki sayfalar
cursor ile. Payload yalnız sürüm açılırken okunur. Sayfa başına belge sayısı
azalmıyor, payload bant genişliği azalıyor. Gerçek fatura maliyeti ölçülmedi.
Default tek alan indeksleri yeterli; emülatörde gerçek sıralama sorguları geçti.
Legacy migration ayrı değerlendirme gerektirir, bu görevde uygulanmadı.

## Kalan riskler

- Production onay servisi ve güvenilir kimlik/IAM operasyonu tamamlanmış değil;
  istemci onayı güvenli tarafta kapalı. B kalıcı onayı kesin kapalı.
- Android Keystore/kurtarma cihaz üzerinde çalıştırılmadı; yalnız build başarılı.
- Web non-extractable key aynı-origin XSS veya ayrıcalıklı eklentiden koruma sağlamaz.
- Tarayıcı/OS temizliği, 300ms debounce öncesi çökme, depolama kotası ve aynı kullanıcının
  birden çok sekmesi için kesin kurtarma garantisi yok; son yerel kopya tutulur.
- Kurtarma sunucu sürümü çakışırsa otomatik merge yapmaz, kopyayı koruyarak reddeder.
- Kurtarma payload üst sınırı 2.5MB; sunucu snapshot sınırı 650KB. Anahtar/şifreleme
  başarısızlığında düz metin fallback yok.
- Eski geçmiş payload maliyeti ve UI kaydırma gecikmesi sonraki çalışmaya açıkça bırakıldı.

## Dosyalar ve tekrar üretim

Değişen dosyaların tam listesi `CHANGES_1_9E.txt`; ham ölçümler
`results/stage_1_9e_*.json`. Mimari: `STABILIZATION_1_9E.md`.

```sh
source /workspace/akys-toolchain/activate.sh
flutter analyze --no-pub
dart analyze lib test tool/solver_v2 tool/clinical_approval
flutter test --no-pub
# Tarayıcı test seçimi: önceki 1.9D seçimine recovery_test.dart eklenir.
# Yerel server (production config kabul etmez):
NODE_PATH=/workspace/akys/tool/firestore-tests/node_modules \
 /workspace/akys/tool/firestore-tests/node_modules/.bin/firebase emulators:exec \
 --config firebase.v2-emulator.json --project demo-akys --only firestore \
 'python3 tool/clinical_approval/emulator_acceptance.py && node test/v2_firestore_rules.test.cjs && node test/firestore_rules.test.cjs'
dart run tool/clinical_approval/timeout_check.dart
python3 tool/solver_v2/stabilization/recovery_browser.py
# Firebase UI: build_v2_firebase_web.sh; auth+firestore emulators:exec altında
# seed_auth_emulator.cjs && run_v2_firebase.py (tümü demo-akys).
```

Yerel commit SHA, bu raporu içeren commit için `git log -1 --format=%H` ile alınır.
