# Download the Eurostat statistics used to anchor the physical and monetary flow.
#
# Why    : national statistics anchor the accounts, and these tables hold their production, value and prices.
# Sources: apro_cpsh1  crop production in EU standard humidity, thousand tonnes, and area in thousand hectares
#          aact_eaa02  economic accounts for agriculture, production value at basic price and at the
#                       prices of the previous year (n-1), million euro
#          prc_hicp_aind  harmonised index of consumer prices, EU27, annual average (2015 = 100)
# Outputs: data/inputs/eurostat/production_crop.rds  (geo, crop, year, production_t, area_ha)
#          data/inputs/eurostat/eaa_value_crop.rds   (geo, crop, year, value_meur)
#          data/inputs/eurostat/hicp_eu27.rds
# Method : Each reporting year is the mean of the three years centred on it, which avoids odd
#          fluctuations (2023 to 2025 for 2024). A code without any figure in the window is left missing,
#          and the crop total of a country sums the codes that have figures.
# Run    : source("scripts/08_download_eurostat.R", encoding = "UTF-8"), from the project root.
#          Needs internet access. The committed outputs are what scripts 11 and 12 read.

options(timeout = 1800)
library(eurostat)
library(dplyr)
library(tidyr)
library(readr)
source("scripts/helpers_pollination.R", encoding = "UTF-8")

out_dir <- "data/inputs/eurostat"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
eu27 <- read_csv("data/inputs/params/eu27_countries.csv", show_col_types = FALSE)$geo

# Eurostat crop codes that form each CAPRI crop group. Other fruits takes all fruit, berries and nuts
# without apples, pears, peaches and nectarines, and with strawberries.
production_codes <- tribble(
  ~crop,  ~code,        ~sign,
  "APPL", "F1110",      1,
  "APPL", "F1120",      1,
  "APPL", "F1210_1220", 1,
  "OFRU", "F0000",      1,
  "OFRU", "F1110",     -1,
  "OFRU", "F1120",     -1,
  "OFRU", "F1210_1220",-1,
  "OFRU", "S0000",      1,
  "RAPE", "I1110",      1,
  "SUNF", "I1120",      1,
  "SOYA", "I1130",      1,
  "OOIL", "I1140",      1,
  "OOIL", "I1150",      1,
  "OOIL", "I1190",      1,
  "PULS", "P0000",      1,
  "TEXT", "I2100",      1,
  "TEXT", "I2200",      1,
  "TOMA", "V3100",      1,
  "CITR", "T0000",      1
)

other_fruit_parts <- c("F1190", "F1230", "F1240", "F1250", "F1290", "F2000", "F3000", "F4000", "S0000")

windows <- tibble(year = years_report) |>
  rowwise() |>
  mutate(source_year = list((year - 1):(year + 1))) |>
  unnest(source_year)

window_mean <- function(data) {
  data |>
    inner_join(windows, by = "source_year", relationship = "many-to-many") |>
    group_by(geo, code, year) |>
    summarise(value = if (all(is.na(value))) NA_real_ else mean(value, na.rm = TRUE), .groups = "drop")
}

# Physical production and area ----------------------------------------------
apro <- get_eurostat("apro_cpsh1", time_format = "num", cache = FALSE) |>
  filter(geo %in% eu27)

national_crops <- function(indicator, multiplier, name) {
  raw <- apro |>
    filter(strucpro == indicator) |>
    transmute(geo, code = crops, source_year = as.integer(TIME_PERIOD), value = values)

  # Peaches and nectarines are reported together in recent years and separately in earlier years.
  peach_parts <- raw |>
    filter(code %in% c("F1210", "F1220")) |>
    group_by(geo, source_year) |>
    summarise(parts = if (all(is.na(value))) NA_real_ else sum(value, na.rm = TRUE), .groups = "drop")
  peach <- raw |>
    filter(code == "F1210_1220") |>
    full_join(peach_parts, by = c("geo", "source_year")) |>
    transmute(geo, code = "F1210_1220", source_year, value = coalesce(value, parts))

  means <- bind_rows(filter(raw, code != "F1210_1220"), peach) |>
    filter(code %in% c(production_codes$code, other_fruit_parts)) |>
    window_mean()

  groups <- means |>
    inner_join(production_codes, by = "code", relationship = "many-to-many") |>
    group_by(geo, crop, year) |>
    summarise(value = if (all(is.na(value))) NA_real_ else max(sum(sign * value, na.rm = TRUE), 0), .groups = "drop")

  # The total of fruits has gaps in some years, so other fruits takes the larger of the total minus
  # the named fruits and the sum of its parts.
  from_parts <- means |>
    filter(code %in% other_fruit_parts) |>
    group_by(geo, year) |>
    summarise(parts = if (all(is.na(value))) NA_real_ else sum(value, na.rm = TRUE), .groups = "drop") |>
    mutate(crop = "OFRU")

  groups |>
    full_join(from_parts, by = c("geo", "crop", "year")) |>
    mutate(value = pmax(value, parts, na.rm = TRUE)) |>
    transmute(geo, crop, year, !!name := value * multiplier)
}

production <- national_crops("HPRD_HUMD_EU_THS_T", 1000, "production_t") |>
  full_join(national_crops("AR_THS_HA", 1000, "area_ha"), by = c("geo", "crop", "year"))

saveRDS(production, file.path(out_dir, "production_crop.rds"))

# Production value ----------------------------------------------------------
items <- read_csv("data/inputs/params/crop_dependency.csv", show_col_types = FALSE) |>
  transmute(crop = capri_code, code = strsplit(eaa_items, ";")) |>
  unnest(code)

eaa <- get_eurostat("aact_eaa02", time_format = "num", cache = FALSE) |>
  filter(unit == "MIO_EUR", indic_agr == "PRD_BP", geo %in% eu27, am_item %in% items$code) |>
  transmute(geo, code = am_item, source_year = as.integer(TIME_PERIOD), value = values) |>
  window_mean() |>
  inner_join(items, by = "code") |>
  group_by(geo, crop, year) |>
  summarise(value_meur = if (all(is.na(value))) NA_real_ else sum(value, na.rm = TRUE), .groups = "drop")

saveRDS(eaa, file.path(out_dir, "eaa_value_crop.rds"))

# Price index ---------------------------------------------------------------
hicp <- get_eurostat("prc_hicp_aind", time_format = "num", cache = FALSE,
                     filters = list(geo = "EU27_2020", coicop = "CP00", unit = "INX_A_AVG")) |>
  rename(any_of(c(period = "TIME_PERIOD", period = "time"))) |>
  transmute(year = as.integer(period), hicp_2015 = values) |>
  arrange(year)
saveRDS(hicp, file.path(out_dir, "hicp_eu27.rds"))
