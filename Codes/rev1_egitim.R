options(warn = 1, width = 160, survey.lonely.psu = "adjust", datatable.print.nrows = 200, future.globals.maxSize = 4 * 1024^3)
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(survey)
  library(splines)
  library(MASS)
  library(flextable)
  library(officer)
  library(future)
  library(furrr)
  library(jsonlite)
  library(openxlsx)
})
set.seed(20261026)
baslangic <- Sys.time()
rdir <- "Results/Rev1"
dir.create(file.path(rdir, "log"), showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(rdir, "Supplementary"), showWarnings = FALSE, recursive = TRUE)
sink(file.path(rdir, "log", "rev1_egitim_log.txt"), split = TRUE)
cat("rev1_egitim.R basladi:", format(baslangic), "\n")
cat(R.version.string, "| BLAS:", extSoftVersion()[["BLAS"]], "\n")
sureler <- list()
sure_ekle <- function(adim, t0) {
  sureler[[length(sureler) + 1]] <<- data.table(adim = adim, dakika = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2))
  invisible(NULL)
}
kapilar <- list()
kapi <- function(kapi_no, ad, beklenen, bulunan, tol = 0) {
  fark <- if (is.numeric(beklenen) && is.numeric(bulunan)) abs(bulunan - beklenen) else NA_real_
  durum <- if (is.numeric(beklenen) && is.numeric(bulunan)) { if (fark <= tol + 1e-12) "Tuttu" else "Tutmadi" } else if (identical(as.character(beklenen), as.character(bulunan))) "Tuttu" else "Tutmadi"
  kapilar[[length(kapilar) + 1]] <<- data.table(kapi = kapi_no, kontrol = ad, beklenen = format(beklenen, digits = 12), bulunan = format(bulunan, digits = 12), fark = fark, tolerans = tol, durum = durum)
  invisible(durum == "Tuttu")
}
kapi_yaz <- function() fwrite(rbindlist(kapilar), file.path(rdir, "kontrol_rev1.csv"))
kapi_dur <- function(no) {
  k <- rbindlist(kapilar)[kapi == no]
  kapi_yaz()
  cat("\nKapi", no, ":", k[durum == "Tuttu", .N], "/", nrow(k), "tuttu\n")
  if (any(k$durum != "Tuttu")) {
    print(k[durum != "Tuttu"])
    sink()
    stop(paste("Kapi", no, "tutmadi; Results/Rev1/kontrol_rev1.csv"))
  }
}

ddir <- "R_Data ve Python Data"
t0 <- Sys.time()
d <- as.data.table(read_parquet(file.path(ddir, "gyka_2023_2025.parquet")))
d[, egitim5 := fcase(FE030 %in% 0:1, 1L, FE030 %in% 2:3, 2L, FE030 == 4, 3L, FE030 %in% 5:6, 4L, FE030 %in% 7:10, 5L, default = NA_integer_)]
h <- as.data.table(read_parquet(file.path(ddir, "hane_2023_2025.parquet")))
cat("Veri:", nrow(d), "kisi satiri,", nrow(h), "hane\n")
kapi(1, "nrow(d)", 239985, nrow(d))
kapi(1, "2025 hane sayisi", 25836, h[yil == 2025, .N])
kapi(1, "2025 hane sayisi (kisi verisinde hane_reisi == 1)", 25836, d[yil == 2025 & hane_reisi == 1, .N])
kapi(1, "H3 yetiskin evreni (2025, FK070 >= 18, f_kayit == 1)", 57899, d[yil == 2025 & FK070 >= 18 & f_kayit == 1, .N])
kapi(1, "hane_kimlik yillar arasinda tekil", 0, h[, .N, by = hane_kimlik][N > 1, .N])
kapi_dur(1)
sure_ekle("okuma ve kapi 1", t0)

t0 <- Sys.time()
h[, egitim_max := fifelse(is.na(egitim_max), 0L, as.integer(egitim_max))]
h[, egitim3_max := fcase(egitim_max == 0L, 0L, egitim_max <= 2L, 1L, egitim_max <= 4L, 2L, default = 3L)]
h[, q_egitim3 := paste0(gelir_dilim5, "_", egitim3_max)]
h[, `:=`(e_yoksul_60 = yoksul, e_yoksul_50 = as.integer(yoksul_50), e_yoksul_70 = as.integer(yoksul_70), e_msy_etsiz_5 = as.integer(msy_etsiz_5), e_dusuk_is = fifelse(is.na(dusuk_is_yogunlugu), 0L, as.integer(dusuk_is_yogunlugu)))]
esikler <- c("e_yoksul_60", "e_yoksul_50", "e_yoksul_70", "e_msy_etsiz_5", "e_dusuk_is")
hane_sut <- c("hane_kimlik", "FI", "yoksul", "kacirilan", esikler, "HB030", "HB031", "HB050", "gelir_bandi", "gelir_dilim5", "HH020", "cocuk_var", "calisan_var", "is_yog_grup", "reis_faaliyet3", "yasli_var", "test_temiz", "egitim_max", "egitim3_max", "q_egitim3")
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
kirilimlar <- c("egitim_max", "egitim3_max", "q_egitim3")
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

gd <- list()
for (yy in 2023:2025) for (kk in c("egitim_max", "egitim3_max")) {
  dat <- h[yil == yy]
  des <- tasarim(dat, "hane")
  for (q in 1:5) {
    ix <- dat$gelir_dilim5 == q
    a <- svyby(as.formula("~FI"), as.formula(paste0("~", kk)), des[ix, ], svymean, na.rm = TRUE)
    nn <- dat[ix, .(n = .N, n_FI = sum(FI)), keyby = .(kategori = as.character(get(kk)))]
    r <- data.table(kategori = as.character(a[[kk]]), FI = 100 * a$FI, FI_se = 100 * SE(a))
    r <- merge(r, nn, by = "kategori", all.x = TRUE)
    r[, `:=`(yil = yy, duzey = "hane", gelir_dilim5 = q, egitim_degiskeni = kk)]
    gd[[length(gd) + 1]] <- r
  }
}
gd <- rbindlist(gd)
gd[, kucuk_hucre := fcase(n_FI < 20, "suppressed", n_FI <= 50, "flag", default = "")]
gd[, `:=`(alt = FI - 1.96 * FI_se, ust = FI + 1.96 * FI_se)]

h1_ref <- fread("Results/H1_temel_tahminler.csv")
h1_ref <- h1_ref[tr63_haric == FALSE & ibbs2_tabaka == FALSE]
for (yy in 2023:2025) for (dz in c("hane", "kisi")) {
  dat <- if (dz == "hane") h[yil == yy] else p_dt[yil == yy]
  for (kk in c("egitim_max", "egitim3_max", "q_egitim3")) kapi(2, paste(yy, dz, kk, "kategori n toplami = toplam"), nrow(dat), h1_kir[yil == yy & duzey == dz & kirilim == kk, sum(n)])
  if (dz == "hane") for (kk in c("egitim_max", "egitim3_max")) kapi(2, paste(yy, "hane gelir beslikleri x", kk, "n toplami"), nrow(dat), gd[yil == yy & egitim_degiskeni == kk, sum(n)])
  des <- tasarim(dat, dz)
  fi <- oran_svy(des, ~FI)
  ds <- oran_svy(des, ~I(1 - e_yoksul_60), dat$FI == 1)
  kapi(2, paste(yy, dz, "FI (H1_temel_tahminler)"), h1_ref[yil == yy & duzey == dz & olcu == "FI", tahmin], fi[["tahmin"]], tol = 1e-6)
  kapi(2, paste(yy, dz, "FI SE (H1_temel_tahminler)"), h1_ref[yil == yy & duzey == dz & olcu == "FI", se], fi[["se"]], tol = 1e-6)
  kapi(2, paste(yy, dz, "dislama e_yoksul_60 (H1_temel_tahminler)"), h1_ref[yil == yy & duzey == dz & olcu == "dislama" & esik == "e_yoksul_60", tahmin], ds[["tahmin"]], tol = 1e-6)
  kapi(2, paste(yy, dz, "dislama SE (H1_temel_tahminler)"), h1_ref[yil == yy & duzey == dz & olcu == "dislama" & esik == "e_yoksul_60", se], ds[["se"]], tol = 1e-6)
}
kapi_dur(2)
sifir_sec <- quote((kirilim %in% c("egitim_max", "egitim3_max") & kategori == "0") | (kirilim == "q_egitim3" & grepl("_0$", kategori)))
n_sifir <- c(h1_kir = h1_kir[eval(sifir_sec), .N], gd = gd[kategori == "0", .N])
h1_kir <- h1_kir[!eval(sifir_sec)]
gd <- gd[kategori != "0"]
na_sut <- c("FI", "FI_se", "dislama", "dislama_se", "kacirilan_bilesim", "kacirilan_bilesim_se", "alt", "ust")
for (s_ in intersect(na_sut, names(h1_kir))) set(h1_kir, i = which(h1_kir$kucuk_hucre == "suppressed"), j = s_, value = NA_real_)
for (s_ in intersect(na_sut, names(gd))) set(gd, i = which(gd$kucuk_hucre == "suppressed"), j = s_, value = NA_real_)
cat("\nKapi 2 sonrasi, yazmadan once cikarilan egitim_max = 0 (bireysel kaydi olan yetiskini olmayan hane) satirlari: kirilim", n_sifir[["h1_kir"]], ", gelir besligi", n_sifir[["gd"]], "\n")
cat("Bastirilan (n_FI < 20) hucre: kirilim", h1_kir[kucuk_hucre == "suppressed", .N], ", gelir besligi", gd[kucuk_hucre == "suppressed", .N], "\n")
fwrite(h1_kir, file.path(rdir, "R1_egitim_H1_kirilim.csv"))
fwrite(gd, file.path(rdir, "R1_egitim_H1_gelir_dilimi.csv"))
cat("\nParca A, 2025 hane, en yuksek egitim:\n")
print(h1_kir[yil == 2025 & duzey == "hane" & kirilim == "egitim_max", .(kategori, n, n_FI, FI = round(FI, 1), dislama = round(dislama, 1), bilesim = round(kacirilan_bilesim, 1), kucuk_hucre)])
print(h1_kir[yil == 2025 & duzey == "kisi" & kirilim == "egitim_max", .(kategori, n, FI = round(FI, 1), dislama = round(dislama, 1))])
cat("\nGelir besligi x egitim (3 grup), 2025 hane FI %:\n")
print(dcast(gd[yil == 2025 & egitim_degiskeni == "egitim3_max", .(gelir_dilim5, kategori, FI = round(FI, 1))], gelir_dilim5 ~ kategori, value.var = "FI"))
sure_ekle("Parca A (H1 eki) ve kapi 2", t0)

t0 <- Sys.time()
Sys.setenv(VECLIB_MAXIMUM_THREADS = "1", OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1")
plan(multisession, workers = 14)
obdir <- file.path(ddir, "onbellek", "rev1")
dir.create(obdir, showWarnings = FALSE, recursive = TRUE)
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
wald_p <- function(sg, terim) as.numeric(regTermTest(sg, as.formula(paste("~", terim)), method = "Wald")$p)

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
sure_ekle("Parca B hazirlik (carpan matrisi, yetiskin verisi)", t0)

t0 <- Sys.time()
olcu_E <- function(p) {
  o <- olcu_A(p)
  for (k in 1:3) {
    p0 <- unname(p[paste0("A0|", k)])
    p1 <- unname(p[paste0("A1|", k)])
    o <- c(o, setNames(c(100 * p0, 100 * p1, 100 * (p1 - p0), p1 / p0), paste0(c("p0_", "p1_", "PD_", "PR_"), k)))
  }
  c(o, PD_3_1 = unname(o["PD_3"] - o["PD_1"]))
}
h3_ref <- fread("Results/H3_gcomp_sonuclari.csv")
h3_ref <- h3_ref[duzey == "yetiskin" & karsilastirma == "C1" & ana_model == TRUE]
tani <- fread("Results/H3_model_tanilari.csv")[duzey == "yetiskin" & karsilastirma == "C1"]
c1_sonuc <- list()
c1_etk <- list()
c1_ort <- list()
for (v in h3_y) {
  kapi(3, paste("C1", v, "ana model esnek (H3_model_tanilari)"), "esnek", tani[sonuc == v, ana_model])
  kapi(3, paste("C1", v, "yas 4 df natural spline (H3_model_tanilari)"), "4 df natural spline", tani[sonuc == v, yas])
  kapi(3, paste("C1", v, "ek kovaryat yok (H3_model_tanilari)"), "none", tani[sonuc == v, ek_kovaryat])
  dt <- h3_veri("C1", v, yt)
  ix <- match(dt$hane_kimlik, hane_id)
  frm <- as.formula(paste(v, "~", esnek_yap(sag_kur("C1", yas_terim["df4"]))))
  m <- mm_kur(frm, dt, senaryo = sen_A)
  w <- dt$FB030
  r <- gc_tahmin(m, w, olcu_E, grup = dt$egitim3)
  s <- gc_if(m, w, r, olcu_E, grup = dt$egitim3, kume = dt$hane_kimlik)
  for (o in c("p0", "p1", "PD", "PR")) kapi(3, paste("C1", v, o, "tahmin (H3_gcomp_sonuclari)"), h3_ref[sonuc == v & olcu == o, tahmin], unname(r$olc[o]), tol = 1e-4)
  kapi(3, paste("C1", v, "n (H3_gcomp_sonuclari)"), h3_ref[sonuc == v & olcu == "PD", n], nrow(dt))
  kapi(3, paste("C1", v, "parametre sayisi (H3_gcomp_sonuclari)"), h3_ref[sonuc == v & olcu == "PD", npar], ncol(m$X))
  if (any(rbindlist(kapilar)[kapi == 3, durum] != "Tuttu")) kapi_dur(3)
  Bm <- boot_gc(paste0("rev1_C1_", v, "_egitim_B4000"), m, w, ix, olcu_E, r$b, grup = dt$egitim3, Mp = M_parca)
  oz <- gc_ozet(r, s, Bm)
  for (o in c("p0", "p1", "PD", "PR")) {
    kapi(3, paste("C1", v, o, "bootstrap alt sinir"), h3_ref[sonuc == v & olcu == o, alt], oz[olcu == o, alt], tol = 0.01)
    kapi(3, paste("C1", v, o, "bootstrap ust sinir"), h3_ref[sonuc == v & olcu == o, ust], oz[olcu == o, ust], tol = 0.01)
  }
  kapi(3, paste("C1", v, "bootstrap tekrar sayisi"), 4000, nrow(Bm))
  kapi(3, paste("C1", v, "IRLS sinira ulasan replikat"), 0, sum(Bm[, "iter"] >= 30))
  oz[, `:=`(sonuc = v, egitim3 = fcase(grepl("_1$", olcu), 1L, grepl("_2$", olcu), 2L, grepl("_3$", olcu), 3L, default = NA_integer_))]
  oz[olcu == "PD_3_1", egitim3 := NA_integer_]
  nn <- dt[, .(n = .N, olay = sum(get(v))), keyby = .(egitim3, A)]
  nt <- dt[, .(n = .N, olay = sum(get(v))), keyby = .(A)][, egitim3 := 0L]
  nn <- rbind(nt, nn, use.names = TRUE)
  nw <- dcast(nn, egitim3 ~ A, value.var = c("n", "olay"))
  setnames(nw, c("egitim3", "n_G1", "n_G2", "olay_G1", "olay_G2"))
  oz[, egitim_anahtar := fifelse(is.na(egitim3), 0L, egitim3)]
  oz <- merge(oz, nw, by.x = "egitim_anahtar", by.y = "egitim3", all.x = TRUE, sort = FALSE)
  oz[olcu == "PD_3_1", c("n_G1", "n_G2", "olay_G1", "olay_G2") := NA]
  oz[, egitim_anahtar := NULL]
  c1_sonuc[[v]] <- oz
  des <- svydesign(ids = ~hane_kimlik, weights = ~FB030, data = dt)
  sg <- svyglm(frm, des, family = quasibinomial())
  tt <- regTermTest(sg, ~A:f_egit, method = "Wald")
  c1_etk[[v]] <- data.table(sonuc = v, terim = "A:f_egit", wald_F = as.numeric(tt$Ftest), df = tt$df, ddf = tt$ddf, wald_p = wald_p(sg, "A:f_egit"))
  nw[, `:=`(sonuc = v, G2_n_50_alti = n_G2 < 50)]
  c1_ort[[v]] <- nw
  cat("\nC1", v, ": genel PD", round(r$olc[["PD"]], 2), "| PD_1", round(r$olc[["PD_1"]], 2), "PD_2", round(r$olc[["PD_2"]], 2), "PD_3", round(r$olc[["PD_3"]], 2), "| PD_3_1", round(r$olc[["PD_3_1"]], 2), "| Wald p", signif(c1_etk[[v]]$wald_p, 3), "\n")
}
kapi_dur(3)
c1_sonuc <- rbindlist(c1_sonuc, use.names = TRUE, fill = TRUE)
c1_etk <- merge(rbindlist(c1_etk), rbindlist(c1_ort)[, .(sonuc, egitim3, n_G1, n_G2, olay_G1, olay_G2, G2_n_50_alti)], by = "sonuc", allow.cartesian = TRUE)
setcolorder(c1_sonuc, c("sonuc", "olcu", "egitim3"))
fwrite(c1_sonuc, file.path(rdir, "R1_egitim_C1.csv"))
fwrite(c1_etk, file.path(rdir, "R1_egitim_C1_etkilesim.csv"))
fwrite(rbindlist(boot_kayit), file.path(rdir, "log", "rev1_bootstrap_kayit.csv"))
print(c1_sonuc[olcu %in% c("PD", "PD_1", "PD_2", "PD_3", "PD_3_1"), .(sonuc, olcu, tahmin = round(tahmin, 2), alt = round(alt, 2), ust = round(ust, 2), se_if = round(se_if, 2))])
print(c1_etk[egitim3 == 0, .(sonuc, wald_F, df, wald_p)])
sure_ekle("Parca B (C1 egitim gruplari, bootstrap) ve kapi 3", t0)

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
rek_kl <- file.path(rdir, "Supplementary")
eg5_lab <- function(k) if (k == "0") "No adult with an individual questionnaire" else kat_et("egitim_max", k)
eg3_lab <- c("0" = "No adult with an individual questionnaire", "1" = "Primary or less", "2" = "Secondary", "3" = "Tertiary")
hucre_fi <- function(r) if (!nrow(r)) "" else if (r$kucuk_hucre == "suppressed") "–" else if (is.na(r$FI)) "" else paste0(f1(r$FI), if (r$kucuk_hucre == "flag") "^{a}" else "")
t1_rows <- list()
gs_ <- integer(0)
for (yy in 2023:2025) {
  t1_rows[[length(t1_rows) + 1]] <- data.table(E = as.character(yy), n = "", FI = "", Ex = "", Mi = "", Q1 = "", Q2 = "", Q3 = "", Q4 = "", Q5 = "")
  gs_ <- c(gs_, length(t1_rows))
  kh <- h1_kir[yil == yy & duzey == "hane" & kirilim == "egitim_max"]
  kh[, sira := as.integer(kategori)]
  kh <- kh[order(sira == 0, sira)]
  for (i in seq_len(nrow(kh))) {
    r <- kh[i]
    sup <- r$kucuk_hucre == "suppressed"
    q <- lapply(1:5, function(qq) hucre_fi(gd[yil == yy & egitim_degiskeni == "egitim_max" & gelir_dilim5 == qq & kategori == r$kategori]))
    t1_rows[[length(t1_rows) + 1]] <- data.table(E = eg5_lab(r$kategori), n = nfmt(r$n), FI = if (sup) "–" else ga(r$FI, r$FI - 1.96 * r$FI_se, r$FI + 1.96 * r$FI_se),
                                                 Ex = if (sup) "–" else paste0(ga(r$dislama, r$dislama - 1.96 * r$dislama_se, r$dislama + 1.96 * r$dislama_se), if (r$kucuk_hucre == "flag") "^{a}" else ""),
                                                 Mi = if (sup) "–" else f1(fifelse(is.na(r$kacirilan_bilesim), 0, r$kacirilan_bilesim)), Q1 = q[[1]], Q2 = q[[2]], Q3 = q[[3]], Q4 = q[[4]], Q5 = q[[5]])
  }
}
t1 <- rbindlist(t1_rows)
setnames(t1, c("Highest education among adults", "Households, n", "Meal-deprived, % (95% CI)", "Exclusion error, % (95% CI)", "Share of missed households, %", "Q1 (lowest)", "Q2", "Q3", "Q4", "Q5 (highest)"))
tablo_cikar(t1, "Ek_rev1_egitim_H1", "Table S–. Meal-affordability deprivation and exclusion error of the 60% poverty line by the highest education among adults in the household, 2023–2025.",
            klasor = rek_kl, yatay = TRUE, grup_satir = gs_, girinti = setdiff(seq_len(nrow(t1)), gs_),
            ust = list(degerler = c(names(t1)[1:5], "Meal-deprived by income quintile, %"), genislik = c(1, 1, 1, 1, 1, 5), dikey = 1:5),
            notlar = c("Household level; household weight HB040; n, unweighted number of households; percentages weighted. 95% CI from Taylor linearization. Exclusion error: % of meal-deprived households not poor (equivalized income ≥60% of the median). Share of missed households: distribution of meal-deprived, non-poor households across education groups. Income quintiles: equivalized disposable income.",
                       "Highest education among adults: highest completed level among household members aged ≥18 with an individual questionnaire; households without such an adult are not shown (none in 2023 and 2024, one in 2025). Person-level estimates (FK050, household clusters) are in the accompanying file.",
                       "^{a} 20–50 meal-deprived households in the cell; –, fewer than 20 (not shown).",
                       "Added in revision at a reviewer's request, after the main results were known; no previously reported estimate changed."))

sad <- c(et_az = "Meat, chicken or fish <1/week", meyve_az = "Fruit <1/day", sebze_az = "Vegetables or salad <1/day")
t2_rows <- list()
gs_ <- integer(0)
for (v in h3_y) {
  t2_rows[[length(t2_rows) + 1]] <- data.table(G = sad[[v]], n = "", p0 = "", p1 = "", PD = "", PR = "")
  gs_ <- c(gs_, length(t2_rows))
  x <- c1_sonuc[sonuc == v]
  ort <- c1_etk[sonuc == v]
  for (k in 0:3) {
    sf <- if (k == 0) "" else paste0("_", k)
    g <- function(o, d = 1) { r <- x[olcu == paste0(o, sf)]; ga(r$tahmin, r$alt, r$ust, d) }
    nr <- ort[egitim3 == k]
    t2_rows[[length(t2_rows) + 1]] <- data.table(G = if (k == 0) "All non-poor adults" else eg3_lab[[as.character(k)]], n = paste0(nfmt(nr$n_G1), " / ", nfmt(nr$n_G2), if (isTRUE(nr$G2_n_50_alti)) "^{a}" else ""),
                                                 p0 = f1(x[olcu == paste0("p0", sf), tahmin]), p1 = f1(x[olcu == paste0("p1", sf), tahmin]), PD = g("PD"), PR = g("PR", 2))
  }
}
t2 <- rbindlist(t2_rows)
setnames(t2, c("Outcome and education", "Adults, n (non-deprived / meal-deprived)", "Non-deprived, %", "Meal-deprived, %", "Difference, pp (95% CI)", "Ratio (95% CI)"))
p_metin <- paste(sapply(h3_y, function(v) paste0(sad[[v]], " p ", pfmt(c1_etk[sonuc == v & egitim3 == 0, wald_p]))), collapse = "; ")
d31 <- paste(sapply(h3_y, function(v) { r <- c1_sonuc[sonuc == v & olcu == "PD_3_1"]; paste0(sad[[v]], " ", ga(r$tahmin, r$alt, r$ust, 1)) }), collapse = "; ")
tablo_cikar(t2, "Ek_rev1_egitim_H3", "Table S–. Consumption-frequency gaps between meal-deprived and non-deprived non-poor adults by the adult's education, 2025 (comparison C1).",
            klasor = rek_kl, grup_satir = gs_, girinti = setdiff(seq_len(nrow(t2)), gs_),
            notlar = c("Non-poor adults aged ≥18 with an individual questionnaire (FB030, household clusters). Standardized prevalences by g-computation from the fully interacted logistic model of comparison C1 (group indicator interacted with all covariates, including education in five levels); within each education group, predictions are standardized to the covariate distribution of that group's non-poor adults. 95% CI: 4,000 Rao–Wu–Yue rescaled household bootstrap replicates (percentile); the multiplier matrix is shared with the main estimates. All non-poor adults: the main C1 estimates.",
                       paste0("Group × education interaction (design-based Wald test in the main model): ", p_metin, "."),
                       paste0("Difference in the gap, Tertiary − Primary or less, pp (95% CI): ", d31, "."),
                       paste0("Education: Primary or less, no diploma or primary school; Secondary, lower or upper secondary; Tertiary, higher education. The meat outcome excludes ", yt[et_tavuk_balik_siklik == 0, .N], " vegetarian or vegan adults."),
                       if (any(c1_etk$G2_n_50_alti, na.rm = TRUE)) "^{a} Fewer than 50 meal-deprived adults in the group." else NULL,
                       "Frequency of consumption; quantities, intake and diet quality not measured.",
                       "Added in revision at a reviewer's request, after the main results were known; no previously reported estimate changed."))

s11_rows <- list()
k25 <- h1_kir[yil == 2025]
s11_ekle <- function(kk, lab_f) {
  kh <- k25[kirilim == kk & duzey == "hane"]
  kp <- k25[kirilim == kk & duzey == "kisi"]
  for (i in seq_len(nrow(kh))) {
    r <- kh[i]
    rp <- kp[kategori == r$kategori]
    sup <- r$kucuk_hucre == "suppressed"
    taut <- !is.na(r$dislama_se) && r$dislama_se < 1e-8
    s11_rows[[length(s11_rows) + 1]] <<- data.table(kirilim = kk, kategori = r$kategori, Characteristic = lab_f(r$kategori), n = nfmt(r$n), FI = if (sup) "–" else ga(r$FI, r$FI - 1.96 * r$FI_se, r$FI + 1.96 * r$FI_se),
                                                    Exclusion = if (sup) "–" else if (taut) "–b" else paste0(ga(r$dislama, r$dislama - 1.96 * r$dislama_se, r$dislama + 1.96 * r$dislama_se), if (r$kucuk_hucre == "flag") "a" else ""),
                                                    Missed = if (sup) "–" else f1(fifelse(is.na(r$kacirilan_bilesim), 0, r$kacirilan_bilesim)), Exclusion_p = if (taut) "–" else if (nrow(rp) && !is.na(rp$dislama)) f1(rp$dislama) else "")
  }
}
s11_ekle("egitim_max", eg5_lab)
qlab <- c("Q1", "Q2", "Q3", "Q4", "Q5")
s11_ekle("q_egitim3", function(k) { p <- strsplit(k, "_")[[1]]; paste0(qlab[as.integer(p[1])], ", ", eg3_lab[[p[2]]]) })
s11 <- rbindlist(s11_rows)
s11[, `:=`(s1 = as.integer(sub("_.*", "", kategori)), s2 = as.integer(sub(".*_", "", kategori)))]
s11[kirilim == "egitim_max", `:=`(s1 = 0L, s2 = as.integer(kategori))]
s11 <- s11[order(kirilim != "egitim_max", s1, s2 == 0, s2)][, c("s1", "s2") := NULL]
fwrite(s11, file.path(rdir, "S11_egitim_blogu_2025.csv"))

s22_rows <- list()
for (v in h3_y) for (o in c("PD_1", "PD_2", "PD_3", "PD_3_1")) {
  r <- c1_sonuc[sonuc == v & olcu == o]
  s22_rows[[length(s22_rows) + 1]] <- data.table(sonuc = v, olcu = o, metin = ga(r$tahmin, r$alt, r$ust, 1))
}
for (v in h3_y) s22_rows[[length(s22_rows) + 1]] <- data.table(sonuc = v, olcu = "wald_p", metin = pfmt(c1_etk[sonuc == v & egitim3 == 0, wald_p]))
s22 <- rbindlist(s22_rows)
fwrite(dcast(s22, olcu ~ sonuc, value.var = "metin"), file.path(rdir, "S22_egitim_blogu_C1.csv"))
cat("\nS11 egitim blogu (2025):\n")
print(s11[, .(Characteristic, n, FI, Exclusion, Missed, Exclusion_p)])
cat("\nS22 egitim blogu:\n")
print(dcast(s22, olcu ~ sonuc, value.var = "metin"))

write_json(list(olusturma = format(Sys.time()), kapilar = rbindlist(kapilar), h1_egitim_kirilim = h1_kir, h1_gelir_dilimi_egitim = gd, c1_egitim = c1_sonuc, c1_etkilesim_ortusme = c1_etk,
                tablo_Ek_rev1_egitim_H1 = tablo_listesi[["Ek_rev1_egitim_H1"]], tablo_Ek_rev1_egitim_H3 = tablo_listesi[["Ek_rev1_egitim_H3"]], S11_egitim_blogu = s11, S22_egitim_blogu = s22),
           file.path(rdir, "sayilar_rev1.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE, na = "null")
writeLines(capture.output(sessionInfo()), file.path(rdir, "sessionInfo_rev1.txt"))
kapi_yaz()
sure_ekle("tablolar ve JSON", t0)
sureler <- rbindlist(sureler)
sureler <- rbind(sureler, data.table(adim = "toplam", dakika = round(as.numeric(difftime(Sys.time(), baslangic, units = "mins")), 2)))
fwrite(sureler, file.path(rdir, "log", "rev1_sureler.csv"))
print(sureler)
cat("rev1_egitim.R bitti:", format(Sys.time()), "\n")
plan(sequential)
sink()
