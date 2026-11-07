# Reduce the disaggregated CAPRI data to compact stacks of the ten pollinator-dependent crops.
#
# Why    : demand and production come from these layers, and the stacks let the tables run from the repository.
# Source : Koeble et al. (2024), EU Wide Disaggregated CAPRI Model Data, Zenodo,
#          https://doi.org/10.5281/zenodo.13992301, licence CC-BY 4.0, 1 km, EPSG:3035, 2000 to 2018.
#          The layers are read as cloud-optimised GeoTIFFs from the public STAC catalogue
#          (collection jrc_data_catalog), which holds the same variables for the reporting years.
# Outputs: data/inputs/capri/capri_area_ha_<year>.tif     one band per crop, hectares per 1 km cell
#          data/inputs/capri/capri_yield_kgha_<year>.tif  one band per crop, kilograms per hectare
# Run    : source("scripts/04_prepare_capri.R", encoding = "UTF-8"), once, from the project root.
#          Resumable. Needs internet access.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

base <- "/vsicurl/https://resources.integratedmodelling.org/aries-public-stac/jrc_data_catalog/"
folders <- c(area_ha = "agricultural_produce_area", yield_kgha = "agricultural_yield")
crops <- readr::read_csv("data/inputs/params/crop_dependency.csv", show_col_types = FALSE)$capri_code
template <- rast(analysis_extent, resolution = 1000, crs = "EPSG:3035")
out_dir <- "data/inputs/capri"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

for (param in names(folders)) {
  for (year in c(2000, 2006, 2012, 2018)) {
    out <- file.path(out_dir, sprintf("capri_%s_%s.tif", param, year))
    if (file.exists(out)) next
    layers <- lapply(crops, function(crop) {
      # The source grid has the same origin as the template, up to rounding noise in its header.
      r <- rast(sprintf("%s%s/%s_%s_cog.tif", base, folders[[param]], crop, year))
      ext(r) <- round(as.vector(ext(r)))
      r <- crop(extend(r, template), template)
      names(r) <- crop
      r
    })
    stack <- rast(layers)
    # Three significant decimals are well beyond the precision of the data, and compress far better.
    writeRaster(round(stack, 3), out, overwrite = TRUE, datatype = "FLT4S", gdal = raster_options)
  }
}
