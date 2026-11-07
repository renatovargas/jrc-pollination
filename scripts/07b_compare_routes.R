# Compare pollination potential from the rebuilt and the catalogue routes.
#
# Why    : the report chooses between two routes for land cover and distance, and this table is the evidence.
# Inputs : data/inputs/ebm/ebm_rebuilt_<year>_1km.tif (script 07, route "rebuilt")
#          refs/ebm_catalogue/ebm_catalogue_<year>_1km.tif (script 07, route "catalogue", not versioned)
#          data/inputs/sdm/bumblebee_sdm_1km.tif (script 03)
# Output : data/outputs/report/route_comparison.rds, one row per year.
# Method : Only 2000 and 2018 are compared. They are the first and last years that both routes hold, and they
#          are enough to measure the effect of the route.
# Run    : source("scripts/07b_compare_routes.R", encoding = "UTF-8"), from the project root. It stays out of
#          scripts/run_all.R, because no result depends on it and it needs the reductions in refs/.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_accounts.R", encoding = "UTF-8")

#' Million hectares of the 1 km cells in the service providing area of one route, each cell being 100 hectares.
service_area_mha <- function(potential) sum(potential >= spa_threshold) * 100 / 1e6

compare_year <- function(year) {
  rebuilt <- potential_1km(year)
  catalogue <- potential_1km(year, route = "catalogue")
  r <- values(rebuilt, mat = FALSE)
  k <- values(catalogue, mat = FALSE)
  both <- !is.na(r) & !is.na(k)
  class_r <- values(classify_potential(rebuilt), mat = FALSE)
  class_k <- values(classify_potential(catalogue), mat = FALSE)
  tibble(
    Year = as.integer(year),
    `Cells compared` = sum(both),
    Correlation = cor(r[both], k[both]),
    `Mean of rebuilt` = mean(r[both]),
    `Mean of catalogue` = mean(k[both]),
    `Largest absolute gap` = max(abs(r[both] - k[both])),
    `Service area, rebuilt (Mha)` = service_area_mha(r[both]),
    `Service area, catalogue (Mha)` = service_area_mha(k[both]),
    `Class differs (%)` = 100 * mean(class_r[both] != class_k[both])
  )
}

save_report_table(bind_rows(lapply(c(2000, 2018), compare_year)), "route_comparison")
clean_rasters()
