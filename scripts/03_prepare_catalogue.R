# Prepare the climate and bumblebee layers, and fetch the harmonised catalogue land cover layers.
#
# Why    : the activity index and the bumblebee model enter potential, and the catalogue offers both on public grids.
# Source : Public STAC catalogue of the k.LAB implementation of this service,
#          https://stac.integratedmodelling.org/collections/jrc_data_catalog
#          Air temperature: ERA5 monthly means of 2 m temperature, 3-year means, 0.25 degrees, in 0.1 K.
#          Solar radiation: Copernicus climate and energy indicators, surface downwelling shortwave
#          radiation, 3-year means, expressed over day length, 0.25 degrees, in 0.01 W per square metre.
#          Bumblebees: aggregated species distribution model (Polce et al., 2018), 10 km.
#          Land cover and distance: Corine accounting layers version 20 and the distance to semi-natural
#          areas derived from them, 100 m, for 2000 and 2018.
# Outputs: data/inputs/climate/activity_index_<year>_1km.tif  growing season activity index in percent
#          data/inputs/sdm/bumblebee_sdm_1km.tif              probability of occurrence, 0 to 1
#          refs/catalogue/clc_<year>.tif, refs/catalogue/dist_<year>.tif (not versioned, on request, see below)
# Run    : source("scripts/03_prepare_catalogue.R", encoding = "UTF-8"), once, from the project root.
#          Resumable. Needs internet access.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

base <- "https://resources.integratedmodelling.org/aries-public-stac/jrc_data_catalog/"
months <- c("April", "May", "June", "July", "August", "September")
template <- rast(analysis_extent, resolution = 1000, crs = "EPSG:3035")
for (d in c("data/inputs/climate", "data/inputs/sdm", "refs/catalogue")) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# Activity index. Each month is computed on the climate grid and limited to 0 to 100 before averaging.
for (year in years_report) {
  out <- sprintf("data/inputs/climate/activity_index_%s_1km.tif", year)
  if (file.exists(out)) next
  win <- climate_window[[as.character(year)]]
  monthly <- rast(lapply(months, function(m) {
    # The temperature files of 2011-2013 use short month names.
    label <- if (win == "2011-2013") c(April = "Apr", May = "Mai", June = "Jun", July = "Jul", August = "Aug", September = "Sep")[[m]] else m
    temperature <- rast(sprintf("/vsicurl/%sair_temp/t2m_%s_%s_cog.tif", base, win, label)) * 0.1 - 273.15
    radiation <- rast(sprintf("/vsicurl/%ssolar_radiation/ssrd_%s_%s_cog.tif", base, win, m)) * 0.01
    activity_index(temperature, radiation)
  }))
  # Keep the land and a 5 km margin. The rest of the grid is never read and only costs disk space.
  ai <- round(project(mean(monthly), template, method = "bilinear"), 2)
  ai <- mask(ai, buffer(vect("data/inputs/gis/nuts0_eu27.gpkg"), 5000))
  names(ai) <- "activity_index"
  writeRaster(ai, out, overwrite = TRUE, datatype = "FLT4S", gdal = raster_options)
}

# Bumblebee model, bilinear from 10 km to 1 km. Land cells left without a value along the coast
# take the mean of their neighbours, in two passes of up to 10 km.
out <- "data/inputs/sdm/bumblebee_sdm_1km.tif"
if (!file.exists(out)) {
  sdm <- rast(paste0("/vsicurl/", base, "bumblebee_species_distribution/bumblebee_composite_richness_eu_cog.tif"))
  sdm <- project(sdm, template, method = "bilinear")
  for (pass in 1:2) sdm <- focal(sdm, w = 21, fun = "mean", na.rm = TRUE, na.policy = "only")
  names(sdm) <- "bumblebee_sdm"
  writeRaster(sdm, out, overwrite = TRUE, datatype = "FLT4S", gdal = raster_options)
}

# Land cover and distance layers of the catalogue, only for the comparison of input routes in script 07b.
# Set `routes` to include "catalogue" to fetch them.
# The first and last years with both versions of the layers are enough to measure the effect.
for (year in if (exists("routes") && "catalogue" %in% routes) c(2000, 2018)) {
  pairs <- c(
    setNames(sprintf("%scorine_landcover_accounts/CLC%sACC_V2018_20_cog.tif", base, year), sprintf("refs/catalogue/clc_%s.tif", year)),
    setNames(sprintf("%sdist_to_semi_natural_area/seminatural_%s_cog.tif", base, year), sprintf("refs/catalogue/dist_%s.tif", year))
  )
  for (f in names(pairs)) {
    if (!file.exists(f)) system2("curl", c("-sL", "--retry", "5", "-o", shQuote(f), shQuote(pairs[[f]])))
  }
}
