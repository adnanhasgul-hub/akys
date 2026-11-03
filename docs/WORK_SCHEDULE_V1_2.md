# V1.2 — Nöbet zorluk puanı ve Türkiye resmî tatilleri

## Ayarlar ve snapshot

Çalışma Çizelgesi → Ayarlar → Nöbet Puanlama Ayarları'nda haftanın yedi gününü ve `preHolidayDifficultyScore` değerini 1–10 arası tam sayılarla yönetin. İlk değerler Pazartesi–Pazar için 3/3/3/1/6/9/5, tatil öncesi için 6'dır. Bunlar yalnız başlangıç değerleridir; Kaydet işlemi gerçek Firestore `work_schedule/main/settings/difficulty` belgesine revision kontrollü transaction ile yazar. Varsayılanları geri yüklemek formu değiştirir; kalıcılık için Kaydet gerekir. Özel günler kaynak/açıklama ve tam/yarım gün bilgisiyle eklenebilir; varsayılan puanlara dönüş özel günleri silmez.

Yeni ay oluştururken güncel ayarlar okunur, doğrulanmış takvim alınır. Ayın kendi tatilleri yoksa popup açılmaz. Varsa her tarih için ayrı puan seçilmelidir; yarım günler dahil bütün puanlar seçilmeden onay butonu açılmaz. İptal, ay oluşturma yazısını engeller. Ay sonundan sonraki ilk gün tatilse boundary snapshot'ına alınır; gelecek aya ait puan bu ay için istenmez.

Ay belgesinde `difficultySchemaVersion=1`, `difficultySettingsSnapshot`, `holidayCalendarSnapshot` ve `holidayDifficultyOverrides` saklanır. Yeni veri schemaVersion'ı 3; motor çıktısı engineVersion'ı 1.2.0'dır. Settings revision'ı popup sırasında değişirse create transaction'ı reddedilir ve yeniden doğrulama istenir. Create transaction'ı hedef ay ve settings belgesini okumadan yazmaya başlamaz.

Aylık puan snapshot'ları genel Kaydet ile de değiştirilemez. Merkezî ayarlar eski taslak/final/published ayları değiştirmez. Bu sürümde taslak puanlarını topluca yenileme butonu yoktur; yeni aylar güncel ayarları alır. Legacy aylar güvenle okunur; eski engine provenance korunur. Snapshot yoksa başlangıç haftalık puanları yalnız açıklanmış bir legacy gösterimidir; takvim bilinmiyor olarak işaretlenir, geriye dönük tatil veya ayar yazımı yapılmaz.

## Puanlama kuralı

1. Tarih tatilse o tarihin admin tarafından seçilen puanı.
2. Sonraki gün tam gün tatilse, Cumartesi için snapshot'ın Cumartesi puanı.
3. Sonraki gün tam gün tatilse, diğer günler için snapshot'ın preHolidayDifficultyScore'u.
4. Diğer tarihlerde haftalık snapshot puanı.

Puanlar toplanmaz. Yarım gün tatili kendi puanıyla işlenir; bir önceki günü otomatik tam tatil öncesi yapmaz (`triggersPreHoliday=false`). Ay sınırı ve yıl sınırı dahil tüm günler UTC civil-date olarak değerlendirilir. Tatil Perşembe ise yine Perşembe kategorisinde sayılır, ayrıca tatil nöbeti olarak işaretlenir.

Takvim kaynağı ve sekiz desteklenen yıl: [HOLIDAY_CALENDAR_SOURCES.md](HOLIDAY_CALENDAR_SOURCES.md). Tarihler runtime'da tahmin edilmez; doğrulanmış paket offline çalışır. Desteklenmeyen yıl boş takvim sayılmaz.

## Optimizasyon ve istatistik

V1.1 senior/junior ve tek nöbet kıdem öncelikleri, bütün hard kurallar ve max8 üst sınırı korunur. Sekiz zorunlu hedef değildir. Yeni ay UI'ı aylık ihtiyaç için günde iki slot önerir, personel max8 kapasitesiyle sınırlar; admin toplam aylık ihtiyacı değiştirebilir. Eski modelin implicit toplamı backward compatibility için korunur. Günlük 1–3 staffing dağılımını motor belirler.

Soft objective'ler lexicographic uygulanır: staffing, karışık grup kompozisyonu, senior'ın çömezli nöbet önceliği, toplam adet dengesi; ardından Cumartesi aşırı dengesizlik koruması, kategori aşırılıkları, toplam zorluk aralığı/varyansı, tatil nöbeti adaleti, ayrı Cumartesi dengesi ve mevcut kategori/Perşembe→Pazar/pairing tercihleri. Tek nöbetleri alt senior'da toplamak ayrı bir adaletsizlik cezası değildir. Puan dengesi grup kıdemini ezemez. Snapshot'sız eski girdiler V1.1 öncelikleriyle çalışır.

Weighted aylar iki deterministik yerel arama sırasıyla değerlendirilir ve daha iyi hard-valid sonuç seçilir. Taşıma/swap kişi toplamlarını korur; sonuçta hard invariant checker çalışır. Global optimum garantisi yoktur; mevcut CSP düğüm sınırı ve yerel arama sınırları sürer.

İstatistikler toplam/tek/eşli/çömezli, beş gerçek gün kategorisi, resmî tatil sayısı ve toplam zorluk puanı içerir. Manuel değişikliklerde yeniden hesaplanır. Excel iki sayfada günlük puanları ve tatil/tatil öncesi işaretlerini; nöbet sayfası altında kişi puan özetini içerir.

Kasım 2026 regresyon fixture'ı, V1.1 (`8a6d973`) algoritmasından türetilmiş hard-valid bir stres varyantıdır; gerçek production verisi veya kullanıcıdan gelmiş Excel değildir. Puan aralığı 23'ten 10'a düşer. Daha küçük fark mümkün olabilir; test global optimum iddia etmez. Gerçek Kasım örnek dosyası erişilebilir workspace'te bulunmadı.

## Güvenlik ve doğrulama

AuthGate/admin claim modeli ve Firestore rules değiştirilmez. Settings admin-only private path altındadır. Public projection'a puan yönetimi, takvim override'ları veya personel grubu eklenmez. Security suite artık gerçek SDK ile settings-read/month-create transaction'ını da çalıştırır; yalnız demo-akys emulator'üne bağlanır. Hosting/Rules workflow dosyaları korunur; Codex'ten production deploy veya credential üretimi yapılmaz.

## Görev dağılımında resmî iş günü kuralı

Yeni aylar `taskWorkdaySchemaVersion=1` ve ayrı `taskHolidayCalendarSnapshot` taşır. Kaynak aynı TBB takvimidir; puan snapshot'ından ve nöbet motorundan bağımsızdır. Pazartesi–Cuma görevler aktiftir. Hafta sonu ve tam tatilde beş görev pasiftir; asıl/yedek/manuel atama ve çakışma değerlendirmesi yapılmaz. Yarım tatil hafta içine gelirse görevler yalnız 13.00 öncesini kapsar; hafta sonu öncelikle pasiftir.

Eski belgeler sürüm 0 ile eski davranışını aynen korur. Görev Dağılımı ekranındaki “Görevleri Resmî İş Günlerine Göre Yeniden Hesapla” yalnız eski taslaklarda, açık onay ve mevcut revision kontrolüyle sürüm 1'e geçer. Var olan V1.2 ayının kendi tatil snapshot'ı kullanılır; daha eski aylar doğrulanmış yerel takvim ve mevcut özel günlerle snapshot alır. Desteklenmeyen yıl işlemi durdurur. Kesin/yayımlanmış aylar otomatik değiştirilmez; snapshot sonradan sıradan kaydetmeyle değiştirilemez. Asıl/yedek tanımları ve eski manuel kayıtlar silinmez; pasif günlerde uygulanmaz.

Günlük masaüstü/mobil görünüm ve Excel pasif günleri “Görev yok” olarak, yarım günleri “13.00 öncesi” olarak gösterir. Yeni paylaşımlarda pasif görevler projection'a eklenmez; yalnız yarım gün görevlerine yönetim verisi içermeyen `halfDay` göstergesi eklenir. Mevcut paylaşımlar kendiliğinden yeniden yayımlanmaz. ICS yarım gün görevlerini açıklamasında 13.00 öncesi olarak etiketler; mevcut tüm-gün hatırlatıcı biçimi korunur. Nöbet atamaları, zorluk puanları ve nöbet istatistikleri değişmez.
