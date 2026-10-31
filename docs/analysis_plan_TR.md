Written analysis plan, prepared before model fitting (in Turkish). Words identifying the publication venue and local folder names were neutralized for the archive; no other content was changed.

# Gıda güvencesizliği, gelir yoksulluğu ve hedefleme: Analiz Talimatı

Sürüm 1, 26 Ekim 2026. Bu belge VS Code'daki ajana yazılmıştır. Makaleyi biz yazacağız; senden istenen, aşağıdaki analizlerin tamamını bitirmiş, dosyalanmış, yeniden üretilebilir ve raporlanmış olarak teslim etmendir. Önce bu belgeyi baştan sona oku, sonra proje kökündeki `GYKA_2023_2025_tarif.docx` ve `GYKA_2023_2025_inceleme_raporu.docx` belgelerini oku. Sorularını ve kararlarını `Rapor.md` içinde tut; bizden cevap beklemeden ilerleyebileceğin her yerde varsayılan kararı uygula ve kaydet.

---

## 0. Çalışmanın özü

**Soru.** Türkiye'de gıda güvencesiz haneleri gelir yoksulluğu eşiği ne ölçüde kaçırıyor; kaçırılan haneleri idari kayıtlarda da bulunabilecek az sayıda yapısal özellik tanıyabiliyor mu; kaçırılanların beslenmesi gerçekten yoksun mu?

**Veri.** TÜİK Gelir ve Yaşam Koşulları Araştırması (GYKA) 2023, 2024 ve 2025 kesit mikro verileri, birleşik dosya `GYKA_2023_2025_birlesik.xlsx` (239.985 fert satırı, 266 sütun). Gıda güvencesizliği göstergesi HE090 = 2 (hane iki günde bir et, tavuk veya balık içeren yemeği karşılayamıyor). Veride FIES gibi bir ölçek yok; HE090 tek maddedir ve makalede böyle anlatılacaktır. Diyet sıklığı, sağlık harcaması yükü, BKİ ve WG-SS yalnız 2025 modülünde vardır.

**Çıkış noktası (birinci çalışmadan bilinen).** 2025'te kişilerin %35,1'i HE090 = 2 olan hanede yaşıyor; göreli yoksulluk (%60 eşiği) %20,6. 2023'ten 2025'e toplam pay %39,1'den %35,1'e inerken en yüksek gelir diliminde %9,6'dan %2,8'e, en düşük dilimde %68,2'den %72,1'e gitti. Yani düşüş üstte yoğunlaştı, gradyan dikleşti.

**Önceden belirlenmiş hipotezler.**

- H1. Gıda güvencesiz hanelerin yarısından fazlası gelir yoksulluğu eşiğinin (%60) dışındadır ve bu pay 2023'ten 2025'e artmıştır.
- H2. İdari kayıtlarda bulunabilecek az sayıda yapısal özellikten kurulan bir kural seti, aynı kapsama oranında yoksulluk eşiğinden ve yalnız gelire göre sıralamadan anlamlı ölçüde daha fazla gıda güvencesiz hane yakalar; bu kazanım geçmiş yıllarda kurulup 2025'te sınandığında korunur.
- H3. Gelir yoksulu olmayan gıda güvencesiz hanelerdeki yetişkinlerde düşük sıklıklı et, meyve ve sebze tüketimi, gıda güvenceli hanelerdekine göre belirgin biçimde yaygındır ve gelir yoksulu gıda güvencesizlerdekine yakındır.

Hipotezler sınanır, doğrulanmaz. Aşama 0 (keşif) bittiğinde hipotezlerin yeniden ifade edilmesi gerekip gerekmediğini `Rapor.md` "Bize sorular" bölümünde gerekçesiyle yaz; biz cevap verene kadar bu belgedeki tanımlarla devam et. Sonuçları gördükten sonra yapılan her değişiklik karar defterinde "sonuçlar görüldükten sonra" diye işaretlenir.

**Hedef dergi.** [Hedef dergi bilgisi arşiv sürümünde çıkarılmıştır.] Makale türü araştırma makalesi. Ana metinde tablo ve figür toplamı en çok 6; gerisi Supplementary Material.

**Senin ürünün.** Kodlar, veri setleri, sonuç tabloları (docx, csv, xlsx), figürler (PNG, PDF, TIFF), `sayilar.json`, `Rapor.md`, `README_kodlar.md`, altyazı ve tablo notu taslakları. Makale metni yazma.

---

## 1. Klasör yapısı ve dosya kuralları

Proje kökü: `[proje kökü]/`. Bütün komutlar proje kökünden çalıştırılır; göreli yollar köke göredir. Yapı birinci çalışmayla (`../[birinci çalışma]/`) aynıdır:

```
[proje kökü]/
  GYKA_2023_2025_birlesik.xlsx
  GYKA_2023_2025_inceleme_raporu.docx
  GYKA_2023_2025_tarif.docx
  [talimat dosyası].md              (bu belge)
  Rapor.md                          (sen yazacaksın)
  Codes/
    README_kodlar.md
    analiz.R                        (tek giriş noktası: veri, H1, H3, tablolar, sayilar.json)
    ml.py                           (H2: modeller, metrikler, SHAP, kurallar)
    simulasyon.R                    (ya da simulasyon.py; Bölüm 7)
    figurler.py, figur_stili.py     (bütün figürler)
    xlsx_simge.py                   (xlsx alt/üst simge; birinci çalışmadan kopyalanabilir)
    kesif.R                         (Aşama 0; Ek A'daki başlangıç kodu)
  Figures/                          (Figure1.png/.pdf/.tiff ...; figur_altyazilari.md)
  Figures/Supplementary/            (FigureS1 ...)
  R_Data ve Python Data/            (parquet, rds, csv kopyaları; yalnız burada kişi düzeyi veri)
  R_Data ve Python Data/onbellek/   (bootstrap ve model önbellekleri)
  R_Data ve Python Data/simulasyon/
  R_Data ve Python Data/figur_verileri/   (figürlerin çizildiği toplulaştırılmış CSV'ler)
  Results/                          (Table1.docx/csv ..., tablolar_tumu.xlsx, sayilar.json, model_ozetleri.txt, sessionInfo.txt, python_ortam.txt, paket_atiflari.txt, strobe_akis.md, tripod_notlari.md)
  Results/Supplementary/            (TableS1 ...)
  Results/kesif/                    (Aşama 0 çıktıları)
  Results/log/                      (çalıştırma logları, tanı grafikleri)
```

Kurallar:

- Mikro veri ve kişi düzeyinde ara dosyalar yalnız `R_Data ve Python Data/` altında durur. `Results/` ve `Figures/` yalnız toplulaştırılmış çıktı içerir.
- Birinci çalışmanın kodları `../[birinci çalışma]/Codes/` altındaysa oradan yeniden kullanabilirsin: `figur_stili.py`, `xlsx_simge.py`, `analiz.R` içindeki `irls`, `mm_kur`, `gc_tahmin`, `gc_if`, `boot_gc` (g-computation, etki fonksiyonu SE'si, Rao-Wu-Yue-Beaumont hane bootstrap'ı) ve `tablo_cikar` (flextable + xlsx tablo kurucu). Kopyaladığını `Rapor.md`'de belirt.
- Veri okuma: tarif belgesi Bölüm 1.4, Okuma 1 (`col_types = sozluk$okuma_turu`). xlsx bir kez okunur, `R_Data ve Python Data/gyka_2023_2025.parquet` ve `.rds` yazılır; sonraki bütün adımlar parquet'ten okur. `sozluk`, `kodlar`, `dogrulama` sayfaları CSV olarak aynı klasöre yazılır. Okuma 19 GB tepe bellek ister; makine 64 GB.
- Her şey ham xlsx'ten tek komutla yeniden üretilebilir olmalı: `Rscript Codes/analiz.R` sırasıyla veri hazırlığını, `Codes/kesif.R` çıktılarının yokluğunda keşfi, H1'i, `Codes/ml.py`'yi (çıktıları yoksa), H3'ü, simülasyonu (özeti yoksa), tabloları ve `sayilar.json`'ı üretir; ardından `python Codes/figurler.py` bütün figürleri `figur_verileri/*.csv` dosyalarından çizer. Figür kodu veri hesaplamaz.

---

## 2. Çalışma kuralları (bizim kalıcı tercihlerimiz)

**Kod.**

- Veri düzenleme ve istatistiksel analiz R'de; makine öğrenmesi Python'da (lightgbm, scikit-learn, shap); figürler Python'da (matplotlib). Python yorumlayıcısı `/Users/salim/veri-ortami/bin/python3` (uv sanal ortamı). Eksik paketleri bu ortama kur (lightgbm, shap, scikit-learn, pyarrow; isteğe bağlı torch, tabpfn), kurulumdan önce mevcut sürümlerin değişmeyeceğini kuru çalıştırmayla denetle; sürümleri `Results/python_ortam.txt`'e yaz.
- R kodunda `#` ile açıklama veya bölüm başlığı satırı yazma. ASCII süsleme (`# ====`) yok. R kodunda Türkçe karakter kullanma; değişken adları ve mesajlar ASCII, etiketler İngilizce. Tipografik işaretler gerekiyorsa (en dash, ≥, ±) Unicode kaçış kodu olarak yazılabilir. Python'da bu ASCII kuralı geçerli değildir ama kod yine açıklama satırlarından arındırılmış ve sade olsun.
- Her script baştan sona hatasız çalışmalı; bir yıl sonra açıldığında aynı sonuçları vermeli. Tohumlar sabit ve raporda yazılı. Uzun hesaplar önbelleklenir (`onbellek/`), dosya varsa yeniden hesaplanmaz; sıfırdan üretim için klasör boşaltılır.
- Paket atıfları uydurulmaz: `citation("paket")` çıktısı `Results/paket_atiflari.txt`'e, Python kütüphaneleri için README'lerinin önerdiği atıflar aynı dosyaya yazılır.

**Donanım.**

- Mac, 64 GB bellek, 18 çekirdek CPU, 40 çekirdek GPU. CPU'da en çok 16 işçi (`future::plan(multisession, workers = 16)`, işçilerde `VECLIB_MAXIMUM_THREADS = 1`; LightGBM `num_threads = 16`).
- GPU (PyTorch MPS) yalnız derin ağ karşılaştırması ve gerçekten büyük matris işlemleri için. LightGBM, bootstrap ve simülasyon CPU'da paralel. Hangi adımın nerede ve kaç dakikada koştuğunu `Rapor.md` Bölüm 13'e (süreler) yaz.

**Tasarım ve ağırlıklar (tarif belgesi Bölüm 1.4, 2.2, 2.3).**

- Hane düzeyi: her hane bir kez (`hane_reisi == 1`), ağırlık HB040, `ids = ~1`. Kişi düzeyi (tüm yaşlar): FK050, hane kümeli. 15+ yetişkin: FB030, hane kümeli. Tabaka ve birincil örnekleme birimi veride yok; İBBS 2 (HB031) sözde tabaka duyarlılıkta.
- Yıllar ayrı ayrı analiz edilir; havuzlanmış tahmin yapılmaz. Yıllar arası fark hesaplanırken örneklemler bağımsız sayılır ve bunun (rotasyon örtüşmesi nedeniyle) tutucu olduğu not edilir.
- Gelir nominal TL'dir; yıllar arası karşılaştırmada yalnız göreli ölçüler (goreli_esdeger_gelir, gelir_dilim5/10, yoksul_50/60/70) kullanılır.
- Küçük hücre: ağırlıksız n < 20 ise tahmin verilmez, 20–50 ise işaretlenir (tarif Bölüm 2.4). Seyrek kategoriler (n < 100 veya olay < 10) komşuyla birleştirilir ve karar defterine yazılır.
- Bütün tablolarda n ağırlıksız, yüzde ağırlıklı; bu tablo notunda yazar.

**Dil ve çıktı biçimi.**

- Rapor ve karar defteri Türkçe. Figür içindeki bütün yazılar, tablo başlıkları, sütun adları ve notlar Amerikan İngilizcesi (standardized, equivalized, analyzed). Nedensel dil yok: "association", "difference", "prevalence", "captured".
- Tablolar: flextable ile docx + aynı içerik csv + `Results/tablolar_tumu.xlsx` (tek çalışma kitabı, sayfa başına tablo; alt ve üst simgeler `xlsx_simge.py` ile gerçek biçim). Times New Roman 9 pt, notlar 8 pt. Birbirini kapsayan başlıklar birleşik hücre; grup başlıkları tek satır (ör. "Household type" bir kez yazılır, kategoriler altında girintili). "Decision", "Reject" gibi sütunlar yok. Açıklama gerekmedikçe tabloya not ekleme; notlar kısa.
- Figürler: üstte "Figure 1." başlığı olmaz; paneller aynı figür içinde, dergi biçiminde **(a)**, **(b)** etiketli; 600 dpi PNG, gömülü yazı tipli PDF ve LZW TIFF; yazı tipi Avenir Next (yoksa Helvetica Neue), temel 8 pt, panel harfi 11 pt kalın; renkler Okabe-Ito tabanlı, renk körlüğü denetiminden geçmiş; çift eksen yok; alt simgeler gerçek alt simge (mathtext). Figür kalitesi SCI düzeyinde; varsayılan matplotlib görünümü kabul edilmez. Her figürün altyazı taslağı `Figures/figur_altyazilari.md`'ye İngilizce yazılır.
- Denetim çıktısı ile yayın çıktısını ayır: her tanı grafiğini supplementary öğesine çevirme; `Results/log/` ve `Results/kesif/` altında tut, raporda özetle.

**Rapor.md.** Birinci çalışmadaki yapıyı kullan:

0. Durum (son güncelleme zamanı, hangi aşamada, bitenler, sırada ne var, tahmini süre; uzun koşularda ilerleme satırı)
1. Aşama günlüğü (her aşamada: amaç, ne yapıldı, neden, nasıl, ne bulundu, hangi dosyalar üretildi)
2. Karar defteri (K1, K2, ...: karar, gerekçe, alternatif, etkisi; sonuçlar görüldükten sonra alınanlar işaretli)
3. Doğrulama kontrolleri (tablo)
4. Özellik katmanları ve kovaryat seçimi
5. Model kurma protokolü (kontrol, ölçüt, sonuç, karar, etkilenen model)
6. Nihai değişken tanımları
7. Ana sayılar (Results için)
8. Simülasyon özeti
9. Methods için notlar (İngilizce taslak cümleler dâhil)
10. Hipotez değerlendirmesi (her hipotez için kanıt ve iddianın düzeyi)
11. Bize sorular
12. Eksikler ve yapılamayanlar
13. Dosya envanteri ve süreler

Her aşama bittiğinde ve 30 dakikayı aşan her hesabın ortasında (ilerleme satırıyla) güncelle. "Bize sorular"a yazdığın her soru için uyguladığın varsayılan kararı da yaz.

**İnisiyatif sınırları.** Sen karar verirsin: kodlama ve seyrek kategori birleştirmeleri, kovaryat seçimi (Bölüm 6'daki kurallarla), hiperparametre arama uzayı, bootstrap tekrar sayısı (yakınsama kuralına bağlı), figür düzeni (stil içinde), simülasyon senaryolarının ayrıntısı. Bize sorarsın (soruyu yazıp varsayılanla devam ederek): tahmin edilen büyüklüklerin tanımında değişiklik, bir analizin tamamen çıkarılması, hipotezlerin yeniden ifadesi, bir nüfus grubunun dışlanması.

---

## 3. Veri hazırlığı (Aşama 0a)

### 3.1. Okuma ve doğrulama

Okuma 1 ile oku, parquet yaz. Tarif belgesindeki `dogrulama` sayfasındaki değerleri yeniden üret ve `Results/dogrulama_kontrolleri.csv`'ye yaz. En azından şunlar tutmalı: satır 239.985, sütun 266; 2025 hane 25.836, fert 80.206, fert görüşmesi 61.812; 2025 HE090 = 1 / 2 hane 15.772 / 10.064; 2025 yoksul_60 (FK050, tüm fertler) %20,6; 2025 Gini 0,410; HE090 = 2 kişi payı (FK050) 2023 %39,1, 2024 %39,3, 2025 %35,1 (Eurostat ilc_mdes03 ile aynı); HB040 toplamı 26,7–27,2 milyon hane; FB030 toplamı = 15+ yaş FK050 toplamı. 2023'te TR63 hanesi yok.

### 3.2. Hane veri seti (üç yıl)

Her hane bir satır (`hane_reisi == 1`), `R_Data ve Python Data/hane_2023_2025.parquet`. İçerik:

- Hane değişkenleri: HB030, HB031, HB050, HH010–HH240, HS010–HS070, HE010–HE120, HG010–HG110, hane_buyuklugu, hane_0_17, hane_65plus, esdeger_gelir, goreli_esdeger_gelir, gelir_dilim5, gelir_dilim10, hane_gelir_dilim5, yoksul_50, yoksul_60, yoksul_70, yoksulluk_acigi_60, is_yogunlugu, dusuk_is_yogunlugu, konut_maliyet_orani, konut_maliyet_asiri_yuk, kalabalik_konut, ciddi_konut_yoksunlugu, msy_* maddeleri, msy_sayi, msy_5, msy_7, yoksulluk_sosyal_dislanma.
- Hanehalkı sorumlusu: FK070 (reis_yas), FK090, FB100, FI010, FK210, FS010, FS020, FS030, FE030'dan eğitim 5 grup (0–1 / 2–3 / 4 / 5–6 / 7–10).
- Üyelerden toplananlar (tüm satırlardan, hane_kimlik ile): n_yetiskin (FK070 ≥ 18), n_cocuk (< 18), n_0_5, n_65plus, n_75plus, n_kronik (18+, FS020 = 1), n_gali (FS030 ∈ {1,2}), n_kotu_saglik (FS010 ∈ {4,5}), n_calisan (FI010 ∈ 1:4), n_issiz (5), n_emekli (7), n_ev_isi (9), n_kayitsiz (çalışan ve FI190 = 2), n_yevmiyeli (FI120 = 2), n_gecici (FI210 ≥ 20), n_karsilanmayan (karsilanamayan_tibbi_ihtiyac = 1), egitim_max ve egitim_min (18+ ve f_kayit = 1), 2025 için n_engelli (wg_engellilik = 1).
- Gelir bileşimi (boş = 0 kuralıyla, tarif Bölüm 1.3): g_ucret = Σ(FG010 + FG020), g_mutesebbis = Σ(FG030 + FG040), g_emekli = Σ(FG080 + FG085 + FG090), g_sosyal_fert = Σ(FG070 + FG100 + FG110 + FG120), g_sosyal_hane = HG030N + HG030A + HG040 + HG050N + HG050A, g_ozel_transfer = HG060N + HG060A + HG065N; paylar HG110'a bölünerek (HG110 ≤ 0 ise boş; paylar 1,5'te kırpılır); ikili sosyal_yardim_var, ozel_transfer_var, kira_geliri_var (HG070 > 0).
- Türetilenler: FI = (HE090 == 2); yoksul = yoksul_60; kacirilan = FI ∧ yoksul = 0; log_goreli_gelir = log(goreli_esdeger_gelir, alt sınır 0,01); kiraci (HH020 ∈ {2,3}); kira_orani (12 × HH040 / HG110, kiracı değilse 0); he050_orani (12 × HE050 / HG110; pay anket yılı, payda gelir yılı fiyatlarıyla, raporda not edilir); konut_orani_k ve konut_asiri_k (2024 boş; HH050 kırılması, tarif Bölüm 2.5); m2_kisi; calisan_oran; bagimli_oran; cocuk_var; yasli_var; tek_yetiskin_cocuklu; calisan_yok; msy_etsiz_sayi (13 maddeden HE090 dışındaki 12'sinin toplamı) ve msy_etsiz_5 (≥ 5).

### 3.3. Yıllar arası örtüşme bayrakları

Rotasyonel tasarım yüzünden çok kişili hanelerin yaklaşık %60'ı ertesi yıl da veride, ama kimlikler yeniden verilmiş (inceleme raporu Bölüm 4). H2'nin test setini temizlemek için inceleme raporundaki imza yöntemini yeniden kur: çok kişili hanelerde üyelerin (FK080 doğum yılı, FK075 doğum ayı, FK090 cinsiyet) üçlülerinin sıralı birleşimi imzadır; iki yılda da yalnız bir kez geçen imzalar eşleştirilir; HB031 ve HH010 uyumu kontrol olarak raporlanır. Beklenen eşleşme sayıları: 2023–2024 12.924, 2024–2025 13.396, 2023–2025 7.432 (inceleme raporu Tablo 2); kendi sayılarını bunlarla karşılaştır. Hane veri setine `eslesen_onceki_yil` (2024 ve 2025 haneleri için bir önceki yılla eşleşme), `eslesen_2023` (2025 haneleri için) bayraklarını ekle. Tek kişili haneler imzayla eşleştirilemez; temizliğin kısmi olduğu, temizlenmiş test setinin tek kişili ve yeni rotasyon grubu hanelerine kaydığı raporda ve tablo notlarında yazılır; temizlenmiş ve tam test seti birlikte raporlanır.

### 3.4. Sızıntı listesi

Hiçbir modelde özellik olarak kullanılmaz: HE090, msy_et_tavuk_balik, msy_sayi, msy_5, msy_7, my_sayi, my_3, my_4, yoksulluk_sosyal_dislanma (hepsi HE090'ı içerir). yoksul_60 nüfus tanımıdır, özellik değildir. esdeger_gelir ve konut_maliyet_* nominal/kırılmalı olduğundan yerine log_goreli_gelir ve 2024'ü boş bırakan sürümler kullanılır. Liste `Results/kesif/kesif_dislanan.csv`'de durur ve Table S'lerden birine girer.

---

## 4. Aşama 0b: Keşif

Amaç: hangi özelliklerin hangi katmana gireceğini, hangilerinin birbirinin kopyası olduğunu ve mali baskı maddelerinin ne kadar "aynı soruyu başka biçimde sormak" olduğunu görmek. Yayın tablosu değil, denetim çıktısıdır. Ek A'daki `kesif.R` başlangıç kodunu kullan (yolları ve değişken listesini gerekirse düzelt).

Özellik katmanları:

- T1 gelir: log_goreli_gelir, yoksulluk_acigi_60, gelir_dilim10, hane_gelir_dilim5, yoksul_50, gelir payları, sosyal_yardim_var, ozel_transfer_var, kira_geliri_var.
- T2 yapısal / idari: hane bileşimi sayıları, reis özellikleri, eğitim, istihdam sayıları ve is_yogunlugu, sağlık sayıları, bölge (HB030, HB031), konut tipi, mülkiyet, oda ve m², ısıtma sistemi, banyo/tuvalet/mutfak, konut sorunları HS010–HS070, dayanıklı mal sahipliği HH180–HH240, kalabalik_konut, ciddi_konut_yoksunlugu, kira_orani, konut_orani_k, HH145.
- T3 mali baskı (öz bildirim): HE040, HE010, HE020, HE030, msy_borc_odeme, HE060, HE070, he050_orani.
- T4 aynı yoksunluk bataryası: HE080, HE100, HE110, HE120 ve bunların msy_* karşılıkları. Yalnız üst sınır duyarlılığında.

Çıktılar (`Results/kesif/`): her özellik × yıl × nüfus (bütün haneler; yoksul olmayan haneler) için ağırlıklı tek değişkenli lojistik McFadden R², ağırlıklı AUC, kategori bazlı yaygınlık; özellikler arası karma ilişki matrisi (Spearman, Cramér V, eta) ve kümeleri (2025); yıllar arası sıralama kararlılığı; eksiklik tablosu; dışlama hatası ön izlemesi (`kesif_oran_onizleme.csv`).

Keşif sonunda `Rapor.md`'ye yaz: katman başına ilk 10 özellik; kopya çiftler ve hangisinin tutulacağı; T3'ün T1 + T2'ye göre ek bilgisi; H1'in kaba hâli (FI içinde yoksul olmayan pay, üç yıl). Hipotez güncelleme önerin varsa "Bize sorular"a.

---

## 5. Aşama 1: Dışlama hatası (H1)

Birim: hane (HB040) ve kişi (FK050, hane kümeli); yıllar ayrı.

Tahmin edilen büyüklükler, her yıl için, %95 güven aralığıyla:

- FI yaygınlığı; yoksul_60 yaygınlığı; FI ∧ yoksul; FI ∧ yoksul değil.
- Dışlama hatası = P(yoksul değil | FI). Kapsama = P(FI | yoksul). Eşik seçenekleri: yoksul_50, yoksul_60 (ana), yoksul_70, msy_etsiz_5, dusuk_is_yogunlugu.
- Kaçırılan hanelerde yaşayan çocuk (< 18) sayısı ve payı (FK050 ile kişi düzeyi).
- Kırılımlar: göreli gelir bandı (0,6–0,8; 0,8–1,0; 1,0–1,5; > 1,5 medyan), gelir_dilim5, HB050, çocuk varlığı, mülkiyet, HB030, çalışan yetişkin varlığı ve is_yogunlugu, reis faaliyet durumu (çalışan / emekli / diğer), 65+ varlığı.
- Yıl farkları 2025 − 2023 (ve 2024 − 2023) güven aralığıyla; TR63 hariç 25 bölgeyle duyarlılık.
- Eşitsizlik: FI'nin gelire göre Erreygers yoğunlaşma endeksi, yıl bazında, kişi düzeyi (kısa; Figure 2'ye bir panel olarak girebilir).
- Kaçırılanların profili (2025): kaçırılan haneler ile yoksul gıda güvencesiz haneler ve gıda güvenceli hanelerin özellik dağılımı (Table 1'in malzemesi).

Varyans: tasarım temelli doğrusallaştırma (survey) ana; İBBS 2 sözde tabaka duyarlılık. Yıl farkları için bağımsızlık varsayımı ve tutuculuk notu.

---

## 6. Aşama 2: Kaçırılanları tanıma (H2, makine öğrenmesi)

### 6.1. Nüfuslar ve modeller

- Model A (hedefleme karşılaştırması): bütün haneler. Sonuç FI. Özellik setleri: A1 = T1 + T2; A2 = yalnız T2 (gelirsiz); A3 = T1 + T2 + T3 (duyarlılık); A4 = + T4 (üst sınır, yalnız raporda).
- Model B (kaçırılanlar): yoksul_60 = 0 olan haneler. Sonuç FI. Özellik setleri B1 = T2 + log_goreli_gelir; B2 = yalnız T2; B3 = + T3.
- Karşılaştırma kolları (hedefleme): (i) yoksul_60 bayrağı; (ii) yalnız göreli gelire göre sıralama (aynı kapsama oranında daha yüksek bir eşik); (iii) yoksul_50, yoksul_70, msy_etsiz_5; (iv) lojistik regresyon (glmnet, benchmark); (v) LightGBM (ana); (vi) sade kural seti (6.4).

### 6.2. Eğitim, sınama, ayarlama

- Ana şema: 2023 + 2024'te eğit, 2025'te sına. Ana test seti: 2025'te önceki yıllarla eşleşmeyen haneler (3.3). İkincil: tam 2025. Üçüncül: 2023'te eğit, 2025'te sına (örtüşme %30'a iner).
- Yapı değişikliği matrisi: her yıl için ayrı model, 3 × 3 çapraz uygulama (eğitim yılı × test yılı) AUC ve kalibrasyon; köşegen dışı bozulma ve 2023 modelinin 2024 ve 2025'teki kalibrasyon kayması (kalibrasyon kesme noktası ve eğimi) yapı kaymasının ölçüsüdür.
- Hiperparametre ayarı eğitim yılları içinde yıl bloklu çapraz geçerlemeyle (2023'te eğit 2024'te doğrula ve tersi); hane içi sızıntı olmaması için hane düzeyinde zaten tek satır var. Arama: rastgele arama, en az 60 yapılandırma (num_leaves, min_data_in_leaf, learning_rate, feature_fraction, bagging_fraction, lambda_l2, max_depth), erken durdurma; ölçüt ağırlıklı log-loss. Aynı yapılandırma 5 tohumla yeniden eğitilir, tahminler ortalanır.
- Ağırlık: HB040 eğitimde `sample_weight`, değerlendirmede ağırlıklı metrikler; ağırlıksız metrikler ekte.
- Kategorik değişkenler: LightGBM yerel kategorik; lojistikte one-hot; seyrek kategoriler birleştirilir. Eksikler LightGBM'de yerel, lojistikte gösterge + medyan.
- Eşik ve kapsama: puanlar her yıl kendi içinde sıralanır; kapsama oranları yoksul_60 yaygınlığına eşit, %20, %30, %40 ve FI yaygınlığına eşit. Metrikler: duyarlılık (yakalanan FI hane payı), pozitif kestirim değeri, dışlama ve dahil etme hatası, yakalanan çocuk payı; ayrıca AUC, PR-AUC, Brier, kalibrasyon grafiği ve karar eğrisi (net fayda).
- Belirsizlik: 2025 test setinde hane bootstrap'ı (B = 1.000, aynı çekimler bütün kollara uygulanır, farklar eşleşik); eğitim değişkenliği için 5 tohum. Yakınsama: 500 ile 1.000 tekrarda sınırlar 0,1 puandan fazla oynarsa artır.

### 6.3. Yorumlanabilirlik ve kayma

- SHAP (TreeSHAP): küresel önem (ortalama |SHAP|), ilk 12 özellik için bağımlılık grafikleri, etkileşim taraması (ilk 5 çift). Yıl modellerinde SHAP önem sıralarının karşılaştırılması (Spearman) ve gelir ile konut/borç özelliklerinin payındaki değişim kayma bulgusudur.
- Puan dağılımı kayması: popülasyon kararlılık endeksi (PSI) 2023 modeli için 2024 ve 2025'te.
- Model B'de SHAP çıktısı "kaçırılanları ne tanıyor" sorusunun cevabıdır; Discussion için özellik gruplarına göre (hane bileşimi, konut, istihdam, sağlık, bölge) toplulaştırılmış katkı payları da hesapla.

### 6.4. Sade kural seti

- Eğitim yıllarında, T2 (ve ayrıca T1 + T2) özellikleriyle derinliği en çok 3 olan karar ağacı (CART, maliyet karmaşıklığı budaması, ağırlıklı) ve en çok 6 değişkenli ceza indirgemeli lojistik ("az değişkenli model"). Kurallar düz İngilizce cümlelerle yazılır (ör. "tenant household with ≥3 children and no employed adult").
- Değerlendirme 2025 temizlenmiş test setinde, 6.2'deki kapsama noktalarında, LightGBM üst sınırı ve yoksulluk eşiğiyle yan yana. H2'nin asıl sınaması burasıdır: kural seti ile yoksul_60 arasındaki duyarlılık farkı, eşleşik bootstrap güven aralığıyla.
- Kural seti ayrıca gelir yoksulu olmayan hanelerde (Model B) kurulur; bu, "yoksulluk eşiğine ek olarak hangi haneler alınmalı" sorusuna doğrudan cevaptır.

### 6.5. İsteğe bağlı karşılaştırma kolları (ikincil, zaman kalırsa)

- Çok katmanlı algılayıcı (PyTorch, MPS) ve kuruluyorsa TabPFN; aynı eğitim/test şemasıyla yalnız AUC/PR-AUC/kalibrasyon karşılaştırması. Ana sonuçları etkilemez; Table S'de yer alır. Kurulamazsa "Eksikler"e yaz.
- Nedensel orman (grf, Python'da econml) ile 2025 yetişkinlerinde FI'nin seyrek et tüketimiyle ilişkisinin heterojenliği (CATE dağılımı, en iyi doğrusal izdüşüm, RATE). Keşifsel; yapılırsa ayrı ek tablo ve figür.

### 6.6. Raporlama

TRIPOD+AI maddelerini `Results/tripod_notlari.md`'ye işle (veri, sonuç, özellikler, eksik veri, model, ayarlama, değerlendirme, kalibrasyon, belirsizlik, kayma). Hiperparametreler, çapraz geçerleme sonuçları ve 3 × 3 matris Table S'lerde.

---

## 7. Aşama 3: Kaçırılanlar gerçekten yoksun mu (H3, 2025)

Birim: 18+ yetişkin, fert görüşmesi olan (FK070 ≥ 18, f_kayit = 1; 57.899 kişi), FB030, hane kümeli. Hane sonucu için hane düzeyi (HB040).

Gruplar: G1 gıda güvenceli (HE090 = 1); G2 gıda güvencesiz ve yoksul değil; G3 gıda güvencesiz ve yoksul.

Sonuçlar: haftada birden az et-tavuk-balık (vejetaryen/vegan yetişkinler, et_tavuk_balik_siklik = 0, 195 kişi, ana analizde dışarıda; duyarlılıkta "haftada birden az" sayılır), günde birden az meyve, günde birden az sebze/salata; hane düzeyinde tıbbi veya ilaç harcamasının çok yük olması (MODUL1_H_1 = 1 veya MODUL1_H_3 = 1); ek olarak ödeme güçlüğüyle karşılanmamış tıbbi ihtiyaç (ihtiyacı olanlar içinde; az olay, yalnız ekte).

Karşılaştırmalar (standardize yaygınlık, fark ve oran, g-computation):

- C1: yoksul olmayan yetişkinler içinde G2 − G1; kovaryatlar yaş (4 df doğal spline), cinsiyet, eğitim, bölge, hane büyüklüğü, çocuk sayısı ve log göreli gelir (spline). "Gelirin ötesindeki diyet açığı".
- C2: G2 − G3; aynı kovaryatlar, gelir hariç (gruplar gelirle tanımlı).
- C3: gıda güvencesiz yetişkinlerde göreli gelir bandına göre standardize yaygınlıklar (0,6'nın altı; 0,6–0,8; 0,8–1,0; 1,0–1,5; > 1,5).

Protokol (birinci çalışmanın sırası): eksik veri → yaş biçimi → aday kovaryatlar (değişim ölçütü: farkta ≥ 0,5 puan veya oranda ≥ %10; p değerine dayalı adım adım seçim yok; adaylar: medeni durum, çalışma durumu, kronik hastalık, GALI, hane tipi, mülkiyet) → örtüşme/pozitiflik kaba kontrolü → model biçimi (ana etkili ana model; grup × bölge, grup × cinsiyet, grup × gelir taramasında p < 0,01 heterojenlik varsa esnek model ana model) → uyum iyiliği (Archer-Lemeshow) → ayrışma ve seyreklik (olay/parametre ≥ 10) → kümeleme tasarım etkisi → bootstrap yakınsaması. Bootstrap: Rao-Wu-Yue-Beaumont hane bootstrap'ı, tek ortak çarpan matrisi (eşleşik aralıklar), ana tahminlerde 4.000, diğerlerinde 2.000 tekrar; yüzdelik aralıklar; doğrusallaştırma SE'siyle karşılaştırma `*_gcomp_sonuclari.csv` içinde.

---

## 8. Aşama 4: Simülasyon

Simülasyon üç soruya hizmet eder; hepsi plasmode (gerçek 2024–2025 hane kovaryatları, ağırlıkları ve örtüşme bayrakları sabit; sonuç bilinen bir modelden üretilir).

- S1. Örtüşme sızıntısı: H2'nin eğitim–test şeması aynı hanelerin iki yılda da bulunmasından ne kadar iyimserleşiyor? Sonuç üretimi: 2024 ve 2025 kovaryatlarıyla uydurulmuş lojistik (ya da küçültülmüş LightGBM) modelden temel olasılık; eşleşen hanelerde iki yıl arasında paylaşılan hane rastgele etkisi (gizil ICC 0,3 ve 0,6); örtüşme payı gerçek ve yapay olarak %30 / %60. Simüle 2024'te eğit, simüle 2025'te temizlenmiş ve temizlenmemiş test setlerinde AUC, duyarlılık ve kalibrasyonu karşılaştır; gerçek dışı iyimserlik puan olarak raporlanır.
- S2. Sonuç yanlış sınıflaması: HE090 tek maddedir. Duyarlılık 0,80–0,95 ve özgüllük 0,90–0,99 aralığında, ayrımcı olmayan ve gelire göre ayrımcı (düşük gelirde fazla bildirim) senaryolarla dışlama hatası, kapsama ve kural setinin yakalama oranı yeniden hesaplanır; sonuçlar bant olarak Figure 5 ya da ek figürde.
- S3. Güven aralığı kapsaması: dışlama hatası, duyarlılık ve pozitif kestirim değeri için hane bootstrap aralıklarının kapsaması (gerçek değer bilinen 500 veri seti × 200 bootstrap).

Teknik: `future`/`furrr` ile 16 işçi; her senaryonun tohumu, tekrar sayısı ve süresi `R_Data ve Python Data/simulasyon/senaryo_tablosu.csv` ve `simulasyon_ozet.csv`'de; pilot (50 tekrar) ile süre tahmini yapılır ve `Rapor.md`'ye yazılır; toplam simülasyon bütçesi yaklaşık 3 saat, aşılacaksa tekrar sayısı düşürülür ve gerekçesi yazılır. LightGBM içeren simülasyonlarda ağaç sayısı ve öğrenme hızı sabitlenir. GPU yalnız 6.5'teki derin ağ kolu simülasyona girerse kullanılır.

---

## 9. Tablolar ve figürler

Ana metin planı (toplam 6; biz yazarken yer değiştirebilir):

- Table 1. 2025 hanelerinin (ve kısa bir yetişkin bloğunun) özellikleri üç grupta: gıda güvenceli; gıda güvencesiz, yoksul değil; gıda güvencesiz, yoksul. n ağırlıksız, % ağırlıklı, Rao-Scott p.
- Table 2. Dışlama hatası ve kapsama, 2023–2025, hane ve kişi düzeyi; eşik seçenekleri; çocuklar; yıl farkları.
- Table 3. Hedefleme karşılaştırması, 2025 temizlenmiş test seti: yöntem × kapsama → duyarlılık, pozitif kestirim değeri, yakalanan çocuk payı, güven aralıklarıyla; yoksulluk eşiği, gelir sıralaması, kural seti, lojistik, LightGBM.
- Figure 1. Çalışma tasarımı: (a) veri akışı (yıllara göre hane ve kişi sayıları, analitik örneklemler, örtüşme temizliğiyle test seti), sayılarla orantılı; (b) kavramsal harita: gelir yoksulluğu ve gıda güvencesizliği kümeleri, dışlama ve dahil etme hatası alanları, numaralı analiz yolu H1 → H2 → H3 ve simülasyon. Birinci çalışmanın Figure 1'i biçim örneğidir.
- Figure 2. H1: (a) FI, yoksulluk ve kaçırılan payları 2023–2025 (kişi ve hane); (b) 2025'te göreli gelir bandı ve hane tipine göre dışlama hatası; (c) kaçırılan hanelerdeki çocuklar; (d) yoğunlaşma endeksi yıllara göre.
- Figure 3. H2: (a) kapsama oranına karşı yakalanan FI hane payı eğrileri (LightGBM, kural seti, gelir sıralaması; yoksulluk eşikleri nokta olarak); (b) 2023 modelinin 2024 ve 2025'te kalibrasyonu; (c) yıl modellerinde SHAP önem sırası; (d) kural ağacı şeması.
- Figure 4. H3: (a) üç grupta üç gıda için standardize yaygınlıklar; (b) gıda güvencesiz yetişkinlerde göreli gelir bandına göre yaygınlıklar; (c) sağlık harcaması yükü.
- Figure 5. Simülasyon: (a) örtüşme iyimserliği; (b) yanlış sınıflama bantları; (c) kapsama. (Ana metinde yer kalmazsa ek.)

Supplementary: özellik kataloğu ve katmanlar; sızıntı listesi; keşif sıralaması; örtüşme eşleştirme sayıları; hiperparametreler ve çapraz geçerleme; 3 × 3 yıl matrisi ve PSI; SHAP bağımlılık; karar eğrileri; kurallar (cümle olarak); H3 kovaryat seçimi ve düzeltme merdiveni; duyarlılıklar (eşik tanımları, TR63, temizlenmemiş test, ağırlıksız); simülasyon tablosu; değişken tanımları (Table S8 benzeri); STROBE akışı. Supplementary'deki her öğe ana metinde atıflanacağı için numaraları ilk atıf sırasına göre en sonda verilir.

`sayilar.json`: makalede geçecek her sayı (tahmin, GA, SE, n, olay, model) makine okunur biçimde.

---

## 10. Tuzaklar (okuyup kontrol listesine al)

- Hane sonucu her ferde yazılıdır: H2 hane düzeyinde kurulur; kişi düzeyi analizlerde hane kümesi.
- Yıllar arası örtüşme: rastgele K-katlı çapraz geçerleme yıllar arasında sızdırır; yıl bloklu ayarlama ve temizlenmiş test seti kullan.
- 2024 HH050 kırılması: konut maliyeti göstergeleri 2024'te boş bırakılır.
- 2023'te TR63 yok; yıl karşılaştırmalarında belirt, 25 bölgeli duyarlılık ver.
- Gelir bir önceki yılın, HE050 ve HH040 anket yılının fiyatlarıyladır; oranlar enflasyondan etkilenir, not düş.
- Kategorik kodlar alışılmadık (HB050: 1, 21, 22, 23, 3, 4; HH145: 1, 2, 4, 5; MODUL kodları 6, 11–15 vb.); etiketleri `kodlar` sayfasından al.
- Boş hücre gelirde 0, diğerlerinde filtre dışı ya da yanıtsızdır; gelir dışında 0 ile doldurma.
- 98 "diğer", 99 "bilmiyor" kodları ayrı kategori ya da eksik olarak ele alınır; kararı yaz.
- Ağırlıksız sayıları yalnız n olarak ver; bütün yaygınlıklar ağırlıklı.
- İzafi kira (HG010) negatif olabilir; HG110 ≤ 0 olan birkaç hanede oranlar boş.
- Vejetaryen kodu et sonucunda ana analizden çıkar (195 yetişkin), duyarlılıkta "haftada birden az" sayılır.

---

## 11. Teslim listesi

- `Codes/` içinde çalışır ve sıralı scriptler, `README_kodlar.md` (çalıştırma sırası, süreler, ortam, tohumlar).
- `R_Data ve Python Data/` içinde parquet'ler, önbellekler, simülasyon ham dosyaları, `figur_verileri/`.
- `Results/` içinde Table 1–3 (docx, csv), `tablolar_tumu.xlsx`, `Supplementary/` tabloları, `sayilar.json`, `model_ozetleri.txt`, `model_protokolu.csv`, `dogrulama_kontrolleri.csv`, `degisken_tanimlari.csv`, `strobe_akis.md`, `tripod_notlari.md`, `paket_atiflari.txt`, `sessionInfo.txt`, `python_ortam.txt`, `kesif/`, `log/`.
- `Figures/` içinde Figure 1–5 (PNG 600 dpi, PDF, TIFF) ve `Supplementary/`; `figur_altyazilari.md`.
- `Rapor.md` tamamlanmış: her aşamanın ne için yapıldığı, kararlar, hipotez değerlendirmesi, Methods notları, bize sorular, eksikler, süreler.
- Temiz çalıştırma: türetilmiş dosyalar bir arşiv klasörüne taşınıp ham xlsx'ten baştan çalıştırılır; `sayilar.json` önceki koşuyla karşılaştırılır; sonuç `Rapor.md`'ye yazılır.

---

## Ek A. Keşif başlangıç kodu (`Codes/kesif.R`)

Bu kod başlangıç noktasıdır; değişken listesini ve yolları gerektiğinde düzelt, Bölüm 3.2'deki ek türetilmiş değişkenleri (ör. msy_etsiz_5, n_engelli, eşleşme bayrakları) ekle. Önce xlsx'i proje kökünden okur; parquet varsa onu kullanır.

```r
options(warn = 1, width = 160)
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(readxl)
  library(splines)
})
set.seed(20251026)
ddir <- "R_Data ve Python Data"
rdir <- "Results/kesif"
dir.create(ddir, showWarnings = FALSE, recursive = TRUE)
dir.create(rdir, showWarnings = FALSE, recursive = TRUE)
pq <- file.path(ddir, "gyka_2023_2025.parquet")
if (!file.exists(pq)) {
  xl <- "GYKA_2023_2025_birlesik.xlsx"
  s <- read_excel(xl, sheet = "sozluk")
  d0 <- as.data.table(read_excel(xl, sheet = "veri", col_types = s$okuma_turu))
  write_parquet(d0, pq)
  saveRDS(d0, file.path(ddir, "gyka_2023_2025.rds"))
  fwrite(s, file.path(ddir, "sozluk.csv"))
  fwrite(as.data.table(read_excel(xl, sheet = "kodlar")), file.path(ddir, "kodlar.csv"))
  fwrite(as.data.table(read_excel(xl, sheet = "dogrulama")), file.path(ddir, "dogrulama_sayfasi.csv"))
  rm(d0)
  gc()
}
d <- as.data.table(read_parquet(pq))
sozluk <- fread(file.path(ddir, "sozluk.csv"))
cat("Veri:", nrow(d), "satir,", ncol(d), "sutun\n")

sifir <- function(x) fifelse(is.na(x), 0, as.numeric(x))
enbuyuk <- function(x) if (all(is.na(x))) NA_integer_ else max(x, na.rm = TRUE)
enkucuk <- function(x) if (all(is.na(x))) NA_integer_ else min(x, na.rm = TRUE)
d[, egitim5 := fcase(FE030 %in% 0:1, 1L, FE030 %in% 2:3, 2L, FE030 == 4, 3L, FE030 %in% 5:6, 4L, FE030 %in% 7:10, 5L, default = NA_integer_)]
hagg <- d[, .(
  n_yetiskin = sum(FK070 >= 18),
  n_cocuk = sum(FK070 < 18),
  n_0_5 = sum(FK070 <= 5),
  n_65plus = sum(FK070 >= 65),
  n_75plus = sum(FK070 >= 75),
  n_kronik = sum(FK070 >= 18 & FS020 %in% 1),
  n_gali = sum(FK070 >= 18 & FS030 %in% 1:2),
  n_kotu_saglik = sum(FK070 >= 18 & FS010 %in% 4:5),
  n_calisan = sum(FK070 >= 18 & FI010 %in% 1:4),
  n_issiz = sum(FK070 >= 18 & FI010 %in% 5),
  n_emekli = sum(FK070 >= 18 & FI010 %in% 7),
  n_ev_isi = sum(FK070 >= 18 & FI010 %in% 9),
  n_kayitsiz = sum(FK070 >= 18 & FI010 %in% 1:4 & FI190 %in% 2),
  n_yevmiyeli = sum(FK070 >= 18 & FI120 %in% 2),
  n_gecici = sum(FK070 >= 18 & FI210 %in% 20:29),
  n_karsilanmayan = sum(FK070 >= 18 & karsilanamayan_tibbi_ihtiyac %in% 1),
  egitim_max = enbuyuk(egitim5[FK070 >= 18 & f_kayit == 1]),
  egitim_min = enkucuk(egitim5[FK070 >= 18 & f_kayit == 1]),
  g_ucret = sum(sifir(FG010) + sifir(FG020)),
  g_mutesebbis = sum(sifir(FG030) + sifir(FG040)),
  g_emekli = sum(sifir(FG080) + sifir(FG085) + sifir(FG090)),
  g_sosyal_fert = sum(sifir(FG070) + sifir(FG100) + sifir(FG110) + sifir(FG120))
), by = .(yil, hane_kimlik)]
hv <- c("yil", "hane_kimlik", "HB040", "FK050", "HB030", "HB031", "HB050", "HH010", "HH020", "HH040", "HH050", "HH060", "HH070", "HH080", "HH100", "HH110", "HH120", "HH145",
        "HH180", "HH190", "HH200", "HH220", "HH230", "HH240", "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070",
        "HE010", "HE020", "HE030", "HE040", "HE050", "HE060", "HE070", "HE080", "HE090", "HE100", "HE110", "HE120",
        "HG010", "HG030N", "HG030A", "HG040", "HG050N", "HG050A", "HG060N", "HG060A", "HG065N", "HG070", "HG110",
        "hane_buyuklugu", "esdeger_gelir", "goreli_esdeger_gelir", "gelir_dilim5", "gelir_dilim10", "hane_gelir_dilim5", "yoksul_50", "yoksul_60", "yoksul_70", "yoksulluk_acigi_60",
        "is_yogunlugu", "dusuk_is_yogunlugu", "konut_maliyet_orani", "konut_maliyet_asiri_yuk", "kalabalik_konut", "ciddi_konut_yoksunlugu",
        "msy_beklenmedik_harcama", "msy_tatil", "msy_borc_odeme", "msy_isinma", "msy_otomobil", "msy_mobilya",
        "FK070", "FK090", "FB100", "FI010", "FK210", "FS010", "FS020", "FS030", "egitim5")
h <- d[hane_reisi == 1, ..hv]
setnames(h, c("FK070", "FK090", "FB100", "FI010", "FK210", "FS010", "FS020", "FS030", "egitim5"),
         c("reis_yas", "reis_cinsiyet", "reis_medeni", "reis_fi010", "reis_fk210", "reis_saglik", "reis_kronik", "reis_gali", "reis_egitim"))
h <- merge(h, hagg, by = c("yil", "hane_kimlik"))
h[, `:=`(
  FI = as.integer(HE090 == 2),
  yoksul = as.integer(yoksul_60 == 1),
  gelir_pozitif = HG110 > 0,
  log_goreli_gelir = log(pmax(goreli_esdeger_gelir, 0.01)),
  g_sosyal_hane = sifir(HG030N) + sifir(HG030A) + sifir(HG040) + sifir(HG050N) + sifir(HG050A),
  g_ozel_transfer = sifir(HG060N) + sifir(HG060A) + sifir(HG065N),
  reis_calisma7 = fcase(reis_fi010 %in% 1:4, 1L, reis_fi010 == 5, 2L, reis_fi010 == 6, 3L, reis_fi010 == 7, 4L, reis_fi010 == 8, 5L, reis_fi010 == 9, 6L, reis_fi010 == 10, 7L, default = NA_integer_),
  kiraci = as.integer(HH020 %in% 2:3),
  cocuk_var = as.integer(n_cocuk > 0),
  yasli_var = as.integer(n_65plus > 0),
  tek_yetiskin_cocuklu = as.integer(n_yetiskin == 1 & n_cocuk > 0),
  calisan_yok = as.integer(n_calisan == 0),
  calisan_oran = fifelse(n_yetiskin > 0, n_calisan / n_yetiskin, NA_real_),
  bagimli_oran = (n_cocuk + n_65plus) / hane_buyuklugu
)]
h[, `:=`(
  pay_ucret = fifelse(gelir_pozitif, pmin(g_ucret / HG110, 1.5), NA_real_),
  pay_mutesebbis = fifelse(gelir_pozitif, pmin(g_mutesebbis / HG110, 1.5), NA_real_),
  pay_emekli = fifelse(gelir_pozitif, pmin(g_emekli / HG110, 1.5), NA_real_),
  pay_sosyal = fifelse(gelir_pozitif, pmin((g_sosyal_hane + g_sosyal_fert) / HG110, 1.5), NA_real_),
  sosyal_yardim_var = as.integer((g_sosyal_hane + g_sosyal_fert) > 0),
  ozel_transfer_var = as.integer(g_ozel_transfer > 0),
  kira_geliri_var = as.integer(sifir(HG070) > 0),
  kira_orani = fifelse(gelir_pozitif & kiraci == 1, pmin(12 * sifir(HH040) / HG110, 3), fifelse(gelir_pozitif, 0, NA_real_)),
  he050_orani = fifelse(gelir_pozitif, pmin(12 * HE050 / HG110, 10), NA_real_),
  konut_orani_k = fifelse(yil == 2024, NA_real_, pmin(pmax(konut_maliyet_orani, 0), 3)),
  konut_asiri_k = fifelse(yil == 2024, NA_integer_, as.integer(konut_maliyet_asiri_yuk)),
  m2_kisi = HH070 / hane_buyuklugu
)]
write_parquet(h, file.path(ddir, "hane_2023_2025_kesif.parquet"))
cat("Hane satirlari:", nrow(h), " yil:", paste(h[, .N, keyby = yil]$N, collapse = " / "), "\n")

on <- rbindlist(lapply(c("hane", "kisi"), function(dz) {
  w <- if (dz == "hane") "HB040" else "FK050"
  h[, .(duzey = dz, FI = 100 * sum(FI * get(w)) / sum(get(w)), yoksul = 100 * sum(yoksul * get(w)) / sum(get(w)),
        FI_ve_yoksul = 100 * sum(FI * yoksul * get(w)) / sum(get(w)), FI_yoksul_degil = 100 * sum(FI * (1 - yoksul) * get(w)) / sum(get(w)),
        FI_icinde_yoksul_olmayan_pay = 100 * sum(FI * (1 - yoksul) * get(w)) / sum(FI * get(w)),
        yoksul_icinde_FI_pay = 100 * sum(FI * yoksul * get(w)) / sum(yoksul * get(w)),
        cocuk_FI_yoksul_degil = sum(n_cocuk * FI * (1 - yoksul) * get(w)) / 1e6, cocuk_FI = sum(n_cocuk * FI * get(w)) / 1e6,
        n_hane = .N, n_FI = sum(FI), n_FI_yoksul_degil = sum(FI * (1 - yoksul))), keyby = yil]
}))
fwrite(on, file.path(rdir, "kesif_oran_onizleme.csv"))
print(on)

katalog <- rbindlist(list(
  data.table(katman = "T1 gelir", tur = "sayisal", degisken = c("log_goreli_gelir", "yoksulluk_acigi_60", "pay_ucret", "pay_mutesebbis", "pay_emekli", "pay_sosyal")),
  data.table(katman = "T1 gelir", tur = "kategorik", degisken = c("gelir_dilim10", "hane_gelir_dilim5", "yoksul_50", "sosyal_yardim_var", "ozel_transfer_var", "kira_geliri_var")),
  data.table(katman = "T2 yapisal", tur = "sayisal", degisken = c("reis_yas", "hane_buyuklugu", "n_cocuk", "n_0_5", "n_65plus", "n_75plus", "n_yetiskin", "n_kronik", "n_gali", "n_kotu_saglik", "n_karsilanmayan",
                                                                   "n_calisan", "n_issiz", "n_emekli", "n_ev_isi", "n_kayitsiz", "n_yevmiyeli", "n_gecici", "calisan_oran", "bagimli_oran", "is_yogunlugu",
                                                                   "HH060", "HH070", "m2_kisi", "kira_orani", "konut_orani_k")),
  data.table(katman = "T2 yapisal", tur = "kategorik", degisken = c("HB030", "HB031", "HB050", "reis_cinsiyet", "reis_medeni", "reis_calisma7", "reis_fk210", "reis_egitim", "egitim_max", "egitim_min",
                                                                     "reis_saglik", "reis_kronik", "reis_gali", "cocuk_var", "yasli_var", "tek_yetiskin_cocuklu", "calisan_yok", "dusuk_is_yogunlugu",
                                                                     "HH010", "HH020", "kiraci", "HH080", "HH100", "HH110", "HH120", "HH145", "HH180", "HH190", "HH200", "HH220", "HH230", "HH240",
                                                                     "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070", "kalabalik_konut", "ciddi_konut_yoksunlugu", "konut_asiri_k")),
  data.table(katman = "T3 mali baski", tur = "sayisal", degisken = c("he050_orani")),
  data.table(katman = "T3 mali baski", tur = "kategorik", degisken = c("HE040", "HE010", "HE020", "HE030", "msy_borc_odeme", "HE060", "HE070")),
  data.table(katman = "T4 ayni batarya", tur = "kategorik", degisken = c("HE080", "HE100", "HE110", "HE120", "msy_beklenmedik_harcama", "msy_tatil", "msy_isinma", "msy_otomobil", "msy_mobilya"))
))
katalog <- katalog[degisken %in% names(h)]
dislanan <- data.table(degisken = c("HE090", "msy_et_tavuk_balik", "msy_sayi", "msy_5", "msy_7", "my_sayi", "my_3", "my_4", "yoksulluk_sosyal_dislanma", "yoksul_60", "gelir_dilim5", "esdeger_gelir", "goreli_esdeger_gelir", "konut_maliyet_orani", "konut_maliyet_asiri_yuk"),
                       neden = c("sonuc", rep("sonucu iceriyor", 8), "nufus tanimi", "log_goreli_gelir ile ayni bilgi", "nominal TL, yillar arasi karsilastirilamaz", "log_goreli_gelir ile ayni bilgi", "2024 kirilmasi: konut_orani_k kullanildi", "2024 kirilmasi: konut_asiri_k kullanildi"))
fwrite(katalog, file.path(rdir, "kesif_katalog.csv"))
fwrite(dislanan, file.path(rdir, "kesif_dislanan.csv"))

auc_w <- function(score, y, w) {
  dt <- data.table(s = score, y = y, w = w)[, .(w1 = sum(w[y == 1]), w0 = sum(w[y == 0])), keyby = s]
  dt[, c0 := cumsum(w0) - w0]
  sum(dt$w1 * (dt$c0 + 0.5 * dt$w0)) / (sum(dt$w1) * sum(dt$w0))
}
tek <- function(dt, v, tur, nufus, yy) {
  x <- dt[[v]]
  ok <- !is.na(x)
  eksik <- 100 * mean(!ok)
  if (sum(ok) < 200 || length(unique(x[ok])) < 2) return(NULL)
  dd <- data.table(FI = dt$FI[ok], w = dt$HB040[ok], x = x[ok])
  kat <- NULL
  if (tur == "kategorik") {
    tab <- dd[, .(n = .N, olay = sum(FI), yayginlik = 100 * sum(w * FI) / sum(w), pay = 100 * sum(w)), keyby = .(kod = as.character(x))]
    tab[, pay := pay / sum(pay)]
    kat <- tab[, .(nufus = nufus, yil = yy, degisken = v, kod, n, olay, pay, yayginlik)]
    seyrek <- tab[n < 20, kod]
    dd <- dd[!as.character(x) %in% seyrek]
    dd[, x := factor(x)]
    if (nlevels(dd$x) < 2) return(list(kat = kat))
    f <- FI ~ x
  } else {
    dd[, x := as.numeric(x)]
    f <- if (length(unique(dd$x)) > 6) FI ~ ns(x, df = 3) else FI ~ factor(x)
  }
  m <- suppressWarnings(glm(f, data = dd, family = quasibinomial(), weights = w))
  m0 <- suppressWarnings(glm(FI ~ 1, data = dd, family = quasibinomial(), weights = w))
  p <- fitted(m)
  oz <- data.table(nufus = nufus, yil = yy, degisken = v, tur = tur, n = nrow(dd), olay = sum(dd$FI), eksik_yuzde = eksik,
                   pseudo_r2 = 1 - deviance(m) / deviance(m0), auc = auc_w(p, dd$FI, dd$w),
                   kategori = if (tur == "kategorik") nlevels(dd$x) else length(unique(dd$x)),
                   yayginlik_min = if (!is.null(kat)) min(kat[n >= 20, yayginlik]) else NA_real_,
                   yayginlik_max = if (!is.null(kat)) max(kat[n >= 20, yayginlik]) else NA_real_)
  list(oz = oz, kat = kat)
}
sonuc <- list()
kategori <- list()
t0 <- Sys.time()
for (nufus in c("tum", "yoksul_degil")) {
  for (yy in 2023:2025) {
    dt <- if (nufus == "tum") h[yil == yy] else h[yil == yy & yoksul == 0]
    for (i in seq_len(nrow(katalog))) {
      r <- tek(dt, katalog$degisken[i], katalog$tur[i], nufus, yy)
      if (!is.null(r$oz)) sonuc[[length(sonuc) + 1]] <- r$oz
      if (!is.null(r$kat)) kategori[[length(kategori) + 1]] <- r$kat
    }
    cat(nufus, yy, "bitti\n")
  }
}
cat("Tek degiskenli tarama suresi (dk):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
sonuc <- merge(rbindlist(sonuc), katalog, by = c("degisken", "tur"))
kategori <- rbindlist(kategori)
setorder(sonuc, nufus, yil, -pseudo_r2)
sonuc[, sira := seq_len(.N), by = .(nufus, yil)]
fwrite(sonuc, file.path(rdir, "kesif_tek_degisken.csv"))
fwrite(kategori, file.path(rdir, "kesif_kategori_yayginlik.csv"))

r2w <- dcast(sonuc[, .(nufus, degisken, yil, pseudo_r2)], nufus + degisken ~ yil, value.var = "pseudo_r2")
setnames(r2w, c("2023", "2024", "2025"), c("r2_2023", "r2_2024", "r2_2025"), skip_absent = TRUE)
aucw <- dcast(sonuc[, .(nufus, degisken, yil, auc)], nufus + degisken ~ yil, value.var = "auc")
setnames(aucw, c("2023", "2024", "2025"), c("auc_2023", "auc_2024", "auc_2025"), skip_absent = TRUE)
ozet <- merge(merge(r2w, aucw, by = c("nufus", "degisken")),
              sonuc[, .(katman = katman[1], tur = tur[1], r2_ort = mean(pseudo_r2), sira_ort = mean(sira), eksik_ort = mean(eksik_yuzde)), by = .(nufus, degisken)],
              by = c("nufus", "degisken"))
setorder(ozet, nufus, -r2_ort)
fwrite(ozet, file.path(rdir, "kesif_ozet_siralama.csv"))
for (nf in c("tum", "yoksul_degil")) {
  cat("\n==== ", nf, ": pseudo R2 ortalamasina gore ilk 30 ====\n")
  print(ozet[nufus == nf][1:30, .(degisken, katman, r2_2023 = round(r2_2023, 3), r2_2024 = round(r2_2024, 3), r2_2025 = round(r2_2025, 3), auc_2025 = round(auc_2025, 3))])
}
kar <- dcast(sonuc[, .(nufus, yil, degisken, r2 = pseudo_r2)], nufus + degisken ~ yil, value.var = "r2")
kararlilik <- kar[, .(rho_23_24 = cor(`2023`, `2024`, method = "spearman", use = "complete.obs"), rho_24_25 = cor(`2024`, `2025`, method = "spearman", use = "complete.obs"),
                      rho_23_25 = cor(`2023`, `2025`, method = "spearman", use = "complete.obs")), by = nufus]
fwrite(kararlilik, file.path(rdir, "kesif_yil_kararlilik.csv"))
print(kararlilik)
katmanlar <- sonuc[, .(r2_medyan = median(pseudo_r2), r2_max = max(pseudo_r2), auc_max = max(auc)), keyby = .(nufus, yil, katman)]
fwrite(katmanlar, file.path(rdir, "kesif_katman_ozeti.csv"))
print(katmanlar)

iliski <- function(x, y, tx, ty) {
  ok <- !is.na(x) & !is.na(y)
  x <- x[ok]
  y <- y[ok]
  if (length(x) < 100) return(NA_real_)
  if (tx == "sayisal" && ty == "sayisal") return(abs(cor(as.numeric(x), as.numeric(y), method = "spearman")))
  if (tx == "kategorik" && ty == "kategorik") {
    tb <- table(x, y)
    if (min(dim(tb)) < 2) return(NA_real_)
    chi <- suppressWarnings(chisq.test(tb, correct = FALSE)$statistic)
    return(as.numeric(sqrt(chi / (sum(tb) * (min(dim(tb)) - 1)))))
  }
  if (tx == "sayisal") { num <- as.numeric(x); grp <- y } else { num <- as.numeric(y); grp <- x }
  ort <- tapply(num, grp, mean)
  nn <- tapply(num, grp, length)
  ssb <- sum(nn * (ort - mean(num))^2)
  sst <- sum((num - mean(num))^2)
  if (sst == 0) return(NA_real_)
  sqrt(ssb / sst)
}
h25 <- h[yil == 2025]
vv <- katalog$degisken
M <- matrix(NA_real_, length(vv), length(vv), dimnames = list(vv, vv))
t0 <- Sys.time()
for (i in seq_along(vv)) for (j in i:length(vv)) {
  M[i, j] <- if (i == j) 1 else iliski(h25[[vv[i]]], h25[[vv[j]]], katalog$tur[i], katalog$tur[j])
  M[j, i] <- M[i, j]
}
cat("Iliski matrisi suresi (dk):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
fwrite(as.data.table(M, keep.rownames = "degisken"), file.path(rdir, "kesif_ozellik_iliski_2025.csv"))
M2 <- M
M2[is.na(M2)] <- 0
hc <- hclust(as.dist(1 - M2), method = "average")
kume <- cutree(hc, h = 0.6)
ciftler <- as.data.table(as.table(M))[V1 != V2 & !is.na(N) & N >= 0.5][, .(degisken_1 = as.character(V1), degisken_2 = as.character(V2), iliski = N)]
ciftler <- ciftler[degisken_1 < degisken_2][order(-iliski)]
fwrite(ciftler, file.path(rdir, "kesif_guclu_ciftler_2025.csv"))
kume_tab <- merge(data.table(degisken = names(kume), kume = kume), ozet[nufus == "tum", .(degisken, katman, r2_ort)], by = "degisken")
setorder(kume_tab, kume, -r2_ort)
fwrite(kume_tab, file.path(rdir, "kesif_ozellik_kumeleri_2025.csv"))
cat("\n==== Birbirine yakin ozellik ciftleri (iliski >= 0,7) ====\n")
print(ciftler[iliski >= 0.7])
cat("\n==== Kume sayisi:", length(unique(kume)), "; ikiden fazla uyeli kumeler ====\n")
print(kume_tab[kume %in% kume_tab[, .N, by = kume][N > 2, kume]])
png(file.path(rdir, "kesif_ozellik_iliski_2025.png"), width = 3000, height = 3000, res = 200)
ord <- hc$order
op <- par(mar = c(10, 10, 1, 1))
image(seq_along(vv), seq_along(vv), M2[ord, ord], col = hcl.colors(50, "YlOrRd", rev = TRUE), axes = FALSE, xlab = "", ylab = "", zlim = c(0, 1))
axis(1, at = seq_along(vv), labels = vv[ord], las = 2, cex.axis = 0.55)
axis(2, at = seq_along(vv), labels = vv[ord], las = 2, cex.axis = 0.55)
par(op)
dev.off()

eksik <- dcast(sonuc[nufus == "tum", .(yil, degisken, eksik_yuzde)], degisken ~ yil, value.var = "eksik_yuzde")
fwrite(eksik, file.path(rdir, "kesif_eksik.csv"))
print(eksik[`2023` > 1 | `2024` > 1 | `2025` > 1])
writeLines(capture.output(sessionInfo()), file.path(rdir, "sessionInfo_kesif.txt"))
cat("kesif.R bitti\n")
```

## Ek B. Rapor.md başlangıç şablonu

```
# Rapor

## 0. Durum
Son güncelleme: GG.AA.YYYY SS:DD
Aşama: 0a (kurulum ve doğrulama) sürüyor
Bitenler: -
Sırada: -
Tahmini süre: -

## 1. Aşama günlüğü
### Aşama 0a. Kurulum, okuma, doğrulama
- Amaç:
- Yapılan:
- Bulunan:
- Üretilen dosyalar:

## 2. Karar defteri
K1. ...

## 3. Doğrulama kontrolleri
| Kontrol | Beklenen | Bulunan | Durum |

## 4. Özellik katmanları ve kovaryat seçimi
## 5. Model kurma protokolü
## 6. Nihai değişken tanımları
## 7. Ana sayılar
## 8. Simülasyon özeti
## 9. Methods için notlar
## 10. Hipotez değerlendirmesi
## 11. Bize sorular
## 12. Eksikler ve yapılamayanlar
## 13. Dosya envanteri ve süreler
```
