# Run the pipeline, or some of its stages, in order.
#
# Stages : inputs    scripts 01 to 09. Needs internet access and the files in refs/, and takes many hours.
#          tables    scripts 10 to 12. Takes about five minutes.
#          maps_1km  script 13. Takes about ten minutes.
#          maps_100m scripts 14 and 15. Needs the files in refs/, and takes about two hours.
# Run    : from the project root, with the stages to run. With no stage named, it runs tables and maps_1km,
#          which need only the repository.
#            Rscript scripts/run_all.R
#            Rscript scripts/run_all.R tables
#            Rscript scripts/run_all.R inputs tables maps_1km maps_100m
#          The report is rendered afterwards with `quarto render`.
#
# Script 07b stays out of the pipeline on purpose. It is a one-off comparison that needs files in refs/ which no
# result depends on, and the report reads the small table it saved.

pipeline <- list(
  inputs = c("01_prepare_nuts", "02_download_clc", "03_prepare_catalogue", "04_prepare_capri", "05_prepare_roads",
             "06_prepare_distance", "07_run_expert_model", "08_download_eurostat", "09_write_manifest"),
  tables = c("10_prepare_zone_tables", "11_build_physical_accounts", "12_build_monetary_accounts"),
  maps_1km = "13_write_maps_1km",
  maps_100m = c("14_write_maps_100m", "15_check_maps_100m")
)

requested <- commandArgs(trailingOnly = TRUE)
if (length(requested) == 0) requested <- c("tables", "maps_1km")
unknown <- setdiff(requested, names(pipeline))
if (length(unknown) > 0) stop("Unknown stage: ", paste(unknown, collapse = ", "))

# Stages always run in the order of the pipeline, each script in its own environment.
for (stage in intersect(names(pipeline), requested)) {
  for (script in pipeline[[stage]]) {
    message("== ", script, ", ", format(Sys.time()))
    source(sprintf("scripts/%s.R", script), encoding = "UTF-8", local = new.env())
  }
}
