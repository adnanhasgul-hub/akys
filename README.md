# AKYS — A Klinik Yönetim Sistemi

AKYS V2, Flutter Web ve Android için nöbet çizelgesi uygulamasıdır. Standart giriş
`lib/main.dart`, mevcut Firebase Authentication/admin custom claim altyapısını ve
`v2_schedules` repository'sini kullanır. Android application ID
`com.adnanhasgul.akys`, Firebase projesi `akys-d708a` olarak korunmuştur.

## Mimari

- `lib/solver_v2/`: saf Dart DFS, klinik doğrulayıcı, kesin 19 bileşenli kalite,
  A/B protokolü, manuel düzenleme, kilitli yeniden optimizasyon ve çalışma katmanları.
- `lib/modules/schedule_v2/`: çizelge, hekim/kısıt yönetimi, kalite paneli, taslak,
  revizyon, cursor sayfalaması ve sürüm geçmişi.
- `lib/core/auth/`: mevcut Firebase Auth ve admin claim doğrulaması.
- `lib/core/design/`: ortak Clinical Teal tasarım sistemi.
- Web: ayrı derlenen gerçek Worker. Android: Dart isolate.

V1 ekranları, motorları ve modelleri kaldırılmıştır. Eski production koleksiyonları ve
kullanıcılar **silinmemiştir**; otomatik migration yoktur. Kalıcı klinik onay A ve B için
kapalıdır; güvenilir sunucu doğrulaması henüz sağlanmamıştır. İstemci kalite/kanıt alanları
onay yetkisi oluşturmaz.

## Yerel geliştirme ve doğrulama

Flutter 3.47.9 / Dart 3.13.7 / Java 21 kullanılmıştır.

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release
bash tool/solver_v2/web/build_worker.sh build/web
flutter build apk --debug
```

Varsayılan uygulama gerçek Firebase yapılandırmasını kullanır. Test için production
uygulamasını başlatmayın; açıkça izole demo emülatörünü seçin:

```sh
bash tool/solver_v2/start_v2_emulators.sh
bash tool/solver_v2/build_v2_firebase_web.sh
```

İkinci komut `main.dart`ı demo backend ile `build/v2-firebase` altına derler ve Auth
emülatörünü oturum geri yüklenmeden önce bağlayan yerel Web başlatıcısını paketler.
Bu başlatıcı production `build/web` içine eklenmez. Emulator test kullanıcıları için
`tool/solver_v2/web/seed_auth_emulator.cjs` kullanılabilir; yalnız loopback/demo backend'e
bağlanır. Android emülatörü için `--dart-define=AKYS_V2_EMULATOR_HOST=10.0.2.2` kullanılır.
`lib/main_v2.dart` yalnız offline kabul/test amaçlı giriş olarak korunmuştur.

Auth/Firestore emülatör testleri için `tool/firestore-tests` bağımlılıklarını kurup
`npm test --prefix tool/firestore-tests` çalıştırın. Gerçek Worker ve Flutter tarayıcı
kabul araçları `tool/solver_v2/web` altındadır. Native VM runtime testlerini doğrudan
Chromium paket-test sunucusunda çalıştırmayın; gerçek Worker için derlenmiş asset sunan
ayrı kabul harness'i gerekir.

## Yayın ve güvenlik sınırı

Bu geliştirme branch'inden push/merge/deploy yapılmamıştır. Gelecek production geçişinde
önce test edilmiş V2 Rules ayrıca incelenip uygulanmalıdır. Hosting workflow'u, aktif
Rules'ın test edilen kaynakla aynı olduğunu doğrulamadan V2 istemcisini yayımlamaz.
Başlangıç verilerini veya kullanıcıları otomatik silen/taşıyan işlem yoktur.
Android debug APK derlemesi fiziksel cihaz testi veya release signing yerine geçmez.

- [Geçiş ve güvenlik planı](tool/solver_v2/MIGRATION_1_9D.md)
- [Testler, performans ve sınırlamalar](tool/solver_v2/VALIDATION_1_9D.md)
- [Ölçüm çıktıları](tool/solver_v2/results/)
