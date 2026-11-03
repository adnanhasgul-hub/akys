# Türkiye resmî tatil verisinin kaynağı

Doğrulama tarihi: 3 Kasım 2026.

- Kurum: Türkiye Bankalar Birliği.
- Sayfa: https://www.tbb.org.tr/banka-ve-sektor-bilgileri/banka-bilgileri/bankalar/bankalar-icin-tatil-gunleri
- Sayfanın bağlantı verdiği yıllık PDF: https://www.tbb.org.tr/sites/default/files/docs/tatil-gunleri-2025-2032.pdf
- İndirilen PDF SHA-256: `20ce865e2bf869519c7d505b98c6c84064b43e763e8e23785ada1fcb463dbb11`.
- Kaynak yılları: 2025–2032 (dahil).

PDF'nin yıllık tarih sütunları incelenerek Ramazan/Kurban arefeleri ve bayram başlangıçları birebir aktarıldı. Üç/dört ardışık bayram günü tablodaki aralıklardan açılır; Hicrî tarih tahmini yapılmaz. Sabit tatiller de aynı tablodan alınır. Saat 13.00 sonrası olarak belirtilen arefeler ve 28 Ekim yarım gün olarak kaydedilir. Bir tarihte birden fazla bayram varsa isimler birleştirilir; tam gün kaydı yarım güne düşürülmez.

Aktarılan dinî takvim (arefe / ilk gün):

| Yıl | Ramazan | Kurban |
| --- | --- | --- |
| 2025 | 29 Mart / 30 Mart | 5 Haziran / 6 Haziran |
| 2026 | 19 Mart / 20 Mart | 26 Mayıs / 27 Mayıs |
| 2027 | 8 Mart / 9 Mart | 15 Mayıs / 16 Mayıs |
| 2028 | 25 Şubat / 26 Şubat | 4 Mayıs / 5 Mayıs |
| 2029 | 13 Şubat / 14 Şubat | 23 Nisan / 24 Nisan |
| 2030 | 3 Şubat / 4 Şubat | 12 Nisan / 13 Nisan |
| 2031 | 23 Ocak / 24 Ocak | 1 Nisan / 2 Nisan |
| 2032 | 13 Ocak / 14 Ocak | 21 Mart / 22 Mart |

Uygulama bu doğrulanmış veriyi pure Dart kaynak olarak yerel taşır; runtime API veya internet gerekmez. Desteklenmeyen yılda yeni ay oluşturulması açık takvim doğrulama uyarısıyla durur. Aralık ayının sınır kontrolünde sonraki yılın sabit 1 Ocak tatili kullanılır; bu, sonraki yılın dinî takvim desteği anlamına gelmez.

Diyanet uç noktası bu ortamda HTTP 403 verdi. Alternatif Nager.Date API'sinin 2027 sonuçları tentative ve TBB tablosundan farklı olduğundan o veri takvime alınmadı. Kaynak erişim hatası sessizce boş takvime dönüştürülmez.
