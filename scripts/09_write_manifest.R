# List the heavy inputs kept in refs/, and clip the 100 m inputs to Luxembourg.
#
# Inputs : refs/ (scripts 02, 03, 05 and 06)
# Outputs: data/inputs/manifest_heavy_inputs.csv  file, source, DOI or address, size and md5
#          data/inputs/pilot_lu/<layer>_<year>.tif  Corine codes, distance and roads at 100 m, with
#          a margin of 1 km. They let the 100 m model run from the repository alone.
# Run    : source("scripts/09_write_manifest.R", encoding = "UTF-8"), from the project root.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

clc_uuid <- c(`2000` = "97eed728-309d-47cf-9411-7171be9842a9", `2006` = "bc5f6ad3-5dee-44b6-8fa2-0179ea43ddf0",
              `2012` = "d9533dc9-272b-4dac-9e98-83dfe8d1b32f", `2018` = "0f878901-6c51-41ae-b54d-52e794870e9c",
              `2024` = "a65428d3-bd66-4b47-bcf9-6bfd6fa5df0c")

source_of <- function(path) {
  year <- regmatches(path, regexpr("(?<=clc)[0-9]{4}(?=_v21)", path, perl = TRUE))
  if (length(year) == 1) return(paste0("https://doi.org/10.2909/", clc_uuid[[year]]))
  if (grepl("refs/catalogue/", path)) return("https://stac.integratedmodelling.org/collections/jrc_data_catalog")
  if (grepl("refs/capri/", path)) return("https://doi.org/10.5281/zenodo.13992301")
  if (grepl("refs/roads/", path)) return("OpenStreetMap, via scripts/05_prepare_roads.R")
  if (grepl("refs/distance/", path)) return("Derived with scripts/06_prepare_distance.R")
  NA_character_
}

files <- c(
  list.files("refs/clc_accounting", "\\.zip$", full.names = TRUE),
  list.files("refs/catalogue", "\\.tif$", full.names = TRUE),
  list.files("refs/capri", "\\.zip$", full.names = TRUE),
  "refs/roads/osm_main_roads_3035.gpkg", "refs/roads/osm_major_roads_100m.tif",
  list.files("refs/distance", "\\.tif$", full.names = TRUE)
)
files <- files[file.exists(files)]
manifest <- tibble(
  file = files,
  source = vapply(files, source_of, character(1)),
  size_mb = round(file.size(files) / 1e6, 1),
  md5 = unname(tools::md5sum(files))
)
readr::write_csv(manifest, "data/inputs/manifest_heavy_inputs.csv")

# Luxembourg clips ----------------------------------------------------------
out_dir <- "data/inputs/pilot_lu"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
lu <- vect("data/inputs/gis/nuts0_eu27.gpkg")
lu <- lu[lu$geo == "LU", ]
box <- align(ext(lu) + 1000, rast(ext(0, 1000, 0, 1000), resolution = 1000))
byte_options <- c("COMPRESS=DEFLATE", "ZLEVEL=9", "TILED=YES")

for (year in years_report) {
  clc_file <- list.files(file.path("refs/clc_accounting", year), pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  clc <- crop(rast(clc_file), box)
  levels(clc) <- NULL
  coltab(clc) <- NULL
  writeRaster(clc, sprintf("%s/clc_%s.tif", out_dir, year), overwrite = TRUE, datatype = "INT2S", gdal = byte_options)
  d <- crop(rast(sprintf("refs/distance/dist_seminatural_100m_%s.tif", year)), box)
  writeRaster(d, sprintf("%s/distance_%s.tif", out_dir, year), overwrite = TRUE, datatype = "INT2U", gdal = byte_options)
}
writeRaster(crop(rast("refs/roads/osm_major_roads_100m.tif"), box), file.path(out_dir, "roads.tif"),
            overwrite = TRUE, datatype = "INT1U", gdal = byte_options)
