# Legacy metadata migration — production'da ÇALIŞTIRILMADI

Araç yalnız `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`/localhost ve sabit demo-akys
REST hedefini kabul eder. Production proje veya host seçeneği YOK. Varsayılan
`dry-run` hiçbir Firestore yazması yapmaz. Üretim geçişi aşağıdaki ayrı onaylı
prosedürle hazırlanmalıdır; bu yerel araç production'a yöneltilmemelidir.

```sh
# Yerel emülatör içinde; Dart toolchain PATH'te olmalı.
python3 tool/firestore_migration/metadata_migration.py --report /tmp/dry-run.json
python3 tool/firestore_migration/metadata_migration.py --apply-emulator-only \
 --checkpoint /tmp/checkpoint.json --report /tmp/apply.json
# Otomatik test: python3 tool/firestore_migration/emulator_acceptance.py
```

## Algoritma ve kanıt sınırları

50 belgeli cursor sayfaları, deterministik document ID sırası. Legacy head'ler
(historySchema != 2) ve tüm sürümleri okunur. 1..head.version dizisinin eksiksizliği,
ay bilgisi, payload şeması ve gerçek Dart DraftSnapshot decoder kontrol edilir.
Payload doğrulaması 25 belgeli gruplarla yapılır; tüm payload geçmişi bellekte tutulmaz.
Sürüm numarası/hash raporu geçmiş uzunluğuyla büyür. Checkpoint geçici dosyaya
yazılıp flush/fsync ve atomic rename ile değiştirilir; disk/klasör kaybına karşı
yedek değildir. Hatalı checkpoint yazma başlamadan reddedilir.
Eksik/geçersiz klinik taslak korunabilir; migration bir klinik onay değildir.
Orijinal payload baytları SHA-256 ile kayda alınır, değiştirilmez. Versiyon
belgelerine UPDATE/DELETE yapılmaz. Metadata aynı sürüm alanlarının payload'sız
kopyası + historySchema=2'dir. Önceden aynı metadata varsa skip; farklıysa hata,
üzerine yazma yok. Create precondition exists=false ile idempotent backfill.

Head ancak bütün metadata tamamlanınca updateTime CAS ile historySchema=2 olur.
Çalışma kesilirse legacy head eski yolu okumaya devam eder. Tekrar çalışma mevcut
aynı metadata'yı doğrular ve eksikleri tamamlar. Checkpoint'teki payload hash'i
kaynakla uyuşmazsa durur. Checkpoint sorgu yetkisi/kanıt değildir; yeniden doğrulama
her koşuda yapılır. Head concurrent değişirse cutover reddedilir; yeni koşu yeni
sürümü de kapsar. Başarılı bazı metadata yazmaları hata sonrası kalabilir ama
legacy head bunları henüz kullanmaz. Bu bir bütün koleksiyonu kapsayan transaction
değildir. Admin SDK ile sürüm belgelerini eşzamanlı değiştiren başka bakım işleri
çalışmamalıdır; normal istemci Rules immutable sürümleri zaten korur.

## Production için ayrı onaylı prosedür

1. Yazıcıları bakım penceresine al veya eşzamanlı güncellemeler/CAS hataları için
   durma eşiği belirle. Admin bakım işleri için münhasırlık sağla.
2. Head, versions, metadata, events/server_audit yedeği al. Firestore managed export
   için ayrı backup hesabı, erişimi kısıtlı şifreli bucket, retention ve test edilmiş
   geri yükleme gerekir. Sadece JSON dosyası almak yeterli yedek sayılmaz. Kişisel
   payload'ı Git'e/loglara yazma. Export/restore maliyetini ve bölgeyi önceden onayla.
3. Read-only dry-run sayıları, eksik sürümler, hash/şema hataları, toplam byte ve
   beklenen okumalar/yazmalar raporlanır. Sıfır hata zorunlu; inceleyen operatör
   kaynak commit ve rapor digest'ini onaylar.
4. Küçük canary grup; source hash, payload açma, cursor geçmişi, kayıt/revizyon
   ve onay kapısının durumunu doğrula. Sonra sınırlandırılmış batch/rate-limit.
5. Checkpoint ve hata raporunu erişim kontrollü dayanıklı alana kaydet. Tekrar
   çalıştırmada tamamlanan aynı metadata yazılmamalı. Her head cutover CAS.
6. Önce orijinal version hashleri ve sayıları, sonra metadata sayıları ve açılan
   sürüm sonuçları karşılaştırılır. Klinik quality alanı taşınabilir kanıt değildir.
7. Audit/migration journal'ını operatör kimliği ve sunucu zamanıyla güvenilir
   ortamda tut. Yerel checkpoint tek başına immutable denetim izi değildir.

## Rollback

Payload/sürüm belgeleri korunur. İlgili head hâlâ cutover anındaki version/updateTime
ise yalnız historySchema alanını kaldırarak legacy history yoluna dön. CAS başarısız
olursa yeni kayıt vardır; otomatik rollback yapma, yeniden incele. Metadata'yı
silmek gerekmez. Backup restore geniş kapsamlı/geri dönüşsüz etkileri olan ayrı
operasyondur. Yeni yazma sonrasında eski head'i komple geri yazma.

## Maliyet

Dry-run her head ve her sürümü, ayrıca var olan metadata'yı okur; gerçek API read
faturalandırması absent-doc reads/index seçimine göre değişir. Apply her eksik
metadata için 1 write, her tamamlanan head için 1 write; source payload write yok.
Yeniden başlatma güvenlik için source read'leri tekrarlar, tamamlanan yazmaları
tekrarlamaz. Klinik taslaklar büyükse bu read maliyeti bakım bütçesine dahil edilir.
Normal UI history listelemesi aynı sayıda belge fakat çok daha az payload byte
indirir; tek sürümü açmak hâlâ bir payload read gerektirir. İndeks: version ve
at single-field indexleri + __name__; yeni composite gerekmez. Production index
exemption durumu bu görevde okunmadı.
