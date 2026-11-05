# Helper functions of the report, which only read small tables and format them.
# Load with: source("scripts/helpers_report.R", encoding = "UTF-8")

library(dplyr)
library(tidyr)
library(flextable)

#' Read a small table written by the numbered scripts.
read_report <- function(name) readRDS(file.path("data/outputs/report", paste0(name, ".rds")))

#' Format a data frame as a flextable that works in HTML and PDF.
#'
#' @param x A data frame.
#' @param digits Decimals for numeric columns.
#' @param font_size Font size in points.
#' @return A flextable.
show_table <- function(x, digits = 1, font_size = 9) {
  flextable(x) |>
    colformat_double(digits = digits, big.mark = ",") |>
    colformat_int(big.mark = "") |>
    fontsize(size = font_size, part = "all") |>
    autofit() |>
    fit_for_pdf()
}

#' Keep a table inside the text width of a PDF page. HTML output keeps the table as it is.
fit_for_pdf <- function(table, max_width = 6.2) {
  if (!knitr::is_latex_output()) return(table)
  table |>
    set_table_properties(layout = "fixed") |>
    width(width = max_width / length(table$col_keys))
}

#' Format a number for the text.
num <- function(x, digits = 1) format(round(x, digits), nsmall = digits, big.mark = ",", trim = TRUE)
