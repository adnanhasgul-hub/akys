# AKYS admin authentication

Email/Password ile giriş yapılır. Uygulamada kayıt, hesap oluşturma veya şifre
sıfırlama akışı yoktur. Kullanıcı parolası, token veya UID kaynak koda gömülmez.

## Authentication ve authorization

- `AuthService` test edilebilir oturum arayüzüdür; `FirebaseAuthService`
  `authStateChanges` ve `idTokenChanges` olaylarını izler.
- `AdminAuthorization` yalnızca Firebase tarafından imzalanan ID token içindeki
  **boolean `admin: true`** claim'ini kabul eder. Email/domain veya yalnızca
  authenticated olmak admin yetkisi vermez. Birden fazla admin aynı yöntemle desteklenir.
- Claim yoksa erişim reddedilir. Kontrol sürerken/hata durumunda private shell
  oluşturulmaz. Eski async sonuçlar yeni oturuma uygulanmaz.
- `AuthGate` tüm private route'ları korur. Doğrudan deep link, unknown route ve
  geri navigasyon auth kontrolünü atlamaz. Oturum kapatıldığında shell kaldırılır.
- V1 ile yalnızca `/shared/schedule/{48-hex-token}` için ayrı bir public dal vardır.
  Bu ekran private koleksiyonları okuyamaz; minimum projection kullanır. Ayrıntılar
  [WORK_SCHEDULE_V1.md](WORK_SCHEDULE_V1.md) içindedir. Public projection kuralları
  bu görevde production'a deploy edilmemiştir.
- Flutter istemcisindeki gate tek başına veri güvenliği sağlamaz. Sunucudaki
  Firestore rules aynı signed claim'i zorunlu kılmalıdır.

## Canlı ortam için tamamlanması gerekenler

Canlı Email/Password sağlayıcısı `enabled: true`, `passwordRequired: true` olarak
resmi Identity Toolkit API ile doğrulandı. Firebase Auth ilk başlatması kullanıcı
tarafından Firebase Console üzerinden tamamlandı; billing ayarı değiştirilmedi.
Diğer authentication provider'ları bu çalışma tarafından açılmadı.

`(default)` Firestore database incelendi. Önceki canlı kurallar tüm erişimi
reddediyordu. Yerel kurallar emulator testlerinden geçti, resmi Firebase Rules
API tarafından sunucuda derlendi ve `cloud.firestore` release'ine yayımlandı.
Yayımlama sonrası canlı kaynak yerel `firestore.rules` ile birebir karşılaştırıldı.
Aktif ruleset: `ba9301f4-779f-44a6-a553-cd2fc7d5bacc`.

Firebase CLI rules deploy ön kontrolünde `serviceusage.googleapis.com` ağ engeli
vardır. Yayımlama, erişime açık resmi Firebase Rules API üzerinden yapıldı;
proxy/TLS veya kural doğrulaması devre dışı bırakılmadı. Gelecekte CLI deploy için
bu host ortam allowlist'ine eklenmelidir.

Canlı Auth kullanıcı listesi boş: gerçek admin hesabı, UID ve admin claim henüz
yoktur. Kayıtlı başka bir kullanıcı da yoktur. Gerçek hesapla uçtan uca giriş
henüz denenmemiştir. Altyapı, admin claim verilene kadar default-deny durumundadır.

1. Firebase Console → akys-d708a → Authentication → Users → Add user üzerinden
   gerçek yönetici hesabını yönetici kendisi oluşturmalı. Parola sohbet veya
   repository'ye yazılmamalı; bu görev parola oluşturmaz/istemez.
2. Oluşturulan gerçek hesabın UID'si Console'dan alınmalı.
3. Yetkili bir yönetim ortamında Firebase Admin SDK ile **gerçek UID** için
   mevcut custom claims korunarak `admin: true` atanmalı. Bu işlem Flutter
   istemcisinden yapılamaz. Service account anahtarı repository'ye konmaz.
   UID bir istemci allowlist'ine eklenmez; güvenilir sunucu yetkisiyle claim atanır.
4. Kurallar bu çalışmada yayımlandı. Sonraki kural değişikliklerinde yalnızca
   `firebase deploy --only firestore:rules --project akys-d708a` kullanılmalı;
   önce `serviceusage.googleapis.com` ağ izni sağlanmalıdır. Hosting/Functions
   deploy gerekmez.
5. Claim verildikten sonra kullanıcı çıkış/giriş yaparak yeni ID token almalı.
   Herhangi bir authenticated hesabın claim olmadan reddedildiği ayrıca denenmeli.

Henüz admin UID veya admin claim ataması yapılmamıştır. Tüm gerçek kullanıcılar
geçerli admin claim'i gelene kadar yetkisizdir. Yetki iptali yeni ID token'a
geçildiğinde etkili olur; önceden verilmiş ID token süresi dolana kadar geçerli
kalabilir (genellikle en fazla bir saat). Acil iptal için backend'de ayrıca
revocation kontrolü tasarlanmalıdır; anlık iptal garantisi verilmez.

## Firestore kuralları

Repository'deki rules bütün document path'lerinde default-deny uygular; yalnızca
`request.auth != null` ve `request.auth.token.admin == true` olduğunda erişim
verir. Veri modeli, collection veya public share istisnası eklenmemiştir. Firestore
Admin SDK/IAM erişimi security rules'u bypass eder ve ayrı yönetilir.

## Testler

`flutter test`: login, yetkisiz/admin oturum, logout, deep link/route koruması,
yetki doğrulama hatası, mobil form/Enter/loading ve claim tipi kontrolü.

Rules testi yalnızca `demo-akys` lokal emulator projesinde çalışır, canlıya bağlanmaz:

```sh
npm install --prefix /tmp/akys-rules-test @firebase/rules-unit-testing firebase
NODE_PATH=/tmp/akys-rules-test/node_modules firebase emulators:exec \
  --project demo-akys --only firestore 'node test/firestore_rules.test.cjs'
```

Emulator için Java 21 ve emulator binary indirme erişimi gerekir. Test hesabı ve
test dokümanları yalnızca emulator içindedir; gerçek admin hesabı oluşturulmaz.

## Gerçek UID için manuel claim atama örneği

Aşağıdaki kod yalnızca yetkili yönetim ortamında, gerekli IAM izinleri olan
Application Default Credentials (ADC) ile çalıştırılmalıdır. `firebase-admin`
yönetim ortamında kurulmuş olmalıdır; Flutter uygulamasına eklenmez. Firebase CLI
login'i tek başına Admin SDK ADC yetkilendirmesi anlamına gelmez.

`AKYS_ADMIN_UID` ortam değişkenine Console'daki **gerçek** UID atanır; eksikse kod
işlem yapmaz. Bu kod kullanıcı oluşturmaz, mevcut claim'leri korur ve parola istemez:

```js
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
initializeApp({ credential: applicationDefault(), projectId: 'akys-d708a' });
async function grantAdmin() {
  const uid = process.env.AKYS_ADMIN_UID;
  if (!uid) throw new Error('Gerçek admin UID gerekli');
  const auth = getAuth();
  const user = await auth.getUser(uid);
  await auth.setCustomUserClaims(uid, { ...user.customClaims, admin: true });
}
grantAdmin().catch(() => { process.exitCode = 1; });
```

Claim ataması bu çalışma kapsamında çalıştırılmadı. Credential JSON'u veya private
key üretmek gerekmez; credential değerleri komut çıktısına veya repository'ye konmaz.
