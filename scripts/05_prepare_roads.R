# Download the OpenStreetMap major roads and rasterise them on the 100 m Corine grid.
#
# Source : OpenStreetMap contributors (Open Database Licence), main road extract published by the
#          k.LAB geoserver as layer im-data-global-infrastructure:osm_main_roads_laea_4326, with the
#          attribute `highway`. Motorway, trunk and primary roads and their links correspond to the
#          major road categories 0, 1 and 2 of the road network named in the method.
# Output : refs/roads/osm_main_roads_3035.gpkg (vector, EPSG:3035)
#          refs/roads/osm_major_roads_100m.tif (1 on a major road, 0 elsewhere, 100 m, Corine grid)
# Run    : source("scripts/05_prepare_roads.R", encoding = "UTF-8"), once, from the project root.
#          Resumable. Pages already downloaded are kept. Needs internet access.

library(terra)

out_dir <- "refs/roads"
page_dir <- file.path(out_dir, "pages")
dir.create(page_dir, showWarnings = FALSE, recursive = TRUE)

wfs <- "https://integration.integratedmodelling.org/geoserver/im-data-global-infrastructure/ows"
layer <- "im-data-global-infrastructure:osm_main_roads_laea_4326"
n_features <- 2421954
page_size <- 100000
major <- c("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link")

# Download the road network in pages, several at a time. A stable sort key keeps the pages from overlapping,
# and the server compresses each response.
download_page <- function(start) {
  page <- file.path(page_dir, sprintf("page_%08d.geojson.gz", start))
  if (file.exists(page)) return(0L)
  url <- sprintf(
    "%s?service=WFS&version=2.0.0&request=GetFeature&typeNames=%s&outputFormat=application/json&srsName=EPSG:4326&sortBy=__gid&count=%d&startIndex=%d",
    wfs, layer, page_size, start
  )
  tmp <- paste0(page, ".tmp")
  status <- system2("curl", c("-s", "--retry", "5", "--max-time", "1800", "-H", shQuote("Accept-Encoding: gzip"),
                              "-o", shQuote(tmp), shQuote(url)))
  if (status == 0) file.rename(tmp, page)
  status
}
status <- parallel::mclapply(seq(0, n_features - 1, by = page_size), download_page, mc.cores = 5, mc.preschedule = FALSE)
if (any(unlist(status) != 0)) stop("Some pages failed. Run the script again to resume.")

# Keep the major road classes and project them to the Corine reference system.
gpkg <- file.path(out_dir, "osm_main_roads_3035.gpkg")
if (!file.exists(gpkg)) {
  where <- sprintf("highway IN (%s)", paste(sprintf("'%s'", major), collapse = ","))
  for (page in list.files(page_dir, pattern = "geojson\\.gz$", full.names = TRUE)) {
    status <- system2("ogr2ogr", c(
      "-f", "GPKG", if (file.exists(gpkg)) c("-update", "-append"), "-nln", "roads", "-t_srs", "EPSG:3035",
      "-where", shQuote(where), "-nlt", "MULTILINESTRING",
      shQuote(gpkg), shQuote(paste0("/vsigzip/", page))
    ))
    if (status != 0) stop("Could not add ", page)
  }
}

# Rasterise on the Corine grid. A cell is a road cell when the road touches it.
road_tif <- file.path(out_dir, "osm_major_roads_100m.tif")
if (!file.exists(road_tif)) {
  system2("gdal_rasterize", c(
    "-burn", "1", "-init", "0", "-at", "-a_nodata", "255", "-ot", "Byte", "-tr", "100", "100",
    "-te", "900000", "900000", "7400000", "5500000", "-l", "roads",
    "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES", "-co", "BIGTIFF=YES", "-co", "NBITS=1",
    shQuote(gpkg), shQuote(road_tif)
  ))
}
