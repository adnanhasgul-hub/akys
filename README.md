# AKYS — A Klinik Yönetim Sistemi

Tek Flutter/Dart kod tabanına sahip uygulama başlangıcıdır. Bu sürüm yalnızca
AKYS başlığını ve iki modül kartını gösterir; kartlar henüz işlem başlatmaz.

## Mimari kararlar

- Android = native-compiled Flutter. WebView kullanılmaz; web sitesi APK içine sarılmaz.
- Android application ID: `com.adnanhasgul.akys`. APK/AAB hedeflenir.
- Web = Flutter Web.
- Desktop kullanımı = Web/PWA üzerinden Microsoft Edge.
- Windows native build / `.exe` hedefi yoktur.
- Yalnızca `android/` ve `web/` platformları oluşturulmuştur.
- Firebase ileride ortak backend olacaktır. Planlanan proje: `akys-d708a`.
  Bu başlangıçta Firebase SDK, bağlantı, Authentication veya Firestore yoktur.
- AKYS üst platformdur. `work_schedule` ve `operative_notes` bağımsız peer modules'dür.
  Ameliyat Notları, Çalışma Çizelgesi'nin altında değildir.
- Modüller birbirini import etmez. `app` modülleri bir araya getirir; `core` ortak,
  pure Dart tanımlarını tutar. Gelecekte iş mantığı platform ve Firebase'den
  bağımsız Dart kodunda tutulmalıdır.

```text
lib/
├── app/                         # Uygulama shell'i ve modüllerin birleştirilmesi
├── core/                        # Pure Dart ortak modül tanımı
├── modules/
│   ├── work_schedule/           # Yalnızca modül kimliği
│   └── operative_notes/         # Yalnızca modül kimliği
└── main.dart
```

Nöbet, görev dağılımı, personel, algoritma ve ameliyat notu özellikleri henüz yoktur.

## Çalıştırma ve doğrulama

Flutter 3.47.9 stable / Dart 3.13.7 ile hazırlanmıştır.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter build web
flutter build apk --debug
```

AKYS bulut ortamında önce `source /workspace/akys-toolchain/activate.sh` çalıştırılır.
Java/Gradle, HTTP proxy ortam değişkenlerini otomatik kullanmadığından bu ortamda
Android build öncesi aşağıdaki ayar gerekir (repository yapılandırmasına gömülmez):

```sh
export GRADLE_OPTS='-Dhttp.proxyHost=proxy -Dhttp.proxyPort=8080 -Dhttps.proxyHost=proxy -Dhttps.proxyPort=8080'
```

Android için Java ve Android SDK gerekir. Ağ erişimi engellenirse güvenlik,
TLS veya dependency doğrulaması kapatılmamalı; engellenen host için ortam ağ izni
sağlanmalıdır. Release APK/AAB için daha sonra özel release signing yapılandırılmalıdır;
şablondaki debug signing üretim dağıtımı için kullanılmamalıdır.

## Web / Edge kurulumu

Manifest AKYS adını, Türkçe dili, 192/512 piksel ikonları ve `standalone` görünümünü
tanımlar. `flutter build web` çıktısı `build/web/` altındadır. Üretimde HTTPS ile
sunulmalıdır (yerel denemede localhost kullanılabilir). Edge'de siteyi açıp
uygulama yükleme menüsünden kurulum yapılabilir. Gerçek Edge kurulumu ve yayın
ortamı bu aşamada doğrulanmamıştır. Çevrimdışı kullanım garantisi yoktur;
çevrimdışı veri/senkronizasyon gelecekte ayrıca tasarlanmalıdır.
