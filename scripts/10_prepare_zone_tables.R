# Turn the 1 km rasters into the tables by region that scripts 11 and 12 read.
#
# Why    : adding up the rasters by region takes minutes, and it only needs to run again when a raster
#          input or the service area threshold changes.
# Inputs : data/inputs/capri/, data/inputs/ebm/, data/inputs/sdm/, data/inputs/gis/, data/inputs/pilot_lu/,
#          data/inputs/climate/
# Outputs: data/inputs/intermediate/capri_by_zone.rds      crop area and production by NUTS3, crop and year,
#                                                          inside and outside the service area
#          data/inputs/intermediate/farmland_by_zone.rds   land and farmland by NUTS3, year and class of potential
#          data/outputs/report/pilot_luxembourg.rds        largest gap between the Luxembourg run and the full run
#          data/outputs/report/territory.rds               regions and land covered
#          data/outputs/report/layer_summary.rds           mean and range of the activity index, models and potential
#          data/outputs/report/demand_large_cells.rds      1 km cells that hold more than 100 hectares of demand
#          data/outputs/report/demand_by_class.rds         CAPRI hectares of demand by class of potential
#          data/outputs/report/uncovered_crop_area.rds     CAPRI hectares in the countries that it does not cover
# Run    : source("scripts/10_prepare_zone_tables.R", encoding = "UTF-8"), from the project root.
#          Each run recomputes all these tables.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_accounts.R", encoding = "UTF-8")

out_dir <- "data/inputs/intermediate"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

saveRDS(bind_rows(lapply(years_report, capri_by_zone)), file.path(out_dir, "capri_by_zone.rds"))
message("CAPRI by zone done, ", format(Sys.time()))

saveRDS(bind_rows(lapply(years_report, potential_by_zone)), file.path(out_dir, "farmland_by_zone.rds"))
message("Farmland by zone done, ", format(Sys.time()))

save_report_table(tibble(largest_gap = run_pilot_luxembourg()), "pilot_luxembourg")
message("Luxembourg done, ", format(Sys.time()))

# Small tables that the report shows or quotes.
regions <- read_regions()
ebm_2018 <- read_ebm(2018)
save_report_table(
  tibble(
    countries = sum(regions$level == "NUTS0"),
    nuts2 = sum(regions$level == "NUTS2"),
    nuts3 = sum(regions$level == "NUTS3"),
    land_mha = global(ebm_2018[["land_cells"]], "sum", na.rm = TRUE)[[1]] / 1e6,
    agro_mha = global(ebm_2018[["agro_cells"]], "sum", na.rm = TRUE)[[1]] / 1e6,
    cells_1km = global(!is.na(ebm_2018[["ebm"]]), "sum", na.rm = TRUE)[[1]]
  ),
  "territory"
)

describe_layer <- function(x, layer, year) {
  s <- global(x, c("mean", "min", "max"), na.rm = TRUE)
  tibble(layer = layer, year = as.integer(year), mean = s$mean, min = s$min, max = s$max)
}
save_report_table(
  bind_rows(lapply(years_report, function(year) {
    ebm <- read_ebm(year)
    ai <- mask(rast(sprintf("data/inputs/climate/activity_index_%s_1km.tif", year)), ebm[["ebm"]])
    bind_rows(
      describe_layer(ai, "activity_index", year),
      describe_layer(ebm[["ebm"]], "expert_model", year),
      describe_layer(mask(rast("data/inputs/sdm/bumblebee_sdm_1km.tif"), ebm[["ebm"]]), "bumblebee_model", year),
      describe_layer(potential_1km(year), "potential", year)
    )
  })),
  "layer_summary"
)
message("Layer summaries done, ", format(Sys.time()))

demand_tables <- lapply(years_report, function(year) {
  capri <- read_capri(year)
  demand <- mask(sum(capri$area), crop_zones(regions = regions))
  total <- global(demand, "sum", na.rm = TRUE)[[1]]
  in_large <- global(ifel(demand > 100, demand, 0), "sum", na.rm = TRUE)[[1]]
  large <- tibble(
    year = as.integer(year),
    cells = global(demand > 100, "sum", na.rm = TRUE)[[1]],
    cells_with_demand = global(demand > 0, "sum", na.rm = TRUE)[[1]],
    largest_ha = global(demand, "max", na.rm = TRUE)[[1]],
    share_of_demand = in_large / total
  )
  labels <- c("none", "low", "medium", "high")
  by_class <- zonal(demand, classify_potential(potential_1km(year)), fun = "sum", na.rm = TRUE)
  names(by_class) <- c("class", "area_ha")
  by_class <- by_class |>
    mutate(class = labels[class + 1], year = as.integer(year)) |>
    bind_rows(tibble(class = "no potential", year = as.integer(year), area_ha = total - sum(by_class$area_ha)))

  zones <- rast("data/inputs/gis/nuts3_id_1km.tif")
  uncovered <- sum_by_zone(capri$area, zones) |>
    tidyr::pivot_longer(-id, names_to = "crop", values_to = "area_ha") |>
    inner_join(filter(regions, geo %in% no_crop_data, level == "NUTS3") |> select(id, geo), by = "id") |>
    group_by(geo, crop) |>
    summarise(area_ha = sum(area_ha), .groups = "drop") |>
    filter(area_ha > 0) |>
    mutate(year = as.integer(year))
  free_rasters()
  list(large = large, by_class = by_class, uncovered = uncovered)
})
save_report_table(bind_rows(lapply(demand_tables, `[[`, "large")), "demand_large_cells")
save_report_table(bind_rows(lapply(demand_tables, `[[`, "by_class")), "demand_by_class")
save_report_table(bind_rows(lapply(demand_tables, `[[`, "uncovered")), "uncovered_crop_area")
message("Demand tables done, ", format(Sys.time()))

clean_rasters()
