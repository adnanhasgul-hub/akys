# AKYS V2 — Aşama 1.9B

Başlangıç: `423bca9b7069582c023d7b491f0e64df534dbfc8`, temiz çalışma ağacı,
`feature/akys-v2-solver-core`. Tarih: 15 Kasım 2026.

## Giriş ve kapsam

`lib/main_v2.dart` → `V2App` → `V2SchedulePage` ayrı, açıkça seçilen yerel
Flutter girişidir. V1'in `main.dart`, AuthGate, yönlendirmeleri ve ekranları
korunur. V2 Firebase başlatmaz, Firestore'a bağlanmaz, yayın/kalıcı onay işlemi
sunmaz. Mevcut Clinical Teal ThemeData ve semantik token'lar kullanılır.
Material tarih/metin kontrolleri Türkçedir. Başlangıçta gerçek kişileri taklit
eden hazır veri bulunmaz; boş ay ve kullanıcı tarafından eklenen hekimler vardır.

```sh
source /workspace/akys-toolchain/activate.sh
flutter run -t lib/main_v2.dart
# Yerel JS Web release + aynı kökende gerçek Worker varlığı:
bash tool/solver_v2/build_v2_web.sh
# Android:
flutter build apk --debug --no-pub -t lib/main_v2.dart
```

Web geliştirmesinde de `akys_v2_worker.js` aynı kökten sunulmalıdır. Normal
Flutter derlemesi ayrı Dart Worker'ı kendiliğinden üretmez; eklenen paketleme
komutu bu adımı içerir. Production workflow'u değiştirilmedi.

## Ekranlar ve işlemler

* **Çizelge:** ay/yıl seçimi, UTC takvim günleri, hafta sonu vurgusu, günlük
  hekim/doluluk/zorluk göstergesi, REQUIRED/OPTIONAL ve kalıcı personel grubu ile
  pozisyonun ayrı etiketlenmesi. Mobil kart, geniş ekranda tablo. Gün ayarlarında
  rol/pozisyon ekleme-silme, zorunlu/opsiyonel seçimi, pozisyonları bütün aya
  uygulama ve tarih bazlı manuel tatil adı/puanı bulunur. Tatil puanı mevcut V2
  `DayDifficulty.effectiveScore` üzerinden alınır; hafta günüyle toplanmaz.
* **Hekimler:** ad, sabit yerel kimlik, grup, K1–K4 seviyesi, genel kıdem sırası,
  rol yetkinlikleri, kişisel üst sınır, Tutacak/Tutamaz günleri ve önceki nöbet
  tarihleri. Günler metinle veya takvim günü seçim penceresiyle girilebilir.
  Çelişki, ay dışı gün, kapasite ve zorunlu tarihlerde dinlenme çelişkileri
  anlaşılır hata verir. Hekim ekleme, düzenleme ve çıkarma vardır.
* **Kalite / Arama:** başlangıç, geçen süre, ilk çözüm zamanı, düğüm/budama,
  A/B aşaması, iptal ve 30 saniye süre uzatma. Feasible, optimal, infeasible,
  timeout (çözümlü/çözümsüz), cancellation ve failure ayrı metinlerle gösterilir.
  Hekim bazında toplam/üst sınır, Perşembe/Cuma/Cumartesi/Pazar ve zorluk;
  grup toplamları; REQUIRED/OPTIONAL doluluk; önce/sonra atamalar ve kalite;
  etiketli 19 kesin bileşen vardır. Yeni bir kalite formülü oluşturulmadı.

Ata/kaldır/taşı/takas/kilitle/kilit kaldır/undo/redo doğrudan `ScheduleEditor`
üzerinden atomik uygulanır. Uzun basıp sürükleme mouse ve dokunmayla çalışır;
menü üzerinden hedef seçimi aynı işlemleri erişilebilir şekilde sağlar. Kilitli
kaynak/hedef veya hard constraint ihlali, işlemi kısmen uygulamaz.
Eksik REQUIRED ve Tutacak yükümlülükleri taslak bildirimi olarak görünür.

## Çalışma alanı ve yeniden optimizasyon

`ScheduleWorkspace` mevcut editörü ve arama problem snapshot'ını ayrı tutar.
Arama sırasında düzenleme/yapılandırma kapalıdır; mevcut taslak değiştirilmez.
Yeni sonuç açık **yerel taslak kabulü** veya reddi bekler. Hata/timeout/iptal
son doğrulanmış incumbent'ı koruyan mevcut runtime üzerinden işlenir.

Kilitli yeniden optimizasyon `ReoptimizationRequest.fromEditor()` ile aynı
fixedAssignments/referenceAssignments snapshot'ını üretir. `ReoptimizationSession`
API'sinin belgelenmiş arka plan yolu kullanılır: request.problem, mevcut
`OptimizationController` içindeki `TransitionSession`a gönderilir; ana UI üzerinde
senkron `ReoptimizationSession.run()` çağrılmaz. `ReoptimizationDiff` değişen
pozisyon/hekimleri, korunan kilitleri ve boş OPTIONAL'ları hesaplar. Önce 19
bileşenli klinik kalite, yalnız eşitlikte değişen pozisyon sayısı tercihi mevcut
çekirdekte uygulanır; burada yeni hedef veya sıralama yoktur. Normal oluşturma
komutunda kilit varsa o komut da kilitli request kullanır.

Kabul sırasında sonuç kaynak snapshot üzerinde yeni `ScheduleEditor` ile yeniden
doğrulanır, kilitlerin eşleşmesi kontrol edilir ve kilitler editörde geri kurulur.
Intrinsic arama kilitleri düzenlenebilir kaynak snapshot'a taşınmaz; dolayısıyla
kullanıcı açık kilit kaldırma işlemine devam edebilir. Kabul yeni bir düzenleme
başlangıcıdır; eski editörün undo geçmişini devralmaz. Manuel düzenlemeler ve
kabul edilen yerel taslak optimumluk kanıtı taşımaz. Son manuel işlemin önce/sonra
kalitesi ayrıca gösterilir.

Ay veya personel/pozisyon yapılandırması değişimi açık sıfırlama onayı ister.
Ay değişiminde tarih kısıtları, önceki nöbetler, tatiller ve pozisyon ayarları da
sıfırlanır; hekim kimlikleri/adları/grup/yetkinlikleri korunur. Önceki ay taslağı
otomatik arşivlenmez. Hesaplama sırasında taslak korunması ile kalıcı saklama
farklıdır; uygulama kapanınca saklama garantisi yoktur.

## A/B güvenliği ve platformlar

VM/Android yolunda mevcut isolate controller; Web'de açık `.web()` constructor
ve aynı kökenli gerçek DedicatedWorker seçilir. Aynı DFS frontier üzerinde
sliced çalışma, iptal, süre uzatma, run ID/sıra kontrolü ve host validator aynen
korunur. Worker'a ait süreç içi kanıt serileştirilmiş yetki gibi kullanılmaz.

B geçişli sonuçlar görüntülenir ve karşılaştırılır; **yerel editöre kabul dahi
kapalıdır**. Transfer edilen preview'dan editör için yerel B kanıtı türetilmez.
Kalıcı onay/yayın bütün modülde yoktur. A sonucu kabulü de yalnız bellek içi
çalışma taslağıdır. A'nın imkânsızlık kanıtı, timeout ve optimumluk semantiği
üretim çekirdeği tarafından belirlenir; UI bunları üretmez.

Android debug APK başarıyla derlendi. Bu ortamda `adb devices -l` boştur:
fiziksel Android cihazı/emülatörü üzerinde etkileşim veya TalkBack testi yapılmadı.
VM isolate gerçek testleri geçmiştir; bunu Android cihaz testi olarak sunmuyoruz.
Web JS release gerçek Chromium üzerinde çalıştırıldı. Diğer tarayıcılar, Wasm
çalıştırması, background-tab throttling ve production CSP/cache kabulü kapsam dışı
kalır. Ayrı V2 girişinin production navigasyonuna alınması bu görevde yapılmadı.

## Doğrulama

Ortam: Flutter 3.47.9, Dart 3.13.7, Linux, Chromium 154.0.8037.57.

| Kontrol | Sonuç |
|---|---|
| Tam Flutter test paketi (V1 ve V2 dahil) | 480 PASS |
| Yeni workspace/widget/etkileşim testleri | 19 PASS; son UI değişikliklerinden sonra tekrar PASS |
| Chromium widget/core regresyonları | 36 PASS (12 yeni + önceki 24) |
| Gerçek DedicatedWorker bağımsız kabulü | 18/18 PASS |
| Gerçek Flutter + Worker uçtan uca | 4 akış grubu PASS; ayrıca gerçek boş release smoke PASS |
| Flutter analyze (tüm proje) | Temiz |
| Dart analyze (eklenen Dart kodu/testleri) | Temiz |
| V2 Web release + ayrı Worker paketleme | PASS, Flutter 37.4 s + Worker 1.71 s |
| V2 Android debug APK | PASS, son derleme 14.0 s |

218 mevcut V2 testinin kaynakları değiştirilmedi; tam paket bunları da kapsar.
Oracle, bağımsız kalite referansı, editör ve A/B testleri dahil eski testler
korundu. Yeni testler ay değişimi, hekim ekleme/çıkarma/kısıt çelişkileri, gün
seçimi, tatil/OPTIONAL snapshot'ı, atama, menüyle taşıma/takas, gerçek drag/drop,
kilit/undo/redo, VM kabul/ret/timeout/uzatma, yeniden optimizasyon ve B reddini kapsar.
360/414/768/1440 px ve %200 metin ölçeği kontrol edildi.

İlk dar ekran testi başarısızdı: büyük sabit araç alanı %200 metinde içeriğe 6 px
bırakıyordu. Araç alanı kompakt erişilebilir kontrollerle düzeltildi; test silinmedi
ve son pakette geçti. İlk sandbox test denemesi loopback socket izninden dolayı
çalışamadı; yerel socket izniyle gerçek testler yürütüldü. Web derlemesinin
Cupertino font ve Android'in mevcut Kotlin/SDK araç zinciri uyarıları sürer;
derlemeleri başarısız kılmadı, kapsam dışı yapılandırmalar değiştirilmedi.

### Gerçek tarayıcı kanıtı

`v2_ui_acceptance.dart` yalnız test hedefidir: aynı `V2App`, ekran ve runtime ile
sentetik snapshot kurar. Ürün girişine test verisi eklenmez. Chromium testleri:

1. Gerçek Worker'da çöz → 19 kesin bileşeni önizle → kabul et → kilitle → yeniden
   optimize et → kabul et. İlk küçük fixture vektörü:
   `[0,-2,0,-2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6]`.
2. 414 px mobil / 1440 px masaüstü navigasyonu.
3. A'nın imkânsız olduğu fixture'da B preview; kabul devre dışı; ret taslağı korur.
4. `6-open` 30 günlük fixture ararken sekme değiştirme, süre uzatma ve iptal.
   Aktif hesaplama penceresinde 35 ana thread timer olayı; gözlenen en büyük
   timer aralığı 151.3 ms; iptal komutundan görünür terminal duruma 147.4 ms.
   Ölçüm Playwright/semantics/render maliyetlerini içerir; saf solver gecikmesi
   veya her cihaz için kare hızı garantisi değildir. Arama UI olaylarını tüm
   hesaplama boyunca bloke etmedi; büyük UI layout'larının maliyeti sıfır değildir.
5. Fixture içermeyen `lib/main_v2.dart` release: UI'dan hekim eklenir; aylık
   REQUIRED kapasitesi yetersiz problem gerçek Worker'da kanıtlanmış imkânsız
   olarak gösterilir. Haricî ağ isteği, tarayıcı script hatası yoktur.

Ham JSON, app/worker SHA256 değerleri `results/stage_1_9b_*.json` içindedir.
Flutter release ve acceptance hedefleri farklı entrypoint'lerdir; hash'leri
birbirine eşitmiş gibi sunulmaz. Görüntüler build/v2-ui-acceptance altında yereldir,
build çıktıları commit edilmez.

## Yeniden çalıştırma

```sh
flutter analyze --no-pub
dart analyze lib/modules/schedule_v2 lib/main_v2.dart test/modules/schedule_v2 tool/solver_v2/v2_ui_acceptance.dart
flutter test --no-pub --reporter expanded
flutter test --no-pub --platform chrome test/modules/schedule_v2/page_test.dart test/modules/schedule_v2/interactions_test.dart test/solver_v2/reoptimization_test.dart test/solver_v2/lifecycle_web_test.dart test/solver_v2/transferred_candidate_test.dart
bash tool/solver_v2/build_v2_web.sh
python3 tool/solver_v2/web/run_v2_release_smoke.py
flutter build web --release --no-pub --no-web-resources-cdn --output build/v2-ui-acceptance -t tool/solver_v2/v2_ui_acceptance.dart
bash tool/solver_v2/web/build_worker.sh build/v2-ui-acceptance
python3 tool/solver_v2/web/run_v2_ui.py
flutter build apk --debug --no-pub -t lib/main_v2.dart
```

## Dosyalar ve sınırlar

Eklenenler: `lib/main_v2.dart`, `lib/modules/schedule_v2/{v2_app,workspace,schedule_page}.dart`;
`test/modules/schedule_v2/{workspace,page,interactions}_test.dart`;
`tool/solver_v2/build_v2_web.sh`, `v2_ui_acceptance.dart`,
`web/run_v2_ui.py`, `web/run_v2_release_smoke.py`, bu rapor ve dört sonuç JSON'u.

Solver, validator, runtime, 19 kalite bileşeni, varsayılan strateji ve forward
checking değiştirilmedi. V1, Firebase, Auth, Rules ve production dosyaları
korundu. Push, merge, deploy yapılmadı. Yerel commit bilgisi teslimat mesajında
ve branch HEAD'inde bulunur.
