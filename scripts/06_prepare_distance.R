# Distance from every 100 m cell to the nearest semi-natural area, for the five reporting years.
#
# Why    : the score of a cell decays with its distance to natural habitat, and version 21 has no ready-made distance map.
# Input  : refs/clc_accounting/<year>/**/*.tif (Corine accounting layers, version 21, script 02)
#          Semi-natural classes follow Garibaldi et al. (2011): 311, 312, 313, 321, 322, 323, 324, 331, 333.
# Output : refs/distance/dist_seminatural_100m_<year>.tif. Euclidean distance in metres between cell
#          centres, up to 20 000 m, with no data beyond that. Too large to version, listed in the manifest.
# Run    : source("scripts/06_prepare_distance.R", encoding = "UTF-8"), once, from the project root.
#          Resumable. Needs GDAL 3.11 or later, and takes tens of minutes per year.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

scores <- read_scores()
targets <- paste(scores$clc[scores$seminatural == 1], collapse = ",")
out_dir <- "refs/distance"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
e <- as.vector(analysis_extent)

run_year <- function(year) {
  out <- file.path(out_dir, sprintf("dist_seminatural_100m_%s.tif", year))
  if (file.exists(out)) return(0L)
  clc <- list.files(file.path("refs/clc_accounting", year), pattern = "\\.tif$", recursive = TRUE, full.names = TRUE)
  stopifnot(length(clc) == 1)

  # Work on the analysis window only.
  window <- tempfile(fileext = ".vrt")
  system2("gdal_translate", c("-q", "-of", "VRT", "-projwin", e[["xmin"]], e[["ymax"]], e[["xmax"]], e[["ymin"]],
                              shQuote(clc), window))
  status <- system2("gdal", c(
    "raster", "proximity", "--overwrite", "--target-values", targets, "--distance-units", "geo",
    "--max-distance", "20000", "--output-data-type", "UInt16", "--nodata", "65535",
    "--creation-option", "COMPRESS=DEFLATE", "--creation-option", "TILED=YES", "--creation-option", "BIGTIFF=YES",
    window, shQuote(out)
  ))
  if (status != 0) stop("Proximity failed for ", year)
  status
}

# One process per year. Each uses little memory.
res <- parallel::mclapply(years_report, run_year, mc.cores = 3, mc.preschedule = FALSE)
print(unlist(res))
