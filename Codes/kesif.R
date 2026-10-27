options(warn = 1, width = 160)
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(splines)
})
set.seed(20251026)
ddir <- "R_Data ve Python Data"
rdir <- "Results/kesif"
dir.create(rdir, showWarnings = FALSE, recursive = TRUE)
hq <- file.path(ddir, "hane_2023_2025.parquet")
if (!file.exists(hq)) stop("hane_2023_2025.parquet yok: once Rscript Codes/analiz.R calistirin (veri hazirligi kesif.R'yi kendisi cagirir)")
h <- as.data.table(read_parquet(hq))
cat("Hane satirlari:", nrow(h), " yil:", paste(h[, .N, keyby = yil]$N, collapse = " / "), "\n")
t_bas <- Sys.time()

on <- rbindlist(lapply(c("hane", "kisi"), function(dz) {
  w <- if (dz == "hane") "HB040" else "FK050"
  h[, .(duzey = dz, FI = 100 * sum(FI * get(w) * if (dz == "kisi") hane_buyuklugu else 1) / sum(get(w) * if (dz == "kisi") hane_buyuklugu else 1),
        yoksul = 100 * sum(yoksul * get(w) * if (dz == "kisi") hane_buyuklugu else 1) / sum(get(w) * if (dz == "kisi") hane_buyuklugu else 1),
        FI_icinde_yoksul_olmayan_pay = 100 * sum(FI * (1 - yoksul) * get(w) * if (dz == "kisi") hane_buyuklugu else 1) / sum(FI * get(w) * if (dz == "kisi") hane_buyuklugu else 1),
        yoksul_icinde_FI_pay = 100 * sum(FI * yoksul * get(w) * if (dz == "kisi") hane_buyuklugu else 1) / sum(yoksul * get(w) * if (dz == "kisi") hane_buyuklugu else 1),
        cocuk_FI_yoksul_degil_milyon = sum(n_cocuk * FI * (1 - yoksul) * FK050) / 1e6, cocuk_FI_milyon = sum(n_cocuk * FI * FK050) / 1e6,
        n_hane = .N, n_FI = sum(FI), n_FI_yoksul_degil = sum(FI * (1 - yoksul))), keyby = yil]
}))
fwrite(on, file.path(rdir, "kesif_oran_onizleme.csv"))
print(on)

katalog <- rbindlist(list(
  data.table(katman = "T1 gelir", tur = "sayisal", degisken = c("log_goreli_gelir", "yoksulluk_acigi_60", "pay_ucret", "pay_mutesebbis", "pay_emekli", "pay_sosyal", "pay_ozel_transfer", "kira_orani", "konut_orani_k")),
  data.table(katman = "T1 gelir", tur = "kategorik", degisken = c("gelir_dilim10", "hane_gelir_dilim5", "yoksul_50", "sosyal_yardim_var", "ozel_transfer_var", "kira_geliri_var", "konut_asiri_k")),
  data.table(katman = "T2 yapisal", tur = "sayisal", degisken = c("reis_yas", "hane_buyuklugu", "n_cocuk", "n_0_5", "n_65plus", "n_75plus", "n_yetiskin", "n_kronik", "n_gali", "n_kotu_saglik", "n_karsilanmayan",
                                                                   "n_calisan", "n_issiz", "n_emekli", "n_ev_isi", "n_kayitsiz", "n_yevmiyeli", "n_gecici", "calisan_oran", "bagimli_oran", "is_yogunlugu",
                                                                   "HH060", "HH070", "m2_kisi", "goreli_kira")),
  data.table(katman = "T2 yapisal", tur = "kategorik", degisken = c("HB030", "HB031", "HB050", "reis_cinsiyet", "reis_medeni", "reis_calisma7", "reis_fk210", "reis_egitim", "egitim_max", "egitim_min",
                                                                     "reis_saglik", "reis_kronik", "reis_gali", "cocuk_var", "yasli_var", "tek_yetiskin_cocuklu", "calisan_yok", "dusuk_is_yogunlugu",
                                                                     "HH010", "HH020", "kiraci", "HH080", "HH100", "HH110", "HH120", "HH145", "HH180_var", "HH190_var", "HH200_var", "HH220_var", "HH230_var", "HH240_var",
                                                                     "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070", "kalabalik_konut", "ciddi_konut_yoksunlugu")),
  data.table(katman = "T3 mali baski", tur = "sayisal", degisken = c("he050_orani")),
  data.table(katman = "T3 mali baski", tur = "kategorik", degisken = c("HE040", "HE010", "HE020", "HE030", "msy_borc_odeme", "HE060", "HE070")),
  data.table(katman = "T4 ayni batarya", tur = "sayisal", degisken = c("msy_etsiz_sayi")),
  data.table(katman = "T4 ayni batarya", tur = "kategorik", degisken = c("HE080", "HE100", "HE110", "HE120", "msy_beklenmedik_harcama", "msy_tatil", "msy_isinma", "msy_otomobil", "msy_mobilya",
                                                                          "HH180", "HH190", "HH200", "HH220", "HH230", "HH240", "msy_internet", "msy_giysi", "msy_ayakkabi", "msy_harclik", "msy_bos_zaman", "msy_arkadas_aile"))
))
katalog <- katalog[degisken %in% names(h)]
dislanan <- data.table(degisken = c("HE090", "msy_et_tavuk_balik", "msy_sayi", "msy_5", "msy_7", "my_sayi", "my_3", "my_4", "yoksulluk_sosyal_dislanma", "yoksul_60", "yoksul_70", "gelir_dilim5", "esdeger_gelir", "goreli_esdeger_gelir", "konut_maliyet_orani", "konut_maliyet_asiri_yuk", "konut_orani_k", "konut_asiri_k", "HH040", "HH050", "HG110"),
                       neden = c("sonuc", rep("sonucu (HE090) iceriyor", 8), "nufus tanimi (Model B) ve karsilastirma kolu", "karsilastirma kolu (esik)", "log_goreli_gelir ile ayni bilgi", "nominal TL, yillar arasi karsilastirilamaz", "log_goreli_gelir ile ayni bilgi", "2024 kirilmasi", "2024 kirilmasi", "2024 tamamen bos: yil bloklu modellerde kullanilmadi", "2024 tamamen bos: yil bloklu modellerde kullanilmadi", "nominal TL: goreli_kira ve kira_orani kullanildi", "nominal TL ve 2024 kirilmasi", "nominal TL: log_goreli_gelir kullanildi"))
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
  if (sum(ok) < 200 || length(unique(x[ok])) < 2) return(list(eksik = data.table(nufus = nufus, yil = yy, degisken = v, eksik_yuzde = eksik)))
  dd <- data.table(FI = dt$FI[ok], w = dt$HB040[ok], x = x[ok])
  kat <- NULL
  if (tur == "kategorik") {
    tab <- dd[, .(n = .N, olay = sum(FI), yayginlik = 100 * sum(w * FI) / sum(w), pay = 100 * sum(w)), keyby = .(kod = as.character(x))]
    tab[, pay := pay / sum(pay)]
    kat <- tab[, .(nufus = nufus, yil = yy, degisken = v, kod, n, olay, pay, yayginlik)]
    seyrek <- tab[n < 20, kod]
    dd <- dd[!as.character(x) %in% seyrek]
    dd[, x := factor(x)]
    if (nlevels(dd$x) < 2) return(list(kat = kat, eksik = data.table(nufus = nufus, yil = yy, degisken = v, eksik_yuzde = eksik)))
    f <- FI ~ x
  } else {
    dd[, x := as.numeric(x)]
    f <- if (length(unique(dd$x)) > 6) FI ~ ns(x, df = 3) else FI ~ factor(x)
    if (length(unique(dd$x)) > 6 && length(unique(quantile(dd$x, c(1 / 3, 2 / 3)))) < 2) {
      dd[, x0 := as.integer(x == min(x))]
      f <- FI ~ x + x0
    }
  }
  m <- suppressWarnings(glm(f, data = dd, family = quasibinomial(), weights = w / mean(w)))
  m0 <- suppressWarnings(glm(FI ~ 1, data = dd, family = quasibinomial(), weights = w / mean(w)))
  p <- fitted(m)
  oz <- data.table(nufus = nufus, yil = yy, degisken = v, tur = tur, n = nrow(dd), olay = sum(dd$FI), eksik_yuzde = eksik,
                   pseudo_r2 = 1 - deviance(m) / deviance(m0), auc = auc_w(p, dd$FI, dd$w),
                   kategori = if (tur == "kategorik") nlevels(dd$x) else length(unique(dd$x)),
                   yayginlik_min = if (!is.null(kat)) min(kat[n >= 20, yayginlik]) else NA_real_,
                   yayginlik_max = if (!is.null(kat)) max(kat[n >= 20, yayginlik]) else NA_real_)
  list(oz = oz, kat = kat, eksik = data.table(nufus = nufus, yil = yy, degisken = v, eksik_yuzde = eksik))
}
sonuc <- list()
kategori <- list()
eksik_l <- list()
t0 <- Sys.time()
for (nufus in c("tum", "yoksul_degil")) {
  for (yy in 2023:2025) {
    dt <- if (nufus == "tum") h[yil == yy] else h[yil == yy & yoksul == 0]
    for (i in seq_len(nrow(katalog))) {
      r <- tek(dt, katalog$degisken[i], katalog$tur[i], nufus, yy)
      if (!is.null(r$oz)) sonuc[[length(sonuc) + 1]] <- r$oz
      if (!is.null(r$kat)) kategori[[length(kategori) + 1]] <- r$kat
      eksik_l[[length(eksik_l) + 1]] <- r$eksik
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
ozet[, katman_sira := seq_len(.N), by = .(nufus, katman)]
fwrite(ozet, file.path(rdir, "kesif_ozet_siralama.csv"))
for (nf in c("tum", "yoksul_degil")) {
  cat("\n==== ", nf, ": pseudo R2 ortalamasina gore ilk 30 ====\n")
  print(ozet[nufus == nf][1:30, .(degisken, katman, r2_2023 = round(r2_2023, 3), r2_2024 = round(r2_2024, 3), r2_2025 = round(r2_2025, 3), auc_2025 = round(auc_2025, 3))])
  cat("\n==== ", nf, ": katman basina ilk 10 ====\n")
  print(ozet[nufus == nf & katman_sira <= 10, .(katman, katman_sira, degisken, r2_ort = round(r2_ort, 4), auc_2025 = round(auc_2025, 3))])
}
fwrite(ozet[katman_sira <= 10, .(nufus, katman, katman_sira, degisken, r2_ort, r2_2023, r2_2024, r2_2025, auc_2025)], file.path(rdir, "kesif_katman_ilk10.csv"))
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
  if (length(x) < 100 || length(unique(x)) < 2 || length(unique(y)) < 2) return(NA_real_)
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
ciftler <- merge(ciftler, katalog[, .(degisken_1 = degisken, katman_1 = katman)], by = "degisken_1")
ciftler <- merge(ciftler, katalog[, .(degisken_2 = degisken, katman_2 = katman)], by = "degisken_2")
setorder(ciftler, -iliski)
fwrite(ciftler, file.path(rdir, "kesif_guclu_ciftler_2025.csv"))
kume_tab <- merge(data.table(degisken = names(kume), kume = kume), ozet[nufus == "tum", .(degisken, katman, r2_ort)], by = "degisken")
setorder(kume_tab, kume, -r2_ort)
fwrite(kume_tab, file.path(rdir, "kesif_ozellik_kumeleri_2025.csv"))
cat("\n==== Birbirine yakin ozellik ciftleri (iliski >= 0,7) ====\n")
print(ciftler[iliski >= 0.7])
cat("\n==== Kume sayisi:", length(unique(kume)), "; ikiden fazla uyeli kumeler ====\n")
print(kume_tab[kume %in% kume_tab[, .N, by = kume][N > 2, kume]])
png(file.path(rdir, "kesif_ozellik_iliski_2025.png"), width = 3400, height = 3400, res = 200)
ord <- hc$order
op <- par(mar = c(10, 10, 1, 1))
image(seq_along(vv), seq_along(vv), M2[ord, ord], col = hcl.colors(50, "YlOrRd", rev = TRUE), axes = FALSE, xlab = "", ylab = "", zlim = c(0, 1))
axis(1, at = seq_along(vv), labels = vv[ord], las = 2, cex.axis = 0.5)
axis(2, at = seq_along(vv), labels = vv[ord], las = 2, cex.axis = 0.5)
par(op)
dev.off()

eksik <- dcast(rbindlist(eksik_l)[nufus == "tum"], degisken ~ yil, value.var = "eksik_yuzde")
eksik <- merge(eksik, katalog[, .(degisken, katman)], by = "degisken")
fwrite(eksik, file.path(rdir, "kesif_eksik.csv"))
print(eksik[`2023` > 1 | `2024` > 1 | `2025` > 1])

hazirla <- function(dt, vars) {
  out <- data.table(FI = dt$FI, w = dt$HB040 / mean(dt$HB040))
  for (v in vars) {
    tur <- katalog[degisken == v, tur]
    x <- dt[[v]]
    if (tur == "kategorik") {
      x <- as.character(x)
      x[is.na(x)] <- "bos"
      tb <- table(x)
      x[x %in% names(tb)[tb < 30]] <- "seyrek"
      set(out, j = v, value = factor(x))
    } else {
      x <- as.numeric(x)
      if (anyNA(x)) {
        set(out, j = paste0(v, "_bos"), value = as.integer(is.na(x)))
        x[is.na(x)] <- median(x, na.rm = TRUE)
      }
      set(out, j = v, value = x)
    }
  }
  out
}
kombin <- list(T1 = "T1 gelir", T2 = "T2 yapisal", T1_T2 = c("T1 gelir", "T2 yapisal"), T1_T2_T3 = c("T1 gelir", "T2 yapisal", "T3 mali baski"),
               T1_T2_T3_T4 = c("T1 gelir", "T2 yapisal", "T3 mali baski", "T4 ayni batarya"), T2_T3 = c("T2 yapisal", "T3 mali baski"))
cok <- list()
for (nf in c("tum", "yoksul_degil")) {
  for (k in names(kombin)) {
    vars <- katalog[katman %in% kombin[[k]], degisken]
    vars <- setdiff(vars, c("HB031", "konut_orani_k", "konut_asiri_k"))
    if (nf == "yoksul_degil") vars <- setdiff(vars, c("yoksul_50", "yoksulluk_acigi_60"))
    egit <- hazirla(h[yil == 2023 & (nf == "tum" | yoksul == 0)], vars)
    test <- hazirla(h[yil == 2025 & (nf == "tum" | yoksul == 0)], vars)
    ortak <- intersect(names(egit), names(test))
    for (v in ortak) if (is.factor(egit[[v]])) {
      lv <- levels(egit[[v]])
      tv <- as.character(test[[v]])
      tv[!tv %in% lv] <- if ("seyrek" %in% lv) "seyrek" else lv[1]
      set(test, j = v, value = factor(tv, levels = lv))
    }
    f <- as.formula(paste("FI ~", paste(setdiff(ortak, c("FI", "w")), collapse = " + ")))
    m <- suppressWarnings(glm(f, data = egit, family = quasibinomial(), weights = w))
    m0 <- suppressWarnings(glm(FI ~ 1, data = egit, family = quasibinomial(), weights = w))
    pt <- suppressWarnings(predict(m, newdata = test, type = "response"))
    cok[[length(cok) + 1]] <- data.table(nufus = nf, set = k, n_ozellik = length(vars), n_parametre = length(coef(m)), r2_egitim_2023 = 1 - deviance(m) / deviance(m0),
                                         auc_egitim_2023 = auc_w(fitted(m), egit$FI, egit$w), auc_test_2025 = auc_w(pt, test$FI, test$w))
  }
}
cok <- rbindlist(cok)
print(cok)
fwrite(cok, file.path(rdir, "kesif_cok_degiskenli_katmanlar.csv"))
writeLines(capture.output(sessionInfo()), file.path(rdir, "sessionInfo_kesif.txt"))
cat("kesif.R bitti. Sure (dk):", round(as.numeric(difftime(Sys.time(), t_bas, units = "mins")), 2), "\n")
