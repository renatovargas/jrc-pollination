# Build the physical accounts: potential by region, demand, actual flow and unmet demand.
#
# Why    : this is the calculation on tables that follows the rasters, and it runs in seconds.
# Inputs : data/inputs/intermediate/capri_by_zone.rds and farmland_by_zone.rds (script 10)
#          data/inputs/eurostat/production_crop.rds (script 08)
#          data/inputs/params/crop_dependency.csv, data/inputs/gis/nuts_regions.csv
# Outputs: data/outputs/results/pollination_accounts_nuts3_crop_year   by NUTS3, crop and year
#          data/outputs/results/pollination_accounts_nuts_crop_year    by NUTS level, crop and year
#          data/outputs/results/pollination_accounts_nuts_year         by NUTS level and year
#          data/outputs/results/pollination_potential_nuts_year        hectares of high and medium potential
#          data/outputs/results/pollination_contribution_country_crop_year
#          data/outputs/results/pollination_eurostat_factors           scaling factors, which script 13 reads
#          data/outputs/results/pollination_eu_series                  each as rds and xlsx
#          data/outputs/results/pollination_physical_results.xlsx      workbook by NUTS level
#          data/outputs/report/                                        small tables for the report
# Method : The CAPRI pattern of each crop is scaled to Eurostat production. Production with no place on the
#          map is estimated from the farmland of each region. The script stops if a check fails.
# Run    : source("scripts/11_build_physical_accounts.R", encoding = "UTF-8"), from the project root.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_accounts.R", encoding = "UTF-8")
source("scripts/helpers_results.R", encoding = "UTF-8")

regions <- read_regions()
crops <- read_crops()
geo_of <- regions |> filter(level == "NUTS3") |> select(id, geo)
production <- readRDS("data/inputs/eurostat/production_crop.rds")
intermediate <- "data/inputs/intermediate"

# Land and farmland by class of potential.
farmland <- readRDS(file.path(intermediate, "farmland_by_zone.rds")) |>
  inner_join(geo_of, by = "id")

potential_nuts <- farmland |>
  filter(class %in% c("medium", "high")) |>
  group_by(id, year, class) |>
  summarise(across(c(land_ha, agro_ha), sum), .groups = "drop") |>
  pivot_wider(names_from = class, values_from = c(land_ha, agro_ha), values_fill = 0) |>
  to_nuts_levels(regions, by = "year", values = c("land_ha_medium", "land_ha_high", "agro_ha_medium", "agro_ha_high"))

# Crop area and production inside and outside the service area, scaled to Eurostat.
capri_zone <- readRDS(file.path(intermediate, "capri_by_zone.rds")) |>
  inner_join(geo_of, by = "id") |>
  inner_join(transmute(crops, crop = capri_code, dependency), by = "crop")

all_scaled <- scale_to_eurostat(capri_zone, select(production, geo, crop, year, production_t)) |>
  mutate(estimated = FALSE)

# A very large or very small factor means that the two sources disagree on the presence of the crop.
out_of_range <- function(k) k > 10 | k < 0.1
accounts <- filter(all_scaled, !out_of_range(factor))
factors <- capri_zone |>
  distinct(geo, crop, year) |>
  left_join(distinct(accounts, geo, crop, year, factor, eurostat_gap), by = c("geo", "crop", "year")) |>
  mutate(factor = coalesce(factor, 0), eurostat_gap = coalesce(eurostat_gap, FALSE))

# Production with no place on the map takes the estimate from the farmland of each region.
placed <- accounts |>
  group_by(geo, crop, year) |>
  summarise(capri_t = sum(production_t), .groups = "drop") |>
  filter(capri_t > 0)
missing <- production |>
  filter(production_t > 0) |>
  anti_join(placed, by = c("geo", "crop", "year")) |>
  inner_join(transmute(crops, crop = capri_code, dependency), by = "crop")
estimates <- estimate_without_map(missing, farmland) |>
  left_join(transmute(missing, geo, crop, year, national_area = area_ha), by = c("geo", "crop", "year")) |>
  group_by(geo, crop, year) |>
  mutate(
    area_ha = coalesce(national_area, 0) * total_t / sum(total_t),
    area_met_ha = if_else(total_t > 0, area_ha * flow_t / (total_t * dependency), 0)
  ) |>
  ungroup() |>
  select(-national_area)

combined <- bind_rows(
  accounts |> select(id, crop, year, geo, dependency, area_ha, area_met_ha, total_t, flow_t, unmet_t, estimated),
  estimates
) |>
  mutate(area_unmet_ha = area_ha - area_met_ha)

contribution <- combined |>
  group_by(geo, crop, year, dependency) |>
  summarise(
    total_t = sum(total_t), flow_t = sum(flow_t), unmet_t = sum(unmet_t),
    area_ha = sum(area_ha), area_met_ha = sum(area_met_ha),
    estimated = any(estimated), .groups = "drop"
  ) |>
  mutate(contribution = if_else(total_t > 0, flow_t / total_t, NA_real_))

eu_series <- contribution |>
  group_by(year) |>
  summarise(
    `Demand (Mha)` = sum(area_ha) / 1e6,
    `Met demand (%)` = 100 * sum(area_met_ha) / sum(area_ha),
    `Actual flow (Mt)` = sum(flow_t) / 1e6,
    `Unmet demand (Mt)` = sum(unmet_t) / 1e6,
    `Share of flow estimated (%)` = 100 * sum(flow_t[estimated]) / sum(flow_t)
  ) |>
  rename(Year = year) |>
  mutate(Year = as.integer(Year))

# The tables add up the NUTS3 values, so the three levels match exactly.
value_columns <- c("area_ha", "area_met_ha", "area_unmet_ha", "total_t", "flow_t", "unmet_t")
nuts_crop <- to_nuts_levels(combined, regions, by = c("crop", "year"), values = value_columns)
nuts_total <- to_nuts_levels(combined, regions, by = "year", values = value_columns)

# Checks, which stop the script on failure.
levels_check <- nuts_total |>
  group_by(level, year) |>
  summarise(flow_t = sum(flow_t), .groups = "drop") |>
  pivot_wider(names_from = level, values_from = flow_t)
identity_check <- combined |>
  summarise(left = sum(flow_t + unmet_t), right = sum(total_t * dependency))
anchor_check <- combined |>
  group_by(geo, crop, year) |>
  summarise(total_t = sum(total_t), .groups = "drop") |>
  inner_join(select(production, geo, crop, year, production_t), by = c("geo", "crop", "year")) |>
  filter(!is.na(production_t), production_t > 0)
checks <- bind_rows(
  record_check(levels_check$NUTS3, levels_check$NUTS0, "Flow by NUTS3 against NUTS0"),
  record_check(levels_check$NUTS2, levels_check$NUTS0, "Flow by NUTS2 against NUTS0"),
  record_check(identity_check$left, identity_check$right, "Flow plus unmet demand against dependent production"),
  record_check(anchor_check$total_t, anchor_check$production_t, "National production against Eurostat", tolerance = 1e-3)
)

# Exports.
export_table(combined, "pollination_accounts_nuts3_crop_year")
export_table(nuts_crop, "pollination_accounts_nuts_crop_year")
export_table(nuts_total, "pollination_accounts_nuts_year")
export_table(potential_nuts, "pollination_potential_nuts_year")
export_table(contribution, "pollination_contribution_country_crop_year")
export_table(factors, "pollination_eurostat_factors")
export_table(eu_series, "pollination_eu_series")

metrics <- list(
  Potential = list(data = potential_nuts, metrics = c(land_ha_high = "High potential (ha)", land_ha_medium = "Medium potential (ha)")),
  Demand = list(data = nuts_total, metrics = c(area_ha = "Demand (ha)", area_met_ha = "Met (ha)", area_unmet_ha = "Unmet (ha)")),
  Flow = list(data = nuts_total, metrics = c(flow_t = "Actual flow (t)", unmet_t = "Unmet demand (t)"))
)
wb <- wb_workbook()
for (table_name in names(metrics)) {
  for (lv in c("NUTS0", "NUTS2", "NUTS3")) {
    wb <- write_results_sheet(
      wb, paste(table_name, lv),
      title = paste(table_name, "by", lv, "region"),
      note = "Demand and flow of 2024 use the crop area and yield of 2018. Croatia, Malta and Cyprus are estimates.",
      data = filter(metrics[[table_name]]$data, level == lv),
      metrics = metrics[[table_name]]$metrics
    )
  }
}
wb_save(wb, "data/outputs/results/pollination_physical_results.xlsx", overwrite = TRUE)

# Small tables for the report.
save_report_table(checks, "checks_physical")
save_report_table(eu_series, "eu_series")

save_report_table(
  farmland |>
    group_by(year, class) |>
    summarise(land_mha = sum(land_ha) / 1e6, agro_mha = sum(agro_ha) / 1e6, .groups = "drop"),
  "potential_by_class"
)

# CAPRI against Eurostat, for the countries and crops that both report, before any scaling.
capri_national <- capri_zone |>
  group_by(geo, crop, year) |>
  summarise(capri_ha = sum(area_ha), capri_t = sum(production_t), .groups = "drop")
save_report_table(
  capri_national |>
    inner_join(select(production, geo, crop, year, area_ha, production_t), by = c("geo", "crop", "year")) |>
    group_by(crop, year) |>
    summarise(
      capri_ha = sum(capri_ha[!is.na(area_ha)]), eurostat_ha = sum(area_ha, na.rm = TRUE),
      capri_t = sum(capri_t[!is.na(production_t)]), eurostat_t = sum(production_t, na.rm = TRUE),
      .groups = "drop"
    ),
  "capri_against_eurostat"
)

# Cases where the sources disagree on the presence of the crop.
all_national <- all_scaled |>
  group_by(geo, crop, year, factor, eurostat_gap) |>
  summarise(capri_t = sum(production_t), eurostat_t = sum(total_t), .groups = "drop") |>
  filter(capri_t > 0)
save_report_table(
  all_national |>
    filter(out_of_range(factor)) |>
    select(geo, crop, year, factor, capri_t, eurostat_t),
  "factors_out_of_range"
)
save_report_table(
  all_national |>
    filter(eurostat_gap) |>
    select(geo, crop, year, capri_t),
  "no_eurostat_figure"
)

save_report_table(
  contribution |> group_by(year) |> summarise(total_t = sum(total_t), .groups = "drop"),
  "production_by_year"
)

# What the estimates hold, by group of countries.
save_report_table(
  combined |>
    filter(estimated) |>
    mutate(group = if_else(geo %in% no_crop_data, geo, "Other countries")) |>
    group_by(group, year) |>
    summarise(total_t = sum(total_t), flow_t = sum(flow_t), unmet_t = sum(unmet_t), area_ha = sum(area_ha), .groups = "drop"),
  "estimates_summary"
)

save_report_table(
  contribution |>
    group_by(crop, year) |>
    summarise(area_ha = sum(area_ha), area_met_ha = sum(area_met_ha), total_t = sum(total_t),
              flow_t = sum(flow_t), unmet_t = sum(unmet_t), .groups = "drop") |>
    mutate(contribution = flow_t / total_t),
  "eu_by_crop"
)

save_report_table(
  contribution |>
    group_by(geo, year) |>
    summarise(area_ha = sum(area_ha), area_met_ha = sum(area_met_ha), total_t = sum(total_t),
              flow_t = sum(flow_t), unmet_t = sum(unmet_t), estimated = any(estimated), .groups = "drop") |>
    left_join(filter(regions, level == "NUTS0") |> select(geo, name), by = "geo"),
  "by_country"
)

# Pollination contribution in 2006 against the values that Vallecillo et al. (2018) publish in Table 4.5.
published <- tribble(
  ~geo, ~APPL_published, ~RAPE_published,
  "DE", 0.57, 0.21, "ES", 0.26, 0.03, "FR", 0.29, 0.05, "IT", 0.13, 0.05, "PL", 0.59, 0.22, "RO", 0.47, 0.05
)
save_report_table(
  contribution |>
    filter(year == 2006, crop %in% c("APPL", "RAPE")) |>
    select(geo, crop, contribution) |>
    pivot_wider(names_from = crop, values_from = contribution, names_glue = "{crop}_here") |>
    inner_join(published, by = "geo"),
  "contribution_published"
)
