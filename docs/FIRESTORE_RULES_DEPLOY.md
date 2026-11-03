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
