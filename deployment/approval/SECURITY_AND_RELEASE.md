# 1.9F — onay servisi ve yayın hazırlığı (uygulanmadı)

## Gerçek durum ve üretime geçiş kapısı

Dart validator sunucu sürecinde çalışıyor; yerel servis yalnız loopback/demo-akys
kabul ediyor. **Mevcut binary Cloud Run production servisi değildir.** Cloud Run
şablonunun imaj alanı bilerek placeholder; CI/CD'ye bağlanmadı. A/B istemci onayı
kapalıdır. B onayı hiçbir sonraki dağıtımda açılmamalı. Yerel test başarısı production
Firebase token doğrulaması veya IAM entegrasyonunun kanıtı sayılmaz.

Önerilen güven sınırı: dış isteği kabul eden doğrulanmış Firebase kimlik gateway'i,
Firebase Admin SDK'nın verifyIdToken(token, checkRevoked=true) ve sunucudan güncel
kullanıcı/admin claim kontrolünü yapar. Gateway yalnız kimlik doğrulaması yapar;
Dart klinik kodu başka dile taşınmaz. Gateway runtime hesabına yalnız özel Cloud
Run servisi için roles/run.invoker verilir. Gateway ayrı workload kimliğiyle
Google OIDC tokenı kullanır; istemci Firebase ID tokenı Cloud Run IAM tokenı
**değildir**. Cloud Run ingress/private IAM doğrulaması atlanamaz.

Gateway -> Dart kimlik aktarımı için son kullanıcı UID'sini içeren, kısa ömürlü,
audience/request digest/nonce bağlı imzalı sunucu zarfı gereklidir. İstemcinin
X-User/X-Admin başlığı veya doğrulanmamış JSON kimliği kabul edilemez. Bu gateway,
imzalı zarf ve production credential adapter henüz UYGULANMADI. Bu yüzden onay
kapalı kalır. Alternatif tek Cloud Run servisi ancak standart denetlenmiş Firebase
JWT doğrulayıcı, Google key rotation/cache/revocation/güncel claim testleriyle
onaylanırsa değerlendirilebilir. Mevcut özel RS256 kodu yalnız test prototipidir.

## IAM ve Rules birbirinin yerine geçmez

`runtime-role.json` Dart runtime için önerilen özel yetki kümesidir: snapshot point
read, transaction başlat/rollback ve create/update. Delete, query/list, export,
index, Auth kullanıcısı değiştirme, IAM yönetimi, Service Account Token Creator
YOK. Cloud Run runtime hesabı üzerinden ADC/workload identity; JSON anahtar dosyası
repository'ye veya container'a konmaz. Deploy hesabının actAs yetkisi runtime
hesabından ayrılır. İmaj build hesabı da ayrıdır. Logging stdout üzerinden platform
loglarına gider; kalıcı retention/uyarılar ayrıca yapılandırılmalıdır.

**Sınır:** Firestore IAM collection bazlı Security Rules değildir. Bu proje/DB'ye
verilen entities.update yetkisi başka koleksiyonlara da erişebilir. Sunucu kodu
sabit v2_schedules yollarını ve allowlist/ID/snapshot/boyut kontrollerini uygular.
Ayrı DB izolasyonu gerekiyorsa ayrıca değerlendirilir; otomatik oluşturulmaz.
Yönetilen Firestore erişimleri Rules'ı bypass eder. İstemci Rules testleri server
IAM testinin yerini tutmaz. Yerel test yalnız önerilen politika dosyasının en az
ayrıcalık allowlist'ini ve sunucu yol kısıtlarını denetler. Gerçek IAM binding,
OIDC invoker zinciri ve yetki reddi cloud üzerinde test EDİLMEDİ.

## Onay bütünlüğü

Sunucu istemciden yalnız ID/sürüm/idempotency-key alır. Payload/quality/proof/approved
almamalıdır. Head ve immutable version transaction içinde okunur; bütün metadata
(historySchema fiziksel indeks göstergesi hariç) karşılaştırılır. A hard constraint
ve REQUIRED/must/lock kontrolleri mevcut Dart validator ile yapılır. A fizibilite
optimumluk değildir. SHA-256, tam kaynak payload baytlarına bağlanır. Idempotent
retry başka admin için başarı sayılmaz; değişmiş onaylı payload digest'i reddedilir.
Head/version/metadata/audit tek commit. Eşzamanlı sürüm ya da event precondition
hatası atomik olarak reddedilir. Yanıt kaybından sonra aynı operation ID ile durum
sorgulanır; timeout sonrası başarılı commit ihtimali başarısız klinik doğrulamayla
karıştırılmaz. Başarısız klinik doğrulama hiçbir write üretmez.

## Dağıtım sırası — bu görevde çalıştırılmadı

1. Test edilmiş commit SHA ve build hashlerini sabitle; değişiklik ve güvenlik
   incelemesini tamamla. Mevcut production Rules/uygulama sürümünü ayrı onaylı
   read-only operasyonda kaydet (bu görev production okumaz).
2. Export/backup doğrula; migration dry-run/prova/rollback tamamla. Prod dry-run bile
   ayrı yetkilendirilmiş bakım işidir; demo aracı production'a yöneltilemez.
3. Gerekli indeksleri önce hazırla. Mevcut metadata sorguları tek alan + documentId
   sıralamasıdır; yeni composite index gerekmiyor. Özel index exemption varsa
   version/at için sorgu uyumluluğunu production öncesi kontrol et.
4. V2 Rules'ı mevcut explicit Rules workflow ile AYRI onaylı dağıt. İstemci onayı
   ve server_audit yazımı kapalı kalır; immutable approved sürümler korunur.
5. Onay runtime/IAM/gateway güvenlik kapıları tamamlanmadan servis dağıtma veya
   istemci onayını açma. Tamamlandığında özel servis/canary/synthetic yetkili test,
   log ve maliyet alarmları, sonra erişim kontrollü açılış ayrı görevdir.
6. Web: flutter analyze/test + Chromium/Worker/emulator; `flutter build web --release`
   ve build_worker.sh build/web. akys_recovery.js + Worker dosyasını artifact içinde
   doğrula. Mevcut Hosting workflow Rules hashini kontrol eder ve yalnız Hosting
   yayınlar. Otomatik workflow kullanılırsa ikinci manuel deploy yok.
7. Android: debug APK yalnız test içindir. Production release için mevcut package
   ID/Google app ID korunarak ayrı release signing/keystore yönetimi gerekir.
   İmzalama anahtarı repository'ye konmaz. Cihazda Auth, Worker yerine isolate,
   Keystore/recovery, hesap değiştirme ve kayıt doğrulanmadan yayın onayı verilmez.
8. Yetkili test hesabı/domain/HTTPS/cache/Worker/MIME/CSP kontrolü ve izleme. İstemci
   feature gate, sunucuda yetkilendirme yerine geçmez.

## Geri dönüş

- Hosting önceki doğrulanmış artifact/commit'e geri döner; eski V1'e otomatik dönüş
  veya veri silme yok. Geri alınan V2 istemcinin historySchema2 uyumu kontrol edilir.
- Onay gateway invoker erişimi kapatılır, yeni onaylar durur; onaylı kayıtlar
  değiştirilmez/silinmez. Mevcut onayları geri alma ayrı klinik denetim sürecidir.
- Rules eski güvenlik boşluklarını açacak şekilde geri alınmaz. Veri şeması uyumu
  korunarak güvenli politika tutulur.
- Metadata migration rollback: eski payload'lar aynen kalır; head storage pointer
  updateTime precondition ile legacy'ye döner. Yeni yazma olmuşsa otomatik rollback
  yapma. Ayrıntı tool/firestore_migration/README.md.

## Maliyet ve bağımlılıklar

Cloud Run CPU/RAM/istek ve cold start, gateway/Auth lookup, Firestore reads/writes,
audit depolaması, Artifact Registry/build ve logging retention maliyetlidir.
minScale=0 maliyeti azaltır ama cold start getirir; maxScale=2 koruma sağlar fakat
rate limit değildir. Bölge, trafik, sürüm boyutu ve retention bilinmeden fiyat
üretilmedi. Proje billing/API/IAM/region kararları ve bütçe alarmı gerekir. Bu görevde
ücretli kaynak oluşturulmadı; gerçek fatura veya IAM başarısı iddia edilmez.
