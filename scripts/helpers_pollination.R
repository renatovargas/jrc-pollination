# Helper functions of the crop pollination routine.
# Load with: source("scripts/helpers_pollination.R", encoding = "UTF-8")
# Each function does one small job, so the numbered scripts read as short steps.
# Equations and parameters follow Vallecillo et al. (2018), Appendix III.

library(terra)
library(dplyr)

years_report <- c(2000, 2006, 2012, 2018, 2024)

# Period of climate data behind each reporting year.
climate_window <- c(`2000` = "1999-2001", `2006` = "2005-2007", `2012` = "2011-2013",
                    `2018` = "2017-2019", `2024` = "2023-2025")

# Crop data year behind each reporting year. Spatial crop data end in 2018.
crop_year <- c(`2000` = 2000, `2006` = 2006, `2012` = 2012, `2018` = 2018, `2024` = 2018)

# Analysis window on the Corine grid: the European territory of the EU27 (metres, EPSG:3035).
analysis_extent <- ext(2630000, 7320000, 1380000, 5420000)

raster_options <- c("COMPRESS=DEFLATE", "PREDICTOR=3", "ZLEVEL=9", "TILED=YES", "BIGTIFF=IF_SAFER")

# The 1 km reductions of the expert-based model are stored as whole numbers, which compress far better than
# decimals. Each band has a factor: the file holds the value times the factor, and it is read back by dividing.
ebm_factors <- c(ebm = 1e4, ebm_agro = 1e4, land_cells = 1, agro_cells = 1)
ebm_supply_factor <- 100

#' Write bands as 16-bit whole numbers, each multiplied by its factor.
write_scaled <- function(x, path, factors) {
  scaled <- rast(lapply(seq_len(nlyr(x)), function(i) round(x[[i]] * factors[i])))
  names(scaled) <- names(x)
  writeRaster(scaled, path, overwrite = TRUE, datatype = "INT2U",
              gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=9", "TILED=YES"))
}

#' Read bands written by `write_scaled()`, as their original values.
read_scaled <- function(path, factors) {
  x <- rast(path)
  scoff(x) <- cbind(1 / factors, 0)
  x
}

# ---------------------------------------------------------------------------
# Land cover scores
# ---------------------------------------------------------------------------

#' Read the table of land cover scores.
#' @return A tibble with one row per Corine class, with `clc`, `floral`, `nesting`, `forest`,
#'   `seminatural`, `agro` and `ecosystem`.
read_scores <- function(path = "data/inputs/params/clc_pollination_scores.csv") {
  readr::read_csv(path, show_col_types = FALSE)
}

#' Replace Corine classes by a value of the score table. Classes that are not listed become NA.
#' @param clc SpatRaster of Corine codes.
#' @param scores Output of `read_scores()`.
#' @param column Name of the column with the new value.
reclass_clc <- function(clc, scores, column) {
  classify(clc, rcl = as.matrix(data.frame(scores$clc, scores[[column]])), others = NA)
}

# ---------------------------------------------------------------------------
# Expert-based model
# ---------------------------------------------------------------------------

#' Landscape suitability, the mean of floral availability and nesting suitability.
landscape_suitability <- function(clc, scores) {
  (reclass_clc(clc, scores, "floral") + reclass_clc(clc, scores, "nesting")) / 2
}

#' Forest core, the forest cells more than one cell away from the forest boundary.
#'
#' With 100 m cells the outer ring of cells is the 100 m edge. Cells beyond the raster or with no
#' data count as non-forest, so the crop used for tiles needs a margin of one cell.
#'
#' @param clc SpatRaster of Corine codes at 100 m.
#' @param forest_codes Corine codes of forest.
#' @return SpatRaster with 1 in forest core and 0 elsewhere.
forest_core <- function(clc, forest_codes = c(311, 312, 313)) {
  forest <- subst(clc, from = forest_codes, to = rep(1, length(forest_codes)), others = 0, raw = TRUE)
  forest <- subst(forest, NA, 0)
  focal(forest, w = 3, fun = "min", na.rm = FALSE, fillvalue = 0)
}

#' Distance decay from semi-natural areas (Ricketts et al., 2008).
#'
#' @param suitability SpatRaster of scores between 0 and 1.
#' @param distance SpatRaster of distance in metres. No data means more than `max_distance`.
#' @param decay Decay rate per metre.
#' @param max_distance Distance beyond which the score is zero, in metres.
apply_distance_decay <- function(suitability, distance, decay = 0.00046, max_distance = 20000) {
  distance <- subst(distance, NA, max_distance + 1)
  decayed <- suitability * exp(-decay * distance)
  ifel(distance > max_distance, 0 * suitability, decayed)
}

#' Monthly activity index of insects, in percent, after Corbet et al. (1993).
#'
#' @param temperature Mean air temperature in degrees Celsius.
#' @param radiation Solar irradiance during daylight in W per square metre.
#' @return The index, limited to the range from 0 to 100.
activity_index <- function(temperature, radiation) {
  black_globe <- -0.62 + 1.027 * temperature + 0.006 * radiation
  clamp(-39.3 + 4.01 * black_globe, lower = 0, upper = 100, values = TRUE)
}

#' Expert-based model on one block of the grid.
#'
#' @param clc Corine codes at 100 m, with a margin of at least one cell.
#' @param roads 1 on a major road and 0 elsewhere.
#' @param distance Distance to semi-natural areas in metres.
#' @param ai Growing season activity index in percent, on the same grid.
#' @param scores Output of `read_scores()`.
#' @return A SpatRaster with the expert-based suitability between 0 and 1, and NA on sea.
expert_model <- function(clc, roads, distance, ai, scores) {
  s <- landscape_suitability(clc, scores)
  s <- ifel(roads == 1, 0 * s, s)
  s <- ifel(forest_core(clc) == 1, 0 * s, s)
  s <- apply_distance_decay(s, distance)
  s * ai / 100
}

#' Mean of the expert-based model over the cells with land inside each 1 km cell.
to_1km_mean <- function(x, ...) aggregate(x, fact = 10, fun = "mean", na.rm = TRUE, ...)

#' Classes of pollination potential: 0 none, 1 low, 2 medium, 3 high.
classify_potential <- function(potential) {
  classify(potential, rcl = matrix(c(-Inf, 0.1, 0, 0.1, 0.2, 1, 0.2, 0.3, 2, 0.3, Inf, 3),
                                   ncol = 3, byrow = TRUE), right = FALSE)
}

# ---------------------------------------------------------------------------
# Downscaling from 1 km to 100 m
# ---------------------------------------------------------------------------

#' Allocate 1 km values to 100 m cells in proportion to a weight, keeping each 1 km total.
#'
#' A 1 km cell with no positive weight spreads its value evenly over its land cells.
#'
#' @param value_1km SpatRaster at 1 km of an extensive quantity (hectares, tonnes, euro).
#' @param weight_100m SpatRaster at 100 m of non-negative weights, aligned with `value_1km`.
#' @param land_100m SpatRaster at 100 m with 1 on land, used as the fallback weight.
#' @return SpatRaster at 100 m with the same unit per cell.
allocate_to_100m <- function(value_1km, weight_100m, land_100m) {
  w_sum <- aggregate(weight_100m, fact = 10, fun = "sum", na.rm = TRUE)
  l_sum <- aggregate(land_100m, fact = 10, fun = "sum", na.rm = TRUE)
  per_weight <- disagg(value_1km / w_sum, fact = 10)
  per_land <- disagg(value_1km / l_sum, fact = 10)
  use_weight <- disagg(w_sum > 0, fact = 10)
  ifel(use_weight == 1, per_weight * subst(weight_100m, NA, 0), per_land * land_100m)
}

# ---------------------------------------------------------------------------
# Tables
# ---------------------------------------------------------------------------

#' Sum the layers of a raster by zone.
#' @param x SpatRaster with one or more layers.
#' @param zones SpatRaster of integer zone ids on the same grid.
#' @return A data frame with `id` and one column per layer.
sum_by_zone <- function(x, zones) {
  out <- zonal(x, zones, fun = "sum", na.rm = TRUE)
  names(out)[1] <- "id"
  out
}

#' Fail with a message when two sets of numbers differ by more than a relative tolerance.
check_conservation <- function(a, b, label, tolerance = 1e-4) {
  if (anyNA(a) || anyNA(b)) stop(label, ": missing values")
  gap <- abs(a - b) / pmax(abs(b), 1e-9)
  if (any(gap > tolerance)) stop(label, ": largest relative gap ", signif(max(gap), 3))
  invisible(TRUE)
}
