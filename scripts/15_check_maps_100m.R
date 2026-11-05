# Check the 100 m maps against the 1 km maps, reading both from disk.
#
# Why    : the 100 m maps are stored as whole numbers outside the repository, so this script records that
#          they still agree with the 1 km maps that the tables are based on.
# Inputs : refs/maps_100m/pollination_<quantity>_100m_<year>.tif (script 10)
#          refs/maps_1km/pollination_<quantity>_1km_<year>.tif (script 13)
# Outputs: data/outputs/results/check_maps_100m_totals.rds, with the total of every map at both resolutions.
#          Potential is an average, so its rows compare means.
#          data/outputs/results/check_maps_100m_cells.rds, with the comparison by 1 km cell.
# Method : Both comparisons read each map in blocks, one map at a time, so they need little memory. The
#          comparison by cell aggregates each 100 m map to the 1 km grid. Each 100 m cell is rounded to a
#          whole unit, so a 1 km cell can differ by at most 50 units because of rounding.
# Run    : source("scripts/15_check_maps_100m.R", encoding = "UTF-8"), from the project root, after script
#          14. Finished rows are kept, so a new run resumes. Set `cell_years` in the session for a subset of years.

source("scripts/helpers_pollination.R", encoding = "UTF-8")

cell_years <- if (exists("cell_years")) cell_years else years_report
work_dir <- "refs/maps_100m/check"
unlink(work_dir, recursive = TRUE)
dir.create(work_dir)
terraOptions(memfrac = 0.1, tempdir = work_dir, progress = 0)

# Each 100 m map, the 1 km map it comes from, and the number of 100 m units in one unit of the 1 km map.
pairs <- tibble::tribble(
  ~quantity,               ~one_km,           ~units, ~method,
  "potential_all_x10000",  "potential_all",   1e4,    "mean",
  "potential_agro_x10000", "potential_agro",  1e4,    "mean",
  "demand_m2",             "demand_ha",       1e4,    "sum",
  "flow_all_kg",           "flow_t",          1e3,    "sum",
  "flow_agro_kg",          "flow_t",          1e3,    "sum",
  "unmet_kg",              "unmet_t",         1e3,    "sum",
  "flow_agro_eur2010",     "flow_meur2010",   1e6,    "sum",
  "unmet_eur2010",         "unmet_meur2010",  1e6,    "sum"
)
file_100m <- function(job) sprintf("refs/maps_100m/pollination_%s_100m_%s.tif", job$quantity, job$year)
file_1km <- function(job) sprintf("refs/maps_1km/pollination_%s_1km_%s.tif", job$one_km, job$year)

#' Run `check` for each job not yet in `path`, adding each finished row to the file.
run_jobs <- function(jobs, path, check) {
  done <- if (file.exists(path)) readRDS(path) else NULL
  for (i in seq_len(nrow(jobs))) {
    job <- jobs[i, ]
    if (!is.null(done) && any(done$quantity == job$quantity & done$year == job$year)) next
    done <- bind_rows(done, check(job))
    saveRDS(done, path)
    message(format(Sys.time()), " ", job$quantity, " ", job$year)
  }
  arrange(done, quantity, year)
}

check_total <- function(job) {
  value_100m <- global(rast(file_100m(job)), job$method, na.rm = TRUE)[[1]] / job$units
  value_1km <- global(rast(file_1km(job)), job$method, na.rm = TRUE)[[1]]
  tibble::tibble(quantity = job$quantity, year = job$year, statistic = job$method, value_1km = value_1km,
                 value_100m = value_100m, relative_gap = (value_100m - value_1km) / value_1km)
}

check_cells <- function(job) {
  reference <- rast(file_1km(job))
  aggregated <- file.path(work_dir, sprintf("%s_%s.tif", job$quantity, job$year))
  from_100m <- aggregate(rast(file_100m(job)), fact = 10, fun = job$method, na.rm = TRUE, filename = aggregated,
                         overwrite = TRUE, wopt = list(datatype = "FLT8S"))
  values_100m <- values(extend(from_100m, reference), mat = FALSE) / job$units
  values_1km <- values(reference, mat = FALSE)
  rm(from_100m)
  file.remove(aggregated)

  both <- !is.na(values_100m) & !is.na(values_1km)
  gap <- abs(values_100m[both] - values_1km[both])
  limit <- if (job$method == "sum") 50 / job$units else NA_real_
  tibble::tibble(
    quantity = job$quantity, year = job$year,
    cells_compared = sum(both),
    largest_cell_gap = max(gap),
    rounding_limit = limit,
    cells_over_limit = if (is.na(limit)) NA_integer_ else sum(gap > limit * 1.001),
    value_without_100m_land = sum(values_1km[is.na(values_100m) & !is.na(values_1km)]),
    value_without_1km_map = sum(values_100m[!is.na(values_100m) & is.na(values_1km)])
  )
}

totals <- run_jobs(tidyr::crossing(pairs, year = years_report),
                   "data/outputs/results/check_maps_100m_totals.rds", check_total)
print(as.data.frame(totals), digits = 5)

cells <- run_jobs(tidyr::crossing(pairs, year = cell_years),
                  "data/outputs/results/check_maps_100m_cells.rds", check_cells)
print(as.data.frame(cells), digits = 5)

unlink(work_dir, recursive = TRUE)
