# Writes one sheet of a results workbook: a banner, a nested header by year and metric, one row per
# region and a total row. Used by scripts 11 and 12 to build the NUTS0, NUTS2 and NUTS3 workbooks.
library(dplyr)
library(tidyr)
library(openxlsx2)

results_number_format <- "#,##0.0"

#' Write one results sheet.
#'
#' @param wb A workbook.
#' @param sheet Sheet name.
#' @param title Table title (second banner line).
#' @param note Explanatory text (third banner line).
#' @param data Long table with `nuts_id`, `name`, `year` and the metric columns.
#' @param metrics Named character vector, column name = header label.
#' @return The workbook.
write_results_sheet <- function(wb, sheet, title, note, data, metrics) {
  years <- sort(unique(data$year))
  wide <- data |>
    select(nuts_id, name, year, all_of(names(metrics))) |>
    pivot_wider(
      names_from = year, values_from = all_of(names(metrics)),
      names_glue = "{year}__{.value}", names_vary = "slowest"
    ) |>
    arrange(nuts_id)
  total <- wide |>
    summarise(across(-c(nuts_id, name), \(v) sum(v, na.rm = TRUE))) |>
    mutate(nuts_id = "Total", name = "Total of the regions", .before = 1)
  wide <- bind_rows(wide, total)

  n_cols <- ncol(wide)
  n_met <- length(metrics)
  header_row <- 5L
  data_start <- 7L
  data_end <- data_start + nrow(wide) - 1L

  wb <- wb_add_worksheet(wb, sheet)

  banner <- c("Crop pollination accounts", title, note)
  for (i in 1:3) {
    wb <- wb_add_data(wb, sheet, x = banner[i], start_row = i, start_col = 1, col_names = FALSE)
    wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = i, cols = 1:min(n_cols, 10)))
    wb <- wb_add_cell_style(
      wb, sheet, dims = wb_dims(rows = i, cols = 1),
      wrap_text = TRUE, vertical = "center"
    )
  }
  wb <- wb_set_row_heights(wb, sheet, rows = 1:3, heights = c(18, 18, 32))

  year_row <- c("Code", "Region", rep(as.character(years), each = n_met))
  metric_row <- c("Code", "Region", rep(unname(metrics), times = length(years)))
  wb <- wb_add_data(wb, sheet, x = matrix(year_row, nrow = 1),
                    start_row = header_row, start_col = 1, col_names = FALSE)
  wb <- wb_add_data(wb, sheet, x = matrix(metric_row, nrow = 1),
                    start_row = header_row + 1L, start_col = 1, col_names = FALSE)
  wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row:(header_row + 1L), cols = 1))
  wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row:(header_row + 1L), cols = 2))
  if (n_met > 1) {
    for (k in seq_along(years)) {
      first <- 3L + (k - 1L) * n_met
      wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row, cols = first:(first + n_met - 1L)))
    }
  }
  header_dims <- wb_dims(rows = header_row:(header_row + 1L), cols = 1:n_cols)
  wb <- wb_add_font(wb, sheet, dims = header_dims, bold = TRUE)
  wb <- wb_add_cell_style(wb, sheet, dims = header_dims,
                          wrap_text = TRUE, horizontal = "center", vertical = "center")
  wb <- wb_add_border(wb, sheet, dims = wb_dims(rows = header_row + 1L, cols = 1:n_cols),
                      bottom_border = "thin", top_border = "none",
                      left_border = "none", right_border = "none")
  wb <- wb_set_row_heights(wb, sheet, rows = header_row:(header_row + 1L), heights = c(20, 34))

  wb <- wb_add_data(wb, sheet, x = wide, start_row = data_start, start_col = 1,
                    col_names = FALSE, na = "", apply_cell_style = FALSE)
  wb <- wb_add_numfmt(wb, sheet, dims = wb_dims(rows = data_start:data_end, cols = 3:n_cols),
                      numfmt = results_number_format)
  total_dims <- wb_dims(rows = data_end, cols = 1:n_cols)
  wb <- wb_add_font(wb, sheet, dims = total_dims, bold = TRUE)
  wb <- wb_add_border(wb, sheet, dims = total_dims,
                      top_border = "thin", bottom_border = "thin",
                      left_border = "none", right_border = "none")
  wb <- wb_set_col_widths(wb, sheet, cols = 1:n_cols, widths = c(10, 30, rep(15, n_cols - 2L)))
  wb_freeze_pane(wb, sheet, first_active_row = data_start, first_active_col = 3L)
}
