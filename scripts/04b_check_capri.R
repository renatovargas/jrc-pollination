# Compare the compact crop stacks with the original CAPRI archives on Zenodo.
#
# Inputs : refs/capri/fsucroparea_ha.zip and fsucropyield_kgperha.zip (https://doi.org/10.5281/zenodo.13992301)
#          data/inputs/capri/capri_<param>_<year>.tif (script 04)
# Output : data/inputs/capri/capri_check_against_archive.rds, one row per crop, year and variable, with
#          the totals of both sources and the largest absolute difference in a cell
# Run    : source("scripts/04b_check_capri.R", encoding = "UTF-8"), once, after both archives are in refs/.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

crops <- readr::read_csv("data/inputs/params/crop_dependency.csv", show_col_types = FALSE)$capri_code
zips <- c(area_ha = "refs/capri/fsucroparea_ha.zip", yield_kgha = "refs/capri/fsucropyield_kgperha.zip")

rows <- list()
for (param in names(zips)) {
  listing <- unzip(zips[[param]], list = TRUE)$Name
  for (year in c(2000, 2006, 2012, 2018)) {
    stack <- rast(sprintf("data/inputs/capri/capri_%s_%s.tif", param, year))
    for (crop_code in crops) {
      member <- grep(sprintf("%s_%s[^/]*\\.tif$", crop_code, year), listing, value = TRUE)
      if (length(member) != 1) stop("Expected one file for ", crop_code, " ", year)
      a <- rast(sprintf("/vsizip/%s/%s", zips[[param]], member))
      a <- crop(extend(a, stack), stack)
      gap <- abs(a - stack[[crop_code]])
      rows[[length(rows) + 1]] <- tibble(
        param, year, crop = crop_code,
        archive_sum = global(a, "sum", na.rm = TRUE)[[1]],
        stack_sum = global(stack[[crop_code]], "sum", na.rm = TRUE)[[1]],
        max_gap = global(gap, "max", na.rm = TRUE)[[1]]
      )
    }
  }
}
saveRDS(bind_rows(rows), "data/inputs/capri/capri_check_against_archive.rds")
