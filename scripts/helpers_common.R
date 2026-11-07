# Helper functions shared by the numbered scripts.
# Load with: source("scripts/helpers_common.R", encoding = "UTF-8")
# Each function does one small job so the scripts read as a sequence of short steps.
# Topic-specific helpers go in their own file, for example scripts/helpers_<topic>.R.

library(dplyr)
library(terra)

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
