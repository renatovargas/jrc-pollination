# Prepare the NUTS boundaries and the 1 km zone raster used for the tables.
#
# Input  : refs/INCA-QGIS-Plugin/src/inca/data/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg
#          (Eurostat GISCO NUTS 2024, scale 1:1 million, EPSG:3035)
#          data/inputs/params/eu27_countries.csv
# Outputs: data/inputs/gis/nuts0_eu27.gpkg            country polygons, used as the EU27 mask
#          data/inputs/gis/nuts_regions.csv           NUTS0, NUTS2 and NUTS3 codes and names
#          data/inputs/gis/nuts3_id_1km.tif           NUTS3 number of each 1 km cell
#          data/inputs/gis/README_NUTS.txt            copyright notice to reproduce
# Method : A 1 km cell belongs to the NUTS3 region at its centre. Coastal and border cells whose centre
#          falls outside every region take the nearest region within 2 km, so that crop area on the coast
#          is not lost. Tables are built by summing cells, so NUTS3, NUTS2 and NUTS0 add up exactly.
# Run    : source("scripts/01_prepare_nuts.R", encoding = "UTF-8"), once, from the project root.

library(sf)
library(terra)
library(dplyr)
source("scripts/helpers_pollination.R", encoding = "UTF-8")

src <- "refs/INCA-QGIS-Plugin/src/inca/data/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg"
out_dir <- "data/inputs/gis"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
file.copy("refs/INCA-QGIS-Plugin/src/inca/data/README_NUTS.txt", file.path(out_dir, "README_NUTS.txt"), overwrite = TRUE)

eu27 <- readr::read_csv("data/inputs/params/eu27_countries.csv", show_col_types = FALSE)$geo
nuts <- st_read(src, layer = st_layers(src)$name[1], quiet = TRUE) |>
  filter(CNTR_CODE %in% eu27)

st_write(
  nuts |> filter(LEVL_CODE == 0) |> transmute(geo = NUTS_ID, name = NAME_LATN),
  file.path(out_dir, "nuts0_eu27.gpkg"), delete_dsn = TRUE, quiet = TRUE
)

template <- rast(analysis_extent, resolution = 1000, crs = "EPSG:3035")
n3 <- nuts |> filter(LEVL_CODE == 3) |> arrange(NUTS_ID) |> mutate(id = row_number())
ids <- rasterize(vect(n3), template, field = "id")

# Give cells just outside the coastline the value of the nearest region, up to 2 km away.
is_land_near <- focal(ids, w = 5, fun = "modal", na.rm = TRUE, na.policy = "only")
writeRaster(is_land_near, file.path(out_dir, "nuts3_id_1km.tif"), overwrite = TRUE, datatype = "INT2U",
            gdal = c("COMPRESS=DEFLATE", "ZLEVEL=9", "TILED=YES"))

regions <- nuts |>
  st_drop_geometry() |>
  filter(LEVL_CODE %in% c(0, 2, 3)) |>
  transmute(level = paste0("NUTS", LEVL_CODE), nuts_id = NUTS_ID, name = NAME_LATN, geo = CNTR_CODE) |>
  left_join(n3 |> st_drop_geometry() |> transmute(nuts_id = NUTS_ID, id), by = "nuts_id") |>
  arrange(level, nuts_id)
readr::write_csv(regions, file.path(out_dir, "nuts_regions.csv"))
