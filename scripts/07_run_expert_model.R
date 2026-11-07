# Expert-based pollination model at 100 m for the EU27, in tiles, with its 1 km reduction.
#
# Why    : this model is half of pollination potential, and the 1 km reductions carry it into the repository.
# Inputs : route "rebuilt"  : refs/clc_accounting/<year> (version 21), refs/distance (script 06)
#          route "catalogue": refs/catalogue/clc_<year>.tif and dist_<year>.tif (version 20, script 03)
#          both routes      : refs/roads/osm_major_roads_100m.tif (script 05)
#                             data/inputs/climate/activity_index_<year>_1km.tif (script 03)
#                             data/inputs/gis/nuts0_eu27.gpkg (script 01)
# Outputs: refs/ebm_tiles/<route>/<year>/ebm_<x>_<y>.tif   model at 100 m (not versioned)
#          data/inputs/ebm/ebm_rebuilt_<year>_1km.tif      reduction, stored as whole numbers (see ebm_factors in
#                                                          scripts/helpers_pollination.R), with these bands:
#            ebm             mean of the model over land cells
#            ebm_agro        mean of the model over agricultural cells
#            land_cells      number of 100 m land cells (0 to 100)
#            agro_cells      number of 100 m agricultural cells (0 to 100)
#          data/inputs/ebm/ebm_supply_rebuilt_<year>_1km.tif  one band per ecosystem type:
#            sum_<ecosystem> sum of the model over the cells of each ecosystem type
#          refs/ebm_catalogue/                             the same two reductions for the catalogue route (not versioned)
# Run    : source("scripts/07_run_expert_model.R", encoding = "UTF-8"), from the project root.
#          Runs the route "rebuilt". The route "catalogue" only serves the comparison of input routes in
#          script 07b, for 2000 and 2018. Set `routes` and `years_override` in the session to change this.
#          Resumable by tile.
#          Uses two forked workers by default, because each can reach 6 GB of memory. Set `workers` in the
#          session to change this.

source("scripts/helpers_pollination.R", encoding = "UTF-8")
library(parallel)

if (!exists("routes")) routes <- "rebuilt"
run_years <- if (exists("years_override")) years_override else years_report
n_workers <- if (exists("workers")) workers else 2
tile_cells <- 5000

scores <- read_scores()
ecosystems <- unique(scores$ecosystem)
scores$ecosystem_id <- match(scores$ecosystem, ecosystems)
eu_mask <- "data/inputs/gis/nuts0_eu27.gpkg"
reduction_dir <- function(route) if (route == "catalogue") "refs/ebm_catalogue" else "data/inputs/ebm"

find_clc <- function(route, year) {
  if (route == "catalogue") return(sprintf("refs/catalogue/clc_%s.tif", year))
  list.files(file.path("refs/clc_accounting", year), pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
}
find_dist <- function(route, year) {
  if (route == "catalogue") return(sprintf("refs/catalogue/dist_%s.tif", year))
  sprintf("refs/distance/dist_seminatural_100m_%s.tif", year)
}

# Tiles of 500 km aligned with the 1 km grid, kept only when they touch the EU27.
tile_grid <- function() {
  size <- tile_cells * 100
  xs <- seq(xmin(analysis_extent), xmax(analysis_extent) - 1, by = size)
  ys <- seq(ymin(analysis_extent), ymax(analysis_extent) - 1, by = size)
  grid <- expand.grid(x = xs, y = ys)
  grid$xmax <- pmin(grid$x + size, xmax(analysis_extent))
  grid$ymax <- pmin(grid$y + size, ymax(analysis_extent))
  eu <- vect(eu_mask)
  keep <- vapply(seq_len(nrow(grid)), function(i) {
    box <- ext(grid$x[i], grid$xmax[i], grid$y[i], grid$ymax[i])
    length(crop(eu, box)) > 0
  }, logical(1))
  grid[keep, ]
}

run_tile <- function(tile, route, year, tile_dir) {
  stem <- sprintf("%d_%d", tile$x, tile$y)
  f100 <- file.path(tile_dir, sprintf("ebm_%s.tif", stem))
  f1 <- file.path(tile_dir, sprintf("r1km_%s.tif", stem))
  if (file.exists(f100) && file.exists(f1)) return(stem)
  terraOptions(memfrac = 0.1, tempdir = tile_dir, progress = 0)

  box <- ext(tile$x, tile$xmax, tile$y, tile$ymax)
  # The margin of one or two cells stays inside the analysis window, where every layer has data.
  margin <- terra::intersect(box + 200, analysis_extent)
  clc <- crop(rast(find_clc(route, year)), margin)
  levels(clc) <- NULL
  coltab(clc) <- NULL
  roads <- crop(rast("refs/roads/osm_major_roads_100m.tif"), clc)
  distance <- crop(rast(find_dist(route, year)), clc)
  ai <- resample(rast(sprintf("data/inputs/climate/activity_index_%s_1km.tif", year)), clc, method = "bilinear")

  ebm <- crop(expert_model(clc, roads, distance, ai, scores), box)
  eu <- crop(vect(eu_mask), box)
  ebm <- mask(ebm, rasterize(eu, ebm, field = 1, touches = TRUE))
  names(ebm) <- "ebm"
  clc <- crop(clc, box)

  land <- ifel(is.na(ebm), NA, 1)
  agro <- mask(reclass_clc(clc, scores, "agro"), land)
  eco <- mask(reclass_clc(clc, scores, "ecosystem_id"), land)
  by_eco <- lapply(seq_along(ecosystems), function(i) {
    aggregate(ifel(eco == i, ebm, 0), fact = 10, fun = "sum", na.rm = TRUE)
  })
  r1 <- c(
    aggregate(ebm, fact = 10, fun = "mean", na.rm = TRUE),
    aggregate(ifel(agro == 1, ebm, NA), fact = 10, fun = "mean", na.rm = TRUE),
    aggregate(land, fact = 10, fun = "sum", na.rm = TRUE),
    aggregate(ifel(agro == 1, 1, NA), fact = 10, fun = "sum", na.rm = TRUE),
    rast(by_eco)
  )
  names(r1) <- c("ebm", "ebm_agro", "land_cells", "agro_cells", paste0("sum_", make.names(ecosystems)))

  # Write under a temporary name, so an interrupted run never leaves a partial tile to resume from.
  for (pair in list(list(ebm, f100), list(r1, f1))) {
    tmp <- paste0(pair[[2]], ".part.tif")
    writeRaster(pair[[1]], tmp, overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
    file.rename(tmp, pair[[2]])
  }
  tmpFiles(remove = TRUE, current = TRUE, orphan = FALSE)
  stem
}

tiles <- tile_grid()
pending <- expand.grid(route = routes, year = run_years, stringsAsFactors = FALSE)
pending <- pending[pending$route == "rebuilt" | pending$year %in% c(2000, 2018), ]

# All tiles run first. Workers forked after the parent has written a mosaic can hang, so mosaics come last.
for (k in seq_len(nrow(pending))) {
  route <- pending$route[k]
  year <- pending$year[k]
  tile_dir <- file.path("refs/ebm_tiles", route, year)
  dir.create(tile_dir, showWarnings = FALSE, recursive = TRUE)
  message(route, " ", year, ": ", nrow(tiles), " tiles, ", format(Sys.time()))
  res <- mclapply(seq_len(nrow(tiles)), function(i) {
    tryCatch(run_tile(tiles[i, ], route, year, tile_dir), error = function(e) paste("ERROR", i, conditionMessage(e)))
  }, mc.cores = n_workers, mc.preschedule = FALSE)
  failed <- grep("^ERROR", unlist(res), value = TRUE)
  if (length(failed) > 0 || any(vapply(res, is.null, logical(1)))) {
    stop("Failed tiles, rerun to resume: ", paste(failed, collapse = "; "))
  }
}

# Mosaics of the 1 km reductions, as whole numbers, whose precision is well beyond that of the model.
template <- rast(analysis_extent, resolution = 1000, crs = "EPSG:3035")
for (k in seq_len(nrow(pending))) {
  route <- pending$route[k]
  year <- pending$year[k]
  out_1km <- reduction_dir(route)
  dir.create(out_1km, showWarnings = FALSE, recursive = TRUE)
  main_file <- file.path(out_1km, sprintf("ebm_%s_%s_1km.tif", route, year))
  supply_file <- file.path(out_1km, sprintf("ebm_supply_%s_%s_1km.tif", route, year))
  if (file.exists(main_file) && file.exists(supply_file)) next
  tile_dir <- file.path("refs/ebm_tiles", route, year)
  parts <- list.files(tile_dir, "^r1km_[0-9_]+\\.tif$", full.names = TRUE)
  m <- crop(extend(merge(sprc(parts)), template), template)
  main <- c("ebm", "ebm_agro", "land_cells", "agro_cells")
  write_scaled(m[[main]], main_file, ebm_factors[main])
  supply <- m[[setdiff(names(m), main)]]
  write_scaled(supply, supply_file, rep(ebm_supply_factor, nlyr(supply)))
}
