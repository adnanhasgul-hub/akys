# V1.1 — Nöbet Kıdem Grupları

`seniorityRank` (K1 en kıdemli) ve `dutySeniorityGroup` bağımsızdır. Kalıcı grup değerleri `senior` / `junior`, Türkçe etiketleri Kıdemli / Çömez'dir. Personel kartındaki Nöbet Grubu alanı admin tarafından değiştirilebilir. Drag/drop kıdem sıralaması grubu değiştirmez; örneğin K6 Kıdemli olabilir. Yeni eklenen personel varsayılan Çömez'dir ve değiştirilebilir. Başlangıç seed'inde ilk dört kişi Kıdemli, sonraki üç kişi Çömez olarak açıkça kaydedilir; motor isim kullanmaz.

## Eski veri ve snapshot

Grubu bulunmayan veya tanınmayan legacy alanlarda sadece kayıtlı rank<=4 → senior, diğerleri → junior fallback'i vardır. Personel registry migration'ı transaction ile bu alanı registry ve personel belgelerine açıkça kaydeder; mevcut açık grup değerlerini ve diğer belge alanlarını korur. Sonraki sıralamalar bu grubu yeniden türetmez.

Yeni aylarda grubun o anki değeri snapshot'a yazılır. Legacy ay okunurken fallback yalnızca kendi snapshot rank'ından hesaplanır; güncel personel listesine bakılmaz ve okuma sırasında belgeye yazılmaz. Eski nöbetler ve engine provenance korunur. Yeni ayların schemaVersion'ı 2, motor çıktısının engineVersion'ı 1.1.0'dır. Eski engineVersion, yeniden oluşturma/optimizasyon yapılana kadar korunur.

Mevcut snapshot'ı genel Kaydet işlemiyle değiştirmek reddedilir. Taslak ayda **Ayın Gruplarını Güncelle** ayrı bir onay ister. Yalnız grup alanları güncel registry'den alınır; isim, rank ve activeAtCreation değişmez. Grup değişmişse nöbetler ve manuel nöbet işaretleri temizlenir, yeniden oluşturma gerekir. Önce/sonra grup değerleri ve zaman `snapshotGroupUpdates` içinde kaydedilir. Grup aynıysa nöbetler temizlenmez. Kesin/published ay önce düzenlemeye açılmalıdır; mevcut V1 paylaşım iptal davranışı korunur. Eski revision ile yenileme reddedilir.

## Motor önceliği

Hard kurallar aynıdır: max8, en az üç takvim günü spacing, Tutamaz/Tutacak, boundary, geçerli personel ve günlük 1..3 kişi/toplam ihtiyaç.

Hard-valid adaylar şu lexicographic sırayla değerlendirilir:

1. Günlük staffing dengesi / ihtiyaç.
2. Çok kişilik günde Kıdemli + Çömez kompozisyonu.
3. Çömezle eşleşen senior'ların rank toplamı: küçük rank tercih edilir; tek nöbet alt senior'a kaydırılır.
4. Toplam nöbet adaleti ve toplam yükün kıdem tercihi.
5. Gün kategorileri ve Perşembe→Pazar dahil mevcut soft tercihler.
6. Diğer pairing ve mevcut üçüncü kişi kıdem kuralı.

Grup yalnızca candidate ordering ve soft objective'dir; hiçbir grup kombinasyonu feasibility filtresi değildir. Tek gruptan personel veya fixed-duty koşulları varsa senior+senior / junior+junior geçerli kalır. Takvimde soft uyarı gösterilir.

CSP önce dengeli kişi yükleri arar; gerekirse max8 kapasiteye geçer. Yerel iyileştirmedeki taşıma ve swap işlemleri kişi toplamlarını korur; grup avantajı için kontrolsüz yük dengesizliği yaratılmaz. Her iki yönde taşıma denenir: sabit senior'lar yer değiştiremese de junior daha önceki güne taşınabilir. Motor sınırlı CSP araması ve yerel iyileştirme kullanmaya devam eder; global optimum garantisi yoktur.

Kritik tam-ay testinde diğer bütün tarihler sabittir ve junior'ın tam iki hard-feasible tarihi vardır: K2'nin tek günü veya K4'ün günü. Hem generate hem optimize, K2+junior / K4 tek sonucunu seçer; toplamlar ve staffing dengesi korunur. Test aynı girdinin aynı çıktısını da denetler.

## İstatistik ve güvenlik

- Tek: tek kişinin nöbet tuttuğu gün sayısı.
- Eşli: en az iki kişiyle nöbet günü sayısı.
- Çömezli: yanında en az bir başka Çömez grubu hekim bulunan gün sayısı.

Grup ve bu üç sayı private canlı istatistik tablosunda görünür. Public projection'a grup veya migration/audit alanları eklenmez. Auth/admin kontrolü, Firestore rules ve mevcut Hosting/Rules workflow dosyaları değiştirilmez. Grup özelliği için production Rules deploy gerekmez. Önceden raporlanan Rules service-account IAM engeli bu geliştirme kapsamında çözülmüş sayılmaz.
