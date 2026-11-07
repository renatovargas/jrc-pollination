# Helper functions that turn the 1 km inputs into the crop pollination accounts.
# Load with: source("scripts/helpers_accounts.R", encoding = "UTF-8")
# Used by the numbered scripts.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

# Rasters of the whole grid are large, so terra keeps them on disk instead of in memory or in /tmp.
terra_tmp <- file.path("refs", "tmp_terra")
dir.create(terra_tmp, showWarnings = FALSE, recursive = TRUE)
terraOptions(todisk = TRUE, tempdir = terra_tmp, progress = 0)

#' Free memory between years. Temporary raster files stay until the end of the script, because
#' live rasters may still read them.
free_rasters <- function() {
  gc(verbose = FALSE)
  invisible(NULL)
}

#' Delete the temporary raster files of this session. Call it once, at the end of a script.
clean_rasters <- function() {
  tmpFiles(current = TRUE, orphan = FALSE, remove = TRUE)
  unlink(list.files(terra_tmp, "^reduction_", full.names = TRUE))
  rm(list = ls(reductions_read), envir = reductions_read)
  invisible(NULL)
}

reductions_read <- new.env()

#' Read a 1 km reduction of the expert-based model as 32-bit floats, once per script.
#'
#' The model values are 32-bit floats, and the files hold them as whole numbers to save space. Returning the
#' same floats keeps the results independent of how the files are stored, because a cell can sit within
#' 0.00000003 of a threshold.
read_reduction <- function(path, factors) {
  if (is.null(reductions_read[[path]])) {
    float_file <- tempfile("reduction_", tmpdir = terra_tmp, fileext = ".tif")
    writeRaster(read_scaled(path, factors), float_file, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE")
    reductions_read[[path]] <- float_file
  }
  rast(reductions_read[[path]])
}

spa_threshold <- 0.2

# Countries that the crop data do not cover (Vallecillo et al., 2018, footnote 6).
no_crop_data <- c("HR", "MT", "CY")

read_crops <- function() readr::read_csv("data/inputs/params/crop_dependency.csv", show_col_types = FALSE)
read_regions <- function() readr::read_csv("data/inputs/gis/nuts_regions.csv", show_col_types = FALSE)

#' Reduced expert-based model of a year.
read_ebm <- function(year, route = "rebuilt") {
  folder <- if (route == "catalogue") "refs/ebm_catalogue" else "data/inputs/ebm"
  read_reduction(sprintf("%s/ebm_%s_%s_1km.tif", folder, route, year), ebm_factors)
}

#' Pollination potential at 1 km, the mean of the expert-based model and the bumblebee model.
potential_1km <- function(year, route = "rebuilt", band = "ebm") {
  ebm <- read_ebm(year, route)[[band]]
  sdm <- rast("data/inputs/sdm/bumblebee_sdm_1km.tif")
  out <- mask((ebm + sdm) / 2, ebm)
  names(out) <- "potential"
  out
}

#' Crop area in hectares and yield in kilograms per hectare for a reporting year, with no data as zero.
read_capri <- function(year) {
  cy <- crop_year[[as.character(year)]]
  list(
    area = subst(rast(sprintf("data/inputs/capri/capri_area_ha_%s.tif", cy)), NA, 0),
    yield = subst(rast(sprintf("data/inputs/capri/capri_yield_kgha_%s.tif", cy)), NA, 0)
  )
}

#' NUTS3 numbers of the 1 km cells, without the countries that the crop data do not cover.
crop_zones <- function(zones = rast("data/inputs/gis/nuts3_id_1km.tif"), regions = read_regions()) {
  drop <- regions$id[regions$geo %in% no_crop_data & !is.na(regions$id)]
  classify(zones, rcl = cbind(drop, NA), others = NULL)
}

#' Physical accounts by NUTS3 region and crop for one year, in CAPRI units.
#'
#' @return Tibble with id, crop, year, area_ha, area_met_ha, production_t and production_met_t.
capri_by_zone <- function(year, zones = crop_zones()) {
  capri <- read_capri(year)
  met <- subst(potential_1km(year) >= spa_threshold, NA, 0)
  production <- capri$area * capri$yield / 1000
  tally <- function(x, name) {
    sum_by_zone(x, zones) |>
      tidyr::pivot_longer(-id, names_to = "crop", values_to = name)
  }
  tally(capri$area, "area_ha") |>
    left_join(tally(capri$area * met, "area_met_ha"), by = c("id", "crop")) |>
    left_join(tally(production, "production_t"), by = c("id", "crop")) |>
    left_join(tally(production * met, "production_met_t"), by = c("id", "crop")) |>
    mutate(year = year, .after = crop) |>
    (\(out) { free_rasters(); out })()
}

#' Land and agricultural hectares by NUTS3 region and class of potential, for one year.
potential_by_zone <- function(year, zones = rast("data/inputs/gis/nuts3_id_1km.tif")) {
  ebm <- read_ebm(year)
  classes <- classify_potential(potential_1km(year))
  labels <- c("none", "low", "medium", "high")
  out <- lapply(0:3, function(k) {
    in_class <- subst(classes == k, NA, 0)
    land <- sum_by_zone(ebm[["land_cells"]] * in_class, zones)
    agro <- sum_by_zone(subst(ebm[["agro_cells"]], NA, 0) * in_class, zones)
    tibble(id = land$id, class = labels[k + 1], land_ha = land[[2]], agro_ha = agro[[2]])
  })
  free_rasters()
  bind_rows(out) |> mutate(year = year, .after = id)
}

#' Run the 100 m model for Luxembourg in 2018 from the clips in the repository.
#'
#' @return The largest gap in a 1 km cell inside Luxembourg between this run and the reduction of the full run.
run_pilot_luxembourg <- function(pilot = "data/inputs/pilot_lu", scores = read_scores()) {
  clc_lu <- rast(file.path(pilot, "clc_2018.tif"))
  roads_lu <- rast(file.path(pilot, "roads.tif"))
  distance_lu <- rast(file.path(pilot, "distance_2018.tif"))
  ai_lu <- resample(rast("data/inputs/climate/activity_index_2018_1km.tif"), clc_lu, method = "bilinear")
  ebm_lu <- expert_model(clc_lu, roads_lu, distance_lu, ai_lu, scores)

  lu <- vect("data/inputs/gis/nuts0_eu27.gpkg")
  lu <- lu[lu$geo == "LU", ]
  ebm_lu_1km <- to_1km_mean(mask(ebm_lu, rasterize(lu, ebm_lu, field = 1, touches = TRUE)))
  reduction <- crop(read_ebm(2018)[["ebm"]], ebm_lu_1km)
  inner <- mask(reduction, buffer(lu, -2000))
  max(abs(values(inner - ebm_lu_1km, mat = FALSE)), na.rm = TRUE)
}

#' Flow by NUTS3 region and ecosystem type for one year, shared by the expert-based suitability of each 1 km cell.
supply_by_ecosystem <- function(year, gis_dir = "refs/maps_1km") {
  path <- sprintf("data/inputs/ebm/ebm_supply_rebuilt_%s_1km.tif", year)
  parts <- subst(read_reduction(path, rep(ebm_supply_factor, nlyr(rast(path)))), NA, 0)
  total <- sum(parts)
  flow <- rast(file.path(gis_dir, sprintf("pollination_flow_t_1km_%s.tif", year)))
  zones <- rast("data/inputs/gis/nuts3_id_1km.tif")
  shared <- ifel(total > 0, parts / total, 0) * flow
  names(shared) <- names(parts)
  # Flow in a cell where no ecosystem supports it is attributed to cropland, where the crops are.
  no_support <- sum_by_zone(ifel(total > 0, 0, flow), zones)
  sum_by_zone(shared, zones) |>
    tidyr::pivot_longer(-id, names_to = "ecosystem", values_to = "flow_t") |>
    mutate(ecosystem = gsub("\\.", " ", sub("^sum_", "", ecosystem)), year = year) |>
    bind_rows(tibble(id = no_support$id, ecosystem = "Cropland", flow_t = no_support[[2]], year = year)) |>
    group_by(id, ecosystem, year) |>
    summarise(flow_t = sum(flow_t, na.rm = TRUE), .groups = "drop")
}

#' Table totals of what the maps hold, by year, which leaves out the estimates.
#'
#' @param combined Accounts by NUTS3 region, crop and year.
#' @param prices Tibble with geo, crop, year and eur_per_t.
mapped_table_totals <- function(combined, prices) {
  combined |>
    filter(!estimated) |>
    left_join(prices, by = c("geo", "crop", "year")) |>
    mutate(
      flow_meur2010 = flow_t * coalesce(eur_per_t, 0) / 1e6,
      unmet_meur2010 = unmet_t * coalesce(eur_per_t, 0) / 1e6
    ) |>
    group_by(year) |>
    summarise(
      demand_ha = sum(area_ha), flow_t = sum(flow_t), unmet_t = sum(unmet_t),
      flow_meur2010 = sum(flow_meur2010), unmet_meur2010 = sum(unmet_meur2010)
    ) |>
    arrange(year)
}

#' Scale CAPRI accounts to Eurostat production, keeping the pattern of each crop within a country.
#'
#' A crop and country without a Eurostat figure keep the CAPRI production, and are flagged.
#'
#' @param capri Output of `capri_by_zone()` with `geo` and `dependency` added.
#' @param eurostat Tibble with geo, crop, year and production_t.
#' @return `capri` with `national_t`, `factor`, `flow_t`, `unmet_t` and `eurostat_gap`.
scale_to_eurostat <- function(capri, eurostat) {
  national <- capri |>
    group_by(geo, crop, year) |>
    summarise(capri_t = sum(production_t), .groups = "drop") |>
    left_join(rename(eurostat, eurostat_t = production_t), by = c("geo", "crop", "year")) |>
    mutate(
      eurostat_gap = is.na(eurostat_t) & capri_t > 0,
      factor = if_else(capri_t > 0 & !is.na(eurostat_t), eurostat_t / capri_t, 1)
    )
  capri |>
    left_join(select(national, geo, crop, year, factor, eurostat_gap), by = c("geo", "crop", "year")) |>
    mutate(
      flow_t = production_met_t * factor * dependency,
      unmet_t = (production_t - production_met_t) * factor * dependency,
      total_t = production_t * factor
    )
}

#' Estimate for national crops that the crop data do not place on the map.
#'
#' The share of a region's farmland inside the service area stands in for the share of the crop inside
#' it. National production is shared among regions in proportion to their farmland.
#'
#' @param missing Tibble with geo, crop, year, dependency and production_t, national values.
#' @param farmland Output of `potential_by_zone()` joined to regions, with geo, id, year, class, agro_ha.
#' @return Tibble by region with the columns of `scale_to_eurostat()` and `estimated = TRUE`.
estimate_without_map <- function(missing, farmland) {
  shares <- farmland |>
    group_by(geo, id, year) |>
    summarise(
      agro = sum(agro_ha),
      agro_met = sum(agro_ha[class %in% c("medium", "high")]),
      .groups = "drop"
    ) |>
    group_by(geo, year) |>
    mutate(region_share = if (sum(agro) > 0) agro / sum(agro) else 0) |>
    ungroup() |>
    mutate(met_share = if_else(agro > 0, agro_met / agro, 0))
  missing |>
    inner_join(shares, by = c("geo", "year"), relationship = "many-to-many") |>
    transmute(
      id, crop, year, geo, dependency,
      total_t = production_t * region_share,
      flow_t = total_t * met_share * dependency,
      unmet_t = total_t * (1 - met_share) * dependency,
      estimated = TRUE
    )
}

#' Add up a table of NUTS3 values to NUTS0, NUTS2 and NUTS3.
#'
#' NUTS2 codes are the first four characters of the NUTS3 codes, and countries the first two.
#'
#' @param data Tibble with `id` and the grouping and value columns.
#' @param regions Output of `read_regions()`.
#' @param by Names of the grouping columns other than the region.
#' @param values Names of the value columns.
#' @return Long tibble with level, nuts_id, name, the grouping columns and the values.
to_nuts_levels <- function(data, regions, by, values) {
  n3 <- regions |> filter(level == "NUTS3") |> select(id, nuts3 = nuts_id)
  base <- data |> inner_join(n3, by = "id") |>
    mutate(NUTS3 = nuts3, NUTS2 = substr(nuts3, 1, 4), NUTS0 = substr(nuts3, 1, 2))
  lapply(c("NUTS0", "NUTS2", "NUTS3"), function(lv) {
    base |>
      group_by(level = lv, nuts_id = .data[[lv]], across(all_of(by))) |>
      summarise(across(all_of(values), \(v) sum(v, na.rm = TRUE)), .groups = "drop")
  }) |>
    bind_rows() |>
    left_join(select(regions, nuts_id, name), by = "nuts_id") |>
    relocate(name, .after = nuts_id)
}

#' Per-cell maps of total demand, flow and unmet demand at 1 km for one year.
#'
#' @param year Reporting year.
#' @param factors Tibble with geo, crop, year and factor, from `scale_to_eurostat()`.
#' @param value_per_t Optional tibble with geo, crop, year and eur_per_t, for the value maps.
#' @return A SpatRaster with layers demand_ha, flow_t, unmet_t and, with prices, flow_meur and unmet_meur.
account_maps <- function(year, factors, value_per_t = NULL) {
  regions <- read_regions()
  crops <- read_crops()
  zones <- crop_zones(regions = regions)
  capri <- read_capri(year)
  met <- subst(potential_1km(year) >= spa_threshold, NA, 0)
  geo_of <- regions |> filter(!is.na(id)) |> select(id, geo)

  # A raster with the national value of a crop in each cell.
  national_raster <- function(table, crop_code, column) {
    rcl <- geo_of |>
      inner_join(filter(table, crop == crop_code, year == !!year), by = "geo") |>
      select(id, all_of(column)) |>
      as.matrix()
    classify(zones, rcl = rcl, others = NA)
  }

  sums <- list(demand_ha = 0, flow_t = 0, unmet_t = 0, flow_meur = 0, unmet_meur = 0)
  for (i in seq_len(nrow(crops))) {
    code <- crops$capri_code[i]
    k <- subst(national_raster(factors, code, "factor"), NA, 1)
    # A factor of zero marks a crop and country that the tables estimate and the maps leave out.
    area <- mask(capri$area[[code]], zones) * (k > 0)
    served <- area * capri$yield[[code]] / 1000 * k * crops$dependency[i]
    flow <- served * met
    unmet <- served * (1 - met)
    sums$demand_ha <- sums$demand_ha + area
    sums$flow_t <- sums$flow_t + flow
    sums$unmet_t <- sums$unmet_t + unmet
    if (!is.null(value_per_t)) {
      u <- subst(national_raster(value_per_t, code, "eur_per_t"), NA, 0)
      sums$flow_meur <- sums$flow_meur + flow * u / 1e6
      sums$unmet_meur <- sums$unmet_meur + unmet * u / 1e6
    }
    gc(verbose = FALSE)
  }
  keep <- if (is.null(value_per_t)) c("demand_ha", "flow_t", "unmet_t") else names(sums)
  out <- rast(sums[keep])
  names(out) <- keep
  out
}

#' Write a 1 km map with the conventions of the repository.
write_map <- function(x, name, dir = "refs/maps_1km", digits = 3) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, paste0(name, ".tif"))
  writeRaster(round(x, digits), path, overwrite = TRUE, datatype = "FLT4S", gdal = raster_options)
  invisible(path)
}
