# AKYS anahtarsız GitHub Actions kurulumu

Bu dosya bir kurulum talimatıdır; Google/GitHub ayarları uygulanmadı. Production
okunmadı/değiştirilmedi. Workflow'lar yerelde hazırlanmıştır, uzaktan çalıştırılmadı.
Repo API kontrolü: adnanhasgul-hub/akys, repository_id=1443450449,
repository_owner_id=328827663, default main; Codex erişimi başarılı.

## 1. Ön hazırlık ve GitHub koruması

1. Google Console'da **akys-d708a** proje NUMARASINI doğrulayın (ID ile karıştırmayın).
   Pool/provider/SA oluşturmak için yetkili yönetici gerekir. API etkinleştirme,
   IAM veya ücretli kaynak bu görevde yapılmadı. Cloud Run kurulmaz.
2. GitHub Settings → Environments: `production-readonly`, `production-hosting`,
   `production-rules`, `production-indexes` oluşturun. Her birinde Required reviewers,
   yalnız main deployment branch kuralı ve mümkünse admin bypass yasağı uygulayın.
   Environment reviewer özelliğinin repo görünürlüğü/GitHub planında kullanılabildiğini
   doğrulayın. Destek yoksa production workflow'u çalıştırmayın; metin onayı bunun
   yerini tutmaz. Tek admin çalıştırıp kendisi onaylayacaksa Prevent self-review
   kapalı olmalı; gerçek iki kişi kontrolü için ikinci reviewer gerekir.
3. main'i koruyun: force push/deletion yasak, PR ve kontroller zorunlu. Workflow,
   deployment script ve IAM değişikliklerini ayrıca inceleyin. Workflow path koşulu
   aynı yoldaki kötü niyetli kod değişikliğini engellemez; main koruması zorunludur.
4. Actions izinlerini gerekli action'larla sınırlandırın. Bu taslak action sürümlerini
   GitHub API'den çözülen tam commit SHA'larına sabitler; SHA sabitleme bağımsız kaynak
   güvenlik denetimi değildir. Güncellemeler ayrı inceleme gerektirir.

## 2. Workload Identity Pool ve OIDC Provider

Google Console → IAM & Admin → Workload Identity Federation:

- Tek pool: `akys-github` (global).
- Dört ayrı OIDC provider: `github-readonly`, `github-hosting`, `github-rules`,
  `github-indexes`. Her biri aşağıdaki kendi environment/workflow koşulunu kullanır.
- Issuer: `https://token.actions.githubusercontent.com`.
- Audience: provider'ın tam canonical resource URL'si:
  `https://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/akys-github/providers/PROVIDER_ID`.
  Auth action'ın varsayılan audience değeri bununla uyumlu tutulmalı. Geniş audience
  listesi veya `*` kullanmayın.
- Attribute mapping:
  - `google.subject = assertion.sub`
  - `attribute.repository_id = assertion.repository_id`
  - `attribute.repository_owner_id = assertion.repository_owner_id`
  - `attribute.ref = assertion.ref`
  - `attribute.workflow_ref = assertion.workflow_ref`
  - `attribute.environment = assertion.environment`

Her provider için attribute condition (ENV ve WORKFLOW aşağıdaki tabloya göre):

```text
assertion.repository_id == '1443450449' &&
assertion.repository_owner_id == '328827663' &&
assertion.repository == 'adnanhasgul-hub/akys' &&
assertion.ref == 'refs/heads/main' &&
assertion.event_name == 'workflow_dispatch' &&
assertion.environment == 'ENV' &&
assertion.sub == 'repo:adnanhasgul-hub/akys:environment:ENV' &&
assertion.workflow_ref == 'adnanhasgul-hub/akys/.github/workflows/WORKFLOW@refs/heads/main'
```

| Provider | ENV | WORKFLOW |
|---|---|---|
| github-readonly | production-readonly | production-inspect.yml |
| github-hosting | production-hosting | production-deploy.yml |
| github-rules | production-rules | production-deploy.yml |
| github-indexes | production-indexes | production-deploy.yml |

GitHub environment kullanan subject branch içermez; bu yüzden ayrıca ref koşulu
zorunludur. Reusable workflow kullanılmadığı için `workflow_ref` kullanılır;
`job_workflow_ref` bu tokenlarda varmış gibi varsayılmaz. Fork/PR/tag/başka repo ve
başka workflow reddedilir. İleride dosya adı değişirse güven koşulları yeniden
incelenmelidir; genişletilerek geçici bypass yapılmamalı.

## 3. Service account ve IAM

Dört anahtarsız hesap oluşturun:
`akys-gh-readonly`, `akys-gh-hosting`, `akys-gh-rules`, `akys-gh-indexes`.
JSON key oluşturmayın. Her hesabın IAM policy'sinde yalnız kendi environment
subject'ine **roles/iam.workloadIdentityUser** verin:

```text
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/akys-github/subject/repo:adnanhasgul-hub/akys:environment:ENV
```

Provider koşulları + subject binding birlikte zorunlu. Pool'un tamamına veya sadece
repo adına blanket binding vermeyin. Token Creator, Owner, Editor, Firebase Admin,
Firestore data user, Auth admin yetkileri bu deployment için gerekli değildir.

`iam-proposals.json` proje custom role izin önerilerini içerir. Bunlar gerçek Google
API üzerinde uygulanıp test edilmedi; Console'da desteklenen izinleri ve CLI'nin
izin ihtiyaçlarını kontrol edin. İzin hatasında Owner/Editor eklemeyin; reddedilen
API'nin dar iznini inceleyin. Hosting hesabının Rules okuma izni, yayın öncesi hash
kontrolü içindir. Rules hesabının data yazma izni yoktur. İndeks hesabında delete
izni yoktur. Read-only hesap entity/Auth kullanıcı okuma izni içermez.

WIF/STS, Service Account Credentials, Firebase Hosting, Firebase Rules, Firestore
API'lerinin etkinliğini kontrol edin. `serviceusage.services.use` kullanım kontrolü
 içindir; API enable veya billing yönetim izni vermez. Admin SDK/IAM Rules'ı bypass
eder; bu hesaplara entity yetkileri verilmedi. Auth admin claim ve klinik onay bu
workflow'ların kapsamında değildir.

## 4. GitHub variables

Her Environment → Variables:

- `GCP_WIF_PROVIDER`: `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/akys-github/providers/github-TARGET`
- `GCP_SERVICE_ACCOUNT`: `akys-gh-TARGET@akys-d708a.iam.gserviceaccount.com`

Bunlar gizli anahtar değildir. Repo secret JSON/FIREBASE_TOKEN kullanılmaz.
Auth action yalnız job süresince kısa ömürlü credential dosyası oluşturur, checkout
sonrasında çalışır ve cleanup yapar. `gha-creds-*` artifact'e eklenmez.
Eski FIREBASE_SERVICE_ACCOUNT_AKYS secret'ı bu değişiklikte kullanılmaz; remote eski
workflow hâlâ dururken secret/key'i otomatik silmeyin. Geçiş tamamlanınca başka
kullanımı kontrol edip uzun ömürlü key'i iptal etmek ayrı yönetici işlemidir.

## 5. Önce salt okunur kontrol

Bu commit'in push/merge'ü ayrıca onayınızı gerektirir; burada yapılmadı. Workflow
manuel menüde görünmek için default main'e alınmalıdır. Feature branch çalıştırması
bilerek hem job hem OIDC tarafında reddedilir. İlk kurulum: güvenlik incelemesi,
onaylı push/PR/merge, environment/provider/SA eşleşmeleri, ardından Actions →
Production read-only inspection → main → Run workflow → environment review.

Çıktı: son10 Hosting release, site kimliği, aktif Rules release/source, tüm composite
index/field override sayfaları ve database metadata. Artifact7 gün tutulur; sadece
repo yetkilileri incelemeli. Başarısız okuma workflow'u başarısız yapar. Tokenlar,
Auth kullanıcıları, koleksiyon/payload içeriği loglanmaz veya okunmaz.
Bu kontrol yedek değildir; export veya restore doğrulaması yapmaz. Veri ve kullanıcı
koruması için ayrıca yetkili backup operatörü gerekir.

## 6. Yedekleme ve rollback kapısı

Production değişikliği öncesinde yönetici:

1. Inspection artifact'i indirip Hosting sürüm adı, Rules source/digest, indeksler,
   SHA, tarih ve run ID'yi kontrollü kayda alın. Hosting sürümünün rollback için
   hâlâ saklandığını Firebase Console'da doğrulayın; artifact tek başına Hosting
   eski dosyalarının yedeği değildir.
2. Mevcut Firestore managed export/PITR/backup durumunu doğrulayın. Geri yükleme
   provası, son başarılı yedek zamanı, retention ve RPO/RTO kaydı olmadan veri
   kaybı riski taşıyan iş yapmayın. Yeni bucket/backup/ücretli kaynak için ayrıca
   onay gerekir. Bu workflow export, migration, import veya delete çalıştırmaz.
3. Auth kullanıcıları silinmez/değiştirilmez. Firestore export Auth yedeği değildir;
   ayrı güvenli hesap kurtarma prosedürünü kontrol edin. Kullanıcı export dosyası
   Git/artifact/log'a konmaz.
4. İndeksler eklemeli: önce oluştur, READY durumunu Console/inspection ile doğrula.
   İndeks oluşturma başarısı hazır olduğu anlamına gelmez. Eski index silinmez.
5. Rules dağıtımından önce kaynak yedeği; geri dönüşte önceden doğrulanmış güvenli
   Rules'ı tekrar yayınla. Kör şekilde eski güvenlik açıklarını geri getirme.
6. Hosting rollback: Firebase Console → Hosting → önceki doğrulanmış release →
   Roll back. Domain/HTTPS/Worker smoke testini tekrar yap. Bu veri geri almaz.
   Firebase CLI rollback komutu varmış gibi varsayılmadı.
7. Yeni yazılmış V2 veriyi eski istemciyle uyumluluk kontrolü olmadan açma. Otomatik
   V1 koleksiyon temizliği veya migration yok. Klinik onay/silme kapalı kalır.

## 7. Manuel deployment

Production-deploy yalnız workflow_dispatch, yalnız main. Her hedef ayrı environment
ve ayrı SA kullanır; test job'ında OIDC yetkisi yoktur. Deploy job environment
onayından sonra kısa ömürlü kimlik alır. Bekleyen review sırasında başka SHA'ya
checkout yapılmaz. `cancel-in-progress:false` yarıda kesmeyi azaltır.

Girdiler: target, exact40hex main SHA, `akys-d708a` onayı, aynı SHA için başarılı
inspection run ID, backup/restore kanıtı referansı. Review eden kişi referansı gerçekten
incelemelidir: metnin dolu olması backup'ın güvenilirliğini makineyle kanıtlamaz.
Workflow inspection run repository/path/event/SHA/success kontrolünü de yapar.

Önerilen sıra: inspection → indeks gereksinimi varsa reviewed index-plan eklemeleri →
READY kontrolü → rules → inspection → hosting. Güncel sorgular için index-plan boş;
indexes seçimi boş planda güvenli biçimde başarısız olur. `indexes.cjs` sadece create
çağırır; alan exemption ve index delete desteklenmez. Ağ kesilirse inspection ile
oluşan operation/index durumunu kontrol edin, yeniden deneyin.

Hosting test edilmiş web artifact'ini indirir; yeniden farklı kaynak derlemez.
Aktif Rules yerel source ile uyuşmadan yayın yapmaz. Mevcut Firebase CLI sürümü
package-lock ile sabittir. Deployment sonrası HTTPS/admin login/Worker/kayıt-açma/
oturum testleri yetkili kullanıcı ile yapılmalı; bu taslakta otomatik admin girişi
ve gerçek backup doğrulaması YOK. Cloud Run/IAM klinik onay servisi kurulmaz.

## 8. Ayrı Android engeli

Mevcut release signingConfig debug anahtarı kullanıyor. Önceki debug APK üzerinde
apksigner doğrulaması `Missing META-INF/MANIFEST.MF` ile başarısız ve v2/v3 block yok.
APK production dağıtımı kapalı tutulmalı. Mevcut imza sürekliliği incelenmeden yeni
anahtar üretilmemeli. Bu GitHub/OIDC çalışması APK imzalama sorununu çözmez.

## Doğrulama sınırı

Yerel workflow/politika/guard kontrolleri gerçek Google OIDC exchange, IAM denial,
Firebase deploy veya rollback testi değildir. İlk read-only koşuda gerçek federation
ve izinleri doğrulayın. Sonra yanlış ref/repo/environment/workflow koşullarının
reddini kontrollü yapılandırma incelemesiyle test edin; tokenları loglamayın.
