# AKYS Çalışma Çizelgesi V1

## Kullanım

Çalışma Çizelgesi kartından modülü açın. Personel ekranında isimleri, aktifliği ve kıdem sırasını yönetin. Tutamacı sürüklemek tüm personel için 1..N rank üretir; K1 en kıdemlidir. Pasifleştirme geçmiş ayları değiştirmez.

Nöbet Hazırla ile ay seçin. Varsayılan toplam aylık ihtiyaç `min(aktif personel × 8, ayın gün sayısı × 3)` olarak önerilir; aylık ihtiyacı değiştirebilirsiniz. Günlük 1/2/3 kişi sayısını seçmeniz gerekmez. Motor bu dağılımı üretir. Ayın personel snapshot'ı oluşturulduktan sonra güncel personel değişikliklerinden etkilenmez.

Tutamaz/Tutacak takviminde güne dokunmak Serbest → Tutamaz → Tutacak → Serbest döngüsünü izler. Önceki kayıtlı ayın nöbetleri otomatik alınır. Önceki ay yoksa sınır nöbetlerini manuel doğrulamak zorunludur; nöbeti olmayan personel boş bırakılır. Koşullar veya sınır nöbetleri sonradan değişirse mevcut nöbetler onayınızla temizlenir.

Ön kontrol doğrudan çelişkileri bulur; tam çözüm uygunluğunu Listeyi Oluştur doğrular. Sonuçtaki personele dokunarak gün değiştirebilir veya swap yapabilirsiniz. Basılı tutarak başka güne sürüklemek de taşıma penceresini açar. Hard-invalid düzenlemeler kaydedilmez; adalet puanı kötüleşirse uyarı gösterilir.

Görev Dağılımı ekranında beş görevin asıl/yedeğini seçin. Nöbet ertesi asıl yerine uygun yedek gelir; sonraki uygun gün asıl geri gelir. Aynı kişiye birden fazla görev atanması veya iki adayın da nöbet ertesi olması uyarı üretir. Günlük göreve dokunarak gerekçeli manuel override yapabilir, sonra otomatiğe dönebilirsiniz. Birleşik Görünüm bütün görevleri ve nöbetleri birlikte gösterir. Görev uyarıları nöbet hard kurallarından ayrıdır.

Kesinleştir nöbet invariant'larını doğrular ve tüm ayı düzenlemeye kapatır. Düzenlemeye Aç, o aya ait paylaşımları aynı transaction içinde iptal eder. Arşivleme veriyi silmez. Kesin ay Excel olarak dışa aktarılabilir. Web doğrudan indirir; Android sistem paylaşım sayfasını açar. XLSX iki sayfa içerir: yazdırılabilir nöbet/asıl-yedek tablosu ve günlük birleşik çizelge.

## Motor

Pure Dart engine Firestore/Flutter bağımlılığı taşımaz. Önce sabit nöbetleri yerleştirir, hard doğrulama yapar. MRV, ileri kontrol ve deterministik backtracking ile dengeli günlük staffing şablonlarında çözüm arar. Dengeli şablonlar yeterli değilse esnek günlük kapasiteli CSP onarımı dener. Her gün 1..3 kişi, kişi başına max8, ≥3 takvim günü spacing, Tutamaz/Tutacak ve önceki ay sınırları zorunludur.

Geçerli çözüm ardından taşıma/swap ile lexicographic local optimization yapılır: toplam sayım varyansı, senior'ın daha az toplam nöbet tercihi, gün kategorisi adaleti, Perşembe→Pazar cezası, bağımsız Perşembe/Cuma/Cumartesi/Pazar kıdem tercihleri, staffing dengesi, senior/junior eşleşmesi ve üçüncü kişi için mevcut ikinci nöbetçinin kıdemi. İlk dört snapshot personeli aktif senior grubudur. Günlerin son kişi sırası kıdeme göre sabittir.

Arama sonludur (varsayılan her arama için 350.000 düğüm; yerel iyileştirme 4 geçiş). Global optimum veya sınırsız exhaustive proof iddiası yoktur. Arama sınırına ulaşmak matematiksel imkânsızlık olarak sunulmaz. Geçersiz çözüm hiçbir zaman başarılı sayılmaz. Tekrar üretilebilirlik input'a bağlıdır; motor saat veya random kullanmaz.

## Kalıcılık ve eşzamanlılık

- `work_schedule/main`: authoritative personel registry; seed/reorder transaction kilidi.
- `work_schedule/main/personnel/{id}`: isim dışı ID ile personel kayıtları; fiziksel silme yok.
- `work_schedule/main/months/{YYYY-MM}`: schemaVersion=1, engineVersion=1.0.0, ay metadata'sı, değişmez snapshot, koşullar, boundary, günlük nöbetler ve manuel provenance, aylık görev çiftleri ve override'lar.
- Ay tek atomik belge olarak saklanır; günlük istatistikler/görev sonuçları private veride duplicate edilmez. V1 boyutları Firestore belge sınırının altındadır.
- Ay güncellemeleri revision kontrolü yapar; eski oturumun yazısı reddedilir. Personel reorder registry karşılaştırmasıyla atomik yapılır. UI başarısız reorder'ı iyimser biçimde kalıcı göstermez.

## Paylaşım güvenliği

`shared_schedules/{token}` ayrı bir minimum-data projection'dır. Token OS CSPRNG ile 192 bit (48 hex karakter) üretilir. Final/published ay paylaşılabilir. Bağlantı bir yıl geçerlidir; aynı ayda en fazla 10 bağlantı tutulur. Revoke desteklenir. Yeniden düzenleme mevcut bağlantıları transaction içinde iptal eder.

Public GET yalnızca tam token, revoked=false ve gelecekte expiresAt ile çalışır. Listeleme/yazma admin-only'dir. Private registry, snapshot/koşullar, boundary ve override gerekçeleri public değildir. Linke sahip herkes isim ve planı görebileceğinden bağlantı yalnızca yetkili kişilerle paylaşılmalıdır. Public ekran admin shell'i açmaz; cache-only veriyi server doğrulanana kadar göstermez. Kişisel ad filtresi ve RFC5545 CRLF/folding/all-day ICS indirme vardır. Hasta verisi tutulmaz.

Mevcut Email/Password, AuthGate ve boolean admin:true custom claim kontrolü korunmuştur. Sadece `/shared/schedule/{48-hex-token}` yolu public'tir; hatalı token/diğer route'lar AuthGate'den geçer.

## Test ve build

```bash
source /workspace/akys-toolchain/activate.sh
cd /workspace/akys
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
npm ci --prefix tool/firestore-tests --no-audit --no-fund
npm test --prefix tool/firestore-tests
```

Son komut yalnızca demo-akys yerel Firestore emulator'ünü kullanır (Java 21 gerekir); production'a bağlanmaz. Test bağımlılıkları yalnızca testte fake Firestore kullanır; uygulama üretim yolunda gerçek cloud_firestore repository'sini kullanır.

Ortamın debug signing override'ı korunmuştur; APK imzasızdır, doğrudan cihaza kurulamaz. Release/private key üretilmez. Android paylaşım sayfasının fiziksel cihaz üzerindeki davranışı ayrıca cihaz testi gerektirir.

## Yayınlama sınırı

GitHub Actions mevcut production Hosting deploy komutunu korur; artık önce emulator güvenlik testlerini de çalıştırır. **Firestore rules bu görevde production'a deploy edilmemiştir.** Mevcut production admin-only rules, anonim paylaşımı henüz açmaz. Public paylaşımın canlı çalışması için repository'deki doğrulanmış kuralların ayrı yetkili/onaylı rules yayını gerekir. Bu işlem private veriyi public yapmaz; yalnızca minimum projection'a token GET istisnası ekler. Service account, private key veya production token gerekmedi/oluşturulmadı.

Canlı yönetici hesabıyla uçtan uca login/veri yazma ve gerçek Android dosya paylaşımı bu geliştirme ortamında doğrulanmış sayılmaz. Ortam publish işlemi yapılmaz.
