options(warn = 1, width = 160, survey.lonely.psu = "adjust", datatable.print.nrows = 200)
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(readxl)
  library(survey)
  library(splines)
  library(flextable)
  library(officer)
  library(future)
  library(furrr)
  library(jsonlite)
  library(openxlsx)
})
set.seed(20261026)
baslangic <- Sys.time()
dir.create("Results/log", showWarnings = FALSE, recursive = TRUE)
dir.create("Results/Supplementary", showWarnings = FALSE)
dir.create("Results/kesif", showWarnings = FALSE)
sink("Results/log/analiz_log.txt", split = TRUE)
cat("analiz.R basladi:", format(baslangic), "\n")
sureler <- list()
sure_ekle <- function(adim, t0) {
  sureler[[length(sureler) + 1]] <<- data.table(adim = adim, dakika = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2))
  invisible(NULL)
}

ddir <- "R_Data ve Python Data"
for (k in c("onbellek", "simulasyon", "figur_verileri")) dir.create(file.path(ddir, k), showWarnings = FALSE, recursive = TRUE)
pq <- file.path(ddir, "gyka_2023_2025.parquet")
t0 <- Sys.time()
if (!file.exists(pq)) {
  s <- read_excel("GYKA_2023_2025_birlesik.xlsx", sheet = "sozluk")
  d0 <- as.data.table(read_excel("GYKA_2023_2025_birlesik.xlsx", sheet = "veri", col_types = s$okuma_turu))
  cat("xlsx okuma suresi (sn):", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "\n")
  write_parquet(d0, pq)
  saveRDS(d0, file.path(ddir, "gyka_2023_2025.rds"))
  fwrite(s, file.path(ddir, "sozluk.csv"))
  fwrite(as.data.table(read_excel("GYKA_2023_2025_birlesik.xlsx", sheet = "kodlar")), file.path(ddir, "kodlar.csv"))
  fwrite(as.data.table(read_excel("GYKA_2023_2025_birlesik.xlsx", sheet = "dogrulama")), file.path(ddir, "dogrulama_sayfasi.csv"))
  rm(d0, s)
  gc()
}
sozluk <- fread(file.path(ddir, "sozluk.csv"))
kodlar <- fread(file.path(ddir, "kodlar.csv"))
dogr_sayfa <- fread(file.path(ddir, "dogrulama_sayfasi.csv"))
d <- as.data.table(read_parquet(pq))
cat("Veri:", nrow(d), "satir,", ncol(d), "sutun\n")
sure_ekle("okuma", t0)

t0 <- Sys.time()
dogr <- list()
kontrol <- function(ad, beklenen, bulunan, tol = 0, kaynak = "talimat") {
  durum <- if (is.numeric(beklenen) && is.numeric(bulunan)) {
    if (abs(bulunan - beklenen) <= tol + 1e-9) "Tuttu" else "Tutmadi"
  } else if (identical(as.character(beklenen), as.character(bulunan))) "Tuttu" else "Tutmadi"
  dogr[[length(dogr) + 1]] <<- data.table(kontrol = ad, kaynak = kaynak, beklenen = as.character(beklenen), bulunan = as.character(bulunan), durum = durum)
  invisible(NULL)
}
wm <- function(x, w) sum(x * w) / sum(w)
gini <- function(y, w) {
  o <- order(y)
  y <- y[o]
  w <- w[o]
  p <- cumsum(w) / sum(w)
  q <- cumsum(w * y) / sum(w * y)
  1 - sum((p - c(0, head(p, -1))) * (q + c(0, head(q, -1))))
}
kontrol("Satir sayisi", 239985, nrow(d))
kontrol("Sutun sayisi", 266, ncol(d))
kontrol("Her hanede tek hane_reisi", 0L, d[, .(k = sum(hane_reisi == 1)), by = hane_kimlik][k != 1, .N])
for (yy in 2023:2025) {
  dy <- d[yil == yy]
  hy <- dy[hane_reisi == 1]
  kontrol(paste(yy, "HB040 toplami (milyon hane, 26,7-27,2)"), 26.95, round(hy[, sum(HB040)] / 1e6, 2), tol = 0.25)
  kontrol(paste(yy, "FB030 toplami = FK070 >= 15 FK050 toplami (milyon)"), round(dy[FK070 >= 15, sum(FK050)] / 1e6, 3), round(dy[f_kayit == 1, sum(FB030)] / 1e6, 3), tol = 0.001)
}
d25 <- d[yil == 2025]
h25 <- d25[hane_reisi == 1]
kontrol("2025 hane (hane_reisi == 1)", 25836, nrow(h25))
kontrol("2025 tum fert", 80206, nrow(d25))
kontrol("2025 fert gorusmesi (f_kayit == 1)", 61812, d25[f_kayit == 1, .N])
kontrol("2025 HE090 = 1 (hane)", 15772, h25[HE090 == 1, .N])
kontrol("2025 HE090 = 2 (hane)", 10064, h25[HE090 == 2, .N])
kontrol("2025 yoksul_60 (FK050, tum fertler, %)", 20.6, round(100 * d25[, wm(yoksul_60, FK050)], 1))
kontrol("2025 Gini (esdeger gelir, FK050)", 0.410, round(d25[, gini(esdeger_gelir, FK050)], 3))
he_kisi <- c("2023" = 39.1, "2024" = 39.3, "2025" = 35.1)
for (yy in 2023:2025) kontrol(paste(yy, "HE090 = 2 kisi payi (FK050, %; Eurostat ilc_mdes03)"), he_kisi[[as.character(yy)]], round(100 * d[yil == yy, wm(HE090 == 2, FK050)], 1))
kontrol("2023 HB031 = TR63 hane", 0, d[yil == 2023 & HB031 == "TR63", .N])
kontrol("2025 18+ yetiskin, fert gorusmesi (H3 evreni)", 57899, d25[FK070 >= 18 & f_kayit == 1, .N])
kontrol("2025 vejetaryen/vegan yetiskin (et_tavuk_balik_siklik = 0, 18+)", 195, d25[FK070 >= 18 & f_kayit == 1 & et_tavuk_balik_siklik == 0, .N])
hesap_gosterge <- function(dy, g) {
  hy <- dy[hane_reisi == 1]
  fy <- dy[f_kayit == 1]
  pay <- function(k, kol) dy[, sum(esdeger_gelir[get(kol) == k] * FK050[get(kol) == k]) / sum(esdeger_gelir * FK050)]
  switch(g,
    "yoksul_40" = 100 * dy[, wm(yoksul_40, FK050)],
    "yoksul_50" = 100 * dy[, wm(yoksul_50, FK050)],
    "yoksul_60" = 100 * dy[, wm(yoksul_60, FK050)],
    "yoksul_70" = 100 * dy[, wm(yoksul_70, FK050)],
    "msy_5" = 100 * dy[, wm(msy_5, FK050)],
    "msy_7" = 100 * dy[, wm(msy_7, FK050)],
    "my_4" = 100 * dy[, wm(my_4, FK050)],
    "yoksulluk_sosyal_dislanma" = 100 * dy[, wm(yoksulluk_sosyal_dislanma, FK050)],
    "yoksulluk_sosyal_dislanma 0-17 yas" = 100 * dy[FK070 < 18, wm(yoksulluk_sosyal_dislanma, FK050)],
    "yoksulluk_sosyal_dislanma 18-64 yas" = 100 * dy[FK070 >= 18 & FK070 <= 64, wm(yoksulluk_sosyal_dislanma, FK050)],
    "yoksulluk_sosyal_dislanma 65+ yas" = 100 * dy[FK070 >= 65, wm(yoksulluk_sosyal_dislanma, FK050)],
    "Gini (esdeger_gelir)" = dy[, gini(esdeger_gelir, FK050)],
    "S80/S20" = pay(5, "gelir_dilim5") / pay(1, "gelir_dilim5"),
    "S90/S10" = pay(10, "gelir_dilim10") / pay(1, "gelir_dilim10"),
    "En yuksek %20 gelir payi" = 100 * pay(5, "gelir_dilim5"),
    "En dusuk %20 gelir payi" = 100 * pay(1, "gelir_dilim5"),
    "Ortalama esdeger gelir (FK050)" = dy[, wm(esdeger_gelir, FK050)],
    "Medyan esdeger gelir (FK050)" = {
      o <- dy[order(esdeger_gelir)]
      o[which(cumsum(FK050) / sum(FK050) >= 0.5)[1], esdeger_gelir]
    },
    "Ortalama hane kullanilabilir geliri (FK050)" = hy[, wm(HG110, FK050)],
    "Ortalama hane kullanilabilir geliri (HB040)" = hy[, wm(HG110, HB040)],
    "kalabalik_konut" = 100 * dy[, wm(kalabalik_konut, FK050)],
    "ciddi_konut_yoksunlugu" = 100 * dy[, wm(ciddi_konut_yoksunlugu, FK050)],
    "konut_maliyet_asiri_yuk" = 100 * dy[!is.na(konut_maliyet_asiri_yuk), wm(konut_maliyet_asiri_yuk, FK050)],
    "karsilanamayan_tibbi_ihtiyac (16+)" = 100 * fy[FK070 >= 16, wm(karsilanamayan_tibbi_ihtiyac, FB030)],
    "karsilanamayan_dis_ihtiyaci (16+)" = 100 * fy[FK070 >= 16, wm(karsilanamayan_dis_ihtiyaci, FB030)],
    "dusuk_is_yogunlugu (0-59 yas)" = 100 * dy[FK070 <= 59 & !is.na(dusuk_is_yogunlugu), wm(dusuk_is_yogunlugu, FK050)],
    "dusuk_is_yogunlugu_064 (0-64 yas)" = 100 * dy[FK070 <= 64 & !is.na(dusuk_is_yogunlugu_064), wm(dusuk_is_yogunlugu_064, FK050)],
    "calisan_yoksul" = 100 * fy[!is.na(calisan_yoksul), wm(calisan_yoksul, FB030)],
    NA_real_)
}
for (i in seq_len(nrow(dogr_sayfa))) {
  r <- dogr_sayfa[i]
  dy <- d[yil == r$yil]
  b <- hesap_gosterge(dy, r$gosterge)
  if (is.na(b)) {
    kontrol(paste(r$yil, r$gosterge), r$hesaplanan, "hesaplanmadi", kaynak = "dogrulama sayfasi")
    next
  }
  dig <- nchar(sub("^[^.]*\\.?", "", format(r$hesaplanan, scientific = FALSE)))
  kontrol(paste(r$yil, r$gosterge), r$hesaplanan, round(b, dig), kaynak = "dogrulama sayfasi")
}
rm(dy)
sure_ekle("dogrulama", t0)

t0 <- Sys.time()
sifir <- function(x) fifelse(is.na(x), 0, as.numeric(x))
enbuyuk <- function(x) if (all(is.na(x))) NA_integer_ else as.integer(max(x, na.rm = TRUE))
enkucuk <- function(x) if (all(is.na(x))) NA_integer_ else as.integer(min(x, na.rm = TRUE))
d[, egitim5 := fcase(FE030 %in% 0:1, 1L, FE030 %in% 2:3, 2L, FE030 == 4, 3L, FE030 %in% 5:6, 4L, FE030 %in% 7:10, 5L, default = NA_integer_)]
msy_kalem <- c("msy_beklenmedik_harcama", "msy_tatil", "msy_borc_odeme", "msy_isinma", "msy_otomobil", "msy_mobilya", "msy_internet", "msy_giysi", "msy_ayakkabi", "msy_harclik", "msy_bos_zaman", "msy_arkadas_aile")
d[, msy_etsiz_sayi := rowSums(.SD), .SDcols = msy_kalem]
d[, msy_etsiz_5 := as.integer(msy_etsiz_sayi >= 5)]
kontrol_msy <- d[, max(abs(msy_etsiz_sayi + msy_et_tavuk_balik - msy_sayi))]
cat("msy_etsiz_sayi + msy_et_tavuk_balik - msy_sayi en buyuk mutlak fark:", kontrol_msy, "\n")
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
  n_engelli = if (yil[1] == 2025) sum(FK070 >= 18 & wg_engellilik %in% 1) else NA_integer_,
  n_f_kayitsiz_yetiskin = sum(FK070 >= 18 & f_kayit == 0),
  egitim_max = enbuyuk(egitim5[FK070 >= 18 & f_kayit == 1]),
  egitim_min = enkucuk(egitim5[FK070 >= 18 & f_kayit == 1]),
  dusuk_is_h = enbuyuk(dusuk_is_yogunlugu),
  arope_h = enbuyuk(yoksulluk_sosyal_dislanma),
  g_ucret = sum(sifir(FG010) + sifir(FG020)),
  g_mutesebbis = sum(sifir(FG030) + sifir(FG040)),
  g_emekli = sum(sifir(FG080) + sifir(FG085) + sifir(FG090)),
  g_sosyal_fert = sum(sifir(FG070) + sifir(FG100) + sifir(FG110) + sifir(FG120))
), by = .(yil, hane_kimlik)]
hv <- c("yil", "gelir_yili", "hane_kimlik", "HB040", "FK050", "HB030", "HB031", "HB050",
        "HH010", "HH020", "HH030", "HH040", "HH050", "HH060", "HH070", "HH080", "HH100", "HH110", "HH120", "HH130", "HH140", "HH145",
        "HH150", "HH160", "HH170", "HH180", "HH190", "HH200", "HH210", "HH220", "HH230", "HH240",
        "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070",
        "HE010", "HE020", "HE030", "HE040", "HE050", "HE060", "HE070", "HE080", "HE090", "HE100", "HE110", "HE120",
        "HG010", "HG020", "HG030N", "HG030A", "HG040", "HG050N", "HG050A", "HG060N", "HG060A", "HG065N", "HG070", "HG080", "HG085", "HG090N", "HG090A", "HG095N", "HG100", "HG103", "HG105", "HG110",
        "hane_buyuklugu", "hane_0_17", "hane_65plus", "esdeger_gelir", "goreli_esdeger_gelir", "gelir_dilim5", "gelir_dilim10", "hane_gelir_dilim5",
        "yoksul_50", "yoksul_60", "yoksul_70", "yoksulluk_acigi_60", "is_yogunlugu", "dusuk_is_yogunlugu", "konut_maliyet_orani", "konut_maliyet_asiri_yuk",
        "kalabalik_konut", "ciddi_konut_yoksunlugu", "msy_beklenmedik_harcama", "msy_tatil", "msy_borc_odeme", "msy_et_tavuk_balik", "msy_isinma", "msy_otomobil", "msy_mobilya",
        "msy_internet", "msy_giysi", "msy_ayakkabi", "msy_harclik", "msy_bos_zaman", "msy_arkadas_aile", "msy_sayi", "msy_5", "msy_7", "my_sayi", "my_3", "my_4",
        "msy_etsiz_sayi", "msy_etsiz_5", "yoksulluk_sosyal_dislanma",
        "MODUL1_H_1", "MODUL1_H_2", "MODUL1_H_3",
        "FK070", "FK090", "FB100", "FI010", "FK210", "FS010", "FS020", "FS030", "egitim5", "f_kayit")
h <- d[hane_reisi == 1, ..hv]
setnames(h, c("FK070", "FK090", "FB100", "FI010", "FK210", "FS010", "FS020", "FS030", "egitim5", "f_kayit", "dusuk_is_yogunlugu"),
         c("reis_yas", "reis_cinsiyet", "reis_medeni", "reis_fi010", "reis_fk210", "reis_saglik", "reis_kronik", "reis_gali", "reis_egitim", "reis_f_kayit", "reis_dusuk_is"))
h <- merge(h, hagg, by = c("yil", "hane_kimlik"))
h[, `:=`(
  FI = as.integer(HE090 == 2),
  yoksul = as.integer(yoksul_60 == 1),
  gelir_pozitif = HG110 > 0,
  log_goreli_gelir = log(pmax(goreli_esdeger_gelir, 0.01)),
  g_sosyal_hane = sifir(HG030N) + sifir(HG030A) + sifir(HG040) + sifir(HG050N) + sifir(HG050A),
  g_ozel_transfer = sifir(HG060N) + sifir(HG060A) + sifir(HG065N),
  reis_calisma7 = fcase(reis_fi010 %in% 1:4, 1L, reis_fi010 == 5, 2L, reis_fi010 == 6, 3L, reis_fi010 == 7, 4L, reis_fi010 == 8, 5L, reis_fi010 == 9, 6L, reis_fi010 == 10, 7L, default = NA_integer_),
  reis_faaliyet3 = fcase(reis_fi010 %in% 1:4, 1L, reis_fi010 == 7, 2L, !is.na(reis_fi010), 3L, reis_fk210 == 1, 1L, default = 3L),
  kiraci = as.integer(HH020 %in% 2:3),
  cocuk_var = as.integer(n_cocuk > 0),
  yasli_var = as.integer(n_65plus > 0),
  tek_yetiskin_cocuklu = as.integer(n_yetiskin == 1 & n_cocuk > 0),
  calisan_yok = as.integer(n_calisan == 0),
  calisan_var = as.integer(n_calisan > 0),
  calisan_oran = fifelse(n_yetiskin > 0, n_calisan / n_yetiskin, NA_real_),
  bagimli_oran = (n_cocuk + n_65plus) / hane_buyuklugu,
  dusuk_is_yogunlugu = dusuk_is_h
)]
h[, `:=`(
  kacirilan = as.integer(FI == 1 & yoksul == 0),
  pay_ucret = fifelse(gelir_pozitif, pmin(g_ucret / HG110, 1.5), NA_real_),
  pay_mutesebbis = fifelse(gelir_pozitif, pmin(g_mutesebbis / HG110, 1.5), NA_real_),
  pay_emekli = fifelse(gelir_pozitif, pmin(g_emekli / HG110, 1.5), NA_real_),
  pay_sosyal = fifelse(gelir_pozitif, pmin((g_sosyal_hane + g_sosyal_fert) / HG110, 1.5), NA_real_),
  pay_ozel_transfer = fifelse(gelir_pozitif, pmin(g_ozel_transfer / HG110, 1.5), NA_real_),
  sosyal_yardim_var = as.integer((g_sosyal_hane + g_sosyal_fert) > 0),
  ozel_transfer_var = as.integer(g_ozel_transfer > 0),
  kira_geliri_var = as.integer(sifir(HG070) > 0),
  kira_orani = fifelse(gelir_pozitif & kiraci == 1, pmin(12 * sifir(HH040) / HG110, 3), fifelse(gelir_pozitif, 0, NA_real_)),
  he050_orani = fifelse(gelir_pozitif, pmin(12 * HE050 / HG110, 10), NA_real_),
  konut_orani_k = fifelse(yil == 2024, NA_real_, pmin(pmax(konut_maliyet_orani, 0), 3)),
  konut_asiri_k = fifelse(yil == 2024, NA_integer_, as.integer(konut_maliyet_asiri_yuk)),
  m2_kisi = HH070 / hane_buyuklugu,
  gelir_bandi = fcase(goreli_esdeger_gelir < 0.6, 1L, goreli_esdeger_gelir < 0.8, 2L, goreli_esdeger_gelir < 1.0, 3L, goreli_esdeger_gelir <= 1.5, 4L, default = 5L),
  is_yog_grup = fcase(is.na(is_yogunlugu), 0L, is_yogunlugu < 0.2, 1L, is_yogunlugu < 0.45, 2L, is_yogunlugu < 0.55, 3L, is_yogunlugu < 0.85, 4L, default = 5L)
)]
for (v in c("HH150", "HH160", "HH170", "HH180", "HH190", "HH200", "HH210", "HH220", "HH230", "HH240")) set(h, j = paste0(v, "_var"), value = as.integer(h[[v]] == 1))
agirlikli_medyan <- function(x, w) {
  o <- order(x)
  x[o][which(cumsum(w[o]) / sum(w) >= 0.5)[1]]
}
kira_medyan <- h[kiraci == 1 & HH040 > 0, .(kira_medyan = agirlikli_medyan(HH040, HB040)), by = yil]
h <- merge(h, kira_medyan, by = "yil")
h[, goreli_kira := fifelse(kiraci == 1, pmin(sifir(HH040) / kira_medyan, 5), 0)]
h[, kira_medyan := NULL]
sure_ekle("hane veri seti", t0)

t0 <- Sys.time()
imza_dt <- d[hane_buyuklugu > 1, .(yil, hane_kimlik, u = sprintf("%04d%02d%d", as.integer(FK080), as.integer(FK075), as.integer(FK090)))][order(yil, hane_kimlik, u)][, .(imza = paste(u, collapse = "-")), by = .(yil, hane_kimlik)]
imza_dt[, imza_n := .N, by = .(yil, imza)]
tekil <- imza_dt[imza_n == 1]
esles <- function(y1, y2) {
  a <- tekil[yil == y1, .(imza, hane_1 = hane_kimlik)]
  b <- tekil[yil == y2, .(imza, hane_2 = hane_kimlik)]
  m <- merge(a, b, by = "imza")
  m[, `:=`(yil_1 = y1, yil_2 = y2)]
  m
}
eslesme <- rbindlist(list(esles(2023, 2024), esles(2024, 2025), esles(2023, 2025)))
hk <- h[, .(hane_kimlik, HB031, HH010)]
eslesme <- merge(eslesme, setnames(copy(hk), c("hane_1", "HB031_1", "HH010_1")), by = "hane_1")
eslesme <- merge(eslesme, setnames(copy(hk), c("hane_2", "HB031_2", "HH010_2")), by = "hane_2")
eslesme_ozet <- eslesme[, .(eslesen_hane = .N, bolge_ayni = round(100 * mean(HB031_1 == HB031_2), 1), konut_tipi_ayni = round(100 * mean(HH010_1 == HH010_2), 1)), keyby = .(yil_1, yil_2)]
eslesme_ozet[, beklenen := c(12924, 7432, 13396)[match(paste(yil_1, yil_2), c("2023 2024", "2023 2025", "2024 2025"))]]
eslesme_ozet[, cok_kisili_hane_yil_1 := imza_dt[, .N, by = yil][match(eslesme_ozet$yil_1, yil), N]]
eslesme_ozet[, eslesme_payi := round(100 * eslesen_hane / cok_kisili_hane_yil_1, 1)]
print(eslesme_ozet)
for (i in seq_len(nrow(eslesme_ozet))) kontrol(paste0("Imza eslesmesi ", eslesme_ozet$yil_1[i], "-", eslesme_ozet$yil_2[i], " (inceleme raporu Tablo 2)"), eslesme_ozet$beklenen[i], eslesme_ozet$eslesen_hane[i], kaynak = "inceleme raporu")
reis_dt <- merge(d[hane_reisi == 1, .(yil, hane_kimlik, r_u = sprintf("%04d%02d%d", as.integer(FK080), as.integer(FK075), as.integer(FK090)))],
                 h[, .(hane_kimlik, HB031, HH010, HH020, hb = hane_buyuklugu)], by = "hane_kimlik")
reis_dt[, anahtar := paste(r_u, HB031, HH010, HH020, sep = "_")]
reis_dt[, anahtar_n := .N, by = .(yil, anahtar)]
reis_tek <- reis_dt[anahtar_n == 1]
esles_reis <- function(y1, y2) {
  m <- merge(reis_tek[yil == y1, .(anahtar, hane_1 = hane_kimlik, n_1 = hb)], reis_tek[yil == y2, .(anahtar, hane_2 = hane_kimlik, n_2 = hb)], by = "anahtar")
  m[, `:=`(yil_1 = y1, yil_2 = y2)]
  m
}
eslesme_reis <- rbindlist(list(esles_reis(2023, 2024), esles_reis(2024, 2025), esles_reis(2023, 2025)))
eslesme_reis[, imza_ile := paste(yil_1, hane_1, hane_2) %in% eslesme[, paste(yil_1, hane_1, hane_2)]]
reis_ozet <- eslesme_reis[, .(reis_anahtari_eslesen = .N, reis_tek_kisili = sum(n_1 == 1 & n_2 == 1), reis_cok_kisili_ayni_buyukluk = sum(n_1 > 1 & n_1 == n_2),
                              reis_imzayla_dogrulanan_pay = round(100 * sum(imza_ile & n_1 > 1 & n_1 == n_2) / sum(n_1 > 1 & n_1 == n_2), 1),
                              reis_buyukluk_degisen = sum(n_1 != n_2)), keyby = .(yil_1, yil_2)]
imza_cift <- merge(eslesme[, .(yil_1, yil_2, hane_1, hane_2)], reis_dt[, .(hane_1 = hane_kimlik, r_u_1 = r_u, anahtar_1 = anahtar)], by = "hane_1")
imza_cift <- merge(imza_cift, reis_dt[, .(hane_2 = hane_kimlik, r_u_2 = r_u, anahtar_2 = anahtar)], by = "hane_2")
imza_cift[, durum := fcase(paste(yil_1, hane_1, hane_2) %in% eslesme_reis[, paste(yil_1, hane_1, hane_2)], "eslesti",
                           r_u_1 != r_u_2, "reis_degisti",
                           anahtar_1 != anahtar_2, "bolge_konut_mulkiyet_degisti",
                           default = "anahtar_tekil_degil")]
reis_duyarlilik <- imza_cift[, .(imza_cifti = .N, reis_duyarlilik = round(100 * mean(durum == "eslesti"), 1), kayip_tekil_degil = round(100 * mean(durum == "anahtar_tekil_degil"), 1),
                                 kayip_reis_degisti = round(100 * mean(durum == "reis_degisti"), 1), kayip_bolge_konut = round(100 * mean(durum == "bolge_konut_mulkiyet_degisti"), 1)),
                             keyby = .(yil_1, yil_2)]
print(reis_duyarlilik)
reis_ozet <- merge(reis_ozet, reis_duyarlilik, by = c("yil_1", "yil_2"))
ek_cift <-eslesme_reis[!paste(yil_1, yil_2, hane_1) %in% eslesme[, paste(yil_1, yil_2, hane_1)] & !paste(yil_1, yil_2, hane_2) %in% eslesme[, paste(yil_1, yil_2, hane_2)]]
eslesme_bir <- rbind(eslesme[, .(yil_1, yil_2, hane_1, hane_2, yontem = "imza")], ek_cift[, .(yil_1, yil_2, hane_1, hane_2, yontem = "reis_anahtari")])
eslesme_ozet <- merge(eslesme_ozet, reis_ozet, by = c("yil_1", "yil_2"))
eslesme_ozet <- merge(eslesme_ozet, eslesme_bir[, .(birlesik_eslesen = .N, eklenen_reis_anahtari = sum(yontem == "reis_anahtari")), keyby = .(yil_1, yil_2)], by = c("yil_1", "yil_2"))
eslesme_ozet[, birlesik_eslesme_payi := round(100 * birlesik_eslesen / h[, .N, keyby = yil][match(eslesme_ozet$yil_1, yil), N], 1)]
print(eslesme_ozet)
bayrak_kur <- function(es, sonek) {
  ad <- paste0(c("eslesen_onceki_yil", "eslesen_2023", "eslesen_sonraki_yil", "eslesen_2025"), sonek)
  h[, (ad) := 0L]
  h[yil == 2024 & hane_kimlik %in% es[yil_1 == 2023 & yil_2 == 2024, hane_2], (ad[1]) := 1L]
  h[yil == 2025 & hane_kimlik %in% es[yil_1 == 2024 & yil_2 == 2025, hane_2], (ad[1]) := 1L]
  h[yil == 2025 & hane_kimlik %in% es[yil_1 == 2023 & yil_2 == 2025, hane_2], (ad[2]) := 1L]
  h[yil == 2023 & hane_kimlik %in% es[yil_1 == 2023 & yil_2 == 2024, hane_1], (ad[3]) := 1L]
  h[yil == 2024 & hane_kimlik %in% es[yil_1 == 2024 & yil_2 == 2025, hane_1], (ad[3]) := 1L]
  h[yil == 2023 & hane_kimlik %in% es[yil_1 == 2023 & yil_2 == 2025, hane_1], (ad[4]) := 1L]
  invisible(NULL)
}
bayrak_kur(eslesme_bir, "")
bayrak_kur(eslesme, "_imza")
h[, cok_kisili := as.integer(hane_buyuklugu > 1)]
h[, test_temiz := as.integer(yil == 2025 & eslesen_onceki_yil == 0L & eslesen_2023 == 0L)]
h[, test_temiz_2023 := as.integer(yil == 2025 & eslesen_2023 == 0L)]
h[, test_temiz_imza := as.integer(yil == 2025 & eslesen_onceki_yil_imza == 0L & eslesen_2023_imza == 0L)]
onceki_anahtar <- reis_dt[yil < 2025, unique(anahtar)]
onceki_imza <- imza_dt[yil < 2025, unique(imza)]
h[, test_temiz_siki := as.integer(test_temiz == 1L & !hane_kimlik %in% reis_dt[yil == 2025 & anahtar %in% onceki_anahtar, hane_kimlik] &
                                    !hane_kimlik %in% imza_dt[yil == 2025 & imza %in% onceki_imza, hane_kimlik])]
cat("Siki temiz test seti:", h[test_temiz_siki == 1, .N], "/", h[test_temiz == 1, .N], "\n")
fwrite(eslesme_ozet, "Results/ortusme_eslesme_sayilari.csv")
fwrite(eslesme_bir, file.path(ddir, "ortusme_eslesmeleri.csv"))
ortusme_bilesim <- rbind(
  h[yil == 2025, .(tanim = "imza + reis anahtari", n = .N, agirlikli_pay = round(100 * sum(HB040) / h[yil == 2025, sum(HB040)], 2), tek_kisili_yuzde = round(100 * mean(hane_buyuklugu == 1), 1),
                   tek_kisili_agirlikli = round(100 * wm(hane_buyuklugu == 1, HB040), 1), FI_yuzde = round(100 * wm(FI, HB040), 1), yoksul_yuzde = round(100 * wm(yoksul, HB040), 1),
                   reis_yas_ort = round(wm(reis_yas, HB040), 1)), keyby = .(test_temiz)],
  h[yil == 2025, .(tanim = "yalniz imza", n = .N, agirlikli_pay = round(100 * sum(HB040) / h[yil == 2025, sum(HB040)], 2), tek_kisili_yuzde = round(100 * mean(hane_buyuklugu == 1), 1),
                   tek_kisili_agirlikli = round(100 * wm(hane_buyuklugu == 1, HB040), 1), FI_yuzde = round(100 * wm(FI, HB040), 1), yoksul_yuzde = round(100 * wm(yoksul, HB040), 1),
                   reis_yas_ort = round(wm(reis_yas, HB040), 1)), keyby = .(test_temiz = test_temiz_imza)],
  h[yil == 2025, .(tanim = "tum 2025", test_temiz = NA_integer_, n = .N, agirlikli_pay = 100, tek_kisili_yuzde = round(100 * mean(hane_buyuklugu == 1), 1),
                   tek_kisili_agirlikli = round(100 * wm(hane_buyuklugu == 1, HB040), 1), FI_yuzde = round(100 * wm(FI, HB040), 1), yoksul_yuzde = round(100 * wm(yoksul, HB040), 1),
                   reis_yas_ort = round(wm(reis_yas, HB040), 1))], use.names = TRUE)
print(ortusme_bilesim)
fwrite(ortusme_bilesim, "Results/ortusme_test_bilesimi_2025.csv")
setorder(h, yil, hane_kimlik)
write_parquet(h, file.path(ddir, "hane_2023_2025.parquet"))
cat("Hane satirlari:", nrow(h), " yil:", paste(h[, .N, keyby = yil]$N, collapse = " / "), "\n")
sure_ekle("ortusme imzasi", t0)

dogr <- rbindlist(dogr)
print(dogr[durum != "Tuttu"])
cat("Dogrulama:", dogr[durum == "Tuttu", .N], "/", nrow(dogr), "tuttu\n")
fwrite(dogr, "Results/dogrulama_kontrolleri.csv")

if (!file.exists("Results/kesif/kesif_cok_degiskenli_katmanlar.csv")) {
  t0 <- Sys.time()
  cat("kesif.R calistiriliyor\n")
  st <- system2("Rscript", "Codes/kesif.R", stdout = "Results/log/kesif_log.txt", stderr = "Results/log/kesif_log.txt")
  if (st != 0) stop("kesif.R hata verdi; Results/log/kesif_log.txt")
  sure_ekle("kesif.R", t0)
}

t0 <- Sys.time()
fdir <- file.path(ddir, "figur_verileri")
h[, `:=`(e_yoksul_60 = yoksul, e_yoksul_50 = as.integer(yoksul_50), e_yoksul_70 = as.integer(yoksul_70), e_msy_etsiz_5 = as.integer(msy_etsiz_5), e_dusuk_is = fifelse(is.na(dusuk_is_yogunlugu), 0L, as.integer(dusuk_is_yogunlugu)))]
esikler <- c("e_yoksul_60", "e_yoksul_50", "e_yoksul_70", "e_msy_etsiz_5", "e_dusuk_is")
hane_sut <- c("hane_kimlik", "FI", "yoksul", "kacirilan", esikler, "HB030", "HB031", "HB050", "gelir_bandi", "gelir_dilim5", "HH020", "cocuk_var", "calisan_var", "is_yog_grup", "reis_faaliyet3", "yasli_var", "test_temiz")
p_dt <- merge(d[, .(yil, hane_kimlik, FK050, FK070, esdeger_gelir)], h[, ..hane_sut], by = "hane_kimlik")
p_dt[, cocuk := as.integer(FK070 < 18)]
tasarim <- function(dat, duzey, tabaka = FALSE) {
  if (duzey == "hane") {
    if (tabaka) svydesign(ids = ~1, strata = ~HB031, weights = ~HB040, data = dat) else svydesign(ids = ~1, weights = ~HB040, data = dat)
  } else {
    if (tabaka) svydesign(ids = ~hane_kimlik, strata = ~HB031, weights = ~FK050, data = dat) else svydesign(ids = ~hane_kimlik, weights = ~FK050, data = dat)
  }
}
oran_svy <- function(des, f, kosul = NULL) {
  dd <- if (is.null(kosul)) des else des[kosul, ]
  m <- svymean(f, dd, na.rm = TRUE)
  c(tahmin = 100 * as.numeric(coef(m))[1], se = 100 * as.numeric(SE(m))[1])
}
h1_satir <- function(olcu, esik, x, n, olay) data.table(olcu = olcu, esik = esik, tahmin = x[["tahmin"]], se = x[["se"]], n = n, olay = olay)
h1_temel <- function(dat, duzey, tabaka = FALSE) {
  des <- tasarim(dat, duzey, tabaka)
  v <- dat
  out <- list(h1_satir("FI", "", oran_svy(des, ~FI), nrow(v), sum(v$FI)))
  for (e in esikler) {
    fe <- v[[e]]
    out[[length(out) + 1]] <- h1_satir("esik", e, oran_svy(des, as.formula(paste0("~", e))), nrow(v), sum(fe))
    out[[length(out) + 1]] <- h1_satir("FI_ve_esik", e, oran_svy(des, as.formula(paste0("~I(FI * ", e, ")"))), nrow(v), sum(v$FI * fe))
    out[[length(out) + 1]] <- h1_satir("FI_esik_degil", e, oran_svy(des, as.formula(paste0("~I(FI * (1 - ", e, "))"))), nrow(v), sum(v$FI * (1 - fe)))
    out[[length(out) + 1]] <- h1_satir("dislama", e, oran_svy(des, as.formula(paste0("~I(1 - ", e, ")")), v$FI == 1), sum(v$FI), sum(v$FI * (1 - fe)))
    out[[length(out) + 1]] <- h1_satir("FI_esik_icinde", e, oran_svy(des, ~FI, fe == 1), sum(fe), sum(v$FI * fe))
  }
  if (duzey == "kisi") {
    cc <- v$cocuk == 1
    m <- svytotal(~kacirilan, des[cc, ])
    out[[length(out) + 1]] <- data.table(olcu = "cocuk_kacirilan_milyon", esik = "e_yoksul_60", tahmin = as.numeric(coef(m)) / 1e6, se = as.numeric(SE(m)) / 1e6, n = sum(cc), olay = sum(v$kacirilan[cc]))
    m <- svytotal(~FI, des[cc, ])
    out[[length(out) + 1]] <- data.table(olcu = "cocuk_FI_milyon", esik = "", tahmin = as.numeric(coef(m)) / 1e6, se = as.numeric(SE(m)) / 1e6, n = sum(cc), olay = sum(v$FI[cc]))
    out[[length(out) + 1]] <- h1_satir("cocuk_kacirilan_pay_tum_cocuk", "e_yoksul_60", oran_svy(des, ~kacirilan, cc), sum(cc), sum(v$kacirilan[cc]))
    out[[length(out) + 1]] <- h1_satir("cocuk_FI", "", oran_svy(des, ~FI, cc), sum(cc), sum(v$FI[cc]))
    out[[length(out) + 1]] <- h1_satir("cocuk_dislama", "e_yoksul_60", oran_svy(des, ~I(1 - yoksul), cc & v$FI == 1), sum(cc & v$FI == 1), sum(v$kacirilan[cc]))
  } else {
    m <- svytotal(~kacirilan, des)
    out[[length(out) + 1]] <- data.table(olcu = "kacirilan_hane_milyon", esik = "e_yoksul_60", tahmin = as.numeric(coef(m)) / 1e6, se = as.numeric(SE(m)) / 1e6, n = nrow(v), olay = sum(v$kacirilan))
  }
  rbindlist(out)
}
h1_ana <- list()
for (yy in 2023:2025) for (dz in c("hane", "kisi")) for (tr in c(FALSE, TRUE)) for (tb in c(FALSE, TRUE)) {
  if (tr && tb) next
  dat <- if (dz == "hane") h[yil == yy] else p_dt[yil == yy]
  if (tr) dat <- dat[HB031 != "TR63"]
  r <- h1_temel(dat, dz, tabaka = tb)
  r[, `:=`(yil = yy, duzey = dz, tr63_haric = tr, ibbs2_tabaka = tb)]
  h1_ana[[length(h1_ana) + 1]] <- r
}
h1_ana <- rbindlist(h1_ana)
h1_ana[, `:=`(alt = tahmin - 1.96 * se, ust = tahmin + 1.96 * se)]
fwrite(h1_ana, "Results/H1_temel_tahminler.csv")
h1_fark <- rbindlist(lapply(list(c(2023, 2025), c(2023, 2024), c(2024, 2025)), function(yp) {
  a <- h1_ana[yil == yp[1]]
  b <- h1_ana[yil == yp[2]]
  m <- merge(a, b, by = c("olcu", "esik", "duzey", "tr63_haric", "ibbs2_tabaka"), suffixes = c("_1", "_2"))
  m[, .(olcu, esik, duzey, tr63_haric, ibbs2_tabaka, yil_1 = yp[1], yil_2 = yp[2], tahmin_1, tahmin_2, fark = tahmin_2 - tahmin_1, se_fark = sqrt(se_1^2 + se_2^2))]
}))
h1_fark[, `:=`(alt = fark - 1.96 * se_fark, ust = fark + 1.96 * se_fark, p = 2 * pnorm(-abs(fark / se_fark)))]
rng_once <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
h1_bs <- function(ciftli, B = 2000L, tohum = 20261028L) {
  v <- h[yil %in% c(2023L, 2025L), .(yil, hane_kimlik, a = HB040 * FI * (1 - yoksul), b = HB040 * FI)]
  cf <- eslesme_bir[yil_1 == 2023 & yil_2 == 2025]
  v[, `:=`(birim = paste0("h", hane_kimlik), tabaka = paste0("tek_", yil))]
  if (ciftli) {
    v[cf, on = .(hane_kimlik = hane_1), `:=`(birim = paste0("c", i.hane_1), tabaka = "cift")]
    v[cf, on = .(hane_kimlik = hane_2), `:=`(birim = paste0("c", i.hane_1), tabaka = "cift")]
  }
  u <- v[, .(a23 = sum(a[yil == 2023L]), b23 = sum(b[yil == 2023L]), a25 = sum(a[yil == 2025L]), b25 = sum(b[yil == 2025L])), by = .(tabaka, birim)]
  if (ciftli) stopifnot(u[tabaka == "cift", .N] == nrow(cf))
  tb <- split(seq_len(nrow(u)), u$tabaka)
  set.seed(tohum)
  fb <- numeric(B)
  for (r in seq_len(B)) {
    m <- numeric(nrow(u))
    for (ix in tb) {
      nk <- length(ix)
      m[ix] <- tabulate(sample.int(nk, nk - 1L, replace = TRUE), nk) * nk / (nk - 1)
    }
    fb[r] <- 100 * (sum(m * u$a25) / sum(m * u$b25) - sum(m * u$a23) / sum(m * u$b23))
  }
  d0 <- c(100 * sum(u$a23) / sum(u$b23), 100 * sum(u$a25) / sum(u$b25))
  data.table(olcu = "dislama", esik = "e_yoksul_60", duzey = "hane", tr63_haric = FALSE, ibbs2_tabaka = FALSE, yil_1 = 2023L, yil_2 = 2025L,
             tahmin_1 = d0[1], tahmin_2 = d0[2], fark = d0[2] - d0[1], se_fark = sd(fb), alt = unname(quantile(fb, 0.025)), ust = unname(quantile(fb, 0.975)), p = NA_real_,
             yontem = if (ciftli) "eslesik_bootstrap" else "bagimsiz_bootstrap", B = B, eslesik_cift = u[tabaka == "cift", .N],
             tek_2023 = u[tabaka == "tek_2023", .N], tek_2025 = u[tabaka == "tek_2025", .N])
}
h1_fark_bs <- rbind(h1_bs(TRUE), h1_bs(FALSE, tohum = 20261029L))
if (is.null(rng_once)) {
  if (exists(".Random.seed", envir = globalenv())) rm(".Random.seed", envir = globalenv())
} else assign(".Random.seed", rng_once, envir = globalenv())
h1_kontrol <- h1_ana[olcu == "dislama" & esik == "e_yoksul_60" & duzey == "hane" & !tr63_haric & !ibbs2_tabaka]
stopifnot(abs(h1_fark_bs$tahmin_1[1] - h1_kontrol[yil == 2023, tahmin]) < 1e-9, abs(h1_fark_bs$tahmin_2[1] - h1_kontrol[yil == 2025, tahmin]) < 1e-9)
fwrite(rbind(copy(h1_fark)[, yontem := "taylor_bagimsiz"], h1_fark_bs, fill = TRUE), "Results/H1_yil_farklari.csv")
cat("\nH1 dislama hatasi farki 2025 - 2023 (hane), bootstrap duyarliligi:\n")
print(rbind(h1_fark[olcu == "dislama" & esik == "e_yoksul_60" & duzey == "hane" & yil_1 == 2023 & yil_2 == 2025 & !tr63_haric & !ibbs2_tabaka, .(yontem = "taylor_bagimsiz", fark, se_fark, alt, ust)],
            h1_fark_bs[, .(yontem, fark, se_fark, alt, ust)])[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 3) else x)])
h1_ana0 <- h1_ana[!tr63_haric & !ibbs2_tabaka]
h1_taban <- merge(merge(h1_ana0[olcu == "esik" & esik == "e_yoksul_60", .(yil, duzey, yoksul_payi = tahmin)], h1_ana0[olcu == "FI", .(yil, duzey, FI_payi = tahmin)], by = c("yil", "duzey")),
                  h1_ana0[olcu == "dislama" & esik == "e_yoksul_60", .(yil, duzey, gozlenen_dislama = tahmin)], by = c("yil", "duzey"))
h1_taban[, `:=`(aritmetik_taban = 100 * pmax(0, 1 - yoksul_payi / FI_payi))]
h1_taban[, gozlenen_eksi_taban := gozlenen_dislama - aritmetik_taban]
fwrite(h1_taban, "Results/H1_kapasite_tabani.csv")
cat("\nH1 aritmetik taban (yoksulluk kadar hane secen herhangi bir kural):\n")
print(h1_taban[, lapply(.SD, function(x) if (is.numeric(x)) round(x, 2) else x)])
cat("\nH1 dislama hatasi (yoksul_60):\n")
print(h1_ana[olcu == "dislama" & esik == "e_yoksul_60" & !tr63_haric & !ibbs2_tabaka, .(yil, duzey, tahmin = round(tahmin, 2), alt = round(alt, 2), ust = round(ust, 2), n, olay)])
print(h1_fark[olcu == "dislama" & esik == "e_yoksul_60" & !tr63_haric & !ibbs2_tabaka, .(yil_1, yil_2, duzey, fark = round(fark, 2), alt = round(alt, 2), ust = round(ust, 2), p = signif(p, 3))])
se_oran <- merge(h1_ana[ibbs2_tabaka == FALSE & tr63_haric == FALSE, .(olcu, esik, yil, duzey, se)], h1_ana[ibbs2_tabaka == TRUE, .(olcu, esik, yil, duzey, se_tabaka = se)], by = c("olcu", "esik", "yil", "duzey"))
se_oran[, oran := se_tabaka / se]
fwrite(se_oran, "Results/log/H1_ibbs2_sozde_tabaka_se_orani.csv")
cat("IBBS2 sozde tabaka SE orani: medyan", round(median(se_oran$oran), 3), " aralik", round(min(se_oran$oran), 3), "-", round(max(se_oran$oran), 3), "\n")

kirilimlar <- c("gelir_bandi", "gelir_dilim5", "HB050", "cocuk_var", "HH020", "HB030", "calisan_var", "is_yog_grup", "reis_faaliyet3", "yasli_var")
h1_kir <- list()
for (yy in 2023:2025) for (dz in c("hane", "kisi")) {
  dat <- if (dz == "hane") h[yil == yy] else p_dt[yil == yy]
  des <- tasarim(dat, dz)
  for (k in kirilimlar) {
    fk <- as.formula(paste0("~", k))
    a <- svyby(~FI, fk, des, svymean, na.rm = TRUE)
    b <- svyby(~I(1 - yoksul), fk, des[dat$FI == 1, ], svymean, na.rm = TRUE)
    cmp <- svymean(as.formula(paste0("~factor(", k, ")")), des[dat$kacirilan == 1, ])
    nn <- dat[, .(n = .N, n_FI = sum(FI), n_kacirilan = sum(kacirilan)), keyby = .(kategori = as.character(get(k)))]
    r <- data.table(kategori = as.character(a[[k]]), FI = 100 * a$FI, FI_se = 100 * SE(a), dislama = 100 * b[["I(1 - yoksul)"]][match(as.character(a[[k]]), as.character(b[[k]]))],
                    dislama_se = 100 * SE(b)[match(as.character(a[[k]]), as.character(b[[k]]))])
    r <- merge(r, nn, by = "kategori", all.x = TRUE)
    kp <- data.table(kategori = sub(paste0("factor\\(", k, "\\)"), "", names(coef(cmp))), kacirilan_bilesim = 100 * as.numeric(coef(cmp)), kacirilan_bilesim_se = 100 * as.numeric(SE(cmp)))
    r <- merge(r, kp, by = "kategori", all.x = TRUE)
    r[, `:=`(yil = yy, duzey = dz, kirilim = k)]
    h1_kir[[length(h1_kir) + 1]] <- r
  }
}
h1_kir <- rbindlist(h1_kir, fill = TRUE)
h1_kir[, kucuk_hucre := fcase(n_FI < 20, "suppressed", n_FI <= 50, "flag", default = "")]
fwrite(h1_kir, "Results/H1_kirilimlar.csv")

erreygers <- function(dat) {
  o <- dat[order(esdeger_gelir)]
  W <- sum(o$FK050)
  o[, R0 := (cumsum(FK050) - FK050 / 2) / W]
  o[, R := sum(R0 * FK050) / sum(FK050), by = esdeger_gelir]
  vR <- sum(o$FK050 * (o$R - sum(o$FK050 * o$R) / W)^2) / W
  des <- svydesign(ids = ~hane_kimlik, weights = ~FK050, data = o)
  m <- svyglm(FI ~ R, design = des)
  data.table(E = 8 * vR * coef(m)[["R"]], se = 8 * vR * SE(m)[["R"]], n = nrow(o))
}
h1_ci <- rbindlist(lapply(2023:2025, function(yy) cbind(yil = yy, erreygers(p_dt[yil == yy]))))
h1_ci[, `:=`(alt = E - 1.96 * se, ust = E + 1.96 * se)]
print(h1_ci)
fwrite(h1_ci, "Results/H1_erreygers.csv")
ci_fark <- data.table(yil_1 = c(2023, 2023), yil_2 = c(2025, 2024))
ci_fark[, `:=`(fark = h1_ci$E[match(yil_2, h1_ci$yil)] - h1_ci$E[match(yil_1, h1_ci$yil)], se_fark = sqrt(h1_ci$se[match(yil_2, h1_ci$yil)]^2 + h1_ci$se[match(yil_1, h1_ci$yil)]^2))]
ci_fark[, `:=`(alt = fark - 1.96 * se_fark, ust = fark + 1.96 * se_fark)]
print(ci_fark)
fwrite(ci_fark, "Results/H1_erreygers_farklar.csv")

rcs_baz <- function(x, k) {
  kk <- length(k)
  sapply(seq_len(kk - 2), function(j) (pmax(x - k[j], 0)^3 - pmax(x - k[kk - 1], 0)^3 * (k[kk] - k[j]) / (k[kk] - k[kk - 1]) +
                                         pmax(x - k[kk], 0)^3 * (k[kk - 1] - k[j]) / (k[kk] - k[kk - 1])) / (k[kk] - k[1])^2)
}
gk <- as.numeric(quantile(h$log_goreli_gelir, c(0.05, 0.275, 0.5, 0.725, 0.95)))
gk7 <- as.numeric(quantile(h$log_goreli_gelir, c(0.025, 0.1833, 0.3417, 0.5, 0.6583, 0.8167, 0.975)))
x_esik <- log(0.6)
adim_7 <- function(dat) {
  B7 <- rcs_baz(dat$x, gk7)
  dd <- data.table(FI = dat$FI, yoksul = dat$yoksul, x = dat$x, HB040 = dat$HB040, B7)
  setnames(dd, paste0("V", seq_len(ncol(B7))), paste0("t", seq_len(ncol(B7))))
  m <- svyglm(as.formula(paste("FI ~ x +", paste0("t", seq_len(ncol(B7)), collapse = " + "), "+ yoksul")), design = svydesign(ids = ~1, weights = ~HB040, data = dd), family = quasibinomial())
  b <- coef(m)
  z0 <- c(1, x_esik, rcs_baz(x_esik, gk7), 0)
  z1 <- z0
  z1[length(z1)] <- 1
  g <- dlogis(sum(z1 * b)) * z1 - dlogis(sum(z0 * b)) * z0
  dp <- 100 * (plogis(sum(z1 * b)) - plogis(sum(z0 * b)))
  dp_se <- 100 * sqrt(as.numeric(t(g) %*% vcov(m) %*% g))
  data.table(test = "esik_adimi_puan_7dugum", n = nrow(dd), tahmin = dp, alt = dp - 1.96 * dp_se, ust = dp + 1.96 * dp_se, p = summary(m)$coefficients["yoksul", 4])
}
adim_parcali <- function(dat) {
  dd <- data.table(FI = dat$FI, yoksul = dat$yoksul, x = dat$x, xk = pmax(dat$x - x_esik, 0), HB040 = dat$HB040)
  m <- svyglm(FI ~ x + xk + yoksul, design = svydesign(ids = ~1, weights = ~HB040, data = dd), family = quasibinomial())
  b <- coef(m)
  z0 <- c(1, x_esik, 0, 0)
  z1 <- c(1, x_esik, 0, 1)
  g <- dlogis(sum(z1 * b)) * z1 - dlogis(sum(z0 * b)) * z0
  dp <- 100 * (plogis(sum(z1 * b)) - plogis(sum(z0 * b)))
  dp_se <- 100 * sqrt(as.numeric(t(g) %*% vcov(m) %*% g))
  data.table(test = "esik_adimi_puan_parcali", n = nrow(dd), tahmin = dp, alt = dp - 1.96 * dp_se, ust = dp + 1.96 * dp_se, p = summary(m)$coefficients["yoksul", 4])
}
izgara <- seq(log(0.1), log(5), length.out = 241)
egri_test <- list()
egri_izgara <- list()
egri_yog <- list()
egri_veri <- list()
for (yy in 2023:2025) {
  dat <- h[yil == yy, .(FI, yoksul, x = log_goreli_gelir, HB040, yil)]
  cat("yoksul ile goreli gelir < 0,6 uyumsuzlugu", yy, ":", dat[, sum(yoksul != as.integer(x < x_esik))], "\n")
  B <- rcs_baz(dat$x, gk)
  dat[, `:=`(s1 = B[, 1], s2 = B[, 2], s3 = B[, 3])]
  egri_veri[[length(egri_veri) + 1]] <- dat
  des <- svydesign(ids = ~1, weights = ~HB040, data = dat)
  m_rcs <- svyglm(FI ~ x + s1 + s2 + s3, design = des, family = quasibinomial())
  m_adim <- svyglm(FI ~ x + s1 + s2 + s3 + yoksul, design = des, family = quasibinomial())
  dn <- regTermTest(m_rcs, ~ s1 + s2 + s3, method = "Wald")
  b <- coef(m_adim)
  V <- vcov(m_adim)
  z0 <- c(1, x_esik, rcs_baz(x_esik, gk), 0)
  z1 <- z0
  z1[length(z1)] <- 1
  e0 <- sum(z0 * b)
  e1 <- sum(z1 * b)
  g <- dlogis(e1) * z1 - dlogis(e0) * z0
  ci_or <- confint(m_adim)["yoksul", ]
  p_adim <- summary(m_adim)$coefficients["yoksul", 4]
  dp <- 100 * (plogis(e1) - plogis(e0))
  dp_se <- 100 * sqrt(as.numeric(t(g) %*% V %*% g))
  egri_test[[length(egri_test) + 1]] <- rbind(
    data.table(yil = as.character(yy), test = "dogrusal_olmama", n = nrow(dat), F = as.numeric(dn$Ftest), df1 = dn$df, df2 = dn$ddf, p = as.numeric(dn$p)),
    data.table(yil = as.character(yy), test = "esik_adimi_OR", n = nrow(dat), tahmin = exp(b[["yoksul"]]), alt = exp(ci_or[[1]]), ust = exp(ci_or[[2]]), p = p_adim),
    data.table(yil = as.character(yy), test = "esik_adimi_puan", n = nrow(dat), tahmin = dp, alt = dp - 1.96 * dp_se, ust = dp + 1.96 * dp_se, p = p_adim),
    cbind(yil = as.character(yy), adim_7(dat)), cbind(yil = as.character(yy), adim_parcali(dat)), fill = TRUE)
  Z <- cbind(1, izgara, rcs_baz(izgara, gk))
  eta <- as.numeric(Z %*% coef(m_rcs))
  se_eta <- sqrt(rowSums((Z %*% vcov(m_rcs)) * Z))
  egri_izgara[[length(egri_izgara) + 1]] <- data.table(yil = yy, goreli_gelir = exp(izgara), p = 100 * plogis(eta), alt = 100 * plogis(eta - 1.96 * se_eta), ust = 100 * plogis(eta + 1.96 * se_eta))
  fi <- dat[FI == 1]
  yg <- density(fi$x, weights = fi$HB040 / sum(fi$HB040), bw = bw.nrd0(fi$x), from = min(izgara), to = max(izgara), n = length(izgara))
  egri_yog[[length(egri_yog) + 1]] <- data.table(yil = yy, goreli_gelir = exp(yg$x), yogunluk_log = yg$y)
}
ev <- rbindlist(egri_veri[c(1, 3)])
ev[, y25 := as.integer(yil == 2025)]
m_yil <- svyglm(FI ~ (x + s1 + s2 + s3) * y25, design = svydesign(ids = ~1, weights = ~HB040, data = ev), family = quasibinomial())
yt_ <- regTermTest(m_yil, ~ y25 + x:y25 + s1:y25 + s2:y25 + s3:y25, method = "Wald")
yt_s <- regTermTest(m_yil, ~ x:y25 + s1:y25 + s2:y25 + s3:y25, method = "Wald")
egri_test <- rbindlist(c(egri_test, list(
  data.table(yil = "2023-2025", test = "yil_farki_egri", n = nrow(ev), F = as.numeric(yt_$Ftest), df1 = yt_$df, df2 = yt_$ddf, p = as.numeric(yt_$p)),
  data.table(yil = "2023-2025", test = "yil_farki_bicim", n = nrow(ev), F = as.numeric(yt_s$Ftest), df1 = yt_s$df, df2 = yt_s$ddf, p = as.numeric(yt_s$p)))), fill = TRUE)
fwrite(egri_test, "Results/H1_gelir_egrisi_testleri.csv")
fwrite(rbindlist(egri_izgara), file.path(fdir, "fig2b_gelir_egrisi.csv"))
fwrite(rbindlist(egri_yog), file.path(fdir, "fig2b_fi_yogunluk.csv"))
cat("\nGelir egrisi testleri (RCS 5 dugum, log goreli gelir; adim = egriye ek yoksul gostergesi):\n")
print(egri_test)
sure_ekle("H1", t0)

py <- "/Users/salim/veri-ortami/bin/python3"
if (!file.exists("Results/H2_ozet.json")) {
  t0 <- Sys.time()
  cat("ml.py calistiriliyor\n")
  st <- system2(py, "Codes/ml.py", stdout = "Results/log/ml_log.txt", stderr = "Results/log/ml_log.txt")
  if (st != 0) stop("ml.py hata verdi; Results/log/ml_log.txt")
  sure_ekle("ml.py", t0)
}
if (!file.exists("Results/H2_mlp.csv")) {
  t0 <- Sys.time()
  st <- system2(py, "Codes/mlp.py", stdout = "Results/log/mlp_log.txt", stderr = "Results/log/mlp_log.txt")
  if (st != 0) cat("mlp.py (istege bagli kol) calismadi; Results/log/mlp_log.txt\n")
  sure_ekle("mlp.py (GPU, MPS)", t0)
}
if (!file.exists("Results/H2_esiksiz_metrikler_GA.csv")) {
  t0 <- Sys.time()
  st <- system2(py, "Codes/esiksiz_ga.py", stdout = "Results/log/esiksiz_ga_log.txt", stderr = "Results/log/esiksiz_ga_log.txt")
  if (st != 0) stop("esiksiz_ga.py hata verdi; Results/log/esiksiz_ga_log.txt")
  sure_ekle("esiksiz_ga.py", t0)
}
if (!file.exists("Results/modeller/tahmin_uygula_denetim.csv")) {
  t0 <- Sys.time()
  st <- system2(py, c("Codes/tahmin_uygula.py", "--denetim"), stdout = "Results/log/tahmin_uygula_log.txt", stderr = "Results/log/tahmin_uygula_log.txt")
  if (st != 0) stop("tahmin_uygula.py denetimi tutmadi; Results/log/tahmin_uygula_log.txt")
  sure_ekle("tahmin_uygula.py denetimi", t0)
}

t0 <- Sys.time()
Sys.setenv(VECLIB_MAXIMUM_THREADS = "1", OMP_NUM_THREADS = "1")
plan(multisession, workers = 16)
obdir <- file.path(ddir, "onbellek")
dir.create(obdir, showWarnings = FALSE)
ns_bilesen <- function(x, df, ad) {
  B <- ns(x, df = df)
  L <- cbind(1, x)
  R <- B - L %*% qr.solve(L, B)
  sv <- svd(R)
  k <- df - 1
  Z <- sv$u[, seq_len(k), drop = FALSE] * sqrt(length(x))
  colnames(Z) <- paste0(ad, seq_len(k))
  as.data.table(Z)
}
irls <- function(X, y, w, b, tol = 1e-9, maxit = 30) {
  for (it in seq_len(maxit)) {
    mu <- plogis(drop(X %*% b))
    H <- crossprod(X, X * (w * mu * (1 - mu)))
    g <- crossprod(X, w * (y - mu))
    ok <- diag(H) > 1e-12
    st <- numeric(length(b))
    st[ok] <- tryCatch(solve(H[ok, ok, drop = FALSE], g[ok]), error = function(e) drop(MASS::ginv(H[ok, ok, drop = FALSE]) %*% g[ok]))
    b <- b + st
    if (max(abs(st)) < tol) break
  }
  attr(b, "iter") <- it
  b
}
mm_kur <- function(formul, dat, senaryo) {
  dv <- dat[, unique(c(all.vars(formul))), with = FALSE]
  mf <- model.frame(formul, dv, na.action = na.fail)
  tt <- terms(mf)
  X <- model.matrix(tt, mf)
  q <- qr(X)
  if (q$rank < ncol(X)) X <- X[, sort(q$pivot[seq_len(q$rank)]), drop = FALSE]
  y <- as.numeric(model.response(mf))
  xl <- .getXlevels(tt, mf)
  tx <- delete.response(tt)
  Xs <- lapply(senaryo, function(s) {
    nd <- copy(dv)
    for (v in names(s)) set(nd, j = v, value = rep(s[[v]], nrow(nd)))
    Z <- model.matrix(tx, model.frame(tx, nd, xlev = xl, na.action = na.fail))
    Z[, colnames(X), drop = FALSE]
  })
  deg <- which(Reduce(`|`, lapply(Xs, function(Z) colSums(abs(Z - X)) > 0)))
  list(X = X, y = y, Xd = lapply(Xs, function(Z) Z[, deg, drop = FALSE]), deg = deg, formul = formul)
}
p_hesap <- function(mus, w, grup = NULL) {
  out <- vapply(mus, function(mu) sum(w * mu) / sum(w), 0)
  names(out) <- paste0(names(mus), "|T")
  if (!is.null(grup)) {
    W <- rowsum(w, grup)
    for (s in names(mus)) {
      v <- rowsum(w * mus[[s]], grup) / W
      out <- c(out, setNames(drop(v), paste0(s, "|", rownames(v))))
    }
  }
  out
}
senaryo_mu <- function(m, b) {
  eta <- drop(m$X %*% b)
  Xdeg <- m$X[, m$deg, drop = FALSE]
  bd <- b[m$deg]
  list(eta = eta, mus = lapply(m$Xd, function(Z) plogis(eta + drop((Z - Xdeg) %*% bd))))
}
olc_cikar <- function(p, b, olcu, katsayi) {
  o <- olcu(p)
  if (length(katsayi)) o <- c(o, setNames(exp(b[katsayi]), paste0("OR_", katsayi)))
  o
}
gc_tahmin <- function(m, w, olcu, grup = NULL, katsayi = character(0), b0 = NULL) {
  if (is.null(b0)) b0 <- setNames(numeric(ncol(m$X)), colnames(m$X))
  b <- irls(m$X, m$y, w, b0)
  sm <- senaryo_mu(m, b)
  p <- p_hesap(sm$mus, w, grup)
  list(b = setNames(as.numeric(b), colnames(m$X)), iter = attr(b, "iter"), eta = sm$eta, mus = sm$mus, p = p, olc = olc_cikar(p, setNames(as.numeric(b), colnames(m$X)), olcu, katsayi))
}
var_toplam <- function(z, kume, tabaka = NULL) {
  z <- as.matrix(z)
  Tc <- rowsum(z, kume, reorder = FALSE)
  if (is.null(tabaka)) {
    nc <- nrow(Tc)
    Tc <- sweep(Tc, 2, colMeans(Tc))
    return(crossprod(Tc) * nc / (nc - 1))
  }
  th <- tabaka[!duplicated(kume)]
  V <- matrix(0, ncol(z), ncol(z))
  for (hh in unique(th)) {
    Th <- Tc[th == hh, , drop = FALSE]
    nh <- nrow(Th)
    if (nh > 1) V <- V + crossprod(sweep(Th, 2, colMeans(Th))) * nh / (nh - 1)
  }
  V
}
jakobyen <- function(f, p) {
  f0 <- f(p)
  J <- matrix(0, length(f0), length(p), dimnames = list(names(f0), names(p)))
  for (j in seq_along(p)) {
    hh <- 1e-6 * max(1, abs(p[j]))
    pp <- p
    pp[j] <- pp[j] + hh
    pm <- p
    pm[j] <- pm[j] - hh
    J[, j] <- (f(pp) - f(pm)) / (2 * hh)
  }
  J
}
gc_if <- function(m, w, r, olcu, grup = NULL, kume, tabaka = NULL, katsayi = character(0)) {
  X <- m$X
  mu <- plogis(r$eta)
  H <- crossprod(X, X * (w * mu * (1 - mu)))
  Hinv <- tryCatch(solve(H), error = function(e) MASS::ginv(H))
  U <- X * (w * (m$y - mu))
  gruplar <- c(list(T = rep(TRUE, nrow(X))), if (is.null(grup)) list() else lapply(split(seq_len(nrow(X)), grup), function(ii) seq_len(nrow(X)) %in% ii))
  Zl <- list()
  for (s in names(r$mus)) {
    ms <- r$mus[[s]]
    a <- w * ms * (1 - ms)
    for (g in names(gruplar)) {
      ig <- gruplar[[g]]
      Wg <- sum(w[ig])
      ps <- sum(w[ig] * ms[ig]) / Wg
      D <- colSums(X[ig, , drop = FALSE] * a[ig]) / Wg
      D[m$deg] <- colSums(m$Xd[[s]][ig, , drop = FALSE] * a[ig]) / Wg
      Zl[[paste0(s, "|", g)]] <- ig * w * (ms - ps) / Wg + drop(U %*% (Hinv %*% D))
    }
  }
  Z <- do.call(cbind, Zl)
  Z <- Z[, names(r$p), drop = FALSE]
  J <- jakobyen(olcu, r$p)
  zt <- Z %*% t(J)
  if (length(katsayi)) {
    zb <- U %*% Hinv[, match(katsayi, colnames(X)), drop = FALSE]
    zb <- sweep(zb, 2, exp(r$b[katsayi]), `*`)
    colnames(zb) <- paste0("OR_", katsayi)
    zt <- cbind(zt, zb)
  }
  Vk <- var_toplam(zt, kume, tabaka)
  Vb <- var_toplam(zt, seq_len(nrow(X)))
  Vcoef <- Hinv %*% var_toplam(U, kume, tabaka) %*% Hinv
  dimnames(Vcoef) <- list(colnames(X), colnames(X))
  list(se = sqrt(diag(Vk)), se_kumesiz = sqrt(diag(Vb)), Vcoef = Vcoef, V = Vk)
}

hane_2025 <- h[yil == 2025]
hane_id <- sort(unique(hane_2025$hane_kimlik))
n_hane <- length(hane_id)
B_ana <- 4000L
B_diger <- 2000L
set.seed(20261027)
M_boot <- matrix(0L, n_hane, B_ana)
for (b in seq_len(B_ana)) M_boot[, b] <- tabulate(sample.int(n_hane, n_hane - 1L, replace = TRUE), n_hane)
fac_hane <- rep(n_hane / (n_hane - 1), n_hane)
M_parca <- lapply(split(seq_len(B_ana), cut(seq_len(B_ana), 16, labels = FALSE)), function(cc) M_boot[, cc, drop = FALSE])
M_parca2 <- lapply(split(seq_len(B_diger), cut(seq_len(B_diger), 16, labels = FALSE)), function(cc) M_boot[, cc, drop = FALSE])
rm(M_boot)
boot_kayit <- list()
boot_gc <- function(anahtar, m, w, idx, olcu, b0, grup = NULL, katsayi = character(0), Mp = M_parca2, fac = fac_hane) {
  f <- file.path(obdir, paste0("boot_", anahtar, ".rds"))
  if (file.exists(f)) {
    Bm <- readRDS(f)
    boot_kayit[[anahtar]] <<- data.table(anahtar = anahtar, B = nrow(Bm), npar = ncol(m$X), iter_en_buyuk = max(Bm[, "iter"]), iter_sinira_ulasan = sum(Bm[, "iter"] >= 30))
    return(Bm)
  }
  t1 <- Sys.time()
  Xdeg <- m$X[, m$deg, drop = FALSE]
  res <- future_map(Mp, function(Mc) {
    out <- NULL
    for (j in seq_len(ncol(Mc))) {
      wb <- w * fac[idx] * Mc[idx, j]
      b <- irls(m$X, m$y, wb, b0, tol = 1e-8)
      eta <- drop(m$X %*% b)
      bd <- b[m$deg]
      mus <- lapply(m$Xd, function(Z) plogis(eta + drop((Z - Xdeg) %*% bd)))
      p <- p_hesap(mus, wb, grup)
      o <- olc_cikar(p, setNames(as.numeric(b), colnames(m$X)), olcu, katsayi)
      out <- rbind(out, c(o, iter = attr(b, "iter")))
    }
    out
  }, .options = furrr_options(seed = NULL, packages = "data.table"))
  Bm <- do.call(rbind, res)
  attr(Bm, "sure_sn") <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  saveRDS(Bm, f)
  boot_kayit[[anahtar]] <<- data.table(anahtar = anahtar, B = nrow(Bm), npar = ncol(m$X), iter_en_buyuk = max(Bm[, "iter"]), iter_sinira_ulasan = sum(Bm[, "iter"] >= 30))
  Bm
}
gc_ozet <- function(r, s, Bm, s_tab = NULL) {
  k <- names(r$olc)
  q <- function(x, pr) as.numeric(quantile(x, pr, na.rm = TRUE))
  B <- nrow(Bm)
  out <- data.table(olcu = k, tahmin = r$olc[k], se_if = s$se[k], se_kumesiz = s$se_kumesiz[k],
             se_boot = apply(Bm[, k, drop = FALSE], 2, sd, na.rm = TRUE),
             alt = apply(Bm[, k, drop = FALSE], 2, q, pr = 0.025), ust = apply(Bm[, k, drop = FALSE], 2, q, pr = 0.975),
             alt_if = r$olc[k] - 1.96 * s$se[k], ust_if = r$olc[k] + 1.96 * s$se[k],
             alt500 = apply(Bm[1:500, k, drop = FALSE], 2, q, pr = 0.025), ust500 = apply(Bm[1:500, k, drop = FALSE], 2, q, pr = 0.975),
             alt1000 = apply(Bm[1:1000, k, drop = FALSE], 2, q, pr = 0.025), ust1000 = apply(Bm[1:1000, k, drop = FALSE], 2, q, pr = 0.975),
             alt2000 = apply(Bm[1:min(B, 2000), k, drop = FALSE], 2, q, pr = 0.025), ust2000 = apply(Bm[1:min(B, 2000), k, drop = FALSE], 2, q, pr = 0.975),
             B = B)
  if (!is.null(s_tab)) out[, se_if_ibbs2 := s_tab$se[k]]
  out
}
gc_hizli <- function(formul, dat, w, senaryo, olcu, grup = NULL, kume = dat$hane_kimlik, tabaka = NULL) {
  m <- mm_kur(formul, dat, senaryo)
  ww <- dat[[w]]
  r <- gc_tahmin(m, ww, olcu, grup)
  s <- gc_if(m, ww, r, olcu, grup, kume = kume, tabaka = tabaka)
  list(m = m, r = r, s = s, w = ww)
}
mo_dosya <- "Results/model_ozetleri.txt"
cat("Model ozetleri (analiz.R)\n", format(Sys.time()), "\n", file = mo_dosya)
ozet_yaz <- function(baslik, nesne) {
  cat("\n\n==== ", baslik, " ====\n", file = mo_dosya, append = TRUE)
  cat(capture.output(print(nesne)), sep = "\n", file = mo_dosya, append = TRUE)
}
protokol <- list()
prot_ekle <- function(kontrol, olcut, sonuc, karar, model) protokol[[length(protokol) + 1]] <<- data.table(kontrol = kontrol, olcut = olcut, sonuc = sonuc, karar = karar, model = model)
wald_p <- function(sg, terim) as.numeric(regTermTest(sg, as.formula(paste("~", terim)), method = "Wald")$p)
fm <- function(x, d = 2) formatC(x, format = "f", digits = d)
agirlikli_ondalik <- function(x, w, k = 10) {
  o <- order(x)
  cw <- cumsum(w[o]) / sum(w)
  g <- integer(length(x))
  g[o] <- pmin(k, floor(cw * k - 1e-12) + 1L)
  g
}
al_test <- function(y, phat, w, kume, etiket_ad) {
  dec <- agirlikli_ondalik(phat, w)
  dd <- data.frame(r = y - phat, dec = factor(dec), kume = kume, w = w, y = y, phat = phat)
  des <- svydesign(ids = ~kume, weights = ~w, data = dd)
  sg <- svyglm(r ~ dec - 1, des)
  tt <- regTermTest(sg, ~dec, method = "Wald")
  kal <- as.data.table(dd)[, .(gozlenen = weighted.mean(y, w), tahmin = weighted.mean(phat, w), n = .N), keyby = dec]
  kal[, model := etiket_ad]
  list(F = as.numeric(tt$Ftest), df = tt$df, ddf = tt$ddf, p = as.numeric(tt$p), kalibrasyon = kal)
}
artik_grafik <- function(y, phat, x, w, dosya, xad) {
  png(dosya, width = 2400, height = 1100, res = 200)
  op <- par(mfrow = c(1, 2), mar = c(4, 4, 2, 1))
  for (k in 1:2) {
    z <- if (k == 1) phat else x
    b <- agirlikli_ondalik(z, w, 40)
    r <- as.data.table(data.frame(b, z, res = y - phat, w))[, .(z = weighted.mean(z, w), r = weighted.mean(res, w), se = sqrt(weighted.mean(res^2, w) / .N)), keyby = b]
    plot(r$z, r$r, pch = 16, cex = 0.7, xlab = if (k == 1) "Predicted probability" else xad, ylab = "Mean residual (binned)", ylim = range(c(r$r - 2 * r$se, r$r + 2 * r$se)))
    lines(r$z, 2 * r$se, col = "grey50")
    lines(r$z, -2 * r$se, col = "grey50")
    abline(h = 0, lty = 2)
  }
  par(op)
  dev.off()
}
ortusme <- function(dt, w, gruplar, tabaka_v, esik = 20) {
  dt <- copy(dt)
  dt[, .grp := do.call(paste, c(.SD, sep = "_")), .SDcols = gruplar]
  dt[, .tab := do.call(paste, c(.SD, sep = "_")), .SDcols = tabaka_v]
  hucre <- dcast(dt[, .N, by = .(.tab, .grp)], .tab ~ .grp, value.var = "N", fill = 0)
  gl <- setdiff(names(hucre), ".tab")
  hucre[, en_az := do.call(pmin, .SD), .SDcols = gl]
  ww <- dt[, .(ww = sum(get(w))), by = .tab]
  hucre <- merge(hucre, ww, by = ".tab")
  list(tabaka_sayisi = nrow(hucre), seyrek_tabaka = hucre[en_az < esik, .N], seyrek_pay = 100 * hucre[en_az < esik, sum(ww)] / hucre[, sum(ww)],
       satir_ortusen = dt$.tab %in% hucre[en_az >= esik, .tab])
}
bk_metin <- function(oz, k) paste0(k, " sinirlari: 500 [", fm(oz[olcu == k, alt500]), ", ", fm(oz[olcu == k, ust500]), "], 1000 [", fm(oz[olcu == k, alt1000]), ", ", fm(oz[olcu == k, ust1000]), "], 2000 [",
                                    fm(oz[olcu == k, alt2000]), ", ", fm(oz[olcu == k, ust2000]), "], ", oz$B[1], " [", fm(oz[olcu == k, alt]), ", ", fm(oz[olcu == k, ust]), "]")
bk_fark <- function(oz, k) oz[olcu == k, max(abs(c(alt1000 - alt2000, ust1000 - ust2000, alt2000 - alt, ust2000 - ust)))]

yt <- merge(d[yil == 2025 & FK070 >= 18 & f_kayit == 1, .(hane_kimlik, fert_kimlik, FB030, FK070, FK090, egitim5, FB100, FI010, FS020, FS030, FS050, FS060, et_tavuk_balik_siklik, gunluk_meyve, gunluk_sebze)],
            hane_2025[, .(hane_kimlik, FI, yoksul, goreli_esdeger_gelir, log_goreli_gelir, gelir_bandi, gelir_dilim5, HB030, HB031, hane_buyuklugu, n_cocuk, HB050, HH020)], by = "hane_kimlik")
kontrol_h3 <- nrow(yt)
cat("H3 yetiskin orneklemi:", kontrol_h3, "\n")
yt[, `:=`(grup = fcase(FI == 0, 1L, yoksul == 0, 2L, default = 3L),
          et_az = fifelse(et_tavuk_balik_siklik == 0, NA_integer_, as.integer(et_tavuk_balik_siklik == 1)),
          et_az_veg = as.integer(et_tavuk_balik_siklik <= 1),
          meyve_az = as.integer(gunluk_meyve == 0), sebze_az = as.integer(gunluk_sebze == 0),
          karsilanmayan_odeme = fifelse(FS050 %in% 1:2, as.integer(FS050 == 1 & FS060 %in% 1), NA_integer_),
          calisma7 = fcase(FI010 %in% 1:4, 1L, FI010 == 5, 2L, FI010 == 6, 3L, FI010 == 7, 4L, FI010 == 8, 5L, FI010 == 9, 6L, FI010 == 10, 7L, default = NA_integer_))]
yt[, `:=`(f_cins = factor(FK090), f_egit = factor(egitim5), f_bolge = factor(HB030), f_hb = factor(pmin(hane_buyuklugu, 7)), f_cocuk = factor(pmin(n_cocuk, 4)),
          f_medeni = factor(FB100), f_calisma = factor(calisma7), f_kronik = factor(FS020), f_gali = factor(FS030), f_htip = factor(HB050), f_mulk = factor(HH020),
          f_grup = factor(grup), f_band = factor(gelir_bandi), egitim3 = fcase(egitim5 <= 2, 1L, egitim5 <= 4, 2L, default = 3L))]
yt <- cbind(yt, ns_bilesen(yt$FK070, 3, "yas3_"), ns_bilesen(yt$FK070, 4, "yas4_"), ns_bilesen(yt$FK070, 5, "yas5_"))
eksik_h3 <- yt[, lapply(.SD, function(x) sum(is.na(x))), .SDcols = c("FK070", "f_cins", "f_egit", "f_bolge", "f_hb", "f_cocuk", "log_goreli_gelir", "f_medeni", "f_calisma", "f_kronik", "f_gali", "f_htip", "f_mulk", "et_az", "meyve_az", "sebze_az")]
print(eksik_h3)
fwrite(eksik_h3, "Results/log/H3_eksik_veri.csv")
h3_grup_n <- yt[, .(n = .N, agirlikli_pay = 100 * sum(FB030) / yt[, sum(FB030)], et_olay = sum(et_az, na.rm = TRUE), meyve_olay = sum(meyve_az), sebze_olay = sum(sebze_az), vejetaryen = sum(et_tavuk_balik_siklik == 0)), keyby = grup]
print(h3_grup_n)
fwrite(h3_grup_n, "Results/H3_grup_sayilari.csv")

hn <- copy(hane_2025)
hn[, `:=`(grup = fcase(FI == 0, 1L, yoksul == 0, 2L, default = 3L), saglik_yuk = as.integer(MODUL1_H_1 %in% 1 | MODUL1_H_3 %in% 1))]
hn[, `:=`(f_cins = factor(reis_cinsiyet), f_egit = factor(fifelse(is.na(reis_egitim), egitim_max, reis_egitim)), f_bolge = factor(HB030), f_hb = factor(pmin(hane_buyuklugu, 7)), f_cocuk = factor(pmin(n_cocuk, 4)),
          f_grup = factor(grup), f_band = factor(gelir_bandi), f_htip = factor(HB050), f_mulk = factor(HH020), f_kronik = factor(pmin(n_kronik, 3)), f_gali = factor(pmin(n_gali, 2)),
          f_medeni = factor(fifelse(is.na(reis_medeni), 9L, as.integer(reis_medeni))), f_calisma = factor(fifelse(is.na(reis_calisma7), 9L, reis_calisma7)), egitim3 = fcase(reis_egitim <= 2, 1L, reis_egitim <= 4, 2L, default = 3L), FK070 = reis_yas)]
hn <- hn[!is.na(f_egit)]
hn <- cbind(hn, ns_bilesen(hn$reis_yas, 3, "yas3_"), ns_bilesen(hn$reis_yas, 4, "yas4_"), ns_bilesen(hn$reis_yas, 5, "yas5_"))
cat("H3 hane orneklemi:", nrow(hn), " saglik_yuk olay:", sum(hn$saglik_yuk), "\n")
sure_ekle("H3 hazirlik", t0)

t0 <- Sys.time()
yas_terim <- c(dogrusal = "FK070", df3 = "FK070 + yas3_1 + yas3_2", df4 = "FK070 + yas4_1 + yas4_2 + yas4_3", df5 = "FK070 + yas5_1 + yas5_2 + yas5_3 + yas5_4")
cekirdek <- "f_cins + f_egit + f_bolge + f_hb + f_cocuk"
gelir_terim <- "log_goreli_gelir + gel3_1 + gel3_2"
sen_A <- list(A0 = list(A = 0), A1 = list(A = 1))
olcu_A <- function(p) c(p0 = 100 * unname(p["A0|T"]), p1 = 100 * unname(p["A1|T"]), PD = 100 * unname(p["A1|T"] - p["A0|T"]), PR = unname(p["A1|T"] / p["A0|T"]))
h3_y <- c("et_az", "meyve_az", "sebze_az")
h3_aday <- c(FB100 = "f_medeni", FI010 = "f_calisma", FS020 = "f_kronik", FS030 = "f_gali", HB050 = "f_htip", HH020 = "f_mulk")
h3_veri <- function(kar, v, tab = yt) {
  dt <- if (kar == "C1") tab[yoksul == 0 & !is.na(get(v))] else tab[FI == 1 & !is.na(get(v))]
  dt <- copy(dt)
  dt[, A := as.integer(grup == 2)]
  if (kar == "C1") dt <- cbind(dt, ns_bilesen(dt$log_goreli_gelir, 3, "gel3_"))
  dt
}
sag_kur <- function(kar, yas, ek = character(0)) paste(c("A", yas, cekirdek, if (kar == "C1") gelir_terim, ek), collapse = " + ")
esnek_yap <- function(sag) paste("A * (", sub("^A \\+ ", "", sag), ")")

h3_protokol <- function(kar, ys, tab, etiket_on) {
  w <- if (etiket_on == "hane") "HB040" else "FB030"
  ff <- rbindlist(lapply(ys, function(v) {
    dt <- h3_veri(kar, v, tab)
    res <- rbindlist(lapply(names(yas_terim), function(k) {
      g <- gc_hizli(as.formula(paste(v, "~", sag_kur(kar, yas_terim[k]))), dt, w, sen_A, olcu_A)
      data.table(karsilastirma = kar, sonuc = v, yas = k, PD = g$r$olc[["PD"]], PR = g$r$olc[["PR"]], se_PD = g$s$se[["PD"]])
    }))
    des <- svydesign(ids = ~hane_kimlik, weights = as.formula(paste0("~", w)), data = dt)
    sg <- svyglm(as.formula(paste(v, "~", sag_kur(kar, yas_terim["df4"]))), des, family = quasibinomial())
    res[, p_dogrusal_disi_df4 := wald_p(sg, "yas4_1 + yas4_2 + yas4_3")]
    res
  }))
  ff[, fark_df4 := PD - PD[yas == "df4"], by = sonuc]
  yk <- ff[, .(dogrusal = p_dogrusal_disi_df4[1] >= 0.10 & abs(fark_df4[yas == "dogrusal"]) < 0.2), by = sonuc]
  yas <- if (all(yk$dogrusal)) yas_terim["dogrusal"] else yas_terim["df4"]
  for (v in ys) prot_ekle("2. Yas bicimi", "Dogrusal disi bilesen p >= 0,10 ve PD farki < 0,2 puan ise dogrusal; aksi halde 4 df dogal spline (talimat varsayilani)",
                          paste0("p = ", formatC(ff[sonuc == v, p_dogrusal_disi_df4[1]], format = "g", digits = 3), "; PD dogrusal - df4 = ", fm(ff[sonuc == v & yas == "dogrusal", fark_df4], 3),
                                 "; df3 = ", fm(ff[sonuc == v & yas == "df3", fark_df4], 3), "; df5 = ", fm(ff[sonuc == v & yas == "df5", fark_df4], 3)),
                          if (yas == yas_terim["df4"]) "Yas 4 df dogal spline" else "Yas dogrusal", paste(etiket_on, kar, v))
  ad <- rbindlist(lapply(ys, function(v) {
    dt <- h3_veri(kar, v, tab)
    g0 <- gc_hizli(as.formula(paste(v, "~", sag_kur(kar, yas))), dt, w, sen_A, olcu_A)
    rbindlist(lapply(names(h3_aday), function(a) {
      g1 <- gc_hizli(as.formula(paste(v, "~", sag_kur(kar, yas, h3_aday[[a]]))), dt, w, sen_A, olcu_A)
      data.table(karsilastirma = kar, sonuc = v, aday = a, PD_once = g0$r$olc[["PD"]], PD_sonra = g1$r$olc[["PD"]], PR_once = g0$r$olc[["PR"]], PR_sonra = g1$r$olc[["PR"]])
    }))
  }))
  ad[, `:=`(PD_degisim = PD_sonra - PD_once, PR_goreli_degisim = 100 * (PR_sonra - PR_once) / PR_once)]
  ad[, karar := fifelse(abs(PD_degisim) >= 0.5 | abs(PR_goreli_degisim) >= 10, "Girer", "Girmez")]
  secilen <- unique(ad[karar == "Girer", aday])
  for (v in ys) prot_ekle("3. Aday kovaryatlar", "Degisim olcutu: PD'de >= 0,5 puan veya PR'de >= %10 degisim; p degerine dayali secim yok; secilenler karsilastirmanin butun sonuclarina eklenir",
                          paste(ad[sonuc == v, paste0(aday, " dPD ", fm(PD_degisim), " dPR% ", fm(PR_goreli_degisim, 1))], collapse = "; "),
                          if (length(secilen)) paste("Girenler:", paste(secilen, collapse = ", ")) else "Hicbiri girmedi", paste(etiket_on, kar, v))
  list(ff = ff, aday = ad, yas = yas, secilen = secilen, ek = unname(h3_aday[secilen]))
}

h3_tab <- list()
h3_g <- list()
h3_tani <- list()
kaba_ortusme <- list()
h3_calistir <- function(kar, ys, tab, etiket_on, pr) {
  w <- if (etiket_on == "hane") "HB040" else "FB030"
  for (v in ys) {
    dt <- h3_veri(kar, v, tab)
    ix <- match(dt$hane_kimlik, hane_id)
    des <- svydesign(ids = ~hane_kimlik, weights = as.formula(paste0("~", w)), data = dt)
    son <- sag_kur(kar, pr$yas, pr$ek)
    modeller <- c(minimal = paste(c("A", pr$yas, "f_cins", if (kar == "C1") gelir_terim), collapse = " + "), cekirdek = sag_kur(kar, pr$yas), nihai = son, esnek = esnek_yap(son))
    gl <- list()
    for (mk in names(modeller)) {
      g <- gc_hizli(as.formula(paste(v, "~", modeller[[mk]])), dt, w, sen_A, olcu_A, tabaka = NULL)
      gl[[mk]] <- g
    }
    em_t <- c(bolge = "A:f_bolge", cinsiyet = "A:f_cins")
    if (kar == "C1") em_t <- c(em_t, gelir = "A:log_goreli_gelir + A:gel3_1 + A:gel3_2")
    em <- sapply(em_t, function(tt) {
      sgz <- svyglm(as.formula(paste(v, "~", son, "+", tt)), des, family = quasibinomial())
      wald_p(sgz, tt)
    })
    names(em) <- names(em_t)
    ana <- if (any(em < 0.01)) "esnek" else "nihai"
    prot_ekle("5. Model bicimi", "Grup x bolge, grup x cinsiyet, grup x gelir (C1) tasarim Wald; p < 0,01 heterojenlik varsa tam etkilesimli (esnek) model ana model",
              paste0("p: ", paste(names(em), formatC(em, format = "g", digits = 3), collapse = ", ")), if (ana == "esnek") "Heterojenlik var: esnek model ana model" else "Heterojenlik yok: ana etkili model ana model", paste(etiket_on, kar, v))
    for (mk in names(modeller)) {
      g <- gl[[mk]]
      Bm <- boot_gc(paste0("h3_", etiket_on, "_", kar, "_", v, "_", mk, "_B", if (mk == ana) B_ana else B_diger), g$m, g$w, ix, olcu_A, g$r$b, Mp = if (mk == ana) M_parca else M_parca2)
      s_tab <- if (mk == ana) gc_if(g$m, g$w, g$r, olcu_A, kume = dt$hane_kimlik, tabaka = dt$HB031) else NULL
      h3_tab[[paste(etiket_on, kar, v, mk)]] <<- gc_ozet(g$r, g$s, Bm, s_tab)[, `:=`(duzey = etiket_on, karsilastirma = kar, sonuc = v, model = mk, ana_model = mk == ana, n = nrow(dt), olay = sum(dt[[v]]),
                                                                                   n_A1 = sum(dt$A), n_A0 = sum(1 - dt$A), npar = ncol(g$m$X), sure_boot_sn = attr(Bm, "sure_sn"))]
    }
    h3_g[[paste(etiket_on, kar, v)]] <<- list(g = gl[[ana]], ana = ana, dt = dt)
    lpm <- svyglm(as.formula(paste(v, "~", son)), des, family = gaussian())
    h3_tab[[paste(etiket_on, kar, v, "lpm")]] <<- data.table(olcu = "PD", tahmin = 100 * unname(coef(lpm)["A"]), se_if = 100 * unname(SE(lpm)["A"]), duzey = etiket_on, karsilastirma = kar, sonuc = v, model = "lpm", ana_model = FALSE, n = nrow(dt))
    ozet_yaz(paste("H3", etiket_on, kar, v, "ana lojistik (", ana, ")"), summary(svyglm(as.formula(paste(v, "~", modeller[[ana]])), des, family = quasibinomial())))
    gv <- if (kar == "C1") c("gelir_bandi", "f_bolge", "egitim3") else c("f_bolge", "egitim3", "f_cins")
    ort <- ortusme(dt, w, "A", gv)
    kaba_ortusme[[paste(etiket_on, kar, v)]] <<- data.table(model = paste(etiket_on, kar, v), tabakalama = paste(gv, collapse = " x "), tabaka = ort$tabaka_sayisi, seyrek_tabaka = ort$seyrek_tabaka, seyrek_nufus_payi = ort$seyrek_pay)
    pd_ort <- NA_real_
    if (ort$seyrek_tabaka > 0) {
      go <- gc_hizli(as.formula(paste(v, "~", modeller[[ana]])), dt[ort$satir_ortusen], w, sen_A, olcu_A)
      pd_ort <- go$r$olc[["PD"]]
      h3_tab[[paste(etiket_on, kar, v, "ortusen")]] <<- data.table(olcu = names(go$r$olc), tahmin = go$r$olc, se_if = go$s$se[names(go$r$olc)], duzey = etiket_on, karsilastirma = kar, sonuc = v, model = "ortusen_tabakalar", ana_model = FALSE, n = sum(ort$satir_ortusen))
    }
    prot_ekle("4. Ortusme ve pozitiflik", paste0("Grup (A) x ", paste(gv, collapse = " x "), " tabakalarinda agirliksiz n < 20"),
              paste0(ort$tabaka_sayisi, " tabakanin ", ort$seyrek_tabaka, "'i seyrek (nufusun %", fm(ort$seyrek_pay, 1), ")", if (!is.na(pd_ort)) paste0("; ortusen tabakalarla PD ", fm(pd_ort), " (tum ", fm(gl[[ana]]$r$olc[["PD"]]), ")") else ""),
              "Ana tahmin tum nufusa standardize; seyrek tabaka varsa ortusen tabakalarla sinirli tahmin duyarlilik", paste(etiket_on, kar, v))
    g <- gl[[ana]]
    phat <- plogis(g$r$eta)
    al <- al_test(dt[[v]], phat, g$w, dt$hane_kimlik, paste(etiket_on, kar, v, ana))
    fwrite(al$kalibrasyon, paste0("Results/log/kalibrasyon_h3_", etiket_on, "_", kar, "_", v, ".csv"))
    artik_grafik(dt[[v]], phat, dt$FK070, g$w, paste0("Results/log/artik_h3_", etiket_on, "_", kar, "_", v, ".png"), "Age")
    prot_ekle("6. Uyum iyiligi", "Archer-Lemeshow F (anket, onda birlik gruplar) ve kalibrasyon",
              paste0("F = ", fm(al$F), " (", al$df, ", ", fm(al$ddf, 0), "), p = ", formatC(al$p, format = "g", digits = 3), "; en buyuk |gozlenen - tahmin| ", fm(100 * max(abs(al$kalibrasyon$gozlenen - al$kalibrasyon$tahmin))), " puan"),
              if (al$p >= 0.05) "Uyum yeterli" else "Test reddetti; kalibrasyon farki raporlandi, esnek model ile karsilastirma tabloda", paste(etiket_on, kar, v))
    ne <- sum(dt[[v]])
    npar <- ncol(g$m$X)
    prot_ekle("7. Ayrisma ve seyreklik", "min(olay, olaysiz) / parametre >= 10",
              paste0("olay ", ne, ", olaysiz ", nrow(dt) - ne, ", parametre ", npar, ", oran ", fm(min(ne, nrow(dt) - ne) / npar, 1), "; IRLS yineleme ", g$r$iter),
              if (min(ne, nrow(dt) - ne) / npar >= 10) "Yeterli" else "Seyrek: minimal model duyarlilik olarak one cikarilir", paste(etiket_on, kar, v))
    deff <- (g$s$se[["PD"]] / g$s$se_kumesiz[["PD"]])^2
    prot_ekle("8. Kumeleme", "Hane kumelemesinin tasarim etkisi (PD)", paste0("SE kumeli ", fm(g$s$se[["PD"]], 3), ", kumesiz ", fm(g$s$se_kumesiz[["PD"]], 3), ", tasarim etkisi ", fm(deff)), "Hane kumelemesi korunur", paste(etiket_on, kar, v))
    oz <- h3_tab[[paste(etiket_on, kar, v, ana)]]
    h3_tani[[paste(etiket_on, kar, v)]] <<- data.table(duzey = etiket_on, karsilastirma = kar, sonuc = v, yas = if (pr$yas == yas_terim["df4"]) "4 df natural spline" else "linear",
                                                       ek_kovaryat = if (length(pr$secilen)) paste(pr$secilen, collapse = ", ") else "none", em_p_bolge = em[["bolge"]], em_p_cinsiyet = em[["cinsiyet"]],
                                                       em_p_gelir = if ("gelir" %in% names(em)) em[["gelir"]] else NA_real_, ana_model = ana, al_F = al$F, al_p = al$p,
                                                       al_maks_fark = 100 * max(abs(al$kalibrasyon$gozlenen - al$kalibrasyon$tahmin)), olay = ne, olaysiz = nrow(dt) - ne, npar = npar,
                                                       epp = min(ne, nrow(dt) - ne) / npar, deff = deff, seyrek_tabaka_pay = ort$seyrek_pay, boot_oynama = bk_fark(oz, "PD"), B = oz$B[1])
    prot_ekle("9. Bootstrap yakinsamasi", "1.000 / 2.000 / 4.000 tekrarda PD sinirlari 0,1 puandan az oynamali", bk_metin(oz, "PD"),
              if (bk_fark(oz, "PD") <= 0.1) "Yeterli (4.000 tekrar)" else paste0("En buyuk oynama ", fm(bk_fark(oz, "PD")), " puan: Monte Carlo hatasi duzeyinde, 4.000 tekrar korundu"), paste(etiket_on, kar, v))
  }
}
pr_C1 <- h3_protokol("C1", h3_y, yt, "yetiskin")
pr_C2 <- h3_protokol("C2", h3_y, yt, "yetiskin")
pr_C1h <- h3_protokol("C1", "saglik_yuk", hn, "hane")
pr_C2h <- h3_protokol("C2", "saglik_yuk", hn, "hane")
fwrite(rbindlist(list(pr_C1$ff, pr_C2$ff, pr_C1h$ff[, duzey := "hane"], pr_C2h$ff[, duzey := "hane"]), fill = TRUE), "Results/log/H3_yas_bicimi.csv")
kov_sec <- rbindlist(list(pr_C1$aday[, duzey := "yetiskin"], pr_C2$aday[, duzey := "yetiskin"], pr_C1h$aday[, duzey := "hane"], pr_C2h$aday[, duzey := "hane"]))
fwrite(kov_sec, "Results/H3_kovaryat_secimi.csv")
print(kov_sec[, .(duzey, karsilastirma, sonuc, aday, PD_degisim = round(PD_degisim, 2), PR_goreli_degisim = round(PR_goreli_degisim, 1), karar)])
for (k in c("pr_C1", "pr_C2", "pr_C1h", "pr_C2h")) cat(k, "yas:", get(k)$yas, " secilen:", paste(get(k)$secilen, collapse = ", "), "\n")
h3_calistir("C1", h3_y, yt, "yetiskin", pr_C1)
h3_calistir("C2", h3_y, yt, "yetiskin", pr_C2)
h3_calistir("C1", "saglik_yuk", hn, "hane", pr_C1h)
h3_calistir("C2", "saglik_yuk", hn, "hane", pr_C2h)
sure_ekle("H3 ana karsilastirmalar (protokol + bootstrap)", t0)

t0 <- Sys.time()
h3_ek <- function(ad, v, dt, w, sag, senaryo, olcu) {
  ix <- match(dt$hane_kimlik, hane_id)
  g <- gc_hizli(as.formula(paste(v, "~", sag)), dt, w, senaryo, olcu)
  Bm <- boot_gc(paste0("h3ek_", ad, "_", v), g$m, g$w, ix, olcu, g$r$b, Mp = M_parca2)
  gc_ozet(g$r, g$s, Bm)[, `:=`(analiz = ad, sonuc = v, n = nrow(dt), olay = sum(dt[[v]]), npar = ncol(g$m$X), sure_boot_sn = attr(Bm, "sure_sn"))]
}
lv_g <- levels(yt$f_grup)
sen_G <- setNames(lapply(lv_g, function(k) list(f_grup = factor(k, levels = lv_g))), paste0("G", lv_g))
olcu_G <- function(p) {
  p1 <- unname(p["G1|T"])
  p2 <- unname(p["G2|T"])
  p3 <- unname(p["G3|T"])
  c(p_G1 = 100 * p1, p_G2 = 100 * p2, p_G3 = 100 * p3, PD_G2_G1 = 100 * (p2 - p1), PD_G3_G1 = 100 * (p3 - p1), PD_G2_G3 = 100 * (p2 - p3), PR_G2_G1 = p2 / p1, PR_G3_G1 = p3 / p1, konum = (p2 - p1) / (p3 - p1))
}
lv_b <- levels(yt$f_band)
sen_B <- setNames(lapply(lv_b, function(k) list(f_band = factor(k, levels = lv_b))), paste0("B", lv_b))
olcu_B <- function(p) {
  o <- 100 * unname(p[paste0("B", lv_b, "|T")])
  names(o) <- paste0("p_B", lv_b)
  c(o, setNames(o[-1] - o[1], paste0("PD_B", lv_b[-1], "_B1")))
}
ek_C2 <- unname(h3_aday[pr_C2$secilen])
ek_C2h <- unname(h3_aday[pr_C2h$secilen])
h3_ekler <- list()
for (v in h3_y) {
  dt <- yt[!is.na(get(v))]
  h3_ekler[[paste("C0", v)]] <- h3_ek("C0_uc_grup", v, dt, "FB030", paste(c("f_grup", pr_C2$yas, cekirdek, ek_C2), collapse = " + "), sen_G, olcu_G)
  dt <- yt[FI == 1 & !is.na(get(v))]
  h3_ekler[[paste("C3", v)]] <- h3_ek("C3_gelir_bandi", v, dt, "FB030", paste(c("f_band", pr_C2$yas, cekirdek, ek_C2), collapse = " + "), sen_B, olcu_B)
}
h3_ekler[["C0 saglik_yuk"]] <- h3_ek("C0_uc_grup_hane", "saglik_yuk", hn, "HB040", paste(c("f_grup", pr_C2h$yas, cekirdek, ek_C2h), collapse = " + "), sen_G, olcu_G)
h3_ekler[["C3 saglik_yuk"]] <- h3_ek("C3_gelir_bandi_hane", "saglik_yuk", hn[FI == 1], "HB040", paste(c("f_band", pr_C2h$yas, cekirdek, ek_C2h), collapse = " + "), sen_B, olcu_B)
for (kar in c("C1", "C2")) {
  pr <- if (kar == "C1") pr_C1 else pr_C2
  dt <- h3_veri(kar, "et_az_veg", yt)
  h3_ekler[[paste(kar, "veg")]] <- h3_ek(paste0(kar, "_vejetaryen_dahil"), "et_az_veg", dt, "FB030", sag_kur(kar, pr$yas, pr$ek), sen_A, olcu_A)
  dt <- h3_veri(kar, "karsilanmayan_odeme", yt)
  h3_ekler[[paste(kar, "karsilanmayan")]] <- h3_ek(paste0(kar, "_karsilanmayan_odeme_minimal"), "karsilanmayan_odeme", dt, "FB030", paste(c("A", "FK070", "f_cins", if (kar == "C1") "log_goreli_gelir"), collapse = " + "), sen_A, olcu_A)
}
h3_ekler <- rbindlist(h3_ekler, fill = TRUE)
fwrite(h3_ekler, "Results/H3_ek_gcomp_sonuclari.csv")
h3_tab <- rbindlist(h3_tab, fill = TRUE)
fwrite(h3_tab, "Results/H3_gcomp_sonuclari.csv")
fwrite(rbindlist(kaba_ortusme), "Results/H3_ortusme_kaba_kontroller.csv")
h3_tani <- rbindlist(h3_tani)
fwrite(h3_tani, "Results/H3_model_tanilari.csv")
fwrite(rbindlist(protokol), "Results/model_protokolu.csv")
print(h3_tab[ana_model == TRUE & olcu %in% c("p0", "p1", "PD", "PR"), .(duzey, karsilastirma, sonuc, olcu, tahmin = round(tahmin, 2), alt = round(alt, 2), ust = round(ust, 2), se_if = round(se_if, 3), se_boot = round(se_boot, 3), B)])
print(h3_ekler[olcu %in% c("p_G1", "p_G2", "p_G3", "konum", "PD_G2_G3") | grepl("^p_B", olcu), .(analiz, sonuc, olcu, tahmin = round(tahmin, 2), alt = round(alt, 2), ust = round(ust, 2))])
sure_ekle("H3 ek analizler", t0)

t0 <- Sys.time()
h3_ham_hesap <- function(dt, v, w, duzey) {
  dt <- dt[!is.na(get(v))]
  idx <- match(dt$hane_kimlik, hane_id)
  ww <- dt[[w]]
  yy <- as.numeric(dt[[v]])
  G <- cbind(G1 = dt$grup == 1L, G1_yoksul_degil = dt$grup == 1L & dt$yoksul == 0, G2 = dt$grup == 2L, G3 = dt$grup == 3L) * 1
  nok <- colSums(G * (ww * yy)) / colSums(G * ww)
  rp <- do.call(rbind, lapply(M_parca2, function(Mc) {
    Wb <- (ww * fac_hane[idx]) * Mc[idx, , drop = FALSE]
    t(crossprod(G * yy, Wb) / crossprod(G, Wb))
  }))
  q <- function(x) as.numeric(quantile(x, c(0.025, 0.975)))
  out <- list()
  for (g in colnames(G)) out[[g]] <- data.table(duzey = duzey, sonuc = v, satir = "grup", ad = g, n = sum(G[, g]), olay = sum(G[, g] * yy), tahmin = 100 * nok[[g]], alt = 100 * q(rp[, g])[1], ust = 100 * q(rp[, g])[2])
  for (kr in list(c("C1", "G1_yoksul_degil"), c("C2", "G3"))) {
    ref <- kr[2]
    sec <- G[, "G2"] == 1 | G[, ref] == 1
    d2 <- dt[sec]
    d2[, A := as.integer(grup == 2L)]
    sg <- svyglm(as.formula(paste(v, "~ A")), svydesign(ids = ~hane_kimlik, weights = as.formula(paste0("~", w)), data = d2))
    fk <- 100 * (nok[["G2"]] - nok[[ref]])
    stopifnot(abs(100 * coef(sg)[["A"]] - fk) < 1e-8)
    se_l <- 100 * SE(sg)[["A"]]
    out[[paste(kr[1], "fark")]] <- data.table(duzey = duzey, sonuc = v, satir = "fark", ad = kr[1], referans = ref, n = sum(sec), olay = sum(yy[sec]), tahmin = fk, alt = 100 * q(rp[, "G2"] - rp[, ref])[1], ust = 100 * q(rp[, "G2"] - rp[, ref])[2],
                                              se_lin = se_l, alt_lin = fk - 1.96 * se_l, ust_lin = fk + 1.96 * se_l, p_referans = 100 * nok[[ref]], p_G2 = 100 * nok[["G2"]])
    out[[paste(kr[1], "oran")]] <- data.table(duzey = duzey, sonuc = v, satir = "oran", ad = kr[1], referans = ref, n = sum(sec), olay = sum(yy[sec]), tahmin = nok[["G2"]] / nok[[ref]],
                                              alt = q(rp[, "G2"] / rp[, ref])[1], ust = q(rp[, "G2"] / rp[, ref])[2])
  }
  rbindlist(out, fill = TRUE)
}
h3_ham <- rbindlist(c(lapply(h3_y, function(v) h3_ham_hesap(yt, v, "FB030", "yetiskin")), list(h3_ham_hesap(hn, "saglik_yuk", "HB040", "hane"))), fill = TRUE)
h3_ham[, B := B_diger]
for (i in which(h3_ham$satir == "fark")) {
  r <- h3_ham[i]
  stopifnot(r$n == h3_tab[duzey == r$duzey & karsilastirma == r$ad & sonuc == r$sonuc & ana_model == TRUE, n[1]])
}
fwrite(h3_ham, "Results/H3_ham_oranlar.csv")
print(h3_ham[, .(duzey, sonuc, satir, ad, n, olay, tahmin = round(tahmin, 2), alt = round(alt, 2), ust = round(ust, 2))])
sure_ekle("H3 ham oranlar", t0)

simdir <- file.path(ddir, "simulasyon")
if (!file.exists(file.path(simdir, "simulasyon_ozet.csv"))) {
  if (!file.exists(file.path(simdir, "pilot", "simulasyon_bilgi.json"))) {
    t0 <- Sys.time()
    st <- system2(py, c("Codes/simulasyon.py", "pilot"), stdout = "Results/log/simulasyon_pilot_log.txt", stderr = "Results/log/simulasyon_pilot_log.txt")
    if (st != 0) stop("simulasyon.py pilot hata verdi")
    dir.create(file.path(simdir, "pilot"), showWarnings = FALSE)
    for (f in list.files(simdir, full.names = TRUE)) if (!dir.exists(f)) file.rename(f, file.path(simdir, "pilot", basename(f)))
    sure_ekle("simulasyon pilot (50 tekrar)", t0)
  }
  t0 <- Sys.time()
  st <- system2(py, c("Codes/simulasyon.py", "tam"), stdout = "Results/log/simulasyon_log.txt", stderr = "Results/log/simulasyon_log.txt")
  if (st != 0) stop("simulasyon.py hata verdi; Results/log/simulasyon_log.txt")
  sure_ekle("simulasyon tam", t0)
}
if (!file.exists("Results/S3_aralik_kapsamasi.csv")) {
  t0 <- Sys.time()
  st <- system2(py, "Codes/s3_aralik.py", stdout = "Results/log/s3_aralik_log.txt", stderr = "Results/log/s3_aralik_log.txt")
  if (st != 0) stop("s3_aralik.py hata verdi; Results/log/s3_aralik_log.txt")
  sure_ekle("S3 aralik yontemleri (yuzdelik, basic, BCa)", t0)
}
sim_ozet <- fread(file.path(simdir, "simulasyon_ozet.csv"))
sim_senaryo <- fread(file.path(simdir, "senaryo_tablosu.csv"))

t0 <- Sys.time()
etk <- fromJSON("Codes/etiketler.json", simplifyVector = TRUE)
deg_et <- function(v) if (is.null(etk$degisken[[v]])) v else etk$degisken[[v]]
kat_et <- function(v, k) {
  tb <- if (is.null(etk$kategori_esleme[[v]])) v else etk$kategori_esleme[[v]]
  lab <- etk$kategori[[tb]][[as.character(k)]]
  if (is.null(lab)) as.character(k) else lab
}
sifir <- function(x, d) { x <- round(x, d); x[!is.na(x) & x == 0] <- 0; x }
f1 <- function(x) formatC(sifir(x, 1), format = "f", digits = 1, big.mark = ",")
f2 <- function(x) formatC(sifir(x, 2), format = "f", digits = 2, big.mark = ",")
nfmt <- function(n) formatC(n, format = "d", big.mark = ",")
ga <- function(e, l, u, d = 1) paste0(formatC(sifir(e, d), format = "f", digits = d), " (", formatC(sifir(l, d), format = "f", digits = d), ", ", formatC(sifir(u, d), format = "f", digits = d), ")")
pfmt <- function(p) fifelse(is.na(p), "", fifelse(p < 0.001, "<0.001", formatC(p, format = "f", digits = 3)))
yazi_tipi_t <- "Times New Roman"
tablo_bicim <- function(ft, notlar = character(0), grup_satir = integer(0)) {
  ft <- font(ft, fontname = yazi_tipi_t, part = "all")
  ft <- fontsize(ft, size = 9, part = "all")
  ft <- border_remove(ft)
  ust <- fp_border(color = "black", width = 1)
  ince <- fp_border(color = "black", width = 0.5)
  ft <- hline_top(ft, border = ust, part = "header")
  ft <- hline_bottom(ft, border = ince, part = "header")
  ft <- hline_bottom(ft, border = ust, part = "body")
  ft <- bold(ft, part = "header")
  ft <- align(ft, align = "center", part = "header")
  ft <- align(ft, j = 1, align = "left", part = "all")
  ft <- valign(ft, valign = "center", part = "header")
  ft <- padding(ft, padding.top = 1, padding.bottom = 1, part = "all")
  if (length(grup_satir)) ft <- bold(ft, i = grup_satir, j = 1, part = "body")
  for (k in seq_along(notlar)) ft <- add_footer_lines(ft, values = notlar[k])
  if (length(notlar)) {
    ft <- fontsize(ft, size = 8, part = "footer")
    ft <- font(ft, fontname = yazi_tipi_t, part = "footer")
  }
  ft <- autofit(ft)
  ft
}
simge_re <- "(_|\\^)\\{([^}]*)\\}"
duz <- function(x) gsub(simge_re, "\\2", x)
parcala <- function(s) {
  m <- gregexpr(simge_re, s, perl = TRUE)[[1]]
  bas <- c(1, m + attr(m, "match.length"))
  out <- list()
  for (k in seq_along(m)) {
    if (m[k] > bas[k]) out[[length(out) + 1]] <- as_chunk(substr(s, bas[k], m[k] - 1))
    tok <- substr(s, m[k], m[k] + attr(m, "match.length")[k] - 1)
    ic <- sub(simge_re, "\\2", tok)
    out[[length(out) + 1]] <- if (substr(tok, 1, 1) == "_") as_sub(ic) else as_sup(ic)
  }
  if (bas[length(bas)] <= nchar(s)) out[[length(out) + 1]] <- as_chunk(substr(s, bas[length(bas)], nchar(s)))
  out
}
simge_uygula <- function(ft, disp, notlar, ust_lab = NULL) {
  for (j in seq_len(ncol(disp))) for (i in which(grepl(simge_re, disp[[j]]))) ft <- compose(ft, i = i, j = j, part = "body", value = do.call(as_paragraph, parcala(disp[[j]][i])))
  for (k in which(grepl(simge_re, notlar))) ft <- compose(ft, i = k, j = 1, part = "footer", value = do.call(as_paragraph, parcala(notlar[k])))
  hi <- nrow_part(ft, "header")
  for (j in which(grepl(simge_re, names(disp)))) ft <- compose(ft, i = hi, j = j, part = "header", value = do.call(as_paragraph, parcala(trimws(names(disp)[j]))))
  ft
}
tablo_yaz <- function(ft, dosya, baslik, yatay = FALSE) {
  doc <- read_docx()
  doc <- body_set_default_section(doc, prop_section(page_size = page_size(orient = if (yatay) "landscape" else "portrait"), page_margins = page_mar(top = 0.8, bottom = 0.8, left = 0.8, right = 0.8)))
  doc <- body_add_fpar(doc, fpar(ftext(baslik, prop = fp_text(font.family = yazi_tipi_t, font.size = 10, bold = TRUE))))
  doc <- body_add_flextable(doc, ft)
  print(doc, target = dosya)
}
wb <- createWorkbook()
xl_stil <- list(
  govde = createStyle(fontName = yazi_tipi_t, fontSize = 9, valign = "center"),
  baslik = createStyle(fontName = yazi_tipi_t, fontSize = 9, textDecoration = "bold", halign = "center", valign = "center", wrapText = TRUE),
  ust = createStyle(border = "top", borderStyle = "medium"),
  alt_ince = createStyle(border = "bottom", borderStyle = "thin"),
  alt_kalin = createStyle(border = "bottom", borderStyle = "medium"),
  not = createStyle(fontName = yazi_tipi_t, fontSize = 8),
  kalin = createStyle(textDecoration = "bold"),
  girinti = createStyle(indent = 1),
  tbaslik = createStyle(fontName = yazi_tipi_t, fontSize = 10, textDecoration = "bold")
)
tablo_listesi <- list()
metin_inc <- function(x, kalin = FALSE) {
  x <- duz(as.character(x))
  x[is.na(x)] <- ""
  vapply(x, function(s) {
    ch <- strsplit(s, "")[[1]]
    if (!length(ch)) return(0)
    w <- rep(0.5, length(ch))
    w[grepl("^[a-z]$", ch)] <- 0.47
    w[ch %in% c("i", "j", "l", "t")] <- 0.28
    w[ch %in% c("f", "r")] <- 0.34
    w[ch %in% c("m", "w")] <- 0.75
    w[grepl("^[A-Z]$", ch)] <- 0.68
    w[ch %in% c("I", "J")] <- 0.36
    w[ch %in% c("M", "W")] <- 0.9
    w[ch %in% c(" ", "\u00a0", ".", ",", ":", ";", "'")] <- 0.25
    w[ch %in% c("(", ")", "[", "]", "-", "/")] <- 0.333
    w[ch %in% c("=", "+", "<", ">", "\u2212", "\u2264", "\u2265", "\u00b1", "\u00d7", "\u0394")] <- 0.6
    w[ch == "%"] <- 0.833
    w[ch == "\u2014"] <- 1
    w[ch == "|"] <- 0.2
    sum(w) * 0.125 * if (kalin) 1.06 else 1
  }, 0, USE.NAMES = FALSE)
}
tablo_cikar <- function(disp, ad, baslik, ust = NULL, notlar = character(0), grup_satir = integer(0), girinti = integer(0), yatay = FALSE, klasor = "Results") {
  disp <- as.data.frame(disp, stringsAsFactors = FALSE, check.names = FALSE)
  disp[] <- lapply(disp, function(x) gsub("(^|[ (\\[,;])-([0-9.])", "\\1\u2212\\2", x))
  notlar <- gsub("(^|[ (\\[,;])-([0-9.])", "\\1\u2212\\2", notlar)
  ft <- flextable(disp)
  jj_cizgi <- integer(0)
  if (!is.null(ust)) {
    seg <- rep(ust$degerler, ust$genislik)
    alt_lab <- trimws(names(disp))
    alt_lab[ust$dikey] <- seg[ust$dikey]
    seg[ust$dikey] <- ""
    ft <- set_header_df(ft, mapping = data.frame(col_keys = names(disp), ust = seg, alt = alt_lab, stringsAsFactors = FALSE), key = "col_keys")
    ft <- merge_h(ft, i = 1, part = "header")
    bas_j <- cumsum(c(1, head(ust$genislik, -1)))
    jj_cizgi <- unlist(lapply(which(ust$genislik > 1), function(k) bas_j[k]:(bas_j[k] + ust$genislik[k] - 1)))
  } else {
    ft <- set_header_labels(ft, values = setNames(as.list(trimws(names(disp))), names(disp)))
  }
  ft <- tablo_bicim(ft, duz(notlar), grup_satir)
  ft <- simge_uygula(ft, disp, notlar)
  ft <- font(ft, fontname = yazi_tipi_t, part = "all")
  ft <- fontsize(ft, size = 8, part = "footer")
  dar <- ncol(disp) >= 9
  if (dar) ft <- padding(ft, padding.left = 2, padding.right = 2, part = "all")
  if (length(girinti)) ft <- padding(ft, i = girinti, j = 1, padding.left = 12, part = "body")
  if (length(jj_cizgi)) ft <- hline(ft, i = 1, j = jj_cizgi, border = fp_border(color = "black", width = 0.5), part = "header")
  ft <- align(ft, j = 1, align = "left", part = "header")
  pad <- if (dar) 0.21 else 0.32
  bas_m <- lapply(seq_len(ncol(disp)), function(j) trimws(names(disp)[j]))
  if (!is.null(ust)) {
    tek <- which(rep(ust$genislik, ust$genislik) == 1)
    ust_m <- rep(ust$degerler, ust$genislik)
    for (j in tek) bas_m[[j]] <- unique(c(bas_m[[j]], ust_m[j]))
  }
  govde_g <- vapply(seq_len(ncol(disp)), function(j) max(c(0, metin_inc(disp[[j]]))), 0) + pad
  if (length(girinti)) govde_g[1] <- max(c(0, metin_inc(disp[[1]][girinti]) + 7 / 72, metin_inc(disp[[1]][-girinti]))) + pad
  govde_g <- pmin(govde_g, c(3.6, rep(3.2, ncol(disp) - 1)))
  bas_tam <- vapply(bas_m, function(b) max(metin_inc(b, kalin = TRUE)), 0) + pad
  bas_kelime <- vapply(bas_m, function(b) max(metin_inc(unlist(strsplit(b, " ")), kalin = TRUE)), 0) + pad
  tam <- pmax(govde_g, bas_tam, 0.45)
  en_az <- pmax(govde_g, bas_kelime, 0.45)
  en_az[1] <- max(bas_kelime[1], min(govde_g[1], 1.5))
  maks <- if (yatay) 9.6 else 6.9
  sar <- vapply(seq_len(ncol(disp)), function(j) any(grepl("[A-Za-z]{3,} [A-Za-z(]", duz(disp[[j]]))), NA)
  sar[1] <- FALSE
  kelime_g <- vapply(seq_len(ncol(disp)), function(j) max(c(0, metin_inc(unlist(strsplit(duz(disp[[j]]), " "))))), 0) + pad
  sar_alt <- pmax(bas_kelime, kelime_g, 1.1)
  daralt <- function(g, alt, j, fazla) {
    pay <- pmax(g[j] - alt[j], 0)
    if (!length(j) || sum(pay) <= 0 || fazla <= 0) return(g)
    g[j] <- g[j] - pay * min(1, fazla / sum(pay))
    g
  }
  gen <- tam
  if (sum(gen) > maks) gen[-1] <- en_az[-1]
  if (sum(gen) > maks) gen <- daralt(gen, replace(en_az, 1, max(en_az[1], min(tam[1], 2))), 1, sum(gen) - maks)
  if (sum(gen) > maks) gen <- daralt(gen, sar_alt, which(sar), sum(gen) - maks)
  if (sum(gen) > maks) gen <- daralt(gen, en_az, 1, sum(gen) - maks)
  if (sum(gen) > maks) {
    gen <- gen * maks / sum(gen)
  } else if (sum(gen) < maks && any(gen[-1] < tam[-1])) {
    ek <- tam[-1] - gen[-1]
    gen[-1] <- gen[-1] + ek * min(1, (maks - sum(gen)) / sum(ek))
  }
  ft <- width(ft, width = gen)
  tablo_yaz(ft, file.path(klasor, paste0(ad, ".docx")), baslik, yatay)
  names(disp) <- gsub("\u00a0", " ", names(disp), fixed = TRUE)
  disp_x <- disp
  notlar_x <- notlar
  disp[] <- lapply(disp, duz)
  fwrite(setNames(disp, duz(names(disp))), file.path(klasor, paste0(ad, ".csv")))
  sayfa <- ad
  addWorksheet(wb, sayfa)
  writeData(wb, sayfa, baslik, startRow = 1, startCol = 1)
  addStyle(wb, sayfa, xl_stil$tbaslik, rows = 1, cols = 1)
  r0 <- 3
  nc <- ncol(disp)
  if (!is.null(ust)) {
    bas <- unlist(mapply(function(v, w) c(v, rep("", w - 1)), ust$degerler, ust$genislik))
    writeData(wb, sayfa, t(bas), startRow = r0, startCol = 1, colNames = FALSE)
    cc <- 1
    for (k in seq_along(ust$genislik)) {
      if (ust$genislik[k] > 1) mergeCells(wb, sayfa, cols = cc:(cc + ust$genislik[k] - 1), rows = r0)
      cc <- cc + ust$genislik[k]
    }
    for (j in ust$dikey) {
      mergeCells(wb, sayfa, cols = j, rows = r0:(r0 + 1))
      writeData(wb, sayfa, trimws(names(disp)[j]), startRow = r0, startCol = j)
    }
    addStyle(wb, sayfa, xl_stil$baslik, rows = r0, cols = 1:nc, gridExpand = TRUE)
    addStyle(wb, sayfa, xl_stil$ust, rows = r0, cols = 1:nc, gridExpand = TRUE, stack = TRUE)
    r0 <- r0 + 1
    hdr <- trimws(names(disp))
    hdr[ust$dikey] <- ""
    writeData(wb, sayfa, t(hdr), startRow = r0, startCol = 1, colNames = FALSE)
  } else {
    writeData(wb, sayfa, t(trimws(names(disp))), startRow = r0, startCol = 1, colNames = FALSE)
    addStyle(wb, sayfa, xl_stil$ust, rows = r0, cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  }
  addStyle(wb, sayfa, xl_stil$baslik, rows = r0, cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  addStyle(wb, sayfa, xl_stil$alt_ince, rows = r0, cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  writeData(wb, sayfa, disp_x, startRow = r0 + 1, startCol = 1, colNames = FALSE)
  addStyle(wb, sayfa, xl_stil$govde, rows = (r0 + 1):(r0 + nrow(disp)), cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  addStyle(wb, sayfa, xl_stil$alt_kalin, rows = r0 + nrow(disp), cols = 1:nc, gridExpand = TRUE, stack = TRUE)
  if (length(grup_satir)) addStyle(wb, sayfa, xl_stil$kalin, rows = r0 + grup_satir, cols = 1, stack = TRUE)
  if (length(girinti)) addStyle(wb, sayfa, xl_stil$girinti, rows = r0 + girinti, cols = 1, stack = TRUE)
  if (length(notlar)) {
    writeData(wb, sayfa, notlar_x, startRow = r0 + nrow(disp) + 1, startCol = 1)
    addStyle(wb, sayfa, xl_stil$not, rows = r0 + nrow(disp) + seq_along(notlar), cols = 1, stack = TRUE)
  }
  setColWidths(wb, sayfa, cols = 1:nc, widths = c(48, rep(16, nc - 1)))
  tablo_listesi[[ad]] <<- disp
  invisible(ft)
}
not_n <- "n, unweighted counts; percentages and prevalences weighted."

t1h <- copy(hane_2025)
t1h[, `:=`(grup = fcase(FI == 0, 1L, yoksul == 0, 2L, default = 3L), hb6 = pmin(hane_buyuklugu, 6), cocuk4 = pmin(n_cocuk, 3),
           reis_yas4 = fcase(reis_yas < 35, 1L, reis_yas < 50, 2L, reis_yas < 65, 3L, default = 4L), he040_4 = fcase(HE040 == 1, 1L, HE040 == 2, 2L, HE040 == 3, 3L, default = 4L))]
t1_spek <- list(
  list(v = "HB050", ad = deg_et("HB050")),
  list(v = "hb6", ad = deg_et("hane_buyuklugu"), lab = c("1" = "1", "2" = "2", "3" = "3", "4" = "4", "5" = "5", "6" = "\u22656")),
  list(v = "cocuk4", ad = deg_et("n_cocuk"), lab = c("0" = "None", "1" = "1", "2" = "2", "3" = "\u22653")),
  list(v = "yasli_var", ad = deg_et("yasli_var"), ikili = 1),
  list(v = "HH020", ad = deg_et("HH020")),
  list(v = "reis_cinsiyet", ad = deg_et("reis_cinsiyet"), ikili = 2, ikili_ad = "Female reference person"),
  list(v = "reis_yas4", ad = deg_et("reis_yas"), lab = c("1" = "<35", "2" = "35\u201349", "3" = "50\u201364", "4" = "\u226565")),
  list(v = "reis_egitim", ad = deg_et("reis_egitim")),
  list(v = "reis_faaliyet3", ad = deg_et("reis_faaliyet3")),
  list(v = "calisan_var", ad = deg_et("calisan_var"), ikili = 1),
  list(v = "is_yog_grup", ad = deg_et("is_yog_grup")),
  list(v = "gelir_bandi", ad = "Equivalized income relative to the median"),
  list(v = "sosyal_yardim_var", ad = deg_et("sosyal_yardim_var"), ikili = 1),
  list(v = "HH240_var", ad = deg_et("HH240_var"), ikili = 1),
  list(v = "kalabalik_konut", ad = deg_et("kalabalik_konut"), ikili = 1),
  list(v = "ciddi_konut_yoksunlugu", ad = deg_et("ciddi_konut_yoksunlugu"), ikili = 1),
  list(v = "msy_etsiz_5", ad = "Deprivation in \u22655 of 12 MSD items (meat item excluded)", ikili = 1),
  list(v = "he040_4", ad = deg_et("HE040"), lab = c("1" = "With great difficulty", "2" = "With difficulty", "3" = "With some difficulty", "4" = "Fairly easily or more easily"))
)
t1_satir <- function(dat, w, sp, des) {
  x <- dat[[sp$v]]
  fk <- factor(fifelse(is.na(x), "NA", as.character(x)))
  dat <- copy(dat)
  dat[, fk_ := fk]
  des <- update(des, fk_ = fk)
  rs <- tryCatch(svychisq(~fk_ + grup, des), error = function(e) NULL)
  p <- if (is.null(rs)) NA_real_ else as.numeric(rs$p.value)
  ws <- dat[, .(n = .N, ww = sum(get(w))), by = .(grup, fk_)]
  ws[, yuzde := 100 * ww / sum(ww), by = grup]
  kodlar_v <- if (!is.null(sp$ikili)) as.character(sp$ikili) else levels(fk)
  out <- list()
  if (is.null(sp$ikili)) out[[1]] <- c(sp$ad, "", "", "", pfmt(p))
  for (k in kodlar_v) {
    lab <- if (!is.null(sp$ikili)) (if (!is.null(sp$ikili_ad)) sp$ikili_ad else sp$ad) else if (k == "NA") "Not available" else if (!is.null(sp$lab)) sp$lab[[k]] else kat_et(sp$v, k)
    hc <- sapply(1:3, function(g) {
      r <- ws[grup == g & fk_ == k]
      if (sp$v == "gelir_bandi" && (g == 3 || (g == 2 && k == "1"))) "\u2013" else if (!nrow(r)) "0 (0.0)" else paste0(nfmt(r$n), " (", f1(r$yuzde), ")")
    })
    out[[length(out) + 1]] <- c(lab, hc, if (!is.null(sp$ikili)) pfmt(p) else "")
  }
  list(satir = do.call(rbind, out), grup = is.null(sp$ikili), p = p)
}
des_t1 <- svydesign(ids = ~1, weights = ~HB040, data = t1h)
t1_govde <- list()
t1_grup <- integer(0)
t1_gir <- integer(0)
t1_uzun <- list()
t1_p <- c()
sat <- 0
for (sp in t1_spek) {
  r <- t1_satir(t1h, "HB040", sp, des_t1)
  if (sp$v != "gelir_bandi") t1_p <- c(t1_p, setNames(r$p, sp$v))
  t1_govde[[length(t1_govde) + 1]] <- r$satir
  if (r$grup) {
    t1_grup <- c(t1_grup, sat + 1)
    t1_gir <- c(t1_gir, sat + 1 + seq_len(nrow(r$satir) - 1))
  }
  sat <- sat + nrow(r$satir)
}
yt[, `:=`(kadin = as.integer(FK090 == 2), yas4 = fcase(FK070 < 35, 1L, FK070 < 50, 2L, FK070 < 65, 3L, default = 4L), kronik = as.integer(FS020 %in% 1), gali = as.integer(FS030 %in% 1:2), calisiyor = as.integer(FI010 %in% 1:4))]
des_t1y <- svydesign(ids = ~hane_kimlik, weights = ~FB030, data = yt)
t1y_spek <- list(list(v = "kadin", ad = "Women", ikili = 1), list(v = "yas4", ad = "Age, years", lab = c("1" = "18\u201334", "2" = "35\u201349", "3" = "50\u201364", "4" = "\u226565")),
                 list(v = "kronik", ad = "Chronic illness", ikili = 1), list(v = "gali", ad = "Activity limitation (GALI)", ikili = 1), list(v = "calisiyor", ad = "Employed", ikili = 1))
yn <- yt[, .N, keyby = grup]$N
t1_govde[[length(t1_govde) + 1]] <- matrix(c(paste0("Adults aged \u226518 years (n = ", nfmt(sum(yn)), ")"), nfmt(yn), ""), nrow = 1)
sat <- sat + 1
t1_grup <- c(t1_grup, sat)
for (sp in t1y_spek) {
  r <- t1_satir(yt, "FB030", sp, des_t1y)
  t1_p <- c(t1_p, setNames(r$p, sp$v))
  t1_govde[[length(t1_govde) + 1]] <- r$satir
  if (r$grup) {
    t1_gir <- c(t1_gir, sat + 1 + seq_len(nrow(r$satir) - 1))
    t1_gir <- c(t1_gir, sat + 1)
  } else t1_gir <- c(t1_gir, sat + 1)
  sat <- sat + nrow(r$satir)
}
t1_disp <- as.data.table(do.call(rbind, t1_govde))[, 1:4]
hn_n <- t1h[, .N, keyby = grup]$N
setnames(t1_disp, c("Characteristic", paste0("(n\u00a0=\u00a0", nfmt(hn_n[1]), ")"), paste0("Not poor (n\u00a0=\u00a0", nfmt(hn_n[2]), ")"), paste0("Poor (n\u00a0=\u00a0", nfmt(hn_n[3]), ")")))
cat("Table 1 en buyuk p:", max(t1_p), "\n")
fwrite(t1_disp, "Results/table1_veri_uzun.csv")
tablo_cikar(t1_disp, "Table1", "Table 1. Characteristics of households and adults by food insecurity and income poverty, Turkey, 2025.",
            ust = list(degerler = c("Characteristic", "Food secure", "Food insecure"), genislik = c(1, 1, 2), dikey = 1),
            notlar = c(paste("Values are n (%):", not_n, "Household characteristics weighted with HB040; adults (individual questionnaire) weighted with FB030."),
                       "Food insecure: household cannot afford a meal with meat, chicken or fish every second day (HE090). Poor: equivalized disposable income below 60% of the national median.",
                       paste0("Every characteristic differed across the three groups (Rao\u2013Scott second-order corrected chi-square test, adults with households as clusters; largest p ", if (max(t1_p) < 0.001) "< 0.001" else formatC(max(t1_p), format = "f", digits = 3),
                              "). \u2013, 0% or 100% by construction (poverty is defined by income below 0.6 of the median). MSD, material and social deprivation.")),
            grup_satir = t1_grup, girinti = t1_gir)
sure_ekle("Table 1", t0)

t0 <- Sys.time()
ek_no <- c(degisken = 1, ozellik = 2, ortusme = 3, ayar = 4, h3_model = 5, sim_senaryo = 6, h1_kirilim = 7, h1_duyarlilik = 8, kesif = 9, esiksiz = 10,
           kurallar = 11, yil = 12, shap = 13, bicim = 14, h2_duyarlilik = 15, h3_tam = 16, h3_ek = 17, sim_sonuc = 18, sim_s2 = 19, sim_s3 = 20)
h1a <- h1_ana[tr63_haric == FALSE & ibbs2_tabaka == FALSE]
h1f <- h1_fark[tr63_haric == FALSE & ibbs2_tabaka == FALSE & yil_1 == 2023 & yil_2 == 2025]
t2_hucre <- function(o, e, dz, yy, d = 1) {
  r <- h1a[olcu == o & esik == e & duzey == dz & yil == yy]
  if (!nrow(r)) return("")
  ga(r$tahmin, r$alt, r$ust, d)
}
t2_fark <- function(o, e, dz, d = 1) {
  r <- h1f[olcu == o & esik == e & duzey == dz]
  if (!nrow(r)) return("")
  ga(r$fark, r$alt, r$ust, d)
}
t2_satirlar <- list(
  list("Food insecurity", "FI", ""),
  list("Income poverty (60% threshold)", "esik", "e_yoksul_60"),
  list("Food insecure and not poor", "FI_esik_degil", "e_yoksul_60"),
  list("Food insecurity among the poor (60% threshold)", "FI_esik_icinde", "e_yoksul_60")
)
t2_dislama <- list(
  list("60% poverty threshold", "dislama", "e_yoksul_60"),
  list("50% poverty threshold", "dislama", "e_yoksul_50"),
  list("70% poverty threshold", "dislama", "e_yoksul_70"),
  list("Deprivation in \u22655 of 12 MSD items", "dislama", "e_msy_etsiz_5"),
  list("Very low work intensity", "dislama", "e_dusuk_is")
)
t2_rows <- list()
t2_grup <- integer(0)
t2_gir <- integer(0)
t2_ekle <- function(s, dz) {
  d_ <- if (length(s) >= 4) s[[4]] else 1
  t2_rows[[length(t2_rows) + 1]] <<- c(s[[1]], sapply(2023:2025, function(yy) t2_hucre(s[[2]], s[[3]], dz, yy, d_)), t2_fark(s[[2]], s[[3]], dz, d_))
  t2_gir <<- c(t2_gir, length(t2_rows))
}
for (dz in c("hane", "kisi")) {
  t2_rows[[length(t2_rows) + 1]] <- c(if (dz == "hane") "Households (weight HB040)" else "Persons (weight FK050; households as clusters)", "", "", "", "")
  t2_grup <- c(t2_grup, length(t2_rows))
  for (s in t2_satirlar) t2_ekle(s, dz)
  if (dz == "hane") {
    t2_ekle(list("Households food insecure and not poor, millions", "kacirilan_hane_milyon", "e_yoksul_60", 2), dz)
  } else {
    for (s in list(list("Children (<18 years) in food-insecure households, %", "cocuk_FI", "", 1), list("Of whom not poor, %", "cocuk_dislama", "e_yoksul_60", 1),
                   list("Children in food-insecure, non-poor households, millions", "cocuk_kacirilan_milyon", "e_yoksul_60", 2))) t2_ekle(s, dz)
  }
  t2_rows[[length(t2_rows) + 1]] <- c("Exclusion error, % of food insecure not identified", "", "", "", "")
  t2_gir <- c(t2_gir, length(t2_rows))
  for (s in t2_dislama) t2_ekle(s, dz)
}
t2_rows[[length(t2_rows) + 1]] <- c("Income gradient of food insecurity (households)", "", "", "", "")
t2_grup <- c(t2_grup, length(t2_rows))
et_ <- function(yy, ts) egri_test[yil == yy & test == ts]
fp_ <- function(r) paste0("F = ", formatC(r$F, format = "f", digits = 1), " (p ", fifelse(r$p < 0.001, "< 0.001", paste0("= ", formatC(r$p, format = "f", digits = 3))), ")")
t2_rows[[length(t2_rows) + 1]] <- c("Non-linearity in log relative income", sapply(as.character(2023:2025), function(yy) fp_(et_(yy, "dogrusal_olmama"))), "")
t2_gir <- c(t2_gir, length(t2_rows))
t2_rows[[length(t2_rows) + 1]] <- c("Step at the 60% threshold, percentage points", sapply(as.character(2023:2025), function(yy) { r <- et_(yy, "esik_adimi_puan"); ga(r$tahmin, r$alt, r$ust) }), "")
t2_gir <- c(t2_gir, length(t2_rows))
t2_rows[[length(t2_rows) + 1]] <- c("Step, seven-knot spline (sensitivity)", sapply(as.character(2023:2025), function(yy) { r <- et_(yy, "esik_adimi_puan_7dugum"); ga(r$tahmin, r$alt, r$ust) }), "")
t2_gir <- c(t2_gir, length(t2_rows))
t2_rows[[length(t2_rows) + 1]] <- c("Step, piecewise-linear (sensitivity)", sapply(as.character(2023:2025), function(yy) { r <- et_(yy, "esik_adimi_puan_parcali"); ga(r$tahmin, r$alt, r$ust) }), "")
t2_gir <- c(t2_gir, length(t2_rows))
t2_rows[[length(t2_rows) + 1]] <- c("Change in the shape of the income curve", "", "", "", fp_(et_("2023-2025", "yil_farki_bicim")))
t2_gir <- c(t2_gir, length(t2_rows))
t2_disp <- as.data.table(do.call(rbind, t2_rows))
setnames(t2_disp, c("Indicator", "2023", "2024", "2025", "2025 \u2212 2023"))
n_hane_yil <- h[, .N, keyby = yil]$N
tablo_cikar(t2_disp, "Table2", "Table 2. Food insecurity, income poverty and exclusion error of poverty-based identification, Turkey, 2023\u20132025.",
            notlar = c(paste0("Estimates are weighted percentages (95% CI) unless stated otherwise; ", nfmt(n_hane_yil[1]), ", ", nfmt(n_hane_yil[2]), " and ", nfmt(n_hane_yil[3]), " households in 2023, 2024 and 2025. Food insecurity: household cannot afford a meal with meat, chicken or fish (or vegetarian equivalent) every second day (HE090). Exclusion error: share of food-insecure households (persons) not identified by the threshold."),
                       paste0("Taylor-linearization intervals with households as units; the area-level clustering of the survey sample is not identified in the files, so intervals are approximate (design-effect sensitivity in Supplementary Table S", ek_no[["h1_duyarlilik"]],
                              "). Differences assume independent samples. 2023 contains no households from TR63."),
                       "MSD, material and social deprivation; 12 of the 13 Eurostat items (meat item excluded).",
                       paste0("Income gradient: survey-weighted logistic regression of food insecurity on log relative income (restricted cubic spline, five knots). Non-linearity: Wald test of the three non-linear terms. Step: indicator for income below the 60% line added to the spline; difference in predicted probability at the line (sensitivity: seven knots, and a piecewise-linear model with a slope change and a jump at the line). Knots at quantiles of pooled 2023\u20132025 log relative income. Change in shape: Wald test of the year interaction with the slope and spline terms, 2023 and 2025 pooled; the test treats the two years as independent samples, although at least ",
                              round(100 * h[yil == 2025, mean(eslesen_2023)]), "% of 2025 households were matched to a 2023 household, and ignores area clustering, so its p value is optimistic.")),
            grup_satir = t2_grup, girinti = t2_gir)
sure_ekle("Table 2", t0)

t0 <- Sys.time()
h2m <- fread("Results/H2_hedefleme_metrikleri.csv")
h2f <- fread("Results/H2_eslesik_farklar.csv")
h2e <- fread("Results/H2_esiksiz_metrikler.csv")
h2oz <- fromJSON("Results/H2_ozet.json")
kol_ad <- c(yoksul_60 = "Poverty line (60% of median income)", gelir_sirasi = "Ranking by relative income",
            cart_T2 = "Rule set (depth-3 tree), structural", cart_T2idari = "Rule set (depth-3 tree), register-like", l1_T2 = "Lasso logistic (\u22646 variables), structural",
            cart_T1T2 = "Rule set (depth-3 tree), income + structural", l1_T1T2 = "Lasso logistic (\u22646 variables), income + structural",
            logit_lin_A1 = "Ridge logistic (linear), income + structural", logit_A1 = "Ridge logistic (splines), income + structural", lgb_A2 = "LightGBM, structural only", lgb_A1 = "LightGBM, income + structural", lgb_A3 = "LightGBM, + financial strain",
            lgb_A2i = "LightGBM, register-like subset",
            `yoksul+cart_B_T2` = "Poverty line + tree among non-poor (structural)", `yoksul+lgb_B1` = "Poverty line + LightGBM among non-poor", tavan = "Perfect ranking (ceiling)")
tv <- fread("Results/H2_tavan.csv")
t3_gruplar <- list("Thresholds" = c("yoksul_60", "gelir_sirasi"), "Sparse rules, structural" = c("cart_T2", "cart_T2idari", "l1_T2"),
                   "Sparse rules, income + structural" = c("cart_T1T2", "l1_T1T2"), "Prediction models" = c("logit_lin_A1", "logit_A1", "lgb_A2i", "lgb_A2", "lgb_A1", "lgb_A3"),
                   "Poverty line plus top-up among non-poor households" = c("yoksul+cart_B_T2", "yoksul+lgb_B1"), "Upper bound" = c("tavan"))
t3_tavan <- function(nk, ci = TRUE) {
  r <- tv[kapsama_noktasi == nk]
  if (ci && r$tavan_duyarlilik < 100) ga(r$tavan_duyarlilik, r$tavan_duyarlilik_alt, r$tavan_duyarlilik_ust) else f1(r$tavan_duyarlilik)
}
t3_hucre <- function(kol, nk, metr, ci = TRUE, sema = "temiz") {
  nk2 <- if (kol == "yoksul_60" && nk == "yoksulluk_orani") "kendi" else nk
  if (kol == "yoksul_60" && nk != "yoksulluk_orani") return("\u2013")
  if (startsWith(kol, "yoksul+") && nk == "yoksulluk_orani") return("\u2013")
  s_ <- sema
  k_ <- kol
  r <- h2m[sema == s_ & nufus == "A" & kol == k_ & kapsama_noktasi == nk2]
  if (!nrow(r)) return("")
  if (ci) ga(r[[metr]], r[[paste0(metr, "_alt")]], r[[paste0(metr, "_ust")]]) else f1(r[[metr]])
}
t3_fark <- function(kol, sema = "temiz") {
  if (kol == "yoksul_60" || startsWith(kol, "yoksul+")) return("")
  if (kol == "gelir_sirasi") return("\u2013")
  s_ <- sema
  k_ <- kol
  r <- h2f[sema == s_ & kol == k_ & karsilastirma == "yoksul_60" & metrik == "duyarlilik"]
  if (!nrow(r)) return("")
  ga(r$fark, r$alt, r$ust)
}
t3_tablo <- function(sema) {
  rows <- list()
  gs <- integer(0)
  gi <- integer(0)
  for (g in names(t3_gruplar)) {
    rows[[length(rows) + 1]] <- c(g, rep("", 7))
    gs <- c(gs, length(rows))
    for (k in t3_gruplar[[g]]) {
      if (k == "tavan") {
        rows[[length(rows) + 1]] <- c(kol_ad[[k]], t3_tavan("yoksulluk_orani"), f1(tv[kapsama_noktasi == "yoksulluk_orani", tavan_ppv]), "\u2013", "\u2013",
                                      t3_tavan("30"), f1(tv[kapsama_noktasi == "30", tavan_ppv]), t3_tavan("FI_yayginligi"))
        gi <- c(gi, length(rows))
        next
      }
      rows[[length(rows) + 1]] <- c(kol_ad[[k]], t3_hucre(k, "yoksulluk_orani", "duyarlilik", sema = sema), t3_hucre(k, "yoksulluk_orani", "ppv", FALSE, sema = sema),
                                    t3_hucre(k, "yoksulluk_orani", "cocuk", FALSE, sema = sema), t3_fark(k, sema = sema),
                                    t3_hucre(k, "30", "duyarlilik", sema = sema), t3_hucre(k, "30", "ppv", FALSE, sema = sema),
                                    t3_hucre(k, "FI_yayginligi", "duyarlilik", sema = sema))
      gi <- c(gi, length(rows))
    }
  }
  dsp <- as.data.table(do.call(rbind, rows))
  setnames(dsp, c("Method", "Sensitivity, %", "PPV, %", "Children, %", "\u0394 sensitivity, pp", "Sensitivity, % ", "PPV, % ", "Sensitivity = PPV, %"))
  list(disp = dsp, gs = gs, gi = gi)
}
kp <- h2m[sema == "temiz" & nufus == "A" & kol == "gelir_sirasi" & kapsama_noktasi %in% c("yoksulluk_orani", "FI_yayginligi"), .(kapsama_noktasi, kapsama)]
c_pov <- kp[kapsama_noktasi == "yoksulluk_orani", kapsama]
c_fi <- kp[kapsama_noktasi == "FI_yayginligi", kapsama]
t3 <- t3_tablo("temiz")
n_temiz <- h2oz$n_test$temiz
tablo_cikar(t3$disp, "Table3", "Table 3. Share of food-insecure households identified by alternative targeting rules at equal targeting rates, 2025 test set.",
            ust = list(degerler = c("Method", paste0("Targeting rate = poverty rate (", f1(c_pov), "%)"), "Targeting rate 30%", paste0("Targeting rate = FI prevalence (", f1(c_fi), "%)")), genislik = c(1, 4, 2, 1), dikey = 1),
            notlar = c(paste0("Models were trained on the 2023 and 2024 surveys and evaluated on ", nfmt(n_temiz), " households of the 2025 survey that could not be matched to a 2023 or 2024 household by member signature or reference-person key (Supplementary Table S3); weights HB040."),
                       paste0("Sensitivity: weighted share of food-insecure households selected (95% CI, household bootstrap, ", nfmt(h2oz$bootstrap$B), " replicates; intervals conditional on the fitted models). PPV: share of selected households that are food insecure. Children: share of children living in food-insecure households who are selected."),
                       "\u0394: paired bootstrap difference from the poverty line. Targeting rules select the highest-scoring households until the targeting rate is reached; households tied at the cut-off (for a tree, a whole leaf) are selected fractionally, i.e., with expected random tie-breaking. \u2013, not applicable (the poverty line has a fixed targeting rate) or identical to the poverty line by construction.",
                       "Register-like subset: survey-measured features of the kind held in population, address, education or social-security registers (household composition, counts of employed, unemployed, retired and informally employed adults, work intensity, education, region, household type, dwelling type, tenure, car ownership, characteristics of the reference person); the structural set additionally contains self-reported housing and health items. Ridge logistic: linear terms only, or cubic B-splines with five quantile knots for continuous features. Lasso logistic: at most six variables selected on the L1 path, coefficients re-estimated with a minimal penalty (relaxed lasso). Rule set: depth-3 classification tree whose leaves are selected in order of training-year prevalence.",
                       "Perfect ranking selects food-insecure households first; at a targeting rate below the prevalence its sensitivity equals the targeting rate divided by the prevalence."),
            grup_satir = t3$gs, girinti = t3$gi, yatay = TRUE)
sure_ekle("Table 3", t0)

t0 <- Sys.time()
fig2a <- h1a[(olcu == "FI" & esik == "") | (olcu %in% c("esik", "FI_esik_degil", "FI_ve_esik", "dislama") & esik == "e_yoksul_60"), .(yil, duzey, olcu, tahmin, alt, ust, n, olay)]
fwrite(fig2a, file.path(fdir, "fig2a_yayginlik.csv"))
fig2b_gelir <- h1_kir[yil == 2025 & kirilim == "gelir_bandi", .(duzey, kategori, FI, FI_alt = FI - 1.96 * FI_se, FI_ust = FI + 1.96 * FI_se, kacirilan_bilesim, n, n_FI, n_kacirilan)]
fig2b_tip <- h1_kir[yil == 2025 & kirilim == "HB050", .(duzey, kategori, etiket = sapply(kategori, function(k) kat_et("HB050", k)), dislama, dislama_alt = dislama - 1.96 * dislama_se, dislama_ust = dislama + 1.96 * dislama_se, FI, kacirilan_bilesim, n, n_FI, n_kacirilan, kucuk_hucre)]
fwrite(fig2b_gelir, file.path(fdir, "fig2b_gelir_bandi.csv"))
fwrite(fig2b_tip, file.path(fdir, "fig2b_hane_tipi.csv"))
fig2c <- h1a[duzey == "kisi" & olcu %in% c("cocuk_FI", "cocuk_dislama", "cocuk_kacirilan_milyon", "cocuk_FI_milyon"), .(yil, olcu, tahmin, alt, ust, n, olay)]
fwrite(fig2c, file.path(fdir, "fig2c_cocuklar.csv"))
fwrite(h1_ci, file.path(fdir, "fig2d_erreygers.csv"))
h1_kir_ozet <- h1_kir[kirilim %in% c("gelir_dilim5", "HB050", "cocuk_var", "HH020", "calisan_var", "reis_faaliyet3", "yasli_var", "HB030", "is_yog_grup")]
fwrite(h1_kir_ozet, file.path(fdir, "figS_h1_kirilimlar.csv"))
v25 <- h1a[yil == 2025 & duzey == "hane"]
kume <- data.table(duzey = "hane", FI = v25[olcu == "FI", tahmin], yoksul = v25[olcu == "esik" & esik == "e_yoksul_60", tahmin], kesisim = v25[olcu == "FI_ve_esik" & esik == "e_yoksul_60", tahmin])
v25k <- h1a[yil == 2025 & duzey == "kisi"]
kume <- rbind(kume, data.table(duzey = "kisi", FI = v25k[olcu == "FI", tahmin], yoksul = v25k[olcu == "esik" & esik == "e_yoksul_60", tahmin], kesisim = v25k[olcu == "FI_ve_esik" & esik == "e_yoksul_60", tahmin]))
fwrite(kume, file.path(fdir, "fig1b_kumeler.csv"))
akis <- rbindlist(list(
  data.table(dugum = "kisi_toplam", n = nrow(d)), data.table(dugum = paste0("kisi_", 2023:2025), n = d[, .N, keyby = yil]$N),
  data.table(dugum = paste0("hane_", 2023:2025), n = h[, .N, keyby = yil]$N),
  data.table(dugum = "hane_toplam", n = nrow(h)),
  data.table(dugum = "egitim_hane", n = h[yil %in% 2023:2024, .N]),
  data.table(dugum = "egitim_yoksul_degil", n = h[yil %in% 2023:2024 & yoksul == 0, .N]),
  data.table(dugum = "test_temiz", n = h[yil == 2025 & test_temiz == 1, .N]),
  data.table(dugum = "test_temiz_tek_kisili", n = h[yil == 2025 & test_temiz == 1 & hane_buyuklugu == 1, .N]),
  data.table(dugum = "test_eslesen", n = h[yil == 2025 & test_temiz == 0, .N]),
  data.table(dugum = "test_eslesen_2024", n = h[yil == 2025 & eslesen_onceki_yil == 1, .N]),
  data.table(dugum = "test_eslesen_yalniz_2023", n = h[yil == 2025 & eslesen_onceki_yil == 0 & eslesen_2023 == 1, .N]),
  data.table(dugum = "test_temiz_yoksul_degil", n = h[yil == 2025 & test_temiz == 1 & yoksul == 0, .N]),
  data.table(dugum = "test_temiz_imza", n = h[yil == 2025 & test_temiz_imza == 1, .N]),
  data.table(dugum = "test_eslesen_imza", n = h[yil == 2025 & test_temiz_imza == 0, .N]),
  data.table(dugum = "test_eslesen_reis_tek_kisili", n = h[yil == 2025 & test_temiz_imza == 1 & test_temiz == 0 & hane_buyuklugu == 1, .N]),
  data.table(dugum = "test_eslesen_reis_cok_kisili", n = h[yil == 2025 & test_temiz_imza == 1 & test_temiz == 0 & hane_buyuklugu > 1, .N]),
  data.table(dugum = "kat_2024_temiz", n = h[yil == 2024 & eslesen_onceki_yil == 0, .N]),
  data.table(dugum = "kat_2023_temiz", n = h[yil == 2023 & eslesen_sonraki_yil == 0, .N]),
  data.table(dugum = "yetiskin_2025", n = nrow(yt)),
  data.table(dugum = paste0("yetiskin_G", 1:3), n = yt[, .N, keyby = grup]$N),
  data.table(dugum = "hane_2025_saglik", n = nrow(hn)),
  data.table(dugum = paste0("hane_2025_G", 1:3), n = hn[, .N, keyby = grup]$N),
  data.table(dugum = "fert_2025_15plus", n = d[yil == 2025 & f_kayit == 1, .N]),
  data.table(dugum = "vejetaryen", n = yt[et_tavuk_balik_siklik == 0, .N])
))
fwrite(akis, file.path(fdir, "fig1a_akis.csv"))
fwrite(akis, "Results/akis_sayilari.csv")
g_lab <- c("1" = "Food secure", "2" = "Food insecure, not poor", "3" = "Food insecure, poor")
fig4a <- h3_ekler[analiz %in% c("C0_uc_grup", "C0_uc_grup_hane") & olcu %in% c("p_G1", "p_G2", "p_G3", "PD_G2_G1", "PD_G2_G3", "konum"), .(analiz, sonuc, olcu, tahmin, alt, ust, n, olay)]
fwrite(fig4a, file.path(fdir, "fig5a_uc_grup.csv"))
fig4b <- h3_ekler[analiz %in% c("C3_gelir_bandi", "C3_gelir_bandi_hane") & grepl("^p_B", olcu), .(analiz, sonuc, olcu, bant = sub("p_B", "", olcu), tahmin, alt, ust, n, olay)]
fig4b <- merge(fig4b, yt[FI == 1, .(n_bant = .N), keyby = .(bant = as.character(gelir_bandi))], by = "bant", all.x = TRUE)
fwrite(fig4b, file.path(fdir, "fig5b_gelir_bandi.csv"))
fig4c <- h3_tab[ana_model == TRUE & olcu %in% c("p0", "p1", "PD", "PR"), .(duzey, karsilastirma, sonuc, olcu, tahmin, alt, ust, n, olay, n_A1, n_A0)]
fwrite(fig4c, file.path(fdir, "fig5c_karsilastirmalar.csv"))
sure_ekle("Figur verileri (R)", t0)

t0 <- Sys.time()
ek_kl <- "Results/Supplementary"
ek_cikar <- function(k, disp, metin, ...) tablo_cikar(disp, paste0("TableS", ek_no[[k]]), paste0("Table S", ek_no[[k]], ". ", metin), klasor = ek_kl, ...)
degisken_tanim <- rbindlist(list(
  data.table(Variable = "Food insecurity (FI)", Definition = "Household cannot afford a meal with meat, chicken or fish (or vegetarian equivalent) every second day (HE090 = 2)", Source = "HE090", Universe = "Households; assigned to members"),
  data.table(Variable = "Income poor", Definition = "Equivalized disposable income below 60% of the national median of the survey year (modified OECD scale; TurkStat income concept)", Source = "yoksul_60", Universe = "Persons; household property"),
  data.table(Variable = "50% and 70% poverty lines", Definition = "As above with 50% and 70% of the median", Source = "yoksul_50, yoksul_70", Universe = "Persons; household property"),
  data.table(Variable = "Missed household", Definition = "Food insecure and not income poor", Source = "derived", Universe = "Households"),
  data.table(Variable = "Exclusion error", Definition = "Weighted share of food-insecure households (persons) that are not identified by a threshold", Source = "derived", Universe = "Food-insecure households (persons)"),
  data.table(Variable = "MSD \u22655 (meat item excluded)", Definition = "Deprivation in at least 5 of the 12 Eurostat material and social deprivation items other than the meat item; value of the reference person", Source = "msy_* items", Universe = "Households"),
  data.table(Variable = "Very low work intensity", Definition = "Any member aged 0\u201359 lives in a household with work intensity below 0.20 (TurkStat-calibrated definition); households without working-age members counted as 0 when used as a threshold", Source = "dusuk_is_yogunlugu", Universe = "Households"),
  data.table(Variable = "Relative income (log)", Definition = "Natural logarithm of equivalized income divided by the survey-year median (floored at 0.01)", Source = "goreli_esdeger_gelir", Universe = "Households"),
  data.table(Variable = "Relative income band", Definition = "<0.6, 0.6\u20130.8, 0.8\u20131.0, 1.0\u20131.5, >1.5 times the median", Source = "goreli_esdeger_gelir", Universe = "Households"),
  data.table(Variable = "Income shares", Definition = "Wages, self-employment, pensions (incl. survivors), social transfers (household and personal) and private transfers divided by disposable income; capped at 1.5; missing if disposable income \u2264 0", Source = "FG, HG components (missing = 0)", Universe = "Households"),
  data.table(Variable = "Rent-to-income ratio", Definition = "12 \u00d7 monthly rent / annual disposable income for tenants (0 otherwise; capped at 3); numerator at survey-year and denominator at income-year prices", Source = "HH040, HG110", Universe = "Households"),
  data.table(Variable = "Relative rent", Definition = "Monthly rent divided by the weighted median rent of tenants in the same survey year (0 for non-tenants; capped at 5)", Source = "HH040", Universe = "Households"),
  data.table(Variable = "Housing cost-to-income ratio", Definition = "Eurostat housing cost burden ratio; set to missing in 2024 because of the break in HH050", Source = "konut_maliyet_orani", Universe = "Households"),
  data.table(Variable = "Member counts", Definition = "Adults (\u226518), children (<18), aged 0\u20135, \u226565, \u226575; adults with chronic illness (FS020), activity limitation (FS030 1\u20132), bad or very bad health (FS010 4\u20135), unmet medical need, employed (FI010 1\u20134), unemployed, retired, domestic or care work, informally employed (not registered with social security), casual and temporary employees", Source = "FK070, FS, FI", Universe = "Households"),
  data.table(Variable = "Education (5 groups)", Definition = "No diploma (incl. illiterate), primary, lower secondary, upper secondary (general or vocational), tertiary; of the reference person, and highest and lowest among adults with an individual record", Source = "FE030", Universe = "Adults with individual record"),
  data.table(Variable = "Activity status of reference person", Definition = "Employed (FI010 1\u20134), retired (7), other; reference persons without individual record classified by FK210", Source = "FI010, FK210", Universe = "Households"),
  data.table(Variable = "Durable goods", Definition = "Ownership of computer, internet, washing machine, dishwasher, air conditioner and car (yes/no); the 'cannot afford' distinction is used only in the deprivation layer", Source = "HH180\u2013HH240", Universe = "Households"),
  data.table(Variable = "Matched to an earlier survey", Definition = "Household matched to a household of an earlier survey year by member signature (sorted birth year, birth month and sex of all members of multi-person households) or by reference-person key (birth year, birth month and sex of the reference person, NUTS 2 region, dwelling type, tenure); each signature or key occurring exactly once in both years", Source = "FK080, FK075, FK090, HB031, HH010, HH020", Universe = "Households, 2023\u20132025"),
  data.table(Variable = "Main test set", Definition = "2025 households matched neither to a 2024 nor to a 2023 household", Source = "derived", Universe = "2025 households"),
  data.table(Variable = "Low meat intake", Definition = "Eats meat, chicken or fish less than once a week (vegetarian or vegan adults excluded; included as low intake in a sensitivity analysis)", Source = "MODUL2_F_5", Universe = "Adults \u226518, 2025"),
  data.table(Variable = "Low fruit intake", Definition = "Eats fruit less than once a day", Source = "MODUL1_F_8", Universe = "Adults \u226518, 2025"),
  data.table(Variable = "Low vegetable intake", Definition = "Eats vegetables or salad less than once a day", Source = "MODUL1_F_9", Universe = "Adults \u226518, 2025"),
  data.table(Variable = "Heavy health-cost burden", Definition = "Medical examination or treatment costs, or medicine costs, were a heavy burden in the past 12 months", Source = "MODUL1_H_1, MODUL1_H_3", Universe = "Households, 2025"),
  data.table(Variable = "Unmet medical need due to cost", Definition = "Could not consult a doctor at least once because of cost, among adults who needed care", Source = "FS050, FS060", Universe = "Adults with a care need, 2025"),
  data.table(Variable = "Groups G1\u2013G3", Definition = "G1 food secure; G2 food insecure, not poor; G3 food insecure and poor", Source = "HE090, yoksul_60", Universe = "Households and adults, 2025")
))
fwrite(degisken_tanim, "Results/degisken_tanimlari.csv")
ek_cikar("degisken", degisken_tanim, "Definitions of derived variables.")

oz_set <- fromJSON(file.path(ddir, "ml", "ozellik_setleri.json"))
katm <- if (!is.null(oz_set$katmanlar)) oz_set$katmanlar else list(T1 = setdiff(oz_set$A1, oz_set$A2), T2 = oz_set$A2, T3 = setdiff(oz_set$A3, oz_set$A1), T4 = setdiff(oz_set$A4, oz_set$A3), T2_idari = character(0))
nominal_v <- c("HB030", "HB031", "HB050", "reis_medeni", "reis_calisma7", "HH010", "HH020", "HH080", "HH100", "HH110", "HE010", "HE020", "HE030", "HE070", "HE120", "HH180", "HH190", "HH200", "HH220", "HH230", "HH240")
sirali_v <- c("hane_gelir_dilim5", "reis_egitim", "egitim_max", "egitim_min", "reis_saglik", "reis_gali", "HE040", "HE060", "HH145")
katman_ad <- c(T1 = "T1 Income", T2 = "T2 Structural (no income information)", T3 = "T3 Financial strain (self-reported)", T4 = "T4 Deprivation items (upper bound only)")
ozk <- list()
gs_ <- integer(0)
for (k in names(katman_ad)) {
  ozk[[length(ozk) + 1]] <- data.table(Feature = katman_ad[[k]], Name = "", Type = "", Administrative = "")
  gs_ <- c(gs_, length(ozk))
  for (v in katm[[k]]) ozk[[length(ozk) + 1]] <- data.table(Feature = deg_et(v), Name = v, Type = if (v %in% nominal_v) "nominal" else if (v %in% sirali_v) "ordinal" else "numeric",
                                                            Administrative = if (v %in% katm$T2_idari || (v == "HB031" && "HB030" %in% katm$T2_idari)) "yes" else "")
}
dis <- fread("Results/kesif/kesif_dislanan.csv")
neden_en <- c("sonuc" = "Outcome", "sonucu (HE090) iceriyor" = "Contains the outcome (HE090)", "nufus tanimi (Model B) ve karsilastirma kolu" = "Defines the Model B population; comparison arm",
              "karsilastirma kolu (esik)" = "Comparison arm (threshold)", "log_goreli_gelir ile ayni bilgi" = "Same information as relative income", "nominal TL, yillar arasi karsilastirilamaz" = "Nominal TRY; not comparable across years",
              "2024 kirilmasi" = "Break in HH050 in 2024", "2024 tamamen bos: yil bloklu modellerde kullanilmadi" = "Missing for all of 2024; not usable with year-blocked training",
              "nominal TL: goreli_kira ve kira_orani kullanildi" = "Nominal TRY; relative rent and rent-to-income ratio used", "nominal TL ve 2024 kirilmasi" = "Nominal TRY; break in 2024",
              "nominal TL: log_goreli_gelir kullanildi" = "Nominal TRY; relative income used")
ozk[[length(ozk) + 1]] <- data.table(Feature = "Not used as features", Name = "", Type = "Reason", Administrative = "")
gs_ <- c(gs_, length(ozk))
for (i in seq_len(nrow(dis))) ozk[[length(ozk) + 1]] <- data.table(Feature = deg_et(dis$degisken[i]), Name = dis$degisken[i], Type = neden_en[[dis$neden[i]]], Administrative = "")
kopya <- data.table(Name = c("msy_tatil", "msy_beklenmedik_harcama", "msy_isinma", "msy_mobilya", "msy_otomobil", "kiraci", "reis_fk210", "gelir_dilim10", "yoksulluk_acigi_60", "msy_borc_odeme", "yasli_var", "cocuk_var", "calisan_yok"),
                    Reason = c("Duplicate of HE080", "Duplicate of HE100", "Duplicate of HE110", "Coded from HE120", "Coded from HH240", "Collapsed HH020", "Near-duplicate of activity status (V = 1.00)", "Monotone function of relative income",
                               "Monotone function of relative income", "Union of HE010\u2013HE030", "Threshold of members aged \u226565", "Threshold of number of children", "Threshold of employed adults"))
for (i in seq_len(nrow(kopya))) ozk[[length(ozk) + 1]] <- data.table(Feature = deg_et(kopya$Name[i]), Name = kopya$Name[i], Type = kopya$Reason[i], Administrative = "")
ozk <- rbindlist(ozk)
setnames(ozk, c("Feature", "Variable", "Type / reason", "Register-like subset"))
ek_cikar("ozellik", ozk, "Feature layers used in the targeting models and variables excluded from the feature set.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(ozk)), gs_),
         notlar = c("HB031 (NUTS 2) is used in LightGBM and ridge models; HB030 (NUTS 1) replaces it in the depth-3 trees and lasso models. Ordinal features enter trees as ordered numbers; nominal features enter LightGBM as native categories and other models as indicators.",
                    "Register-like subset: survey-measured features of the kind held in population, address, education or social-security registers, used for a restricted rule set; informal employment and work intensity would need linked employment records."))

oe <- copy(eslesme_ozet)[order(yil_2 - yil_1, yil_1)]
n_yil <- h[, .N, keyby = yil]
oe[, birlesik_pay_2 := round(100 * birlesik_eslesen / n_yil$N[match(yil_2, n_yil$yil)], 1)]
s3_sat <- list()
s3_gs <- integer(0)
s3_ekle <- function(ad, x = NULL) {
  s3_sat[[length(s3_sat) + 1]] <<- c(ad, if (is.null(x)) rep("", nrow(oe)) else x)
  if (is.null(x)) s3_gs <<- c(s3_gs, length(s3_sat))
}
s3_ekle("Member signature (multi-person households)")
s3_ekle("Multi-person households, first year", nfmt(oe$cok_kisili_hane_yil_1))
s3_ekle("Matched pairs", nfmt(oe$eslesen_hane))
s3_ekle("Matched, % of multi-person households", f1(oe$eslesme_payi))
s3_ekle("Same NUTS 2 region, %", f1(oe$bolge_ayni))
s3_ekle("Same dwelling type, %", f1(oe$konut_tipi_ayni))
s3_ekle("Reference-person key")
s3_ekle("Key matches, one-person households", nfmt(oe$reis_tek_kisili))
s3_ekle("Key matches, household size changed", nfmt(oe$reis_buyukluk_degisen))
s3_ekle("Precision: key matches confirmed by signature, %", f1(oe$reis_imzayla_dogrulanan_pay))
s3_ekle("Recall: signature pairs also matched by the key, %", f1(oe$reis_duyarlilik))
s3_ekle("Missed: key shared by several households, %", f1(oe$kayip_tekil_degil))
s3_ekle("Missed: reference person changed, %", f1(oe$kayip_reis_degisti))
s3_ekle("Missed: region, dwelling type or tenure changed, %", f1(oe$kayip_bolge_konut))
s3_ekle("Both methods combined")
s3_ekle("Matched pairs", nfmt(oe$birlesik_eslesen))
s3_ekle("% of first-year households", f1(oe$birlesik_eslesme_payi))
s3_ekle("% of second-year households", f1(oe$birlesik_pay_2))
o_disp <- as.data.table(do.call(rbind, s3_sat))
setnames(o_disp, c("Measure", paste0(oe$yil_1, "\u2013", oe$yil_2)))
ob <- function(tn, tt) ortusme_bilesim[tanim == tn & test_temiz == tt]
ob_metin <- function(tn) paste0(nfmt(ob(tn, 1)$n), " households (", f1(ob(tn, 1)$agirlikli_pay), "% of weighted households; ", f1(ob(tn, 1)$tek_kisili_agirlikli), "% one-person, weighted; food insecure ",
                                f1(ob(tn, 1)$FI_yuzde), "%, poor ", f1(ob(tn, 1)$yoksul_yuzde), "%)")
ek_cikar("ortusme", o_disp, "Households matched across survey years and composition of the 2025 test sets.", grup_satir = s3_gs, girinti = setdiff(seq_len(nrow(o_disp)), s3_gs),
         notlar = c("Signature: sorted birth year, birth month and sex of all members of multi-person households; signatures occurring once in both years were matched (reproduces the data review report). Reference-person key: birth year, birth month and sex of the reference person, NUTS 2 region, dwelling type and tenure, matched when unique in both years; added for pairs not matched by signature. Precision: share of key matches among multi-person households of unchanged size that the signature also matches. Recall: share of signature-matched pairs that the key also matches; the three reasons for a miss sum to 100 minus recall.",
                    paste0("Re-interviewed one-person households and households whose composition changed are detectable only through the key, whose recall is ", f1(min(oe$reis_duyarlilik)), "\u2013", f1(max(oe$reis_duyarlilik)),
                           "%; some therefore remain in the main test set. Simulation S1 evaluates undetected shares of 10%, 20% and ", f1(h[yil == 2025, 100 * (1 - sum(test_temiz) / sum(test_temiz_imza))]), "% of the test set, and the strict cleaning in Supplementary Table S", ek_no[["h2_duyarlilik"]],
                           " also removes households whose key or signature occurs in an earlier year at all.")))

ev_ornek <- list(y2023 = h[yil == 2023], y2024 = h[yil == 2024], y2025 = h[yil == 2025], test2025 = h[yil == 2025 & test_temiz == 1], gelistirme = h[yil %in% 2023:2024])
ev_ad <- c(y2023 = "2023", y2024 = "2024", y2025 = "2025", test2025 = "2025 main test set", gelistirme = "Development (2023\u20132024)", h3_yetiskin = "H3 adults", h3_hane = "H3 households")
ev_n <- c(sapply(ev_ornek, nrow), h3_yetiskin = nrow(yt), h3_hane = nrow(hn))
oz_tum <- unique(c(katm$T1, katm$T2, katm$T3, katm$T4, katm$T2_idari, "HB030"))
ev_satir <- function(degisken, etiket, grup, xs, tur, islem) {
  r <- data.table(degisken = degisken, etiket = etiket, grup = grup)
  for (s in names(ev_ad)) {
    x <- xs[[s]]
    set(r, j = paste0("n_eksik_", s), value = if (is.null(x)) NA_integer_ else sum(is.na(x)))
    set(r, j = paste0("yuzde_", s), value = if (is.null(x)) NA_real_ else 100 * mean(is.na(x)))
  }
  if (sum(unlist(r[, grep("^n_eksik_", names(r), value = TRUE), with = FALSE]), na.rm = TRUE) == 0) {
    tur <- "yok"
    islem <- "-"
  }
  r[, `:=`(eksiklik_turu = tur, islem = islem)]
  r
}
ev_h2 <- function(f) lapply(ev_ornek, f)
eksik_oz <- oz_tum[sapply(oz_tum, function(v) any(sapply(ev_ornek, function(d) anyNA(d[[v]]))))]
eksik_oz <- eksik_oz[order(-sapply(eksik_oz, function(v) mean(is.na(ev_ornek$gelistirme[[v]]))), eksik_oz)]
ev_tur <- function(v) if (v == "is_yogunlugu") "yapisal" else if (startsWith(v, "reis_")) "yanitsizlik: referans kisinin bireysel kaydi yok" else "yanitsizlik: hicbir yetiskinin bireysel kaydi yok"
ev_islem_h2 <- "LightGBM ve CART: dogal; ridge, lasso, MLP: medyan + eksiklik gostergesi (sayisal) ya da 'bos' kategorisi (kategorik), her katta yalniz egitim verisinden ogrenilir"
diger_oz <- setdiff(oz_tum, c(katm$T1, eksik_oz))
ev_rows <- list(
  ev_satir("FI", "Food insecurity (HE090)", "Outcome and income", c(ev_h2(function(d) d$FI), list(h3_yetiskin = yt$FI, h3_hane = hn$FI)), "yok", "\u2013"),
  ev_satir("T1", paste0("Income features (T1, ", length(katm$T1), " variables)"), "Outcome and income",
           c(ev_h2(function(d) fifelse(rowSums(is.na(d[, katm$T1, with = FALSE])) > 0, NA_real_, 1)), list(h3_yetiskin = yt$log_goreli_gelir, h3_hane = hn$log_goreli_gelir)), "yok", "\u2013"))
for (v in eksik_oz) ev_rows[[length(ev_rows) + 1]] <- ev_satir(v, deg_et(v), "Features with missing values", ev_h2(function(d) d[[v]]), ev_tur(v), ev_islem_h2)
ev_rows[[length(ev_rows) + 1]] <- ev_satir("diger", paste0("All other features (", length(diger_oz), ")"), "Features with missing values",
                                           ev_h2(function(d) fifelse(rowSums(is.na(d[, diger_oz, with = FALSE])) > 0, NA_real_, 1)), "yok", "\u2013")
ev_rows[[length(ev_rows) + 1]] <- ev_satir("konut_orani_k", "Housing cost-to-income ratio (not a model feature)", "Other derived variables", ev_h2(function(d) d$konut_orani_k), "tasarim geregi (2024, HH050 kirilmasi)", "ozellik setlerine alinmadi")
ev_rows[[length(ev_rows) + 1]] <- ev_satir("dusuk_is_yogunlugu", "Very low work intensity (fixed rule)", "Other derived variables", ev_h2(function(d) d$dusuk_is_yogunlugu), "yapisal", "sabit kuralda 0 (cok dusuk degil) sayildi")
ev_h3 <- list(
  list("et_tavuk_balik_siklik", "Meat, chicken or fish frequency", "H3 outcomes", list(h3_yetiskin = yt$et_tavuk_balik_siklik), "yok", "\u2013"),
  list("vejetaryen", "Vegetarian or vegan (excluded from the meat outcome)", "H3 outcomes", list(h3_yetiskin = fifelse(yt$et_tavuk_balik_siklik == 0, NA_real_, 1)), "tanim geregi", "et sonucunun paydasindan cikarildi (eksiklik degil)"),
  list("gunluk_meyve", "Fruit frequency", "H3 outcomes", list(h3_yetiskin = yt$gunluk_meyve), "yok", "\u2013"),
  list("gunluk_sebze", "Vegetable or salad frequency", "H3 outcomes", list(h3_yetiskin = yt$gunluk_sebze), "yok", "\u2013"),
  list("MODUL1_H_1", "Medical costs a burden (household)", "H3 outcomes", list(h3_hane = hn$MODUL1_H_1), "yok", "harcama olmadi (kod 4) agir yuk degil sayildi"),
  list("MODUL1_H_3", "Medicine costs a burden (household)", "H3 outcomes", list(h3_hane = hn$MODUL1_H_3), "yok", "harcama olmadi (kod 4) agir yuk degil sayildi"),
  list("yas", "Age (adult; reference person for households)", "H3 covariates", list(h3_yetiskin = yt$FK070, h3_hane = hn$reis_yas), "yok", "\u2013"),
  list("cinsiyet", "Sex", "H3 covariates", list(h3_yetiskin = yt$FK090, h3_hane = hn$reis_cinsiyet), "yok", "\u2013"),
  list("egitim", "Education", "H3 covariates", list(h3_yetiskin = yt$egitim5, h3_hane = hn$reis_egitim), "yanitsizlik: referans kisinin bireysel kaydi yok (hane)", "hane modelinde yetiskinlerin en yuksek egitimi kullanildi"),
  list("bolge", "Region (NUTS 1)", "H3 covariates", list(h3_yetiskin = yt$HB030, h3_hane = hn$HB030), "yok", "\u2013"),
  list("hane_buyuklugu", "Household size", "H3 covariates", list(h3_yetiskin = yt$hane_buyuklugu, h3_hane = hn$hane_buyuklugu), "yok", "\u2013"),
  list("n_cocuk", "Number of children", "H3 covariates", list(h3_yetiskin = yt$n_cocuk, h3_hane = hn$n_cocuk), "yok", "\u2013"),
  list("medeni", "Marital status", "H3 covariates", list(h3_yetiskin = yt$FB100, h3_hane = hn$reis_medeni), "yanitsizlik: referans kisinin bireysel kaydi yok (hane)", "hane modelinde 'bilinmiyor' kategorisi"),
  list("faaliyet", "Activity status", "H3 covariates", list(h3_yetiskin = yt$FI010, h3_hane = hn$reis_calisma7), "yanitsizlik: referans kisinin bireysel kaydi yok (hane)", "hane modelinde 'bilinmiyor' kategorisi"),
  list("kronik", "Chronic illness (adult; number of members for households)", "H3 covariates", list(h3_yetiskin = yt$FS020, h3_hane = hn$n_kronik), "yok", "\u2013"),
  list("gali", "Activity limitation (adult; number of members for households)", "H3 covariates", list(h3_yetiskin = yt$FS030, h3_hane = hn$n_gali), "yok", "\u2013"),
  list("HB050", "Household type", "H3 covariates", list(h3_yetiskin = yt$HB050, h3_hane = hn$HB050), "yok", "\u2013"),
  list("HH020", "Tenure status", "H3 covariates", list(h3_yetiskin = yt$HH020, h3_hane = hn$HH020), "yok", "\u2013"))
for (e in ev_h3) ev_rows[[length(ev_rows) + 1]] <- ev_satir(e[[1]], e[[2]], e[[3]], e[[4]], e[[5]], e[[6]])
eksik_tab <- rbindlist(ev_rows)
fwrite(eksik_tab, "Results/eksik_veri_ozeti.csv")
reis_yedek <- hn[is.na(reis_egitim), .N]
stopifnot(reis_yedek == hn[is.na(reis_egitim) & !is.na(egitim_max), .N])
ev_hucre <- function(n, p) if (is.na(n)) "\u2013" else if (n == 0) "0" else paste0(nfmt(n), " (", if (p < 0.01) "<0.01" else if (p < 0.1) formatC(p, format = "f", digits = 2) else f1(p), ")")
ev_tur_en <- c(yok = "None", yapisal = "Structural", `tanim geregi` = "By definition", `soru filtresi` = "Question filter", `tasarim geregi (2024, HH050 kirilmasi)` = "By design")
ev_disp_rows <- list()
gs_ <- integer(0)
for (g in unique(eksik_tab$grup)) {
  ev_disp_rows[[length(ev_disp_rows) + 1]] <- as.data.table(c(list(V = g), setNames(as.list(rep("", length(ev_ad) + 1)), c(names(ev_ad), "T"))))
  gs_ <- c(gs_, length(ev_disp_rows))
  for (i in which(eksik_tab$grup == g)) {
    r <- eksik_tab[i]
    tr_ <- if (startsWith(r$eksiklik_turu, "yanitsizlik")) "Item nonresponse" else ev_tur_en[[r$eksiklik_turu]]
    ev_disp_rows[[length(ev_disp_rows) + 1]] <- as.data.table(c(list(V = r$etiket), setNames(lapply(names(ev_ad), function(s) ev_hucre(r[[paste0("n_eksik_", s)]], r[[paste0("yuzde_", s)]])), names(ev_ad)), list(T = tr_)))
  }
}
ev_disp <- rbindlist(ev_disp_rows)
setnames(ev_disp, c("Variable", paste0(ev_ad, " (n\u00a0=\u00a0", nfmt(ev_n[names(ev_ad)]), ")"), "Missingness"))
tablo_cikar(ev_disp, "Ek_eksik_veri", "Table S\u2013. Missing values by variable and analytic sample, n (%).", klasor = ek_kl, grup_satir = gs_, girinti = setdiff(seq_len(nrow(ev_disp)), gs_), yatay = TRUE,
            notlar = c("Unweighted counts of households (H2 samples and H3 households) or adults (H3 adults); \u2013, variable not used in that sample. Development: 2023 and 2024 surveys (training and tuning folds).",
                       "Features: LightGBM and the depth-3 trees use missing values natively; ridge, lasso and the multilayer perceptron use median imputation with a missing indicator (numeric) or a missing category (categorical), learned from the training data of each fold and of the final model. Work intensity is undefined for households without working-age members; reference-person characteristics are missing when the reference person has no individual record.",
                       paste0("H3: complete cases; the household model uses the highest adult education for the ", reis_yedek, " households whose reference person has no individual record, and an unknown category for marital and activity status; ",
                              yt[et_tavuk_balik_siklik == 0, .N], " vegetarian or vegan adults are excluded from the meat outcome by definition. Households answering that they had no such expenditure (a response category of both health-cost items) are counted as not heavily burdened.")))

ok_ornek <- list(y2023 = h[yil == 2023], y2024 = h[yil == 2024], test2025 = h[yil == 2025 & test_temiz == 1], cikarilan2025 = h[yil == 2025 & test_temiz == 0], y2025 = h[yil == 2025])
ok_gel <- h[yil %in% 2023:2024]
wm_ <- function(x, w) { ok <- !is.na(x); sum(w[ok] * x[ok]) / sum(w[ok]) }
wv_ <- function(x, w) { ok <- !is.na(x); m <- wm_(x, w); sum(w[ok] * (x[ok] - m)^2) / sum(w[ok]) }
wmed_ <- function(x, w) { ok <- !is.na(x); x <- x[ok]; w <- w[ok]; o <- order(x); cw <- cumsum(w[o]) / sum(w); x[o][which(cw >= 0.5)[1]] }
ok_deg <- list(
  list("n", "Households, n", "n", function(d) rep(1, nrow(d))),
  list("n_FI", "Food-insecure households, n", "n", function(d) d$FI),
  list("FI", "Food insecure, %", "p", function(d) d$FI),
  list("yoksul", "Income poor, %", "p", function(d) d$yoksul),
  list("tek_kisi", "One-person household, %", "p", function(d) as.numeric(d$HB050 == 1)),
  list("cocuklu", "Household with children, %", "p", function(d) as.numeric(d$n_cocuk > 0)),
  list("yasli", "Member aged \u226565, %", "p", function(d) as.numeric(d$n_65plus > 0)),
  list("hane_buyuklugu", "Household size, mean", "m", function(d) d$hane_buyuklugu),
  list("goreli_gelir", "Relative income, median", "med", function(d) d$goreli_esdeger_gelir),
  list("reis_yas", "Age of reference person, mean", "m", function(d) d$reis_yas),
  list("reis_kadin", "Female reference person, %", "p", function(d) as.numeric(d$reis_cinsiyet == 2)),
  list("reis_yuksekogretim", "Tertiary-educated reference person, %", "p", function(d) as.numeric(d$reis_egitim == 5)),
  list("ev_sahibi", "Owner-occupier, %", "p", function(d) as.numeric(d$HH020 == 1)),
  list("kiraci", "Tenant, %", "p", function(d) as.numeric(d$HH020 == 2)),
  list("otomobil", "Owns a car, %", "p", function(d) as.numeric(d$HH240_var == 1)),
  list("nem", "Leaking roof, damp or rot, %", "p", function(d) as.numeric(d$HS010 == 1)),
  list("istanbul", "Lives in Istanbul (TR10), %", "p", function(d) as.numeric(d$HB031 == "TR10")))
ok_deger <- function(tur, x, w) switch(tur, n = sum(x), p = 100 * wm_(x, w), m = wm_(x, w), med = wmed_(x, w))
ok_smd <- function(tur, d1, d0, f) {
  if (tur == "n") return(NA_real_)
  if (tur == "med") return((wm_(d1$log_goreli_gelir, d1$HB040) - wm_(d0$log_goreli_gelir, d0$HB040)) / sqrt((wv_(d1$log_goreli_gelir, d1$HB040) + wv_(d0$log_goreli_gelir, d0$HB040)) / 2))
  x1 <- f(d1); x0 <- f(d0)
  (wm_(x1, d1$HB040) - wm_(x0, d0$HB040)) / sqrt((wv_(x1, d1$HB040) + wv_(x0, d0$HB040)) / 2)
}
orneklem_kar <- rbindlist(lapply(ok_deg, function(o) {
  r <- data.table(degisken = o[[1]], etiket = o[[2]], tur = o[[3]])
  for (s in names(ok_ornek)) set(r, j = s, value = ok_deger(o[[3]], o[[4]](ok_ornek[[s]]), ok_ornek[[s]]$HB040))
  r[, smd_test_gelistirme := ok_smd(o[[3]], ok_ornek$test2025, ok_gel, o[[4]])]
  r
}))
fwrite(orneklem_kar, "Results/orneklem_karsilastirma.csv")
gel_cift <- eslesme_bir[yil_1 == 2023 & yil_2 == 2024, .N]
gel_benzersiz <- list(hane_yil = nrow(ok_gel), cift_2023_2024 = gel_cift, benzersiz_en_cok = nrow(ok_gel) - gel_cift,
                      cift_imza = eslesme_bir[yil_1 == 2023 & yil_2 == 2024 & yontem == "imza", .N], cift_reis_anahtari = eslesme_bir[yil_1 == 2023 & yil_2 == 2024 & yontem == "reis_anahtari", .N])
ok_fmt <- function(tur, x) switch(tur, n = nfmt(x), p = f1(x), m = f1(x), med = f2(x))
ok_disp <- data.table(Characteristic = orneklem_kar$etiket)
for (s in names(ok_ornek)) set(ok_disp, j = s, value = unname(mapply(ok_fmt, orneklem_kar$tur, orneklem_kar[[s]])))
ok_disp[, SMD := fifelse(is.na(orneklem_kar$smd_test_gelistirme), "", f2(orneklem_kar$smd_test_gelistirme))]
setnames(ok_disp, c("Characteristic", "2023 (development)", "2024 (development)", "2025 main test set", "2025, matched (excluded from testing)", "2025, all", "SMD, main test vs development"))
tablo_cikar(ok_disp, "Ek_orneklem_karsilastirma", "Table S\u2013. Characteristics of the development samples, the 2025 main test set and the 2025 households excluded from testing.", klasor = ek_kl, yatay = TRUE,
            notlar = c(paste0("Percentages, means and medians weighted (HB040); counts unweighted. Development: ", nfmt(gel_benzersiz$hane_yil), " household-years in 2023 and 2024; ", nfmt(gel_cift), " pairs are matched across the two years (",
                              nfmt(gel_benzersiz$cift_imza), " by member signature, ", nfmt(gel_benzersiz$cift_reis_anahtari), " by reference-person key), so the development data contain at most ", nfmt(gel_benzersiz$benzersiz_en_cok),
                              " distinct households. Matched (excluded): 2025 households matched to a 2023 or 2024 household by either method."),
                       "SMD, standardized mean difference between the main test set and the pooled development sample (relative income on the log scale); relative income, equivalized disposable income divided by the survey-year median.",
                       paste0("Signature-only cleaned test set (sensitivity analysis): ", ob_metin("yalniz imza"), ".")))

hp <- fread("Results/H2_hiperparametreler.csv")
kol_ad_kod <-c(logit_A1 = "splines, income + structural", logit_A2 = "splines, structural", logit_B1 = "splines, non-poor, structural + relative income", logit_A1_2023 = "splines, trained 2023",
                logit_lin_A1 = "linear, income + structural", logit_lin_A2 = "linear, structural", cart_T2 = "structural", cart_T1T2 = "income + structural", cart_T2idari = "register-like",
                cart_B_T2 = "non-poor, structural", cart_B_T2gelir = "non-poor, structural + relative income", cart_T2_2023 = "structural, trained 2023")
hp_disp <- hp[, .(Model = set, Description = sub("administrative subset", "register-like subset", aciklama, fixed = TRUE), Features = n_ozellik, Stage = fcase(startsWith(asama, "1"), "broad", startsWith(asama, "2"), "focused", startsWith(asama, "3"), "focused", default = "extended"),
                  `Learning rate` = formatC(learning_rate, format = "f", digits = 4), Leaves = num_leaves, `Min. data in leaf` = min_data_in_leaf, `Max. depth` = max_depth,
                  `Feature fraction` = f2(feature_fraction), `Bagging fraction` = f2(bagging_fraction), lambda2 = trimws(formatC(lambda_l2, format = "g", digits = 3)), lambda1 = trimws(formatC(lambda_l1, format = "g", digits = 3)),
                  Rounds = n_tur_final, `CV log-loss` = formatC(cv_logloss, format = "f", digits = 4), `CV AUC` = formatC(cv_auc, format = "f", digits = 3))]
setnames(hp_disp, c("lambda2", "lambda1"), c("\u03bb_{2}", "\u03bb_{1}"))
asama_not <- ""
if (uniqueN(hp_disp$Stage) == 1) {
  asama_not <- paste0(" In all models the selected configuration came from the ", c(broad = "broad", focused = "focused", extended = "boundary-extension")[hp_disp$Stage[1]], " search.")
  hp_disp[, Stage := NULL]
}
ek_cikar("ayar", hp_disp, "LightGBM hyperparameters selected by year-blocked cross-validation.", yatay = TRUE,
         notlar = c(paste0("Search: 60 configurations from a broad space and 60 from a focused space (random search), the five best re-evaluated with three seeds; a further 30-configuration search around the selected configuration when a value lay at a search boundary. Stage: search that produced the selected configuration (focused, focused space or seed re-evaluation; extended, boundary extension).", asama_not),
                    "Folds: train on 2023, validate on 2024 households not matched to 2023, and vice versa; criterion weighted log-loss averaged over folds and seeds; early stopping patience max(100, 2/learning rate).",
                    paste0("Ridge logistic C (selected on the folds; halved for the final fit on two years): ", paste(sprintf("%s %s", kol_ad_kod[names(h2oz$lojistik_C)], trimws(formatC(unlist(h2oz$lojistik_C), format = "g", digits = 2))), collapse = "; "),
                           ". Rule sets (depth-3 trees): ", paste(sprintf("%s, %s, minimum leaf weight %s, \u03b1 = %s", kol_ad_kod[names(h2oz$cart)], sapply(h2oz$cart, function(z) z$olcut), sapply(h2oz$cart, function(z) z$mwf),
                                                                     sapply(h2oz$cart, function(z) trimws(formatC(z$alpha, format = "g", digits = 2)))), collapse = "; "), ".")))

h3t <- fread("Results/H3_model_tanilari.csv")
sonuc_ad <- c(et_az = "Meat <1/week", meyve_az = "Fruit <1/day", sebze_az = "Vegetables <1/day", saglik_yuk = "Health costs heavy burden", et_az_veg = "Meat <1/week (vegetarians included)", karsilanmayan_odeme = "Unmet need due to cost")
kar_ad <- c(C1 = "C1: G2 vs G1 (non-poor)", C2 = "C2: G2 vs G3 (food insecure)")
aday_en <- c(FB100 = "marital status", FI010 = "activity status", FS020 = "chronic illness", FS030 = "activity limitation", HB050 = "household type", HH020 = "tenure")
h3m_disp <- h3t[, .(Comparison = kar_ad[karsilastirma], Outcome = sonuc_ad[sonuc], Age = yas, `Added covariates` = sapply(strsplit(ek_kovaryat, ", "), function(z) if (identical(z, "none")) "none" else paste(aday_en[z], collapse = ", ")),
                    `Interaction p: region / sex / income` = paste(pfmt(em_p_bolge), pfmt(em_p_cinsiyet), fifelse(is.na(em_p_gelir), "\u2013", pfmt(em_p_gelir)), sep = " / "),
                    `Main model` = fifelse(ana_model == "esnek", "fully interacted", "main effects"), AL_p = pfmt(al_p), `Max. calibration gap, pp` = f1(al_maks_fark),
                    `Events per parameter` = f1(epp), DEFF = f2(deff), `Bootstrap shift, pp` = f2(boot_oynama))]
setnames(h3m_disp, "AL_p", "Archer\u2013Lemeshow p")
ek_cikar("h3_model", h3m_disp, "Model specification and diagnostics for the dietary and health-cost comparisons (H3), 2025.", yatay = TRUE,
         notlar = c("Core covariates: age, sex, education, region (NUTS 1), household size, number of children; C1 additionally relative income (log, natural spline). Household outcome: characteristics of the reference person.",
                    "Covariates added when they changed the risk difference by \u22650.5 percentage points or the prevalence ratio by \u226510% (no p-value-based selection). Fully interacted model used when an interaction p < 0.01.",
                    "DEFF, design effect of household clustering for the risk difference. Bootstrap shift: largest change in 95% limits between 1,000, 2,000 and 4,000 replicates."))
sure_ekle("Ek tablolar 1", t0)

t0 <- Sys.time()
s1o <- fread(file.path(simdir, "S1_ozet.csv"))
s2o <- fread(file.path(simdir, "S2_ozet.csv"))
s2kf <- fread(file.path(simdir, "S2_kapali_form.csv"))
s2tn <- fread(file.path(simdir, "S2_tani_eski.csv"))
s2huc <- fread(file.path(simdir, "S2_hucreler.csv"))
s2rsk <- fread(file.path(simdir, "S2_risk_hucreleri.csv"))
s2tas <- fread(file.path(simdir, "S2_tasarimlar.csv"))
for (k in c("izgara", "uyumlu_A", "uyumlu_B", "uyumlu_A_risk_ondaligi")) set(s2tas, j = k, value = as.logical(s2tas[[k]]))
s2bilgi <- fromJSON(file.path(simdir, "simulasyon_bilgi.json"))
s3o <- fread(file.path(simdir, "S3_ozet.csv"))
ss <- copy(sim_senaryo)
dk_fmt <- function(x) if (x < 0.05) "<0.1 min" else paste0(f1(x), " min")
sim_disp <- rbindlist(list(
  data.table(Study = "S1 Panel overlap", Scenarios = paste0(ss[calisma == "S1", .N], " (latent ICC 0.3, 0.6 \u00d7 overlap 30%, observed, 60%)"), Replicates = nfmt(ss[calisma == "S1", tekrar][1]),
             `Data-generating model` = "Small LightGBM fitted to 2024\u20132025 food insecurity; shared household random effect for matched 2024\u20132025 pairs; intercept recalibrated to the observed prevalence",
             Evaluation = "Model with the A1 tuning (fixed trees and learning rate) trained on simulated 2024, tested on simulated 2025 (full, unmatched, and unmatched with a share of re-interviewed households left undetected); optimism = metric with shared minus independent random effects"),
  data.table(Study = "S2 Outcome misclassification", Scenarios = paste0(ss[calisma == "S2", .N], " (Se 0.80\u20130.95 \u00d7 Sp 0.90\u20130.99; non-differential and income-differential) and ", s2tas[izgara == FALSE, .N],
                                                                       " near-error-free (Se 0.98\u20131.00 \u00d7 Sp 0.999\u20131.000); compatible with the observed data: ", s2tas[izgara == TRUE & uyumlu_A == TRUE, .N], " + ", s2tas[izgara == FALSE & uyumlu_A == TRUE, .N],
                                                                       " under design A, ", s2tas[uyumlu_B == TRUE, .N], " under design B"),
             Replicates = nfmt(ss[calisma == "S2", max(tekrar)]),
             `Data-generating model` = "Design A: true status assigned from observed HE090 by Bayes' rule within cells of equivalized income quintile \u00d7 poverty status, using each cell's observed prevalence; design B: the same Se and Sp for every household, true status assigned from the recalibrated out-of-time LightGBM probability of reporting food insecurity; differential: Sp 5 pp lower in income quintiles 1\u20132",
             Evaluation = "Exclusion error (simulated and closed form), food insecurity among the poor, rule-set, LightGBM and poverty-line sensitivity recomputed with assigned true status; realized Se and Sp by decile of LightGBM risk"),
  data.table(Study = "S3 Interval coverage", Scenarios = "1", Replicates = paste0(nfmt(ss[calisma == "S3", tekrar][1]), " data sets \u00d7 ", nfmt(ss[calisma == "S3", bootstrap][1]), " bootstrap replicates"),
             `Data-generating model` = "Pseudo-population of 2025 households with HB040 weights and calibrated LightGBM probabilities; equal-probability resampling of households",
             Evaluation = "Coverage of 95% percentile household-bootstrap intervals for exclusion error, rule-set sensitivity and PPV")
))
ek_cikar("sim_senaryo", sim_disp, "Design of the plasmode simulation studies.", yatay = TRUE, notlar = paste0("Seeds: scenario seed 20261101 + 1000 \u00d7 scenario number; replicate seeds derived from the scenario seed; S2 design B and the added near-error-free scenarios: numpy SeedSequence (20261101, design, scenario)."))

kir_ad <- c(gelir_dilim5 = "Equivalized income quintile", HB050 = "Household type", cocuk_var = "Children in household", yasli_var = "Member aged \u226565", HH020 = "Tenure status",
            calisan_var = "Employed adult in household", is_yog_grup = "Work intensity", reis_faaliyet3 = "Activity status of reference person", HB030 = "Region (NUTS 1)")
k25 <- h1_kir[yil == 2025 & kirilim %in% names(kir_ad)]
kk_rows <- list()
gs_ <- integer(0)
for (k in names(kir_ad)) {
  kk_rows[[length(kk_rows) + 1]] <- data.table(Characteristic = kir_ad[[k]], n = "", FI = "", Exclusion = "", Missed = "", Exclusion_p = "")
  gs_ <- c(gs_, length(kk_rows))
  kh <- k25[kirilim == k & duzey == "hane"]
  kp <- k25[kirilim == k & duzey == "kisi"]
  kh[, sira := suppressWarnings(as.numeric(kategori))]
  setorder(kh, sira, kategori)
  for (i in seq_len(nrow(kh))) {
    r <- kh[i]
    rp <- kp[kategori == r$kategori]
    lab <- if (k %in% c("cocuk_var", "yasli_var", "calisan_var")) c("0" = "No", "1" = "Yes")[[r$kategori]] else if (k == "gelir_dilim5") c("Q1 (lowest)", "Q2", "Q3", "Q4", "Q5 (highest)")[as.integer(r$kategori)] else kat_et(k, r$kategori)
    sup <- r$kucuk_hucre == "suppressed"
    taut <- !is.na(r$dislama_se) && r$dislama_se < 1e-8
    kk_rows[[length(kk_rows) + 1]] <- data.table(Characteristic = lab, n = nfmt(r$n), FI = ga(r$FI, r$FI - 1.96 * r$FI_se, r$FI + 1.96 * r$FI_se),
                                                 Exclusion = if (sup) "\u2013" else if (taut) "\u2013^{b}" else paste0(ga(r$dislama, r$dislama - 1.96 * r$dislama_se, r$dislama + 1.96 * r$dislama_se), if (r$kucuk_hucre == "flag") "^{a}" else ""),
                                                 Missed = f1(fifelse(is.na(r$kacirilan_bilesim), 0, r$kacirilan_bilesim)), Exclusion_p = if (taut) "\u2013" else if (nrow(rp) && !is.na(rp$dislama)) f1(rp$dislama) else "")
  }
}
kk <- rbindlist(kk_rows)
setnames(kk, c("Characteristic", "n", "Food insecure, % (95% CI)", "Exclusion error, % (95% CI)", "Share of missed households, %", "Exclusion error, persons, %"))
ek_cikar("h1_kirilim", kk, "Food insecurity and exclusion error of the 60% poverty line by household characteristics, 2025.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(kk)), gs_), yatay = TRUE,
         notlar = c(paste("n, unweighted number of households; percentages and prevalences weighted.", "Exclusion error: % of food-insecure households not poor. Share of missed households: distribution of food-insecure, non-poor households across categories."),
                    "^{a} 20\u201350 food-insecure households in the cell; \u2013, fewer than 20 (not shown). ^{b} Determined by construction: all households in the category lie on the same side of the poverty line."))

duy_rows <- list()
for (dz in c("hane", "kisi")) for (yy in 2023:2025) {
  base <- h1_ana[duzey == dz & yil == yy & olcu == "dislama" & esik == "e_yoksul_60"]
  b0 <- base[!tr63_haric & !ibbs2_tabaka]
  duy_rows[[length(duy_rows) + 1]] <- data.table(Level = if (dz == "hane") "Households" else "Persons", Year = as.character(yy),
                                                 Main = ga(b0$tahmin, b0$alt, b0$ust),
                                                 `Excluding TR63` = ga(base[tr63_haric == TRUE, tahmin], base[tr63_haric == TRUE, alt], base[tr63_haric == TRUE, ust]),
                                                 `NUTS 2 pseudo-strata` = ga(base[ibbs2_tabaka == TRUE, tahmin], base[ibbs2_tabaka == TRUE, alt], base[ibbs2_tabaka == TRUE, ust]),
                                                 `Design effect 2` = ga(b0$tahmin, b0$tahmin - 1.96 * sqrt(2) * b0$se, b0$tahmin + 1.96 * sqrt(2) * b0$se))
}
for (dz in c("hane", "kisi")) for (yp in list(c(2023, 2025), c(2023, 2024), c(2024, 2025))) {
  ff <- h1_fark[duzey == dz & yil_1 == yp[1] & yil_2 == yp[2] & olcu == "dislama" & esik == "e_yoksul_60"]
  f0 <- ff[!tr63_haric & !ibbs2_tabaka]
  duy_rows[[length(duy_rows) + 1]] <- data.table(Level = if (dz == "hane") "Households" else "Persons", Year = paste0(yp[2], " \u2212 ", yp[1]),
                                                 Main = ga(f0$fark, f0$alt, f0$ust),
                                                 `Excluding TR63` = ga(ff[tr63_haric == TRUE, fark], ff[tr63_haric == TRUE, alt], ff[tr63_haric == TRUE, ust]),
                                                 `NUTS 2 pseudo-strata` = ga(ff[ibbs2_tabaka == TRUE, fark], ff[ibbs2_tabaka == TRUE, alt], ff[ibbs2_tabaka == TRUE, ust]),
                                                 `Design effect 2` = ga(f0$fark, f0$fark - 1.96 * sqrt(2) * f0$se_fark, f0$fark + 1.96 * sqrt(2) * f0$se_fark))
}
for (yy in 2023:2025) {
  r <- h1_ci[yil == yy]
  duy_rows[[length(duy_rows) + 1]] <- data.table(Level = "Erreygers index (persons)", Year = as.character(yy), Main = ga(r$E, r$alt, r$ust, 3), `Excluding TR63` = "\u2013", `NUTS 2 pseudo-strata` = "\u2013",
                                                 `Design effect 2` = ga(r$E, r$E - 1.96 * sqrt(2) * r$se, r$E + 1.96 * sqrt(2) * r$se, 3))
}
r <- ci_fark[yil_2 == 2025]
duy_rows[[length(duy_rows) + 1]] <- data.table(Level = "Erreygers index (persons)", Year = "2025 \u2212 2023", Main = ga(r$fark, r$alt, r$ust, 3), `Excluding TR63` = "\u2013", `NUTS 2 pseudo-strata` = "\u2013",
                                               `Design effect 2` = ga(r$fark, r$fark - 1.96 * sqrt(2) * r$se_fark, r$fark + 1.96 * sqrt(2) * r$se_fark, 3))
duy <- rbindlist(duy_rows)
ek_cikar("h1_duyarlilik", duy, "Exclusion error of the 60% poverty line: sensitivity to the TR63 region and to the variance estimator, and income-related concentration of food insecurity.",
         notlar = c("Exclusion error, % of food-insecure households (persons) not poor (95% CI). TR63 (Hatay, Kahramanmara\u015f, Osmaniye) has no households in 2023. Pseudo-strata: NUTS 2 regions used as strata in the linearization variance.",
                    "Design effect 2: intervals with the variance doubled, as a stand-in for the area-level clustering of the survey sample, which is not identified in the files.",
                    "Erreygers concentration index of food insecurity by equivalized-income rank (persons, FK050); negative values indicate concentration among lower-income persons. Differences assume independent samples. \u2013, not computed."))
sure_ekle("Ek tablolar 2", t0)

t0 <- Sys.time()
k10 <- fread("Results/kesif/kesif_katman_ilk10.csv")
kullanilan_oz <- unique(unlist(oz_set[c("A1", "A2", "A3", "A4", "B1", "B2", "B3")]))
kcok <- fread("Results/kesif/kesif_cok_degiskenli_katmanlar.csv")
kat_en <- c("T1 gelir" = "T1 Income", "T2 yapisal" = "T2 Structural", "T3 mali baski" = "T3 Financial strain", "T4 ayni batarya" = "T4 Deprivation items")
kr_rows <- list()
gs_ <- integer(0)
for (kt in names(kat_en)) {
  kr_rows[[length(kr_rows) + 1]] <- data.table(Feature = kat_en[[kt]], a = "", b = "", c = "", d = "")
  gs_ <- c(gs_, length(kr_rows))
  x <- k10[nufus == "tum" & katman == kt][order(katman_sira)]
  y <- k10[nufus == "yoksul_degil" & katman == kt]
  for (i in seq_len(nrow(x))) {
    yy_ <- y[degisken == x$degisken[i]]
    kr_rows[[length(kr_rows) + 1]] <- data.table(Feature = paste0(deg_et(x$degisken[i]), if (x$degisken[i] %in% kullanilan_oz) "" else "^{a}"), a = formatC(x$r2_ort[i], format = "f", digits = 3), b = formatC(x$auc_2025[i], format = "f", digits = 3),
                                                 c = if (nrow(yy_)) formatC(yy_$r2_ort, format = "f", digits = 3) else "", d = if (nrow(yy_)) formatC(yy_$auc_2025, format = "f", digits = 3) else "")
  }
}
kr_rows[[length(kr_rows) + 1]] <- data.table(Feature = "Layer combinations (main-effects logistic, trained 2023, tested 2025)", a = "", b = "", c = "", d = "")
gs_ <- c(gs_, length(kr_rows))
set_en <- c(T1 = "T1", T2 = "T2", T1_T2 = "T1 + T2", T1_T2_T3 = "T1 + T2 + T3", T1_T2_T3_T4 = "T1 + T2 + T3 + T4", T2_T3 = "T2 + T3")
for (s_ in names(set_en)) {
  a_ <- kcok[nufus == "tum" & set == s_]
  b_ <- kcok[nufus == "yoksul_degil" & set == s_]
  kr_rows[[length(kr_rows) + 1]] <- data.table(Feature = set_en[[s_]], a = formatC(a_$r2_egitim_2023, format = "f", digits = 3), b = formatC(a_$auc_test_2025, format = "f", digits = 3),
                                               c = formatC(b_$r2_egitim_2023, format = "f", digits = 3), d = formatC(b_$auc_test_2025, format = "f", digits = 3))
}
kr <- rbindlist(kr_rows)
setnames(kr, c("Feature", "McFadden R^{2}", "AUC 2025", "McFadden R^{2} ", "AUC 2025 "))
ek_cikar("kesif", kr, "Univariable association of features with food insecurity (ten strongest per layer) and multivariable comparison of feature layers.",
         ust = list(degerler = c("Feature", "All households", "Non-poor households"), genislik = c(1, 2, 2), dikey = 1), grup_satir = gs_, girinti = setdiff(seq_len(nrow(kr)), gs_),
         notlar = c("Univariable: weighted logistic regression per survey year (numeric features as 3-df natural splines); McFadden R^{2} averaged over 2023\u20132025; weighted AUC in 2025. Exploratory output used to assign layers; not a test.",
                    paste0("Layer combinations: McFadden R^{2} in the 2023 training data and weighted AUC in 2025. ^{a}Screened candidate not used as a model feature (Supplementary Table S", ek_no[["ozellik"]], ")."))) 

kol_ad2 <- c(kol_ad[names(kol_ad) != "logit_lin_A1"], lgb_A4 = "LightGBM, + deprivation items (upper bound)", logit_A2 = "Ridge logistic, structural only", lgb_B1 = "LightGBM, structural + relative income", lgb_B2 = "LightGBM, structural only",
             lgb_B3 = "LightGBM, + financial strain", logit_B1 = "Ridge logistic, structural + relative income", cart_B_T2 = "Rule set (depth-3 tree), structural", cart_B_T2gelir = "Rule set (depth-3 tree), structural + relative income",
             l1_B_T2 = "Lasso logistic (\u22646 variables), structural", lgb_A1_2023 = "LightGBM, income + structural (trained 2023)", cart_T2_2023 = "Rule set (depth-3 tree), structural (trained 2023)",
             logit_A1_2023 = "Ridge logistic (trained 2023)", lgb_B1_2023 = "LightGBM, structural + relative income (trained 2023)", gelir_sirasi = "Ranking by relative income",
             logit_lin_A1 = "Linear terms (ridge logistic)", logit_lin_A2 = "Linear terms (ridge logistic)", lgb_ek_A1 = "Boosted, additive (no interactions)", lgb_ek_A2 = "Boosted, additive (no interactions)",
             lgb_d2_A1 = "Boosted, pairwise interactions (depth 2)", lgb_d2_A2 = "Boosted, pairwise interactions (depth 2)")
bicim_kol <- "^(logit_lin|lgb_ek|lgb_d2)_"
es_rows <- list()
gs_ <- integer(0)
for (pp in c("A", "B")) {
  es_rows[[length(es_rows) + 1]] <- data.table(Method = if (pp == "A") "All households (main test set)" else "Non-poor households (main test set)", AUC = "", PR = "", Brier = "", Int = "", Slope = "", AUCu = "")
  gs_ <- c(gs_, length(es_rows))
  x <- h2e[sema == "temiz" & nufus == pp & !grepl(bicim_kol, kol)]
  for (i in seq_len(nrow(x))) {
    r <- x[i]
    es_rows[[length(es_rows) + 1]] <- data.table(Method = kol_ad2[[r$kol]], AUC = ga(r$auc, r$auc_alt, r$auc_ust, 3), PR = if (!is.na(r$pr_auc_alt)) ga(r$pr_auc, r$pr_auc_alt, r$pr_auc_ust, 3) else formatC(r$pr_auc, format = "f", digits = 3),
                                                 Brier = if (!is.na(r$brier)) formatC(r$brier, format = "f", digits = 3) else "", Int = if (!is.na(r$kalibrasyon_kesim)) f2(r$kalibrasyon_kesim) else "",
                                                 Slope = if (!is.na(r$kalibrasyon_egim)) f2(r$kalibrasyon_egim) else "", AUCu = formatC(r$auc_agirliksiz, format = "f", digits = 3))
  }
}
if (file.exists("Results/H2_mlp.csv")) {
  mlp <- fread("Results/H2_mlp.csv")
  for (i in seq_len(nrow(mlp))) {
    r <- mlp[i]
    es_rows <- append(es_rows, list(data.table(Method = paste0("Multilayer perceptron, ", if (r$set == "A1") "income + structural" else "structural only", "^{a}"), AUC = formatC(r$auc, format = "f", digits = 3),
                                               PR = formatC(r$pr_auc, format = "f", digits = 3), Brier = formatC(r$brier, format = "f", digits = 3), Int = "", Slope = f2(r$kalibrasyon_egim), AUCu = "")), after = gs_[2] - 1)
    gs_[2] <- gs_[2] + 1L
  }
}
es_t <- rbindlist(es_rows)
setnames(es_t, c("Method", "AUC (95% CI)", "PR-AUC (95% CI)", "Brier score", "Calibration intercept", "Calibration slope", "AUC, unweighted"))
ek_cikar("esiksiz", es_t, "Discrimination and calibration of the scoring rules in the 2025 test set.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(es_t)), gs_), yatay = TRUE,
         notlar = c(paste0("Weighted (HB040) unless stated otherwise; 95% CI from ", nfmt(h2oz$bootstrap$B), " household bootstrap replicates. Calibration intercept estimated with the logit of the predicted probability as offset; slope from logistic recalibration."),
                    "Brier score and calibration are not defined for the income ranking.",
                    if (file.exists("Results/H2_mlp.csv")) paste0("^{a} Additional comparison: two-hidden-layer network (PyTorch, Apple MPS), same training and test sets; AUC difference from LightGBM ",
                                                                  paste(sprintf("%s %s (%s, %s)", mlp$set, formatC(mlp$auc_fark_mlp_eksi_lgb, format = "f", digits = 3), formatC(mlp$auc_fark_alt, format = "f", digits = 3), formatC(mlp$auc_fark_ust, format = "f", digits = 3)), collapse = "; "), ".") else character(0)))

kr2 <- fread("Results/H2_kurallar.csv")
kural_ad <- c(cart_T2 = "Rule set (depth-3 tree), structural (all households)", cart_T1T2 = "Rule set (depth-3 tree), income + structural (all households)", cart_T2idari = "Rule set (depth-3 tree), register-like (all households)",
              cart_B_T2 = "Rule set (depth-3 tree), structural (non-poor households)", cart_B_T2gelir = "Rule set (depth-3 tree), structural + relative income (non-poor households)")
ku_rows <- list()
gs_ <- integer(0)
for (k in names(kural_ad)) {
  ku_rows[[length(ku_rows) + 1]] <- data.table(Rule = kural_ad[[k]], a = "", b = "", c = "", d = "", e = "")
  gs_ <- c(gs_, length(ku_rows))
  x <- kr2[kural_seti == k][order(sira)]
  for (i in seq_len(nrow(x))) ku_rows[[length(ku_rows) + 1]] <- data.table(Rule = paste0(x$sira[i], ". ", gsub(" AND ", " and ", x$kural[i], fixed = TRUE)), a = f1(x$egitim_pay[i]), b = f1(x$egitim_FI[i]), c = f1(x$test_pay[i]), d = f1(x$test_FI[i]), e = "")
}
l1k <- fread("Results/H2_l1_katsayilar.csv")
l1_ad <- c(l1_T2 = "Lasso logistic, structural (all households)", l1_T1T2 = "Lasso logistic, income + structural (all households)", l1_B_T2 = "Lasso logistic, structural (non-poor households)")
for (k in names(l1_ad)) {
  ku_rows[[length(ku_rows) + 1]] <- data.table(Rule = l1_ad[[k]], a = "", b = "", c = "", d = "", e = "")
  gs_ <- c(gs_, length(ku_rows))
  x <- l1k[model == k & abs(katsayi_ham) > 1e-8 & !grepl("=bos$", terim)]
  for (i in seq_len(nrow(x))) {
    tm <- x$terim[i]
    ikili12 <- c("HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070", "reis_kronik", "HH120", "reis_cinsiyet")
    lab <- if (tm == "(sabit)") "Intercept (odds)"
           else if (grepl("=", tm)) paste0(deg_et(x$degisken[i]), ": ", kat_et(x$degisken[i], sub("\\.0$", "", sub("^[^=]*=", "", tm))))
           else if (x$degisken[i] == "log_goreli_gelir") "Relative income, per unit of log"
           else if (x$degisken[i] %in% ikili12) paste0(deg_et(x$degisken[i]), ": ", kat_et(x$degisken[i], 2), " vs ", kat_et(x$degisken[i], 1))
           else if (grepl("_var$", x$degisken[i]) || x$degisken[i] %in% c("tek_yetiskin_cocuklu", "kalabalik_konut", "ciddi_konut_yoksunlugu", "sosyal_yardim_var", "ozel_transfer_var", "kira_geliri_var")) paste0(deg_et(x$degisken[i]), ": yes vs no")
           else paste0(deg_et(x$degisken[i]), ", per unit")
    ku_rows[[length(ku_rows) + 1]] <- data.table(Rule = lab, a = "", b = "", c = "", d = "", e = if (tm == "(sabit)") formatC(x$OR_birim[i], format = "g", digits = 3) else f2(x$OR_birim[i]))
  }
}
ku <- rbindlist(ku_rows)
setnames(ku, c("Rule (leaf) or term", "Share of households, %", "Food insecure, %", "Share of households, % ", "Food insecure, % ", "Odds ratio (lasso)"))
ek_cikar("kurallar", ku, "Sparse rule sets: leaves of the depth-3 trees in plain language and terms of the lasso logistic models.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(ku)), gs_), yatay = TRUE,
         ust = list(degerler = c("Rule (leaf) or term", "Training (2023\u20132024)", "Test (2025)", "Odds ratio (lasso)"), genislik = c(1, 2, 2, 1), dikey = c(1, 6)),
         notlar = c("Leaves are ordered by the training-year share food insecure; a rule set at a given targeting rate selects leaves in this order. Shares and prevalences weighted (HB040).",
                    "Lasso: largest penalty path point with at most six variables, refitted with a weak ridge penalty. Categorical variables enter as indicators for every category (no reference category), so their ORs are relative to the average of the categories. Intercept: odds when every term, including the missing-value indicators not shown, is zero; intercepts, all coefficients and the preprocessing parameters are provided with the code (Results/modeller)."))

ym <- fread("Results/H2_yil_matrisi.csv")
psi <- fread("Results/H2_psi.csv")
rhoS <- fread("Results/H2_yil_shap_spearman.csv")
yr_rows <- list()
gs_ <- integer(0)
for (s_ in c("A1", "B1")) {
  yr_rows[[length(yr_rows) + 1]] <- as.data.table(as.list(setNames(c(if (s_ == "A1") "LightGBM, income + structural (all households)" else "LightGBM, structural + relative income (non-poor households)", rep("", 11)), paste0("v", 1:12))))
  gs_ <- c(gs_, length(yr_rows))
  for (ey in 2023:2025) {
    x <- ym[set == s_ & egitim_yili == ey]
    hc <- unlist(lapply(2023:2025, function(ty) {
      r <- if (ty == ey) x[test_yili == ty & test_seti == "OOF"] else x[test_yili == ty & test_seti == "temiz"]
      c(formatC(r$auc, format = "f", digits = 3), f2(r$kalibrasyon_kesim), f2(r$kalibrasyon_egim))
    }))
    p_ <- psi[set == s_]
    yr_rows[[length(yr_rows) + 1]] <- as.data.table(as.list(setNames(c(paste("Trained on", ey), hc, if (ey == 2023) formatC(p_[yil == 2024, PSI], format = "f", digits = 3) else "",
                                                                       if (ey == 2023) formatC(p_[yil == 2025, PSI], format = "f", digits = 3) else ""), paste0("v", 1:12))))
  }
}
yr <- rbindlist(yr_rows)
setnames(yr, c("Model", paste0(rep(c("AUC", "Intercept", "Slope"), 3), rep(c("", " ", "  "), each = 3)), "2024", "2025"))
ek_cikar("yil", yr, "Transportability of year-specific models across survey years: discrimination, calibration and score drift.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(yr)), gs_), yatay = TRUE,
         ust = list(degerler = c("Model", "Tested on 2023", "Tested on 2024", "Tested on 2025", "Population stability index"), genislik = c(1, 3, 3, 3, 2), dikey = 1),
         notlar = c("Within the training year: five-fold cross-fitted predictions. Other years: test households not matched to the training year. Intercept and slope: logistic calibration. PSI: distribution of the 2023 model's scores in 2024 and 2025 relative to its 2023 cross-fitted scores (deciles).",
                    paste0("Spearman correlation of mean |SHAP| across features between year models (A1): 2023\u20132024 ", f2(rhoS[set == "A1" & yil_1 == 2023 & yil_2 == 2024, spearman]), ", 2024\u20132025 ",
                           f2(rhoS[set == "A1" & yil_1 == 2024 & yil_2 == 2025, spearman]), ", 2023\u20132025 ", f2(rhoS[set == "A1" & yil_1 == 2023 & yil_2 == 2025, spearman]), ".")))
sure_ekle("Ek tablolar 3", t0)

t0 <- Sys.time()
sh <- fread("Results/H2_shap_onem.csv")
shg <- fread("Results/H2_shap_grup_paylari.csv")
ysg <- fread("Results/H2_yil_shap_grup_paylari.csv")
ysh <- fread("Results/H2_yil_shap.csv")
grup_en <- names(etk$grup)
sh_rows <- list(data.table(F = "Feature group, % of total mean |SHAP|", a = "", b = "", c = "", d = "", e = "", f = ""))
gs_ <- 1L
for (g in c(grup_en, "Other")) {
  v <- function(m) { x <- shg[model == m & grup == g, pay]; if (length(x)) f1(x) else "" }
  vy <- function(yy) { x <- ysg[set == "A1" & yil == yy & grup == g, pay]; if (length(x)) f1(x) else "" }
  if (all(c(v("A1_ana"), v("B1_ana"), v("A3_ana")) == "")) next
  sh_rows[[length(sh_rows) + 1]] <- data.table(F = g, a = v("A1_ana"), b = v("B1_ana"), c = v("A3_ana"), d = vy(2023), e = vy(2024), f = vy(2025))
}
sh_rows[[length(sh_rows) + 1]] <- data.table(F = "Features among the 15 most important in A1 or B1, mean |SHAP| (rank)", a = "", b = "", c = "", d = "", e = "", f = "")
gs_ <- c(gs_, length(sh_rows))
ilk <- unique(c(sh[model == "A1_ana"][order(sira)][1:15, degisken], sh[model == "B1_ana"][order(sira)][1:15, degisken]))
fmt_sh <- function(x, r) if (length(x) && !is.na(x)) paste0(formatC(x, format = "f", digits = 3), " (", r, ")") else ""
for (v in ilk) {
  m1 <- sh[model == "A1_ana" & degisken == v]
  m2 <- sh[model == "B1_ana" & degisken == v]
  m3 <- sh[model == "A3_ana" & degisken == v]
  yv <- function(yy) { x <- ysh[set == "A1" & yil == yy & degisken == v]; if (nrow(x)) fmt_sh(x$ortalama_mutlak_shap, x$sira) else "" }
  sh_rows[[length(sh_rows) + 1]] <- data.table(F = deg_et(v), a = if (nrow(m1)) fmt_sh(m1$ortalama_mutlak_shap, m1$sira) else "", b = if (nrow(m2)) fmt_sh(m2$ortalama_mutlak_shap, m2$sira) else "",
                                               c = if (nrow(m3)) fmt_sh(m3$ortalama_mutlak_shap, m3$sira) else "", d = yv(2023), e = yv(2024), f = yv(2025))
}
sh_t <- rbindlist(sh_rows)
setnames(sh_t, c("Feature", "A1", "B1", "A3", "2023", "2024", "2025"))
ek_cikar("shap", sh_t, "Contribution of features and feature groups to LightGBM predictions (TreeSHAP).", grup_satir = gs_, girinti = setdiff(seq_len(nrow(sh_t)), gs_), yatay = TRUE,
         ust = list(degerler = c("Feature", "2025 test set (models trained on 2023\u20132024)", "A1 year-specific models"), genislik = c(1, 3, 3), dikey = 1),
         notlar = c("A1: all households, income + structural; B1: non-poor households, structural + relative income; A3: A1 + financial strain. Weighted mean absolute SHAP values on the log-odds scale, averaged over five seeds.",
                    "Year-specific models were trained and evaluated within each survey year."))

bm <- fread("Results/H2_bicim_merdiveni.csv")
hs <- fread("Results/H2_etkilesim_H.csv")
hso <- fread("Results/H2_etkilesim_H_ozellik.csv")
bm_ad <- c(logit_lin = "Linear terms (ridge logistic)", logit = "Smooth main effects (ridge logistic, splines)", lgb_ek = "Boosted main effects, no interactions",
           lgb_d2 = "Boosted, pairwise interactions (depth-2 trees)", lgb = "Boosted, unrestricted interactions (main model)")
f3 <- function(x) formatC(x, format = "f", digits = 3)
f4 <- function(x) formatC(x, format = "f", digits = 4)
bm_rows <- list()
gs_ <- integer(0)
for (s_ in c("A1", "A2")) {
  bm_rows[[length(bm_rows) + 1]] <- data.table(M = if (s_ == "A1") "Income + structural features" else "Structural features only", a = "", b = "", c = "", d = "", e = "", f = "", g = "")
  gs_ <- c(gs_, length(bm_rows))
  x <- bm[set == s_][order(sira)]
  for (i in seq_len(nrow(x))) {
    r <- x[i]
    bm_rows[[length(bm_rows) + 1]] <- data.table(M = bm_ad[[r$basamak]], a = f4(r$cv_logloss), b = ga(r$logloss, r$logloss_alt, r$logloss_ust, 4), c = ga(r$auc, r$auc_alt, r$auc_ust, 3),
                                                 d = ga(r$duyarlilik, r$duyarlilik_alt, r$duyarlilik_ust), e = if (i == 1) "" else ga(r$d_logloss, r$d_logloss_alt, r$d_logloss_ust, 4),
                                                 f = if (i == 1) "" else ga(r$d_auc, r$d_auc_alt, r$d_auc_ust, 3), g = if (i == 1) "" else ga(r$d_duyarlilik, r$d_duyarlilik_alt, r$d_duyarlilik_ust))
  }
}
bm_t <- rbindlist(bm_rows)
setnames(bm_t, c("Model", "CV log-loss", "Log-loss (95% CI)", "AUC (95% CI)", "Sensitivity, % (95% CI)", "\u0394 log-loss", "\u0394 AUC", "\u0394 sensitivity, pp"))
hs_ilk <- hs[order(-H_mutlak)][1:5]
ek_cikar("bicim", bm_t, "Non-linearity and interactions: targeting models of increasing functional flexibility, 2025 main test set.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(bm_t)), gs_), yatay = TRUE,
         ust = list(degerler = c("Model", "Tuning folds", "2025 main test set", "Difference from the row above (95% CI)"), genislik = c(1, 1, 3, 3), dikey = 1),
         notlar = c(paste0("All models trained on 2023\u20132024 with the same features and year-blocked tuning; boosted models are LightGBM with interaction constraints (one feature per tree), depth-2 trees, or the unrestricted main model. Sensitivity at the poverty line's targeting rate. Differences: paired household bootstrap (",
                           nfmt(h2oz$bootstrap$B), " replicates); negative \u0394 log-loss and positive \u0394 AUC or sensitivity favor the more flexible model. The additive model on structural features selected the lowest learning rate and stopped close to the 30,000-round cap; the best configuration below the cap differed by 0.0001 in tuning-fold log-loss."),
                    paste0("Friedman's H statistic for the main income + structural model (", hso$n[1], " households drawn with probability proportional to weight; partial dependence on the log-odds scale): strongest pairs ",
                           paste(sprintf("%s \u00d7 %s %s", sapply(hs_ilk$degisken_1, deg_et), sapply(hs_ilk$degisken_2, deg_et), f3(hs_ilk$H_mutlak)), collapse = "; "),
                           " (root-mean-square interaction component, log-odds). Overall interaction strength of a feature with all others, H\u00b2 (share of the prediction variance): ",
                           paste(sprintf("%s %s", sapply(hso[order(-H2)][1:3]$degisken, deg_et), f3(hso[order(-H2)][1:3]$H2)), collapse = "; "), ".")))

d_rows <- list()
gs_ <- integer(0)
s15_setler <- c("temiz", "temiz_siki", "temiz_imza", "tam", "temiz_2023")
s15_satir <- function(x) as.data.table(as.list(setNames(x, paste0("v", 1:12))))
d_rows[[1]] <- s15_satir(c("All households: sensitivity at the poverty line's targeting rate", rep("", 11)))
gs_ <- 1L
eslik <- c(yoksul_60 = "yoksul_60", gelir_sirasi = "gelir_sirasi", cart_T2 = "cart_T2_2023", logit_A1 = "logit_A1_2023", lgb_A1 = "lgb_A1_2023")
s15_d <- function(sema_, nf_, kol_, kars_) {
  r <- h2f[sema == sema_ & nufus == nf_ & kol == kol_ & karsilastirma == kars_ & metrik == "duyarlilik"]
  if (!nrow(r)) "" else ga(r$fark, r$alt, r$ust)
}
s15_s <- function(sema_, nf_, kol_, nk_) {
  r <- h2m[sema == sema_ & nufus == nf_ & kol == kol_ & kapsama_noktasi == nk_]
  if (!nrow(r)) "" else f1(r$duyarlilik)
}
for (k in c("yoksul_60", "gelir_sirasi", "cart_T2", "cart_T2idari", "cart_T1T2", "l1_T2", "logit_lin_A1", "logit_A1", "lgb_A2i", "lgb_A2", "lgb_A1", "lgb_A3", "lgb_A4")) {
  hucre <- unlist(lapply(s15_setler, function(se) {
    k_ <- if (se == "temiz_2023") if (k %in% names(eslik)) eslik[[k]] else NA_character_ else k
    if (is.na(k_)) return(c("", ""))
    c(s15_s(se, "A", k_, if (k_ == "yoksul_60") "kendi" else "yoksulluk_orani"), if (k_ == "yoksul_60") "" else if (k_ == "gelir_sirasi") "\u2013" else s15_d(se, "A", k_, "yoksul_60"))
  }))
  r_e <- h2e[sema == "temiz" & nufus == "A" & kol == k]
  d_rows[[length(d_rows) + 1]] <- s15_satir(c(if (k %in% names(kol_ad)) kol_ad[[k]] else kol_ad2[[k]], hucre, if (nrow(r_e)) formatC(r_e$auc_agirliksiz, format = "f", digits = 3) else ""))
}
d_rows[[length(d_rows) + 1]] <- s15_satir(c("Non-poor households: sensitivity with 20% of households targeted", rep("", 11)))
gs_ <- c(gs_, length(d_rows))
for (k in c("gelir_sirasi", "cart_B_T2", "cart_B_T2gelir", "l1_B_T2", "logit_B1", "lgb_B2", "lgb_B1", "lgb_B3")) {
  hucre <- unlist(lapply(s15_setler, function(se) {
    if (se == "temiz_2023") return(c("", ""))
    c(s15_s(se, "B", k, "20"), if (k == "gelir_sirasi") "" else s15_d(se, "B", k, "gelir_sirasi@20"))
  }))
  r_e <- h2e[sema == "temiz" & nufus == "B" & kol == k]
  d_rows[[length(d_rows) + 1]] <- s15_satir(c(kol_ad2[[k]], hucre, if (nrow(r_e)) formatC(r_e$auc_agirliksiz, format = "f", digits = 3) else ""))
}
d_t <- rbindlist(d_rows)
setnames(d_t, c("Method", paste0(rep(c("Sensitivity, %", "\u0394, pp (95% CI)"), 5), rep(c("", " ", "  ", "   ", "    "), each = 2)), "AUC, unweighted"))
n_23 <- h[yil == 2025 & test_temiz_2023 == 1, .N]
ek_cikar("h2_duyarlilik", d_t, "Sensitivity of the targeting comparison to the definition of the test set, the training period and weighting.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(d_t)), gs_), yatay = TRUE,
         ust = list(degerler = c("Method", paste0("Main test set (n\u00a0=\u00a0", nfmt(h2oz$n_test$temiz), ")"), paste0("Strict cleaning (n\u00a0=\u00a0", nfmt(h2oz$n_test$temiz_siki), ")"),
                                 paste0("Signature-only cleaning (n\u00a0=\u00a0", nfmt(h2oz$n_test$temiz_imza), ")"), paste0("Full 2025 sample (n\u00a0=\u00a0", nfmt(h2oz$n_test$tam), ")"),
                                 paste0("Trained on 2023 only (n\u00a0=\u00a0", nfmt(n_23), ")"), "Main test set"), genislik = c(1, 2, 2, 2, 2, 2, 1), dikey = 1),
         notlar = c(paste0("Main test set: 2025 households not matched to 2023 or 2024 by member signature or reference-person key. Strict cleaning: additionally excludes households whose reference-person key or member signature occurs in 2023 or 2024 at all, including keys shared by several households. ",
                           "Signature-only cleaning: households unmatched by member signature alone (keeps re-interviewed one-person households and households whose composition changed). Full 2025 sample: all households. Trained on 2023 only: models trained on 2023 and tested on 2025 households not matched to 2023; hyperparameters were taken from the main tuning, whose folds include a 2024 training fold (no 2025 data were used)."),
                    paste0("\u0394: paired bootstrap difference in sensitivity from the poverty line at its targeting rate (all households) or from income ranking at the same targeting rate (non-poor households), in the same test set; 95% CI from ",
                           nfmt(h2oz$bootstrap$B), " household bootstrap replicates. \u2013, identical to the poverty line by construction.")))
sure_ekle("Ek tablolar 4", t0)

t0 <- Sys.time()
mod_ad <- c(minimal = "Minimal (age, sex; income in C1)", cekirdek = "Core covariates", nihai = "Final (core + selected)", esnek = "Fully interacted", lpm = "Linear probability (final)", ortusen_tabakalar = "Overlapping strata only")
h3_rows <- list()
gs_ <- integer(0)
for (dz in c("yetiskin", "hane")) for (kar in c("C1", "C2")) for (v in unique(h3_tab[duzey == dz & karsilastirma == kar, sonuc])) {
  h3_rows[[length(h3_rows) + 1]] <- data.table(M = paste0(kar_ad[[kar]], " \u00b7 ", sonuc_ad[[v]]), n = "", p0 = "", p1 = "", PD = "", PDi = "", PR = "")
  gs_ <- c(gs_, length(h3_rows))
  cr <- h3_ham[duzey == dz & satir == "fark" & ad == kar & sonuc == v]
  co <- h3_ham[duzey == dz & satir == "oran" & ad == kar & sonuc == v]
  if (nrow(cr)) h3_rows[[length(h3_rows) + 1]] <- data.table(M = "Crude (unadjusted)", n = nfmt(cr$n), p0 = f1(cr$p_referans), p1 = f1(cr$p_G2), PD = ga(cr$tahmin, cr$alt, cr$ust, 1),
                                                         PDi = ga(cr$tahmin, cr$alt_lin, cr$ust_lin, 1), PR = ga(co$tahmin, co$alt, co$ust, 2))
  for (mk in names(mod_ad)) {
    x <- h3_tab[duzey == dz & karsilastirma == kar & sonuc == v & model == mk]
    if (!nrow(x)) next
    g <- function(o, d = 1) { r <- x[olcu == o]; if (!nrow(r)) "" else if (!is.na(r$alt)) ga(r$tahmin, r$alt, r$ust, d) else ga(r$tahmin, r$tahmin - 1.96 * r$se_if, r$tahmin + 1.96 * r$se_if, d) }
    gi <- function(o, d = 1) { r <- x[olcu == o]; if (!nrow(r) || is.na(r$se_if)) "" else ga(r$tahmin, r$tahmin - 1.96 * r$se_if, r$tahmin + 1.96 * r$se_if, d) }
    pt <- function(o) { r <- x[olcu == o]; if (!nrow(r)) "" else f1(r$tahmin) }
    ana_ <- isTRUE(x$ana_model[1])
    h3_rows[[length(h3_rows) + 1]] <- data.table(M = paste0(mod_ad[[mk]], if (ana_) " (main)" else ""), n = nfmt(x$n[1]), p0 = pt("p0"), p1 = pt("p1"),
                                                 PD = if (mk %in% c("lpm", "ortusen_tabakalar")) gi("PD") else g("PD"), PDi = gi("PD"), PR = if (mk == "lpm") "" else if (mk == "ortusen_tabakalar") gi("PR", 2) else g("PR", 2))
  }
}
h3_t <- rbindlist(h3_rows)
setnames(h3_t, c("Model", "n", "Reference, %", "G2, %", "Difference, pp (95% CI)", "Difference, linearization 95% CI", "Prevalence ratio (95% CI)"))
ek_cikar("h3_tam", h3_t, "Standardized prevalence of low dietary frequency and heavy health-cost burden among food-insecure, non-poor adults and households, by model specification, 2025.",
         grup_satir = gs_, girinti = setdiff(seq_len(nrow(h3_t)), gs_), yatay = TRUE,
         notlar = c("Reference: G1 (food secure, not poor) in C1 and G3 (food insecure and poor) in C2. Standardized by g-computation to the comparison population; weights FB030 (adults) or HB040 (households). Crude: weighted prevalences in the same analytic sample without adjustment or standardization.",
                    "95% CI: household bootstrap (Rao\u2013Wu\u2013Yue rescaled bootstrap; 4,000 replicates for the main model, 2,000 otherwise, including the crude rows); linearization CI from influence functions with household clusters."))

hh_grup_ad <- c(G1 = "G1 food secure, all", G1_yoksul_degil = "G1 food secure, not poor (reference in C1)", G2 = "G2 food insecure, not poor", G3 = "G3 food insecure and poor (reference in C2)")
hh_rows <- list()
gs_ <- integer(0)
for (dz in c("yetiskin", "hane")) for (v in unique(h3_ham[duzey == dz, sonuc])) {
  hh_rows[[length(hh_rows) + 1]] <- data.table(G = paste0(sonuc_ad[[v]], if (dz == "hane") ", households" else ", adults"), n = "", o = "", p = "")
  gs_ <- c(gs_, length(hh_rows))
  for (g in names(hh_grup_ad)) {
    r <- h3_ham[duzey == dz & sonuc == v & satir == "grup" & ad == g]
    hh_rows[[length(hh_rows) + 1]] <- data.table(G = hh_grup_ad[[g]], n = nfmt(r$n), o = nfmt(r$olay), p = ga(r$tahmin, r$alt, r$ust, 1))
  }
}
hh_t <- rbindlist(hh_rows)
setnames(hh_t, c("Group", "n", "Events", "Weighted prevalence, % (95% CI)"))
tablo_cikar(hh_t, "Ek_H3_ham_oranlar", "Table S\u2013. Analytic samples of the dietary and health-cost comparisons: numbers, events and crude weighted prevalences by group, 2025.", klasor = ek_kl,
            grup_satir = gs_, girinti = setdiff(seq_len(nrow(hh_t)), gs_),
            notlar = c(paste0("Unweighted numbers; prevalences weighted (FB030 for adults, HB040 for households); 95% CI from ", nfmt(B_diger), " household bootstrap replicates (Rao\u2013Wu\u2013Yue), the multiplier matrix shared with the adjusted estimates. The meat outcome excludes ",
                              yt[et_tavuk_balik_siklik == 0, .N], " vegetarian or vegan adults by definition."),
                       paste0("C1 compares G2 with food-secure adults who are not poor, so its reference is not all of G1. Crude differences and prevalence ratios are the first row of each block in Supplementary Table S", ek_no[["h3_tam"]], ".")))

s17_ad <- c(h3_y, "saglik_yuk")
s17_sat <- list()
gs_ <- integer(0)
s17_ekle <- function(ad, x = NULL) {
  s17_sat[[length(s17_sat) + 1]] <<- c(ad, if (is.null(x)) rep("", length(s17_ad)) else x)
  if (is.null(x)) gs_ <<- c(gs_, length(s17_sat))
}
gfmt <- function(x, o, d = 1) { r <- x[olcu == o]; if (!nrow(r)) "" else ga(r$tahmin, r$alt, r$ust, d) }
s17_x <- function(an) lapply(s17_ad, function(v) h3_ekler[analiz %in% an & sonuc == v])
s17_n <- function(xs) sapply(xs, function(x) paste0(nfmt(x$n[1]), " (", nfmt(x$olay[1]), ")"))
s17_ekle("Three groups standardized to all adults (households), no income adjustment")
x0 <- s17_x(c("C0_uc_grup", "C0_uc_grup_hane"))
lab0 <- c(p_G1 = "G1 food secure, %", p_G2 = "G2 food insecure, not poor, %", p_G3 = "G3 food insecure and poor, %", PD_G2_G1 = "G2 \u2212 G1, pp", PD_G2_G3 = "G2 \u2212 G3, pp",
          konum = "Position of G2 between G1 (0) and G3 (1)")
for (o in names(lab0)) s17_ekle(lab0[[o]], sapply(x0, function(x) gfmt(x, o, if (o == "konum") 2 else 1)))
s17_ekle("n (events)", s17_n(x0))
s17_ekle("Food-insecure adults (households) by equivalized income relative to the median, %")
x3 <- s17_x(c("C3_gelir_bandi", "C3_gelir_bandi_hane"))
for (bb in levels(yt$f_band)) s17_ekle(c("1" = "<0.6", "2" = "0.6\u20130.8", "3" = "0.8\u20131.0", "4" = "1.0\u20131.5", "5" = ">1.5")[[bb]], sapply(x3, function(x) gfmt(x, paste0("p_B", bb))))
s17_ekle("n (events)", s17_n(x3))
s17_ekle("Meat <1/week with vegetarian or vegan adults counted as low intake")
for (an in c("C1_vejetaryen_dahil", "C2_vejetaryen_dahil")) {
  x <- h3_ekler[analiz == an]
  s17_ekle(paste0(if (an == "C1_vejetaryen_dahil") "C1, G2 \u2212 G1" else "C2, G2 \u2212 G3", ", pp; prevalence ratio (n\u00a0=\u00a0", nfmt(x$n[1]), ")"), c(paste0(gfmt(x, "PD"), "; ", gfmt(x, "PR", 2)), "", "", ""))
}
ek_t <- as.data.table(do.call(rbind, s17_sat))
setnames(ek_t, c("Estimate", "Meat, chicken or fish <1/week", "Fruit <1/day", "Vegetables or salad <1/day", "Medical costs a heavy burden (households)"))
ku1 <- h3_ekler[analiz == "C1_karsilanmayan_odeme_minimal"]
ku2 <- h3_ekler[analiz == "C2_karsilanmayan_odeme_minimal"]
ek_cikar("h3_ek", ek_t, "Additional dietary and health-cost estimates: three-group standardization, income gradient among the food insecure, and sensitivity analyses, 2025.",
         grup_satir = gs_, girinti = setdiff(seq_len(nrow(ek_t)), gs_), yatay = TRUE,
         notlar = c("Covariates as in C2 (age, sex, education, region, household size, number of children and covariates selected for C2); income is not adjusted because it defines the groups. Position: (G2 \u2212 G1) / (G3 \u2212 G1). Estimates with 95% CI from 2,000 household bootstrap replicates.",
                    paste0("Unmet medical need due to cost, among adults reporting a need for medical care (few events; minimal model: age, sex; income in C1): C1 ", gfmt(ku1, "PD"), " pp, prevalence ratio ", gfmt(ku1, "PR", 2),
                           " (n\u00a0=\u00a0", nfmt(ku1$n[1]), "); C2 ", gfmt(ku2, "PD"), " pp, prevalence ratio ", gfmt(ku2, "PR", 2), " (n\u00a0=\u00a0", nfmt(ku2$n[1]), ").")))

sm_rows <- list()
gs_ <- integer(0)
for (icc_ in sort(unique(s1o$icc))) {
  sm_rows[[length(sm_rows) + 1]] <- data.table(S = paste0("Latent ICC ", icc_), a = "", b = "", c = "", d = "")
  gs_ <- c(gs_, length(sm_rows))
  for (i in which(s1o$icc == icc_)) {
    r <- s1o[i]
    if (r$test_seti == "eslesen") next
    if (startsWith(r$test_seti, "temiz_gizli") && r$ortusme_tanim != "gercek") next
    ts_ad <- if (r$test_seti == "tam") "full 2025 sample" else if (r$test_seti == "temiz") "unmatched households" else paste0("unmatched, ", format(as.numeric(sub("temiz_gizli_", "", r$test_seti))), "% undetected re-interviews")
    sm_rows[[length(sm_rows) + 1]] <- data.table(S = paste0(if (r$ortusme_tanim == "gercek") paste0("Observed overlap (", f1(100 * r$ortusme_payi), "%)") else paste0("Overlap ", f1(100 * r$ortusme_payi), "%"), ", ", ts_ad),
                                                 a = paste0(formatC(sifir(r$iyimserlik_auc, 4), format = "f", digits = 4), " (", formatC(r$iyimserlik_auc_mcse, format = "f", digits = 4), ")"),
                                                 b = paste0(f2(r$iyimserlik_duyarlilik), " (", f2(r$iyimserlik_duyarlilik_mcse), ")"), c = f2(r$egim_paylasilan), d = f2(r$egim_bagimsiz))
  }
}
sm_t <- rbindlist(sm_rows)
setnames(sm_t, c("Overlap with the training year, test set", "AUC optimism (MCSE)", "Sensitivity optimism, pp (MCSE)", "Calibration slope, shared effects", "Calibration slope, independent effects"))
ek_cikar("sim_sonuc", sm_t, "Simulation S1: optimism of out-of-time performance from households re-interviewed across survey years.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(sm_t)), gs_), yatay = TRUE,
         notlar = c("Optimism: metric when outcomes share the household random effect of the training year minus the same metric with independent effects; MCSE, Monte Carlo standard error. Sensitivity at the poverty line's targeting rate. ICC, intraclass correlation of the latent household effect.",
                    "Undetected re-interviews: randomly chosen re-interviewed households evaluated as if unmatched, as a share of the evaluated set; the largest share equals the share of households in the signature-only cleaned test set that the reference-person key identifies as re-interviewed; undetected-overlap rows are shown for the observed overlap only."))

f3 <- function(x) formatC(x, format = "f", digits = 3)
s2o[, uyumlu := as.logical(uyumlu)]
s2kf[, uyumlu := as.logical(uyumlu)]
s2_gozlenen <- s2bilgi$gozlenen
s2_bk <- s2bilgi$S2_B_kalibrasyon[[s2bilgi$S2_B_denetim$kalibrasyon_secilen]]
sm_rows <- list()
gs_ <- integer(0)
for (tr_ in c("ayrimci_degil", "gelire_gore")) {
  sm_rows[[length(sm_rows) + 1]] <- data.table(Sp = if (tr_ == "ayrimci_degil") "Non-differential misclassification" else "Income-differential misclassification (specificity 5 pp lower in income quintiles 1\u20132)",
                                               Se = "", a = "", b = "", c = "", d = "", e = "", f = "", g = "")
  gs_ <- c(gs_, length(sm_rows))
  k <- s2tas[tur == tr_ & (uyumlu_A | uyumlu_B | Sp == 0.9)][order(Sp, Se)]
  for (i in seq_len(nrow(k))) {
    r <- k[i]
    ilk <- i == 1 || k$Sp[i - 1] != r$Sp
    sm_rows[[length(sm_rows) + 1]] <- data.table(Sp = if (!ilk) "" else paste0(if (r$Sp >= 0.995) f3(r$Sp) else f2(r$Sp), if (!r$uyumlu_A && !r$uyumlu_B) "\u2020" else ""),
                                                 Se = paste0(f2(r$Se), if (tr_ == "ayrimci_degil" && r$Se == 1 && r$Sp == 1) "^{a}" else ""),
                                                 a = f1(r$kapali_form_dislama_hane), b = f1(r$kapali_form_dislama_kisi),
                                                 c = if (r$uyumlu_A) f1(r$A_kural_eksi_esik) else "\u2013", d = if (r$uyumlu_A) f1(r$A_lgb_eksi_esik) else "\u2013",
                                                 e = if (r$uyumlu_B) f1(r$B_kural_eksi_esik) else "\u2013", f = if (r$uyumlu_B) f1(r$B_lgb_eksi_esik) else "\u2013",
                                                 g = if (r$uyumlu_A && r$uyumlu_B) "A, B" else if (r$uyumlu_A) "A" else if (r$uyumlu_B) "B" else "\u2013")
  }
}
sm_t <- rbindlist(sm_rows)
setnames(sm_t, c("Specificity", "Sensitivity", "Households", "Persons", "Rule set", "LightGBM", "Rule set ", "LightGBM ", "Compatible design"))
huc_min <- s2huc[which.min(gozlenen_FI)]
rsk_min <- s2rsk[denetimde == TRUE][which.min(gozlenen_FI)]
ek_cikar("sim_s2", sm_t, "Simulation S2: exclusion error and targeting performance under misclassification of the food insecurity item, by design of the misclassification.", grup_satir = gs_, girinti = setdiff(seq_len(nrow(sm_t)), gs_),
         ust = list(degerler = c("Specificity", "Sensitivity", "Exclusion error, % (closed form)", "Design A: difference from the poverty line, pp", "Design B: difference from the poverty line, pp", "Compatible design"),
                    genislik = c(1, 1, 2, 2, 2, 1), dikey = c(1, 2, 9)), yatay = TRUE,
         notlar = c(paste0("Exclusion error: share of food-insecure households (persons) that are not income poor, implied by sensitivity (Se), specificity (Sp) and the observed prevalences in cells of equivalized income quintile \u00d7 poverty status (closed form; the same under both designs). ",
                           "Differences: sensitivity at the poverty line's targeting rate minus that of the poverty line in the 2025 main test set, mean of ", max(s2o$M), " simulated assignments of true status; rule set, depth-3 tree on structural features; LightGBM, income + structural features; observed ",
                           f1(s2_gozlenen$kural_eksi_esik), " and ", f1(s2_gozlenen$lgb_eksi_esik), " pp."),
                    "Design A: Se and Sp hold within each cell, and true status is assigned by Bayes' rule from the cell's observed prevalence, so within a cell it depends on household characteristics only through the observed item. Design B: Se and Sp hold for every household, and true status is assigned from each household's calibrated probability of reporting food insecurity (out-of-time LightGBM score recalibrated on 2025 households with cell indicators and a restricted cubic spline of its logit).",
                    paste0("Compatible with the observed data: A, every cell's observed prevalence lies within [1 \u2212 Sp, Se] (Sp \u2265 ", f3(s2kf$uyumlu_en_kucuk_Sp[1]), ", Se \u2265 ", f3(s2kf$uyumlu_en_kucuk_Se[1]),
                           "); B, fewer than 1% of households (weighted) have a calibrated probability outside [1 \u2212 Sp, Se], and these were truncated (Sp \u2265 ", f3(s2_bk$B_en_kucuk_Sp), ", Se \u2265 ", f3(s2_bk$B_en_kucuk_Se),
                           "). In deciles of LightGBM risk the lowest decile has an observed prevalence of ", f1(rsk_min$gozlenen_FI), "%, which requires Sp \u2265 ", f3(s2kf$risk_en_kucuk_Sp[1]), " (", f3(s2kf$risk_en_kucuk_Sp_2se[1]),
                           " allowing for two standard errors). \u2020 Compatible with neither design; closed form only; \u2013, not simulated."),
                    "Rows with Sp 0.999\u20131.000 and Se 0.98\u20131.00 were added because no scenario of the original grid (Sp 0.90\u20130.99, Se 0.80\u20130.95) was compatible with design B; Sp 0.92 and 0.94 are compatible with neither design. ^{a} No misclassification; reproduces the observed values."))

sm_rows <- list()
s3_ad <- c(dislama_hatasi = "Exclusion error", kural_duyarlilik = "Rule-set sensitivity", kural_ppv = "Rule-set PPV")
for (i in seq_len(nrow(s3o))) {
  r <- s3o[i]
  sm_rows[[length(sm_rows) + 1]] <- data.table(S = s3_ad[[r$olcu]], a = f1(r$gercek), b = formatC(r$yanlilik, format = "f", digits = 3), c = f2(r$ampirik_se), e = f2(r$ortalama_boot_se), d = paste0(f1(r$kapsama), " (", f1(r$kapsama_mcse), ")"))
}
sm_t <- rbindlist(sm_rows)
setnames(sm_t, c("Measure", "True value, %", "Bias, pp", "Empirical SE", "Mean bootstrap SE", "Coverage, % (MCSE)"))
ek_cikar("sim_s3", sm_t, "Simulation S3: bias and coverage of household bootstrap intervals.",
         notlar = c("95% percentile intervals from 200 household bootstrap replicates (Rao\u2013Wu\u2013Yue rescaled bootstrap) per simulated sample; MCSE, Monte Carlo standard error. SE, standard error. True value: the value in the pseudo-population, whose outcomes are model-based, so it differs from the observed exclusion error (68.1%)."))
sure_ekle("Ek tablolar 5", t0)

t0 <- Sys.time()
xl_dosya <- "Results/tablolar_tumu.xlsx"
saveWorkbook(wb, xl_dosya, overwrite = TRUE)
st <- system2(py, c("Codes/xlsx_simge.py", shQuote(xl_dosya)), stdout = TRUE, stderr = TRUE)
cat(st, sep = "\n")
sure_ekle("tablolar_tumu.xlsx", t0)

t0 <- Sys.time()
yuv <- function(dt, d = 3) { dt <- copy(as.data.table(dt)); for (j in names(dt)) if (is.numeric(dt[[j]])) set(dt, j = j, value = round(dt[[j]], d)); dt }
an <- setNames(akis$n, akis$dugum)
boot_yak <- rbindlist(boot_kayit)
boot_yak[, ana_model := grepl(paste0("_B", B_ana, "$"), anahtar)]
fwrite(boot_yak, "Results/H3_bootstrap_yakinsama.csv")
boot_yak_oz <- boot_yak[, .(model_sayisi = .N, replikat_toplam = sum(B), iter_en_buyuk = max(iter_en_buyuk), iter_sinira_ulasan = sum(iter_sinira_ulasan)), keyby = ana_model]
print(boot_yak_oz)
s2_A_ond <- fread(file.path(simdir, "S2_A_ondalik_SeSp.csv"))[gelir_grubu == "tum"]
sayilar <- list(
  olusturma = format(Sys.time()),
  orneklem = as.list(an),
  dogrulama = list(toplam = nrow(dogr), tuttu = dogr[durum == "Tuttu", .N], ortusme = yuv(eslesme_ozet, 1), test_bilesimi = yuv(ortusme_bilesim, 2)),
  H1 = list(temel = yuv(h1_ana[tr63_haric == FALSE & ibbs2_tabaka == FALSE, .(yil, duzey, olcu, esik, tahmin, se, alt, ust, n, olay)]),
            farklar = yuv(h1_fark[tr63_haric == FALSE & ibbs2_tabaka == FALSE, .(olcu, esik, duzey, yil_1, yil_2, fark, se_fark, alt, ust, p)], 4),
            tr63_haric = yuv(h1_ana[tr63_haric == TRUE, .(yil, duzey, olcu, esik, tahmin, alt, ust)]),
            tr63_haric_farklar = yuv(h1_fark[tr63_haric == TRUE, .(olcu, esik, duzey, yil_1, yil_2, fark, alt, ust)]),
            farklar_bootstrap = yuv(h1_fark_bs, 4), kapasite_tabani = yuv(h1_taban, 3),
            ibbs2_se_orani = list(medyan = round(median(se_oran$oran), 3), min = round(min(se_oran$oran), 3), max = round(max(se_oran$oran), 3)),
            erreygers = yuv(h1_ci, 4), erreygers_farklar = yuv(ci_fark, 4), gelir_egrisi = yuv(egri_test, 4),
            kirilimlar_2025 = yuv(h1_kir[yil == 2025, .(duzey, kirilim, kategori, n, n_FI, FI, FI_se, dislama, dislama_se, kacirilan_bilesim, kucuk_hucre)], 2)),
  H2 = list(ozet = h2oz, hiperparametreler = yuv(hp, 5), metrikler_temiz = yuv(h2m[sema == "temiz"], 2), metrikler_tam = yuv(h2m[sema == "tam"], 2), metrikler_2023 = yuv(h2m[sema == "temiz_2023"], 2),
            metrikler_temiz_imza = yuv(h2m[sema == "temiz_imza"], 2), metrikler_temiz_siki = yuv(h2m[sema == "temiz_siki"], 2), bicim_merdiveni = yuv(bm, 4), etkilesim_H = yuv(hs, 4), etkilesim_H_ozellik = yuv(hso, 4),
            eslesik_farklar = yuv(h2f, 2), esiksiz = yuv(h2e, 4), kurallar = yuv(kr2, 2), yil_matrisi = yuv(ym, 4), psi = yuv(psi, 4), shap_spearman = yuv(rhoS, 3),
            shap_onem = yuv(sh[sira <= 20], 4), shap_grup = yuv(shg, 2), yil_shap_grup = yuv(ysg, 2), tohum = yuv(fread("Results/H2_tohum_degiskenligi.csv"), 4),
            aralik_yontemleri = yuv(fread("Results/H2_aralik_yontemleri.csv"), 3), tavan = yuv(tv, 3), kazanc_payi = yuv(fread("Results/H2_kazanc_payi.csv"), 2),
            model_model_farklar = yuv(fread("Results/H2_model_model_farklar.csv"), 2), secilen_profil = yuv(fread("Results/H2_secilen_profil.csv"), 3),
            esiksiz_GA = yuv(fread("Results/H2_esiksiz_metrikler_GA.csv"), 4), arama_uzayi_satir = nrow(fread("Results/H2_arama_uzayi_tanim.csv")),
            modeller = list(liste = fread("Results/modeller/model_listesi.csv"), tahmin_uygula_denetim = fread("Results/modeller/tahmin_uygula_denetim.csv"))),
  H3 = list(ana = yuv(h3_tab[ana_model == TRUE, .(duzey, karsilastirma, sonuc, model, olcu, tahmin, alt, ust, se_if, se_boot, se_if_ibbs2, n, olay, n_A1, n_A0, npar, B)], 3),
            tum_modeller = yuv(h3_tab[, .(duzey, karsilastirma, sonuc, model, ana_model, olcu, tahmin, alt, ust, se_if, n, olay)], 3),
            ek = yuv(h3_ekler[, .(analiz, sonuc, olcu, tahmin, alt, ust, se_if, n, olay)], 3), tanilar = yuv(h3t, 4), kovaryat_secimi = yuv(kov_sec, 3),
            grup_sayilari = yuv(h3_grup_n, 2), bootstrap = list(B_ana = B_ana, B_diger = B_diger, tohum = 20261027, yontem = "Rao-Wu-Yue rescaled bootstrap, n-1 households with replacement, one shared multiplier matrix"),
            ham_oranlar = yuv(h3_ham, 3), bootstrap_yakinsama = boot_yak_oz, reis_egitim_yedek_hane = reis_yedek),
  veri = list(eksik_veri = yuv(eksik_tab, 3), orneklem_karsilastirma = yuv(orneklem_kar, 3), gelistirme_benzersiz = gel_benzersiz),
  simulasyon = list(S1 = yuv(s1o, 4), S2 = yuv(s2o, 3), S3 = yuv(s3o, 3), senaryolar = yuv(sim_senaryo, 3), S3_aralik_yontemleri = yuv(fread("Results/S3_aralik_kapsamasi.csv"), 3),
                    S2_kapali_form = yuv(s2kf, 3), S2_tani_eski = yuv(s2tn, 3), S2_hucreler = yuv(s2huc, 2), S2_risk_hucreleri = yuv(s2rsk, 2),
                    S2_tasarimlar = yuv(s2tas, 4), S2_B_kalibrasyon = s2bilgi$S2_B_kalibrasyon, S2_B_denetim = s2bilgi$S2_B_denetim, S2_ek_senaryolar = s2bilgi$S2_ek_senaryolar,
                    S2_A_ondalik_SeSp = yuv(s2_A_ond, 4))
)
writeLines(toJSON(sayilar, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null"), "Results/sayilar.json")
writeLines(capture.output(sessionInfo()), "Results/sessionInfo.txt")
pk <- c("base", "data.table", "arrow", "readxl", "survey", "splines", "flextable", "officer", "future", "furrr", "jsonlite", "openxlsx", "MASS")
atif <- unlist(lapply(pk, function(x) c(paste0("==== ", x, " ", if (x == "base") as.character(getRversion()) else as.character(packageVersion(x)), " ===="), capture.output(print(citation(x), style = "text")), "")))
py_surum <- tryCatch(system2(py, c("-I", "-c", shQuote("import importlib.metadata as m;print(';'.join(f'{p}={m.version(p)}' for p in ['numpy','pandas','scipy','matplotlib','pyarrow','scikit-learn','lightgbm','shap','joblib','openpyxl','torch']))")), stdout = TRUE), error = function(e) "")
py_atif <- c("==== Python kutuphaneleri ====", paste("Surumler:", py_surum),
             "Python: Python Software Foundation. Python Language Reference, version 3.13. https://www.python.org",
             "LightGBM (README onerisi): Ke G, Meng Q, Finley T, Wang T, Chen W, Ma W, Ye Q, Liu TY. LightGBM: A highly efficient gradient boosting decision tree. Advances in Neural Information Processing Systems 30 (NIPS 2017): 3146-3154.",
             "SHAP (README onerisi): Lundberg SM, Lee SI. A unified approach to interpreting model predictions. Advances in Neural Information Processing Systems 30 (NIPS 2017): 4765-4774.",
             "TreeSHAP (README onerisi): Lundberg SM, Erion G, Chen H, DeGrave A, Prutkin JM, Nair B, Katz R, Himmelfarb J, Bansal N, Lee SI. From local explanations to global understanding with explainable AI for trees. Nature Machine Intelligence 2020;2:56-67. doi:10.1038/s42256-019-0138-9",
             "scikit-learn: Pedregosa F, Varoquaux G, Gramfort A, et al. Scikit-learn: Machine learning in Python. Journal of Machine Learning Research 2011;12:2825-2830.",
             "NumPy: Harris CR, Millman KJ, van der Walt SJ, et al. Array programming with NumPy. Nature 2020;585:357-362. doi:10.1038/s41586-020-2649-2",
             "pandas: McKinney W. Data structures for statistical computing in Python. Proceedings of the 9th Python in Science Conference 2010:56-61; The pandas development team. pandas-dev/pandas: Pandas. Zenodo. doi:10.5281/zenodo.3509134",
             "SciPy: Virtanen P, Gommers R, Oliphant TE, et al. SciPy 1.0: fundamental algorithms for scientific computing in Python. Nature Methods 2020;17:261-272. doi:10.1038/s41592-019-0686-2",
             "Matplotlib: Hunter JD. Matplotlib: A 2D graphics environment. Computing in Science & Engineering 2007;9(3):90-95. doi:10.1109/MCSE.2007.55",
             "joblib: Joblib developers. joblib: running Python functions as pipeline jobs. https://joblib.readthedocs.io (yazilim; hakemli atif onerisi yok)",
             "Apache Arrow (pyarrow): Apache Software Foundation. Apache Arrow. https://arrow.apache.org (yazilim)",
             "Not: LightGBM ve SHAP atiflari paketlerin GitHub README dosyalarindaki onerilerdir; gonderimden once guncel README ile karsilastirin.")
writeLines(c(atif, py_atif), "Results/paket_atiflari.txt")
py_env <- tryCatch(system2("/Users/salim/.local/bin/uv", c("pip", "list", "--python", py), stdout = TRUE, stderr = TRUE), error = function(e) "uv pip list calismadi")
writeLines(c(paste("Python:", py, "(uv sanal ortami)"), system2(py, "--version", stdout = TRUE, stderr = TRUE), "", py_env), "Results/python_ortam.txt")
strobe <- c("# Sample flow and STROBE notes (generated by analiz.R)", "",
  "## Flow", "",
  paste0("- ILCS cross-sections 2023-2025: ", nfmt(an[["kisi_toplam"]]), " persons in ", nfmt(an[["hane_toplam"]]), " households (2023: ", nfmt(an[["hane_2023"]]), "; 2024: ", nfmt(an[["hane_2024"]]), "; 2025: ", nfmt(an[["hane_2025"]]), " households)."),
  "- H1: each survey year analyzed separately at household (HB040) and person (FK050, household clusters) level; no pooling. 2023 has no TR63 households.",
  paste0("- H2: training and year-blocked tuning on 2023 + 2024 (", nfmt(an[["egitim_hane"]]), " households; non-poor model: ", nfmt(an[["egitim_yoksul_degil"]]), "). Tuning validation folds restricted to households not matched to the training year (2024: ", nfmt(an[["kat_2024_temiz"]]), "; 2023: ", nfmt(an[["kat_2023_temiz"]]), ")."),
  paste0("- H2 main test set: ", nfmt(an[["test_temiz"]]), " 2025 households not matched to 2023 or 2024 (", nfmt(an[["test_temiz_tek_kisili"]]), " one-person); ", nfmt(an[["test_eslesen"]]), " matched households added back in the full-2025 sensitivity test."),
  paste0("- H3: ", nfmt(an[["yetiskin_2025"]]), " adults aged >=18 with an individual questionnaire in 2025 (G1 ", nfmt(an[["yetiskin_G1"]]), ", G2 ", nfmt(an[["yetiskin_G2"]]), ", G3 ", nfmt(an[["yetiskin_G3"]]), "); meat outcome excludes ", an[["vejetaryen"]], " vegetarian or vegan adults; health-cost outcome ", nfmt(an[["hane_2025_saglik"]]), " households."),
  "- Missing data: no missing values in H3 model covariates for adults; household models use the highest adult education when the reference person has no individual record. ML: missing values native in LightGBM and trees; indicator plus median in logistic models.", "",
  "## STROBE checklist notes (cross-sectional)", "",
  "- Title/abstract (1): repeated cross-sections of TurkStat ILCS 2023-2025; household and person level.",
  "- Setting (5): fieldwork March-July 2023 and 2024, February-June 2025; income reference year preceding the survey.",
  "- Variables (7): food insecurity HE090 (single item); income poverty at 60% of median; structural features in Supplementary Table S2; dietary outcomes MODUL1_F_8, MODUL1_F_9, MODUL2_F_5; health-cost burden MODUL1_H_1/H_3.",
  "- Bias (9): rotational panel overlap handled by member-signature and reference-person-key matching and a cleaned test set (simulation S1 quantifies optimism from undetected overlap); single-item outcome misclassification (simulation S2).",
  "- Statistical methods (12): survey-weighted estimation with household clusters; linearization and household bootstrap; g-computation; LightGBM, ridge, lasso and depth-3 trees; SHAP.",
  "- Limitations (19): no stratum/PSU identifiers (intervals approximate; design-effect sensitivity in the supplement); HE090 is a single affordability item, not a validated food insecurity scale; households that moved or changed reference person cannot be matched; nominal incomes (relative measures used).")
writeLines(strobe, "Results/strobe_akis.md")
hpA1 <- hp[set == "A1"]
tripod <- c("# TRIPOD+AI notes for the targeting models (generated by analiz.R)", "",
  "- Data source (5a-b): TurkStat ILCS cross-sections 2023-2025; household level, one record per household; development 2023-2024, evaluation 2025 (temporal validation).",
  "- Participants (6): all private households (Model A); households above the 60% poverty line (Model B).",
  "- Outcome (7): household cannot afford a meal with meat, chicken or fish every second day (HE090 = 2); assessed at interview by one respondent; not blinded to predictors.",
  "- Predictors (8): four layers (income; structural; financial strain; deprivation items); leakage list excludes items containing HE090 (Supplementary Table S2).",
  paste0("- Sample size (9): development ", nfmt(an[["egitim_hane"]]), " households; main test ", nfmt(an[["test_temiz"]]), " households with ", nfmt(h[yil == 2025 & test_temiz == 1, sum(FI)]), " events."),
  "- Missing data (10): native handling in LightGBM and trees; indicator plus median imputation in logistic models; no imputation of the outcome.",
  paste0("- Model development (12): LightGBM (binary log-loss, HB040 weights); three-stage random search (broad, focused, seed re-evaluation) plus boundary extension, year-blocked folds with overlap-cleaned validation sets, early stopping; final A1: learning rate ",
         formatC(hpA1$learning_rate, format = "f", digits = 4), ", ", hpA1$num_leaves, " leaves, min. data in leaf ", hpA1$min_data_in_leaf, ", ", hpA1$n_tur_final, " rounds; five seeds averaged. Ridge and lasso logistic (scikit-learn); depth-3 CART (minimum leaf weight, split criterion and cost-complexity parameter tuned, the last over the union of both folds' pruning paths evaluated in both folds; selected \u03b1 = ", paste(unique(sapply(h2oz$cart, function(z) trimws(formatC(z$alpha, format = "g", digits = 2)))), collapse = ", "), " for every rule set)."),
  "- Analysis history: hyperparameter search was widened after first results were seen (search boundaries reached); the test-set cleaning was extended to reference-person-key matching after peer review; both changes are logged in the analysis report.",
  paste0("- Performance (12-13): weighted sensitivity, PPV, child coverage at fixed targeting rates; AUC, PR-AUC, Brier, calibration intercept and slope, decision curves; ", nfmt(h2oz$bootstrap$B), " household bootstrap replicates with identical draws for all methods."),
  "- Model updating and drift (12, 23): 3 x 3 year matrix, calibration drift of the 2023 model, population stability index, SHAP rank stability.",
  "- Fairness/subgroups (14): child coverage reported; results by household type for the poverty line (Supplementary Table S7).",
  "- Interpretability (12): TreeSHAP global importance and dependence; functional-form ladder (linear, smooth additive, boosted additive, pairwise, unrestricted) and Friedman H statistics for interactions; plain-language rule sets.",
  "- Limitations (25): residual panel overlap among households that moved or changed reference person; simulation S1 quantifies optimism from undetected overlap; single-item outcome; external validity beyond Turkey not assessed.",
  "- Model presentation (22): intercepts, coefficients and preprocessing parameters of the ridge and lasso models in Results/modeller; Codes/tahmin_uygula.py scores a household table with them. Trained gradient-boosting models are not distributed because individual trees contain leaves based on fewer than five training households; they are re-created exactly by the code from the licensed microdata.",
  "- Code and data availability (27): code in Codes/; micro data available from TurkStat on application.")
writeLines(tripod, "Results/tripod_notlari.md")
sure_ekle("sayilar.json ve belgeler", t0)
sure_tab <- rbindlist(sureler)
ml_sure <- if (file.exists("Results/log/ml_sureler.csv")) fread("Results/log/ml_sureler.csv") else NULL
fwrite(sure_tab, "Results/log/analiz_sureleri.csv")
print(sure_tab)
cat("analiz.R bitti. Toplam sure (dk):", round(as.numeric(difftime(Sys.time(), baslangic, units = "mins")), 2), "\n")
sink()
