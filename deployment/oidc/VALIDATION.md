# Yerel doğrulama — 16 Kasım 2026

Başlangıç branch `feature/akys-v2-solver-core`, HEAD
`c6bcacef965b13197d26ba8d87b7fa0d4328d6df`, temiz ağaç doğrulandı.
GitHub repo API erişimi başarılı: repository1443450449, owner328827663; admin/push/read
izinleri var. Sandbox dışı ağ izniyle salt okunur çağrı kullanıldı; token loglanmadı.

- 8 unittest PASS: doğru/yanlış SHA, boş girdiler, run injection, yanlış run kimliği,
  legacy secret/otomatik push deploy yokluğu, IAM data/delete yetki yokluğu, boş index planı.
- İki YAML parse edildi; yalnız workflow_dispatch tetikleyicisi doğrulandı.
- İki Node script `node --check` geçti.
- Boş index planı ile gerçek script credential exchange/ağ isteğinden ÖNCE reddedildi.
- git diff --check temiz.
- Action referansları GitHub API'den çözülen tam SHA'lara sabitlendi.

Google WIF, SA, IAM, GitHub Environment protection oluşturulmadı/değiştirilmedi.
Workflow GitHub'a gönderilmedi veya çalıştırılmadı. Gerçek OIDC token exchange,
IAM permission listesi, Firebase CLI deployment/rollback başarısı iddia edilmiyor.
IAM JSON dar izin önerisidir; gerçek read-only koşu ve Console kontrolü gerekir.
Actionlint bu ortamda bulunmadı; YAML parse tam GitHub workflow execution testi değildir.
Flutter/solver/UI/Rules değişmedi; gereksiz paket testleri tekrarlanmadı.

Production backup durumu doğrulanmadı. Inspection yapılandırma kaydıdır; Firestore
veri export'u değildir. Backup reference insan incelemesi gerektirir.
Onay/silme/Cloud Run ve Android imzalama bu commit ile açılmadı veya düzeltilmedi.
Remote eski workflow'lar bu yerel commit push/merge edilene kadar değişmez.

Dosyalar:
- Eski iki credential-json deployment workflow'u kaldırıldı.
- production-inspect.yml / production-deploy.yml eklendi.
- deployment/oidc: kurulum, IAM önerisi, boş eklemeli indeks planı, bu rapor.
- tool/deployment: read-only inspection, index create, guard, 8 yerel test.
- .gitignore: kısa ömürlü credential ve inspection çıktısı dışlandı.
