# Value the physical accounts with the economic accounts for agriculture.
#
# Why    : this is the calculation on tables that follows the physical accounts, and it runs in seconds.
# Inputs : data/outputs/results/pollination_accounts_nuts3_crop_year.rds (script 11)
#          data/outputs/results/pollination_contribution_country_crop_year.rds (script 11)
#          data/inputs/eurostat/eaa_value_crop.rds and hicp_eu27.rds (script 08)
# Outputs: data/outputs/results/pollination_value_country_crop_year    which script 13 reads
#          data/outputs/results/pollination_value_nuts_crop_year
#          data/outputs/results/pollination_value_nuts_year
#          data/outputs/results/pollination_value_eu_series            each as rds and xlsx
#          data/outputs/results/pollination_monetary_results.xlsx      workbook by NUTS level
#          data/outputs/report/                                        small tables for the report
#          data/outputs/figures/pollination_value_country_2024.png
# Method : Value of the flow is production value times the pollination contribution, in prices of 2010.
#          The script stops if a check fails.
# Run    : source("scripts/12_build_monetary_accounts.R", encoding = "UTF-8"), from the project root.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_accounts.R", encoding = "UTF-8")
source("scripts/helpers_results.R", encoding = "UTF-8")

base_year <- 2010
regions <- read_regions()
crops <- read_crops()
combined <- readRDS("data/outputs/results/pollination_accounts_nuts3_crop_year.rds")
contribution <- readRDS("data/outputs/results/pollination_contribution_country_crop_year.rds")
eaa <- readRDS("data/inputs/eurostat/eaa_value_crop.rds") |> filter(!is.na(value_meur))
hicp <- readRDS("data/inputs/eurostat/hicp_eu27.rds")

deflator <- tibble(year = years_report) |>
  rowwise() |>
  mutate(
    # Each reporting year averages three years, each in the prices of the year before.
    price_level = mean(hicp$hicp_2015[hicp$year %in% ((year - 2):year)], na.rm = TRUE),
    deflator = hicp$hicp_2015[hicp$year == base_year] / price_level
  ) |>
  ungroup()

national_value <- contribution |>
  inner_join(eaa, by = c("geo", "crop", "year")) |>
  inner_join(deflator, by = "year") |>
  mutate(
    unmet_share = if_else(total_t > 0, unmet_t / total_t, 0),
    flow_meur = value_meur * coalesce(contribution, 0),
    unmet_meur = value_meur * unmet_share,
    flow_meur2010 = flow_meur * deflator,
    unmet_meur2010 = unmet_meur * deflator,
    eur_per_t = if_else(total_t > 0, value_meur * deflator * 1e6 / total_t, 0)
  )

unvalued <- eaa |>
  anti_join(filter(contribution, total_t > 0), by = c("geo", "crop", "year")) |>
  summarise(value = sum(value_meur, na.rm = TRUE))

all_flow <- sum(contribution$flow_t)
no_value <- contribution |>
  anti_join(eaa, by = c("geo", "crop", "year")) |>
  summarise(share = 100 * sum(flow_t) / all_flow)

monetary_series <- national_value |>
  group_by(year) |>
  summarise(
    `Dependent crops, value (M EUR 2010)` = sum(value_meur * deflator),
    `Value of flow (M EUR 2010)` = sum(flow_meur2010),
    `Value of unmet demand (M EUR 2010)` = sum(unmet_meur2010),
    `Value of flow (M EUR, prices of previous year)` = sum(flow_meur)
  ) |>
  rename(Year = year) |>
  mutate(Year = as.integer(Year))

# Regions receive the national value of each crop in proportion to their physical flow and unmet demand.
region_value <- combined |>
  inner_join(select(national_value, geo, crop, year, eur_per_t), by = c("geo", "crop", "year")) |>
  mutate(flow_meur2010 = flow_t * eur_per_t / 1e6, unmet_meur2010 = unmet_t * eur_per_t / 1e6)

nuts_value_crop <- to_nuts_levels(region_value, regions, by = c("crop", "year"), values = c("flow_meur2010", "unmet_meur2010"))
nuts_value <- to_nuts_levels(region_value, regions, by = "year", values = c("flow_meur2010", "unmet_meur2010"))

# Checks, which stop the script on failure.
levels_check <- nuts_value |>
  group_by(level, year) |>
  summarise(v = sum(flow_meur2010), .groups = "drop") |>
  pivot_wider(names_from = level, values_from = v)
ceiling_excess <- with(national_value, flow_meur - value_meur * dependency)
stopifnot(all(ceiling_excess <= 1e-6, na.rm = TRUE))
checks <- bind_rows(
  record_check(sum(region_value$flow_meur2010), sum(national_value$flow_meur2010), "Value of flow, regions against countries"),
  record_check(sum(region_value$unmet_meur2010), sum(national_value$unmet_meur2010), "Value of unmet demand, regions against countries"),
  record_check(levels_check$NUTS3, levels_check$NUTS0, "Value of flow by NUTS3 against NUTS0")
)

# Exports.
export_table(national_value, "pollination_value_country_crop_year")
export_table(nuts_value_crop, "pollination_value_nuts_crop_year")
export_table(nuts_value, "pollination_value_nuts_year")
export_table(monetary_series, "pollination_value_eu_series")

wb <- wb_workbook()
for (lv in c("NUTS0", "NUTS2", "NUTS3")) {
  wb <- write_results_sheet(
    wb, paste("Value", lv),
    title = paste("Value of the actual flow and of unmet demand by", lv, "region, million euro at constant 2010 prices"),
    note = "Values of 2024 use the crop area and yield of 2018. Croatia, Malta and Cyprus are estimates.",
    data = filter(nuts_value, level == lv),
    metrics = c(flow_meur2010 = "Actual flow", unmet_meur2010 = "Unmet demand")
  )
}
wb_save(wb, "data/outputs/results/pollination_monetary_results.xlsx", overwrite = TRUE)

# Small tables for the report.
save_report_table(checks, "checks_monetary")
save_report_table(monetary_series, "value_eu_series")
save_report_table(deflator, "deflators")
save_report_table(tibble(unvalued_meur = unvalued$value, no_value_share = no_value$share), "value_gaps")

value_by_crop <- national_value |>
  group_by(crop, year) |>
  summarise(value_meur = sum(value_meur), flow_meur = sum(flow_meur), value_meur2010 = sum(value_meur * deflator),
            flow_meur2010 = sum(flow_meur2010), unmet_meur2010 = sum(unmet_meur2010), .groups = "drop")
save_report_table(value_by_crop, "value_by_crop")

by_country <- national_value |>
  group_by(geo, year) |>
  summarise(flow_meur2010 = sum(flow_meur2010), unmet_meur2010 = sum(unmet_meur2010),
            value_meur2010 = sum(value_meur * deflator), .groups = "drop")
save_report_table(by_country, "value_by_country")

# Production value and contribution in 2006 against Vallecillo et al. (2018), Tables 4.4 and 4.5, EU row.
published_2006 <- tribble(
  ~crop, ~published_value, ~published_contribution,
  "APPL", 2240.58, 0.48, "OFRU", 5923.31, 0.30, "CITR", 3238.37, 0.02, "PULS", 883.62, 0.03, "OOIL", 155.10, 0.12,
  "RAPE", 4177.13, 0.17, "SOYA", 287.19, 0.16, "SUNF", 1584.96, 0.12, "TEXT", 1135.03, 0.04, "TOMA", 5928.34, 0.04
)
save_report_table(
  national_value |>
    filter(year == 2006) |>
    group_by(crop) |>
    summarise(value_meur = sum(value_meur), flow_meur = sum(flow_meur),
              contribution = sum(flow_t) / sum(total_t), .groups = "drop") |>
    left_join(published_2006, by = "crop"),
  "value_published_2006"
)

# Figure of the report. Bars are in constant prices, sorted by the value of the flow.
library(ggplot2)
figure_data <- by_country |>
  filter(year == 2024) |>
  mutate(geo = reorder(geo, flow_meur2010)) |>
  select(geo, `Actual flow` = flow_meur2010, `Unmet demand` = unmet_meur2010) |>
  pivot_longer(-geo, names_to = "measure", values_to = "meur")
figure <- ggplot(figure_data, aes(meur, geo, fill = measure)) +
  geom_col(position = position_dodge2(padding = 0.1, reverse = TRUE), width = 0.82) +
  scale_fill_manual(values = c(`Actual flow` = "#d97a3a", `Unmet demand` = "#6b7f99"), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.03)), labels = scales::label_comma()) +
  labs(x = "Million euro at constant 2010 prices, 2024", y = NULL) +
  theme_minimal(base_size = 10) +
  theme(panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(), legend.position = "top",
        legend.justification = "left")
dir.create("data/outputs/figures", showWarnings = FALSE, recursive = TRUE)
ggsave("data/outputs/figures/pollination_value_country_2024.png", figure, width = 7, height = 6.2, dpi = 200, bg = "white")
