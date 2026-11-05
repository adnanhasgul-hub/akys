# V1.3 aylık dağılım teşhisi ve yerel düzeltme

Temel production commit: `514d16e9f39fdf8efc5b9e285aabdbb27c23daf3`.
Yerel çalışma branch'i: `fix/v13-monthly-distribution`. Production yayını yok.

## Yeniden üretim

Kullanıcı: Kasım, Tutacak/Tutamaz yok, 10.000 düğüm, aynı sonucu tekrarlıyor.
Yerel fixture: Kasım 2026, K1–K4 senior ve K5–K7 junior, aktif yedi kişi,
boş önceki-ay sınırı. Gerçek production ay belgesi okunmadı; gerçek snapshot ve
önceki ay sınırı doğrulanmadı. İsimler hiçbir algoritmik kararda kullanılmaz.

Eski CSP sırası (onarım callback'i olmadan) 10.000 düğümde:

- `SEARCH_LIMIT_REACHED`, optimumluk kanıtı yok.
- K1/K2/K3/K4 tek nöbetleri: **2 / 2 / 1 / 1**.
- Tek tarihler: **25, 26, 27, 28, 29, 30 Kasım**.
- Aylık hiyerarşi metriği: **66**. Bu, tek nöbet ile alt kıdemlinin eşli nöbeti
  çarpımlarının toplamıdır; 66 ayrı tarih anlamına gelmez.

Aynı fixture için validator'dan geçen, K1/K2/K3/K4 tek nöbetleri **0/0/0/6**
ve hiyerarşi metriği sıfır olan bir tanık çizelge mevcut. Dolayısıyla bu koşullarda
K2'nin iki tek nöbeti veya son altı günün boş junior olması zorunlu değil.
Üç junior × sekiz üst sınır = 24 junior nöbeti olduğundan, 30 günde **en az altı**
boş junior pozisyonu zorunlu; belirli kişiye/tarihe verilmesi bundan çıkmaz.

## Kök neden

1. İlk çözümden sonra arama gerçekten devam ediyor. Ancak lexicographic dalı
   aynı kökten derinlik öncelikli CSP aramasına dönüyor; yeterli erken-ay
   yeniden yerleştirmesi olmadan bütçeyi çoğunlukla sonraki kararları gezerek
   tüketiyor. İlk geçerli incumbent kaybolmuyor ama kalite düşük kalabiliyor.
2. MRV eşitlikleri kronolojik gün sırasını izliyor; adaylar junior doluluğunu
   ve az kullanılmış kişiyi önce deniyor. İlk çözümde junior kapasitesi erken
   tüketiliyor. Tekrar basmak deterministik olarak aynı ağacı ve bütçeyi çalıştırır.
3. Hedef sırası yanlış değil: substitution, junior kapsamı, aylık hiyerarşi,
   senior tek sayıları üst öncelikte. Sorun bunlara uygun alternatiflere ulaşma
   kalitesi ve zaman dağılımı hedefinin eksikliğiydi.
4. Must/Cannot ve boundary filtreleri aramada uygulanıyor. Bunlar gerçek aylarda
   sonucu değiştirebilir; önceki ayın nöbet puan/sayıları yeni ayın fairness
   hesabına eklenmiyor. Kısıtsız/boş boundary örneği hatayı tek başına yeniden üretir.

## Yerel değişiklik

- `incumbent_repair.dart`: ilk geçerli çözümden sonra ayın tamamındaki junior
  yerleşimini yeniden arayan sınırlı aday üretimi ve doğrulanmış yerel taşıma/
  senior değişimi. Basit senior+junior yapısında boş pozisyonlar alt senior kıdemi
  ve ay içi yayılım dikkate alınarak adaylandırılır; junior atamaları backtracking
  ile aranır. Bu aday mümkün değilse mevcut çözüm korunur. Substitution/üçlü
  yapılarda bu özel aday üretimi kullanılmaz; genel doğrulanmış yerel arama sürer.
- Bütün denemeler aynı nodeLimit, cancellation ve event-loop checkpoint'ini
  kullanır; onarım en fazla toplam bütçenin yarısı kadar aday/düğüm harcar.
  Kalan bütçede mevcut CSP devam eder. Sayım artık CSP düğümlerini ve onarım
  adaylarını kapsar; kullanıcı bütçesi aşılmaz.
- Her kabul edilen aday tam ConstraintValidator kontrolünden geçer ve tüm
  leksikografik hedef vektörünü iyileştirmek zorundadır. Sonuç solver içinde
  yeniden doğrulanır; geçerli incumbent korunur.
- `soloCalendarSpread`: kümülatif tek nöbet sayısının aya eşit yayılımından
  sapmasının kareleri toplamı. Substitution, junior kapsamı, hiyerarşi, senior
  tek önceliği ve grup nöbet sayılarından SONRA; gün kategorilerinden ÖNCE gelir.
  Daha yüksek öncelikli hedefler kötüleşemez. Yeni hard constraint değildir.
- Local optimum / belirli boşlukların zorunluluğu / global optimum iddiası yok.
  Arama limiti ve kanıt alanları korunur; yerel başarı proof flag üretmez.

## Sonuç

Aynı 10.000 bütçede yerel düzeltme:

- Tek nöbetler: **0 / 0 / 0 / 6**.
- Tarihler: **4, 8, 12, 16, 24, 28 Kasım**.
- Hiyerarşi metriği: **0**; substitution: **0**; boş junior: **6**.
- Hard constraint kontrolü başarılı; junior kapsamı azalmadı.
- `SEARCH_LIMIT_REACHED` korunuyor; genel optimum kanıtlanmadı.
- VM örnek koşusu yaklaşık 2 saniye; platforma/donanıma göre değişir.

Beş yeni test: eski aramanın deterministik hatası ve daha iyi tanık + düzeltilmiş
aynı-bütçeli çözüm + tekrar determinism; hedef önceliği; Must/Cannot/boundary ve
input immutability; onarımda iptal/valid incumbent; aynı üst hedeflerde temporal
tercih. Mevcut küçük exhaustive optimum ve hard constraint testleri korunuyor.

UI, Firestore model/repository, Rules, Auth, Firebase ve deployment workflow'u
bu düzeltmede değiştirilmedi. Canlı ayın boundary/snapshot farkları için ayrıca
aynı girdilerle doğrulama gerekir. Yerel arama küresel optimum garantisi vermez;
özellikle substitution/üçlü yapı ve yoğun kısıtlarda kalan kalite sınırı açıkça
raporlanmalıdır. Eski Pazar klinik görev konusu kapsam dışıdır.

Son doğrulama: analyze temiz; tam Flutter paketi 236/236 PASS; Chromium solver
ve V1.3 entegrasyon paketi 47/47 PASS. Bu sonuçlar kod değişmeden entegrasyon
hazırlığında referans alınmıştır. Production deploy yapılmadı.
