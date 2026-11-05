# Download the Corine Land Cover accounting layers, version 21, for the five reporting years.
#
# Source : European Environment Agency, Corine Land Cover (raster 100 m) version 21 accounting layer,
#          September 2026, EPSG:3035, one record per reference year (identifiers in `records` below).
#          The DOI of each layer is 10.2909/<identifier>.
# Output : refs/clc_accounting/clc<year>_v21.zip and the GeoTIFF inside it, in refs/clc_accounting/<year>/.
#          The files are too large to version. data/inputs/manifest_heavy_inputs.csv lists them.
# Run    : source("scripts/02_download_clc.R", encoding = "UTF-8"), once, from the project root.
#          Resumable. Years whose raster is already unpacked are skipped. Needs internet access and
#          about 15 GB of disk space.

options(timeout = 7200)

records <- c(
  `2000` = "97eed728-309d-47cf-9411-7171be9842a9",
  `2006` = "bc5f6ad3-5dee-44b6-8fa2-0179ea43ddf0",
  `2012` = "d9533dc9-272b-4dac-9e98-83dfe8d1b32f",
  `2018` = "0f878901-6c51-41ae-b54d-52e794870e9c",
  `2024` = "a65428d3-bd66-4b47-bcf9-6bfd6fa5df0c"
)
out_dir <- "refs/clc_accounting"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# The record page points to a public share whose address ends in /download.
share_link <- function(uuid) {
  page <- paste(readLines(paste0("https://sdi.eea.europa.eu/data/", uuid), warn = FALSE), collapse = " ")
  regmatches(page, regexpr("https://sdi\\.eea\\.europa\\.eu/datashare/s/[A-Za-z0-9]+/download", page))
}

for (year in names(records)) {
  year_dir <- file.path(out_dir, year)
  if (length(list.files(year_dir, pattern = "\\.tif$", recursive = TRUE)) > 0) next

  zip_file <- file.path(out_dir, sprintf("clc%s_v21.zip", year))
  if (!file.exists(zip_file)) {
    status <- system2("curl", c("-sL", "--retry", "5", "-o", shQuote(zip_file), shQuote(share_link(records[[year]]))))
    if (status != 0) stop("Download failed for ", year)
  }
  dir.create(year_dir, showWarnings = FALSE)
  # The share wraps the layer in a zip, sometimes with a second zip inside it.
  unzip(zip_file, exdir = year_dir)
  for (inner in list.files(year_dir, pattern = "\\.zip$", recursive = TRUE, full.names = TRUE)) {
    unzip(inner, exdir = dirname(inner))
  }
}
