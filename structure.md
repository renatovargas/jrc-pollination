# Repository structure and conventions

This file describes how the repository is organised and which conventions the documents follow. The
rules in `AGENTS.md` still apply. This file only adds what those rules do not cover.

## Layout

```
.
├── AGENTS.md                 rules for authors
├── structure.md              this file
├── _quarto.yml               project, menu and format configuration
├── index.qmd                 home page, a short description of what the site is about
├── styles.css                site styles (almost empty)
├── assets/
│   └── apa-6th-edition.csl   citation style shared by all documents
├── documentation/
│   ├── index.qmd             list of the reports, one definition per report
│   └── methods/
│       └── <topic-name>/
│           ├── index.qmd     the report
│           └── <topic-name>.bib
├── downloads/
│   └── index.qmd             buttons to the results workbook and the 100 m maps, HTML only
├── scripts/
│   ├── run_all.R             runs the pipeline, or some of its stages, in order
│   ├── NN_<verb>_<object>.R  numbered scripts of the pipeline
│   ├── helpers_common.R      export and check functions
│   ├── helpers_pollination.R the model equations
│   ├── helpers_accounts.R    functions that turn 1 km inputs into accounts
│   ├── helpers_results.R     workbook layout
│   └── helpers_report.R      reads the small tables and formats them, for the report only
├── data/
│   ├── inputs/
│   │   ├── manifest_heavy_inputs.csv  heavy sources kept in refs/, with URL, DOI, size and md5
│   │   ├── params/           scores, dependency ratios and country list
│   │   ├── gis/              NUTS boundaries, as distributed and for the EU27, and the 1 km zone raster
│   │   ├── capri/            crop area and yield, 1 km
│   │   ├── climate/          activity index, 1 km
│   │   ├── sdm/              bumblebee model, 1 km
│   │   ├── ebm/              expert-based model, 1 km reduction of the 100 m run, as whole numbers
│   │   ├── eurostat/         production, production value and price index
│   │   ├── intermediate/     tables by region computed from the rasters (rds)
│   │   └── pilot_lu/         100 m inputs clipped to Luxembourg, to test the 100 m chain
│   └── outputs/
│       ├── results/          tables for later scripts (rds) and the results workbook (xlsx)
│       ├── report/           small tables that the scripts write for the report (rds)
│       └── figures/          figures that the scripts write for the report (png)
├── research/                 notes, not published
├── refs/                     downloads, reference files and maps, not versioned
│   ├── ebm_catalogue/        1 km reductions of the catalogue route, read by 07b
│   ├── maps_1km/             1 km maps (GeoTIFF), written by 13, read by 14 and 15
│   └── maps_100m/            100 m maps (GeoTIFF), written by 14, published outside the repository
└── docs/                     rendered site, generated, do not edit
```

## Reproducibility levels

The repository supports two levels. The first level needs only the repository. The stages `tables` and `maps_1km`
of `scripts/run_all.R` read the compact 1 km products in `data/inputs/`, rebuild every table and write the 1 km maps to
`refs/maps_1km/`. The report renders from the small tables with no further step. `data/inputs/pilot_lu/` lets
the 100 m model run for Luxembourg with no external download. The second level rebuilds the whole 100 m chain.
It downloads the sources in `data/inputs/manifest_heavy_inputs.csv` to `refs/` with the numbered scripts.

## Scripts

Scripts run in the order of their numbers, from the project root. `scripts/run_all.R` runs them by stage, namely `inputs`, `tables`, `maps_1km` and `maps_100m`, and with no stage named it runs `tables` and `maps_1km`. The preparation scripts skip outputs that already exist, and scripts 10 to 13 recompute everything each time.

All calculation is in the scripts, and the report reads their small tables and figures. After a change, rerun only what it affects, and then render:

| Change | Rerun |
|----|----|
| Text or formatting of the report | Only `quarto render` |
| Crop dependency or Eurostat data | `11`, `12`, `13` |
| The valuation | `12`, `13` |
| A raster input, or the threshold of the service area | `10`, `11`, `12`, `13` |
| Any of the above that changes the 1 km maps | Also `14` and `15`, for the 100 m maps |

| Script | Purpose |
|----|----|
| `01_prepare_nuts.R` | NUTS boundaries and the 1 km zone raster |
| `02_download_clc.R` | Corine accounting layers, version 21 |
| `03_prepare_catalogue.R` | Activity index, bumblebee model, catalogue land cover and distance |
| `04_prepare_capri.R` | Compact crop area and yield stacks |
| `05_prepare_roads.R` | Major roads rasterised at 100 m |
| `06_prepare_distance.R` | Distance to semi-natural areas at 100 m |
| `07_run_expert_model.R` | Expert-based model at 100 m, in tiles, with its 1 km reduction |
| `07b_compare_routes.R` | Comparison of the rebuilt and catalogue routes, run by hand |
| `08_download_eurostat.R` | Production, production value and price index |
| `09_write_manifest.R` | Manifest of the heavy inputs and the Luxembourg clips |
| `10_prepare_zone_tables.R` | Tables by region from the rasters, and small summaries of the layers |
| `11_build_physical_accounts.R` | Potential by region, demand, actual flow and unmet demand, with their checks |
| `12_build_monetary_accounts.R` | Value of the flow and of unmet demand, with their checks |
| `13_write_maps_1km.R` | 1 km maps, map figures, supply by ecosystem type and comparison of maps with tables |
| `14_write_maps_100m.R` | 100 m maps |
| `15_check_maps_100m.R` | Comparison of the 100 m maps with the 1 km maps |

## Menu

The site has three entries in the top bar, "Home", "Documents" and "Downloads". A new report needs its folder under
`documentation/methods/`, a line in the sidebar of `_quarto.yml` and a definition in
`documentation/index.qmd`.

## Report

The report is a narrative with no visible code, and it has these sections, in this order: Summary, Introduction, Methods,
Results, Limitations, Appendix, References and Annex I. Methods follows the logical order of the scripts, with substeps inside each, and it
explains why each decision was taken. Results follows the products. Only the report has a PDF version, which it declares
in its own `format`, so `_quarto.yml` sets HTML alone.

- Every step of the method links to the entry of its script in Annex I, written as `(see [05_prepare_roads.R in Annex I](#script-05))`.
- Annex I has one entry per file in `scripts/`, in the order in which they run. Each entry has the file name as its heading, a link to the file on GitHub and a short paragraph in plain English with no code. A change to a script updates its entry.
- The table of scripts in the Introduction is a markdown table, because its names link to Annex I in both HTML and PDF.
- Numbers in the text come from `data/outputs/report/` through inline code.
- Chunks only read a small table and show it, and their labels are lowercase words separated by hyphens.
- Callouts use `callout-note` for context and `callout-important` for anything that changes how the results should be read.
- The bibliography is one `.bib` file in the report folder, and the citation style is referenced as `../../../assets/apa-6th-edition.csl`.

## Data and file names

- Maps are named `pollination_<quantity>_<resolution>_<year>.tif` and tables `pollination_<quantity>_<dimensions>.rds`.
- The only Excel file is the results workbook, `pollination_results.xlsx`, and other tables are `.rds` only. CSV is kept only for short files edited or read by hand, namely the parameters, the region list and the manifest.
- The 1 km reductions of the expert-based model in `data/inputs/ebm/` are 16-bit whole numbers, each band multiplied by a factor. `read_ebm()` and `read_reduction()` return the original 32-bit values, so always read them through those functions, because a direct reading can tip a cell that sits on a threshold of potential.
- The 1 km maps are written as 32-bit floats with `COMPRESS=DEFLATE`, `PREDICTOR=3` and `TILED=YES`. The 100 m rasters are written as whole numbers in small units with `COMPRESS=DEFLATE`, `PREDICTOR=2` and `TILED=YES`, and the unit is part of the quantity name.
- All maps use EPSG:3035, on a grid aligned with the Corine grid.
- Country codes follow Eurostat (`EL` for Greece).
- Alternatives to the baseline go in their own subfolders, and every file name starts with the same label, such as `catalogue_`.

## Research notes

Notes in `research/` are plain markdown files with statements, each with its source, page and a verification
level (verified in text, inferred or verified online). They are not published.
