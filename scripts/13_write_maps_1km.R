# Write the 1 km maps, the figure of potential and the tables that depend on the maps.
#
# Why    : writing the maps takes minutes, and it only needs to run again when the tables change.
# Inputs : data/outputs/results/pollination_eurostat_factors.rds (script 11)
#          data/outputs/results/pollination_accounts_nuts3_crop_year.rds (script 11)
#          data/outputs/results/pollination_value_country_crop_year.rds (script 12)
#          data/inputs/capri/, data/inputs/ebm/, data/inputs/sdm/, data/inputs/gis/
# Outputs: refs/maps_1km/pollination_<quantity>_1km_<year>.tif, outside the repository, which script 14 reads
#          data/outputs/figures/pollination_potential_class_2000_2024.png
#          data/outputs/figures/pollination_demand_flow_unmet_2024.png
#          data/outputs/results/pollination_results.xlsx, with the sheets of actual flow by ecosystem type added
#          data/outputs/report/maps_against_tables.rds, supply_by_ecosystem.rds
# Method : The script stops if the maps disagree with the tables, and it records the comparison for the report.
# Run    : source("scripts/13_write_maps_1km.R", encoding = "UTF-8"), from the project root, after scripts 11
#          and 12.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_accounts.R", encoding = "UTF-8")
source("scripts/helpers_results.R", encoding = "UTF-8")

results_dir <- "data/outputs/results"
gis_dir <- "refs/maps_1km"
regions <- read_regions()
factors <- readRDS(file.path(results_dir, "pollination_eurostat_factors.rds"))
combined <- readRDS(file.path(results_dir, "pollination_accounts_nuts3_crop_year.rds"))
prices <- readRDS(file.path(results_dir, "pollination_value_country_crop_year.rds")) |>
  select(geo, crop, year, eur_per_t)

for (year in years_report) {
  pot <- potential_1km(year)
  write_map(pot, sprintf("pollination_potential_all_1km_%s", year))
  write_map(potential_1km(year, band = "ebm_agro"), sprintf("pollination_potential_agro_1km_%s", year))
  writeRaster(classify_potential(pot), file.path(gis_dir, sprintf("pollination_potential_class_1km_%s.tif", year)),
              overwrite = TRUE, datatype = "INT1U", gdal = c("COMPRESS=DEFLATE", "ZLEVEL=9", "TILED=YES"))
  m <- account_maps(year, factors, value_per_t = prices)
  write_map(m[["demand_ha"]], sprintf("pollination_demand_ha_1km_%s", year))
  write_map(m[["flow_t"]], sprintf("pollination_flow_t_1km_%s", year))
  write_map(m[["unmet_t"]], sprintf("pollination_unmet_t_1km_%s", year))
  write_map(m[["flow_meur"]], sprintf("pollination_flow_meur2010_1km_%s", year), digits = 6)
  write_map(m[["unmet_meur"]], sprintf("pollination_unmet_meur2010_1km_%s", year), digits = 6)
  rm(pot, m)
  free_rasters()
  message(year, " maps done, ", format(Sys.time()))
}

# The figures of the report.
figure_dir <- "data/outputs/figures"
dir.create(figure_dir, showWarnings = FALSE, recursive = TRUE)
png(file.path(figure_dir, "pollination_potential_class_2000_2024.png"), width = 8, height = 4.2, units = "in", res = 200)
op <- par(mfrow = c(1, 2), mar = c(0.5, 0.5, 2, 0.5))
for (year in c(2000, 2024)) {
  plot(rast(file.path(gis_dir, sprintf("pollination_potential_class_1km_%s.tif", year))),
       col = c("#fdeadb", "#f9b98a", "#d97a3a", "#8c3f12"), type = "classes",
       levels = c("None", "Low", "Medium", "High"), axes = FALSE, main = year, legend = year == 2024,
       plg = list(x = "topleft", bty = "n"), box = FALSE, mar = NA)
}
par(op)
dev.off()

# Classes with fixed limits, because each map holds few very large values among many small ones.
map_panel <- function(name, limits, title) {
  x <- rast(file.path(gis_dir, sprintf("pollination_%s_1km_2024.tif", name)))
  plot(classify(x, rcl = cbind(limits[-length(limits)], limits[-1], seq_len(length(limits) - 1)), right = FALSE),
       col = c("#fdeadb", "#f9b98a", "#d97a3a", "#a9541f", "#6e3210")[seq_len(length(limits) - 1)], type = "classes",
       levels = c(paste("Under", limits[2]), paste(limits[2:(length(limits) - 2)], "to", limits[3:(length(limits) - 1)]),
                  paste(limits[length(limits) - 1], "or more")),
       axes = FALSE, main = title, cex.main = 0.95, plg = list(x = "topleft", bty = "n", cex = 0.75), box = FALSE, mar = NA)
}
png(file.path(figure_dir, "pollination_demand_flow_unmet_2024.png"), width = 9.6, height = 3.8, units = "in", res = 200)
op <- par(mfrow = c(1, 3), mar = c(0.5, 0.5, 2, 0.5))
map_panel("demand_ha", c(0.001, 1, 5, 20, 50, Inf), "Demand, hectares per km2")
map_panel("flow_t", c(0.001, 1, 5, 20, 100, Inf), "Actual flow, tonnes per km2")
map_panel("unmet_t", c(0.001, 1, 5, 20, 100, Inf), "Unmet demand, tonnes per km2")
par(op)
dev.off()

# Supply of the flow by ecosystem type, which needs the flow maps.
ecosystem_supply <- bind_rows(lapply(years_report, supply_by_ecosystem))

# Sheets of the results workbook, added here because they need the flow maps. Running the script again replaces them.
ecosystem_nuts <- to_nuts_levels(ecosystem_supply, regions, by = c("ecosystem", "year"), values = "flow_t") |>
  pivot_wider(names_from = ecosystem, values_from = flow_t)
ecosystem_names <- sort(unique(ecosystem_supply$ecosystem))
workbook_file <- file.path(results_dir, "pollination_results.xlsx")
wb <- wb_load(workbook_file)
for (lv in c("NUTS0", "NUTS2", "NUTS3")) {
  sheet <- paste("Flow by ecosystem", lv)
  if (sheet %in% wb_get_sheet_names(wb)) wb <- wb_remove_worksheet(wb, sheet)
  wb <- write_results_sheet(
    wb, sheet,
    title = paste0("Actual flow in physical terms by ecosystem type, in tonnes, ", lv),
    note = paste("The flow of each kilometre is shared in proportion to the expert-based suitability of each ecosystem type. This is the mapped",
                 "flow, without the estimates of the Flow sheets, which include Croatia, Malta and Cyprus. Values of 2024 use the crop area and yield",
                 "of 2018, so changes between 2018 and 2024 reflect pollination potential and national statistics, and not crop relocation."),
    data = filter(ecosystem_nuts, level == lv),
    metrics = setNames(paste(ecosystem_names, "(t)"), ecosystem_names)
  )
}
wb_save(wb, workbook_file, overwrite = TRUE)

save_report_table(
  ecosystem_supply |>
    inner_join(filter(regions, level == "NUTS3") |> select(id), by = "id") |>
    group_by(ecosystem, year) |>
    summarise(flow_t = sum(flow_t), .groups = "drop"),
  "supply_by_ecosystem"
)

# Totals of the maps, read back from disk, which are compared with the tables below.
read_total <- function(name, year) {
  global(rast(file.path(gis_dir, sprintf("pollination_%s_1km_%s.tif", name, year))), "sum", na.rm = TRUE)[[1]]
}
map_totals <- bind_rows(lapply(years_report, function(year) {
  range_potential <- minmax(rast(file.path(gis_dir, sprintf("pollination_potential_all_1km_%s.tif", year))))
  tibble(
    year = as.integer(year),
    demand_ha = read_total("demand_ha", year), flow_t = read_total("flow_t", year), unmet_t = read_total("unmet_t", year),
    flow_meur2010 = read_total("flow_meur2010", year), unmet_meur2010 = read_total("unmet_meur2010", year),
    potential_min = range_potential[1], potential_max = range_potential[2]
  )
}))

mapped <- mapped_table_totals(combined, prices)
stopifnot(all(map_totals$potential_min >= 0), all(map_totals$potential_max <= 1))
for (name in c("demand_ha", "flow_t", "unmet_t")) {
  check_conservation(map_totals[[name]], mapped[[name]], paste(name, "map against table"))
}
check_conservation(map_totals$flow_meur2010, mapped$flow_meur2010, "Value of flow, map against table", tolerance = 1e-3)
check_conservation(map_totals$unmet_meur2010, mapped$unmet_meur2010, "Value of unmet demand, map against table", tolerance = 1e-3)

# The comparison for the report. The tables also hold estimates, which the maps leave out.
all_totals <- combined |>
  group_by(year) |>
  summarise(table_flow_t = sum(flow_t), table_demand_ha = sum(area_ha), .groups = "drop")
save_report_table(
  inner_join(map_totals, rename_with(mapped, ~ paste0("mapped_", .x), -year), by = "year") |>
    inner_join(all_totals, by = "year"),
  "maps_against_tables"
)

clean_rasters()
