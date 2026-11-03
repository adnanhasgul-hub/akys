# Production Firestore rules yayını

`.github/workflows/deploy-firestore-rules.yml` yalnızca `workflow_dispatch` ile, `main` üzerinde çalışır. Uygulama commitleri rules yayını başlatmaz. Aynı anda bir rules yayını çalışabilir; çalışan yayın iptal edilmez.

1. `security-tests` job'u, lockfile ile kurulan araçlarla yalnızca `demo-akys` yerel emulator testlerini çalıştırır. Credential kullanmaz.
2. `deploy-rules` job'u yalnızca security job'u başarılıysa çalışır ve aynı commit'i checkout eder.
3. Mevcut Hosting workflow'undaki `FIREBASE_SERVICE_ACCOUNT_AKYS` secret referansı, aynı Google auth action üzerinden yalnızca CI'da kullanılır. Secret okunmaz, çıktıya basılmaz veya Codex ortamına aktarılmaz.
4. Sabit deploy komutu yalnızca `--only firestore:rules --project akys-d708a --config firebase.json --non-interactive` kullanır. Hosting, Functions, Storage veya indeks deploy etmez.
5. CI içindeki salt okunur verifier, aktif `cloud.firestore` ruleset kaynağını repository dosyasıyla karşılaştırır. Anonim private GET/LIST, projection LIST ve geçersiz/mevcut olmayan token GET isteklerinin reddedildiğini kontrol eder. Production belge yazımı yapmaz; hata yanıt gövdelerini veya credential ayrıntılarını yazdırmaz.

Manuel başlatma:

```sh
gh workflow run deploy-firestore-rules.yml --ref main
```

Canlı Firebase kullanıcı credential'ı kullanılmaz. Authenticated non-admin/admin custom-claim erişimi, geçerli/revoked/expired token okuması, public create/update/delete ve filtreli token keşfi emulator suite'inde doğrulanır. Bunlar canlı kullanıcılarla test edilmiş sayılmaz. Production OAuth/IAM erişimi custom-claim rules testinin yerine kullanılmaz.

Yayın başarısızsa job log'undaki güvenli hata özeti incelenmelidir. Secret veya IAM izinleri değiştirilmez; ihtiyaç varsa eksik izin raporlanır. Verifier başarısızlığı, deploy adımının mutlaka başarısız olduğu anlamına gelmez: job adımları ayrı kontrol edilmelidir. Yayımlanmış kurallar otomatik olarak geri alınmaz.

Mevcut Hosting workflow dosyası değiştirilmez. Bu workflow'u ekleyen altyapı commit'i `[skip ci]` kullanır; böylece gereksiz Hosting push yayını oluşmaz. Bu işaret manuel rules dispatch'ini engellemez.

## İlk production denemesi — IAM engeli

[Actions run 41585454659](https://github.com/adnanhasgul-hub/akys/actions/runs/41585454659), `0b7ba1e` commit'inde manuel başlatıldı. Security job'u, CLI/config kontrolleri ve mevcut secret ile authentication başarılıydı. Deploy, `https://firebaserules.googleapis.com/v1/projects/akys-d708a:test` çağrısında HTTP 403 `The caller does not have permission` hatasıyla durdu. Yeni kurallar yayımlanmadı; production verifier bu nedenle çalışmadı.

Eksik önkoşul: mevcut `FIREBASE_SERVICE_ACCOUNT_AKYS` secret'ının temsil ettiği service account'a **yalnızca `akys-d708a` projesinde** Firebase Rules yayınlama yetkisi verilmesi. Başarısız test çağrısı `firebaserules.rulesets.test` iznine ihtiyaç duyar; tam CLI yayın akışı ruleset/release oluşturma, okuma ve güncelleme izinlerini de gerektirir. Resmî hazır rol: **Firebase Rules Admin (`roles/firebaserules.admin`)**. Kaynak: [Google Cloud IAM Firebase Rules rolleri](https://docs.cloud.google.com/iam/docs/roles-permissions/firebaserules).

IAM değişikliği bu görevde yapılmadı. Yeni service account veya anahtar oluşturmak, secret değerini okumak/değiştirmek, Owner/Editor vermek gerekmez. Yetkili proje yöneticisi mevcut hesaba gereken proje rolünü verdikten sonra yukarıdaki manuel workflow yeniden başlatılmalı; security testleri yeniden çalışmalıdır. Doğrulama başarılı olmadan production security PASS sayılmamalıdır.

Bu denemede Hosting workflow dosyası değişmedi ve yeni Hosting çalışması tetiklenmedi. Production kullanıcı credential'ları kullanılmadı; canlı authenticated admin/non-admin ve public yazma kontrolleri yapılmış sayılmaz. Bunların güvenlik davranışı emulator testleriyle doğrulandı.
