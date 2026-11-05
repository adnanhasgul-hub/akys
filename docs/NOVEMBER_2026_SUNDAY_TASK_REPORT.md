# 1 Kasım 2026 Pazar — klinik görev gösterimi

Bu rapor kaynak kod ve yerel test fixture'larına dayanır. Production Firestore
belgesi okunmadı veya değiştirilmedi; canlı ayın schema version değeri doğrulanmadı.

## Bulgu

1 Kasım 2026 Pazar günüdür. `taskWorkdaySchemaVersion == 0` olan eski aylarda,
asıl/yedek atamaları varsa Poliklinik, Konsültasyon, Servis, Yoğun Bakım ve Epikriz
hesaplanıp gösterilebilir. Atama yoksa beş görev için eksik atama uyarısı çıkar.

## Kök neden ve katmanlar

- Veri modeli: `ScheduleMonth` ve `fromJson`, eksik `taskWorkdaySchemaVersion`
  alanını 0 kabul eder. Eski veri sessizce dönüştürülmez.
- Hesaplama: `engine/task_engine.dart` içindeki `dailyTasks`, hafta sonu ve
  snapshot'taki tam tatil kontrolünü yalnız schema version > 0 olduğunda uygular.
  Version 0 için eski asıl/yedek/override hesaplaması çalışır. Asıl neden bu
  açık geriye dönük uyumluluk dalıdır; tarih formatı veya timezone hatası değildir.
- Görüntüleme: `CombinedDayCards`, motorun `active`, `halfDay`, `personId` ve
  uyarı sonuçlarını sunar. Pasif günlerde atama ve düzenleme göstermez. UI yeni
  görev üretmez ve motorun aktif saydığı eski günü kendi başına pasifleştirmez.

## Karşılaştırma

Aynı Kasım ayı schema version 1 ile okunduğunda 1 Kasım'ın beş görevi pasiftir;
manuel override/asıl/yedek bulunsa da o gün devralma ve görev uyarısı üretilmez.
Mevcut task_workday testleri bu farkı ve 28 Ekim yarım/29 Ekim tam tatili doğrular.
UI testleri de Pazar pasifliği ve eski ayda manuel görevin korunmasını doğrular.

## Sonraki iş için öneri

Gerçek ay belgesinin schema version ve task calendar snapshot alanları yetkili
ortamda salt okunur incelenmeli. Ay eski şemadaysa mevcut taslak ay için açık
onaylı “Görevleri Resmî İş Günlerine Göre Yeniden Hesapla” akışı değerlendirilmeli.
Kesinleşmiş/geçmiş aylar otomatik değiştirilmemeli. Version > 0 olmasına rağmen
Pazar görevi görülüyorsa ayrı bir hata olarak yeniden üretilmeli.

Bu UI aşamasında veri, algoritma, schema, migration veya production değişikliği
yapılmadı. Bulgu production'daki belirli bir kaydın incelendiği anlamına gelmez.
