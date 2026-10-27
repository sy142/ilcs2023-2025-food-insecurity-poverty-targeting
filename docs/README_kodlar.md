# Kodlar: çalıştırma sırası, süreler, ortam

Bütün komutlar proje kökünden çalıştırılır (`Foods Makalesi 2/`). Göreli yollar proje köküne göredir.

## Sıra

1. `Rscript Codes/analiz.R`
   Tek giriş noktası. Sırasıyla:
   - xlsx okuma (yalnız ilk çalıştırmada; tarif belgesi Okuma 1, `col_types = sozluk$okuma_turu`), `R_Data ve Python Data/gyka_2023_2025.parquet` ve `.rds`, `sozluk.csv`, `kodlar.csv`, `dogrulama_sayfasi.csv`;
   - doğrulama (`Results/dogrulama_kontrolleri.csv`), hane veri seti ve yıllar arası imza eşleştirmesi (`R_Data ve Python Data/hane_2023_2025.parquet`, `ortusme_eslesmeleri.csv`);
   - `Codes/kesif.R` (çıktısı `Results/kesif/kesif_cok_degiskenli_katmanlar.csv` yoksa);
   - H1 (survey paketi; tasarım temelli doğrusallaştırma);
   - `Codes/ml.py` (`Results/H2_ozet.json` yoksa);
   - `Codes/mlp.py` (derin ağ kolu, PyTorch MPS; `Results/H2_mlp.csv` yoksa; hata verirse akış durmaz);
   - H3 (g-computation, etki fonksiyonu SE'si, Rao–Wu–Yue yeniden ölçeklenmiş hane bootstrap'ı; önbellek `R_Data ve Python Data/onbellek/boot_*.rds`);
   - `Codes/simulasyon.py` (özet yoksa önce 50 tekrarlık pilot `simulasyon/pilot/`, sonra tam koşu);
   - `Codes/s3_aralik.py` (`Results/S3_aralik_kapsamasi.csv` yoksa): S3'ün 500 örneklemini ve 200'er replikatını aynı tohumlarla yeniden kurar (yüzdelik sınırların `S3_ham.csv` ile aynı olduğunu denetler) ve yüzdelik, basic ve BCa aralıklarının kapsamasını hesaplar; yeni veri üretmez;
   - Table 1–3, Table S1–S20 (docx + csv), `Results/tablolar_tumu.xlsx` (`Codes/xlsx_simge.py` alt/üst simgeleri gerçek biçime çevirir), figür verileri, `sayilar.json`, oturum bilgisi, paket atıfları, STROBE ve TRIPOD+AI notları.
2. `/Users/salim/veri-ortami/bin/python3 Codes/figurler.py`
   Bütün figürler `R_Data ve Python Data/figur_verileri/*.csv` (ve birkaç `Results/H2_*.csv` özet tablosu) dosyalarından çizilir; figür kodu veri hesaplamaz (yalnız arı kovanı yerleşimi gibi görsel düzen hesapları yapar; görüntü alt örneği `ml.py`'de seçilir). Ana metin: Figure 1–6; ek: Figure S1 (karar eğrileri), S2 (yıllar arası kalibrasyon), S3 (SHAP bağımlılık özetleri). Tek figür: `python Codes/figurler.py 4` ya da `python Codes/figurler.py S3`. Ortak stil ve palet `Codes/figur_stili.py`, metin etiketleri `Codes/etiketler.json` (R tabloları da aynı dosyayı okur).

Ayrı çalıştırma: `Rscript Codes/kesif.R` (önce `analiz.R`'nin hane veri setini yazmış olması gerekir), `python Codes/ml.py`, `python Codes/mlp.py`, `python Codes/simulasyon.py pilot|tam`, `python Codes/s3_aralik.py` (önce ml.py ve simülasyonun çalışmış olması gerekir).

Tekrar üretim denetimi: `python Codes/sayilar_karsilastir.py eski/sayilar.json Results/sayilar.json` iki çalıştırmanın bütün sayısal alanlarını karşılaştırır (süre alanları hariç).

## Önbellekler

- `R_Data ve Python Data/onbellek/ml/`: LightGBM ayar sonuçları (`ayar_*.csv`, `ayar4_*.csv`), biçim merdiveninin kısıtlı LightGBM ayarları ve modelleri (`bicim_ayar_*.csv`, `bicim_model_*.pkl`), nihai ve yıl modelleri (adlarında seçilen yapılandırma ve tur sayısı var; ayar değişirse yeniden eğitilir), lojistik, CART ve L1 modelleri, SHAP değerleri (`shap_*.npy`) ve Friedman H sonuçları (`etkilesim_H_*.pkl`). Ayar önbellekleri katların tanımına bağlıdır: eşleştirme ya da kat tanımı değişirse `onbellek/ml/` taşınıp ml.py baştan çalıştırılmalıdır.
- `R_Data ve Python Data/onbellek/boot_*.rds`: H3 bootstrap tekrarları (anahtar adında tekrar sayısı var).
- `R_Data ve Python Data/simulasyon/S1_sid*_R*.parquet`: S1 tekrarları.
Sıfırdan üretim için bu klasörler ve `Results/` boşaltılır (arşiv klasörüne taşınması önerilir); `analiz.R` gerekli klasörleri kendisi oluşturur.

## Süreler (64 GB, 18 çekirdekli Mac; 16 işçi)

Son temiz çalıştırmanın süreleri `Rapor.md` Bölüm 13'te; ayrıntı `Results/log/analiz_sureleri.csv` ve `Results/log/ml_sureler.csv`.

## Ortam

- R 4.6.1, Apple Accelerate BLAS; paket sürümleri `Results/sessionInfo.txt`.
- Python 3.13.16, `/Users/salim/veri-ortami` (uv sanal ortamı); paketler `Results/python_ortam.txt` (lightgbm 4.7.0, scikit-learn 1.9.1, shap 0.54.1, torch 2.14.1, numpy, pandas, scipy, matplotlib, pyarrow, joblib).
- Paralel hesap: R'de `future::plan(multisession, workers = 16)` ve `furrr`, işçilerde `VECLIB_MAXIMUM_THREADS = 1`; Python'da `joblib` (16 işçi, LightGBM `num_threads = 1` ayar görevlerinde, nihai modellerde 3 iş parçacığı × 5 tohum). GPU (Apple MPS) yalnız derin ağ kolunda (`mlp.py`) kullanıldı; ağaç modelleri ve simülasyon CPU'da.

## Tohumlar

- R: genel 20261026; H3 bootstrap çarpan matrisi 20261027 (4.000 sütun; 2.000 tekrarlık modeller ilk 2.000 sütunu kullanır).
- ml.py: 20261026 (geniş arama yapılandırmaları), 20261027 (ince arama), 20261127/20261128 (3. aşama ek tohumları), 20261426 + tur (sınır genişletme), nihai modeller 20261026–20261030 (5 tohum), H2 bootstrap 20261033.
- simulasyon.py: senaryo tohumu 20261101 + 1000 × senaryo numarası; tekrar tohumları senaryo tohumundan türetilir; S3 için 20761101 + veri seti numarası.

## Veri güvenliği

Mikro veri ve hane/kişi düzeyinde ara dosyalar yalnız `R_Data ve Python Data/` altında; `Results/` ve `Figures/` yalnız toplulaştırılmış çıktı içerir.
