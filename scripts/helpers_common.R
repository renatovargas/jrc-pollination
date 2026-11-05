# Helper functions shared by the numbered scripts.
# Load with: source("scripts/helpers_common.R", encoding = "UTF-8")
# Each function does one small job so the scripts read as a sequence of short steps.
# Topic-specific helpers go in their own file, for example scripts/helpers_<topic>.R.

library(dplyr)
library(terra)

# ---------------------------------------------------------------------------
# Spatial disaggregation
# ---------------------------------------------------------------------------

#' Rasterise the country polygons on the grid of a template raster.
#'
#' @param countries A SpatVector with a character column `geo`.
#' @param template A SpatRaster that defines the grid.
#' @return A list with `raster` (integer country ids per cell) and `ids` (a tibble
#'   that links each id to its country code).
make_country_ids <- function(countries, template) {
  countries$id <- seq_len(nrow(countries))
  grid <- rasterize(countries, template, field = "id")
  list(
    raster = grid,
    ids = tibble(id = countries$id, geo = countries$geo)
  )
}

#' Sum the weights of each country once, so every year can reuse the result.
#'
#' @param weight A SpatRaster of non-negative weights.
#' @param country_ids Output of `make_country_ids()`.
#' @return A tibble with geo and weight_sum.
country_weight_sums <- function(weight, country_ids) {
  zonal(weight, country_ids$raster, fun = "sum", na.rm = TRUE) |>
    setNames(c("id", "weight_sum")) |>
    left_join(country_ids$ids, by = "id") |>
    select(geo, weight_sum)
}

#' Spread country totals over a weight raster.
#'
#' Each cell receives `total * weight / weight_sum` for its country, so the cells of
#' a country add up to the national total (conservation of the sum).
#'
#' @param totals A tibble with geo and value (the national totals).
#' @param weight A SpatRaster of weights.
#' @param country_ids Output of `make_country_ids()`.
#' @param weight_sums Output of `country_weight_sums()`.
#' @return A SpatRaster with the same units as `totals$value`.
spread_totals <- function(totals, weight, country_ids, weight_sums) {
  per_weight <- country_ids$ids |>
    left_join(weight_sums, by = "geo") |>
    left_join(totals |> select(geo, value), by = "geo") |>
    mutate(factor = if_else(weight_sum > 0, value / weight_sum, NA_real_)) |>
    filter(!is.na(factor))

  factor_raster <- classify(
    country_ids$raster,
    rcl = as.matrix(per_weight[, c("id", "factor")]),
    others = NA
  )
  weight * factor_raster
}

# ---------------------------------------------------------------------------
# Export and checks
# ---------------------------------------------------------------------------

#' Save a table as rds and xlsx in one call.
#'
#' @param x A data frame.
#' @param name File name without extension.
#' @param dir Output directory.
#' @return The two file paths, invisibly.
export_table <- function(x, name, dir = "data/outputs/results") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, paste0(name, c(".rds", ".xlsx")))
  saveRDS(x, paths[1])
  writexl::write_xlsx(x, paths[2])
  invisible(paths)
}

#' Save a small table that the report reads.
#'
#' @param x A data frame.
#' @param name File name without extension.
save_report_table <- function(x, name, dir = "data/outputs/report") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(x, file.path(dir, paste0(name, ".rds")))
  invisible(x)
}

#' Run a conservation check, which stops the script on failure, and return a row for the report.
#'
#' @param a,b Numbers that should agree.
#' @param label Description of the check.
#' @param tolerance Largest relative gap allowed.
#' @return A one-row tibble with the check, its largest relative gap and its tolerance.
record_check <- function(a, b, label, tolerance = 1e-4) {
  check_conservation(a, b, label, tolerance = tolerance)
  tibble::tibble(check = label, largest_gap = max(abs(a - b) / pmax(abs(b), 1e-9)), tolerance = tolerance)
}
