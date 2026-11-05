# Write the 100 m maps of the crop pollination accounts.
#
# Why    : the 100 m maps are too large to version, so they go to refs/maps_100m/ and are published
#          outside the repository.
# Inputs : refs/ebm_tiles/rebuilt/<year>/ebm_<x>_<y>.tif (script 07)
#          refs/clc_accounting/<year> (script 02)
#          data/inputs/sdm/bumblebee_sdm_1km.tif
#          refs/maps_1km/pollination_<quantity>_1km_<year>.tif (script 13)
# Outputs: refs/maps_100m/pollination_<quantity>_100m_<year>.tif. Values are whole numbers in small units,
#          which keeps the files several times smaller than decimals, with no loss that matters:
#            potential_all_x10000, potential_agro_x10000   suitability times 10 000 (16-bit integer)
#            demand_m2                                     square metres of dependent crops per cell
#            flow_all_kg, flow_agro_kg                     kilograms attributable to pollination per cell
#            unmet_kg                                      kilograms of unmet demand per cell
#            flow_agro_eur2010, unmet_eur2010              euro at constant 2010 prices per cell
# Method : Potential at 100 m is the mean of the 100 m expert-based model and the bumblebee model
#          interpolated to 100 m. The other maps allocate the 1 km values, so each 1 km cell keeps its
#          total. `agro` maps and demand use agricultural cells as the weight. `flow_all` uses the
#          expert-based suitability of all land cells as the weight, so the flow is placed on the
#          ecosystems that support the pollinators. A 1 km cell with no positive weight spreads its
#          value evenly over its land cells.
# Run    : source("scripts/14_write_maps_100m.R", encoding = "UTF-8"), from the project root, after the
#          script 13. Resumable by tile. Set `years_override` in the session to run a subset.

source("scripts/helpers_pollination.R", encoding = "UTF-8")
library(parallel)

run_years <- if (exists("years_override")) years_override else years_report
n_workers <- if (exists("workers")) workers else 2
scores <- read_scores()
out_dir <- "refs/maps_100m"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
quantities <- c("potential_all_x10000", "potential_agro_x10000", "demand_m2", "flow_all_kg", "flow_agro_kg", "unmet_kg",
                "flow_agro_eur2010", "unmet_eur2010")
integer_options <- function() c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=6", "TILED=YES")

one_km <- function(name, year, box) {
  crop(subst(rast(sprintf("refs/maps_1km/pollination_%s_1km_%s.tif", name, year)), NA, 0), box)
}

run_tile <- function(ebm_file, year, tile_dir) {
  stem <- sub("^ebm_(.*)\\.tif$", "\\1", basename(ebm_file))
  targets <- file.path(tile_dir, sprintf("%s_%s.tif", quantities, stem))
  if (all(file.exists(targets))) return(stem)
  terraOptions(memfrac = 0.1, tempdir = tile_dir, progress = 0)

  ebm <- rast(ebm_file)
  box <- ext(ebm)
  clc_file <- list.files(file.path("refs/clc_accounting", year), pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  clc <- crop(rast(clc_file), box)
  levels(clc) <- NULL
  coltab(clc) <- NULL
  land <- ifel(is.na(ebm), NA, 1)
  agro <- mask(reclass_clc(clc, scores, "agro"), land)

  sdm <- resample(rast("data/inputs/sdm/bumblebee_sdm_1km.tif"), ebm, method = "bilinear")
  potential <- mask((ebm + sdm) / 2, ebm)

  out <- list(
    potential_all_x10000 = potential * 1e4,
    potential_agro_x10000 = ifel(agro == 1, potential, NA) * 1e4,
    demand_m2 = allocate_to_100m(one_km("demand_ha", year, box), agro, land) * 1e4,
    flow_all_kg = allocate_to_100m(one_km("flow_t", year, box), ebm, land) * 1e3,
    flow_agro_kg = allocate_to_100m(one_km("flow_t", year, box), agro, land) * 1e3,
    unmet_kg = allocate_to_100m(one_km("unmet_t", year, box), agro, land) * 1e3,
    flow_agro_eur2010 = allocate_to_100m(one_km("flow_meur2010", year, box), agro, land) * 1e6,
    unmet_eur2010 = allocate_to_100m(one_km("unmet_meur2010", year, box), agro, land) * 1e6
  )
  for (q in quantities) {
    r <- round(out[[q]])
    names(r) <- q
    is_potential <- grepl("^potential", q)
    target <- file.path(tile_dir, sprintf("%s_%s.tif", q, stem))
    tmp <- paste0(target, ".part.tif")
    writeRaster(r, tmp, overwrite = TRUE, datatype = if (is_potential) "INT2U" else "INT4U",
                NAflag = if (is_potential) 65535 else 4294967295, gdal = integer_options())
    file.rename(tmp, target)
  }
  tmpFiles(remove = TRUE, current = TRUE, orphan = FALSE)
  stem
}

for (year in run_years) {
  tile_dir <- file.path(out_dir, "tiles", year)
  dir.create(tile_dir, showWarnings = FALSE, recursive = TRUE)
  ebm_files <- list.files(file.path("refs/ebm_tiles/rebuilt", year), "^ebm_.*\\.tif$", full.names = TRUE)
  message(year, ": ", length(ebm_files), " tiles, ", format(Sys.time()))
  res <- mclapply(ebm_files, function(f) {
    tryCatch(run_tile(f, year, tile_dir), error = function(e) paste("ERROR", f, conditionMessage(e)))
  }, mc.cores = n_workers, mc.preschedule = FALSE)
  failed <- grep("^ERROR", unlist(res), value = TRUE)
  if (length(failed) > 0 || any(vapply(res, is.null, logical(1)))) {
    stop("Failed tiles, rerun to resume: ", paste(failed, collapse = "; "))
  }

  # One compressed GeoTIFF per quantity.
  for (q in quantities) {
    out <- file.path(out_dir, sprintf("pollination_%s_100m_%s.tif", q, year))
    if (file.exists(out)) next
    list_file <- tempfile(fileext = ".txt")
    writeLines(list.files(tile_dir, sprintf("^%s_[0-9_]+\\.tif$", q), full.names = TRUE), list_file)
    vrt <- tempfile(fileext = ".vrt")
    system2("gdalbuildvrt", c("-q", "-input_file_list", list_file, vrt))
    status <- system2("gdal_translate", c(
      "-q", "-co", "COMPRESS=DEFLATE", "-co", "PREDICTOR=2", "-co", "ZLEVEL=9", "-co", "TILED=YES",
      "-co", "BIGTIFF=YES", "-co", "NUM_THREADS=ALL_CPUS", vrt, shQuote(out)
    ))
    if (status != 0) stop("Could not write ", out)
  }
}
