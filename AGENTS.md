## Rules

- **Structure:** the layout of the repository, the menu and the naming conventions are described in `structure.md`, at the same level as this file. Read it before creating or moving files.
- **Pipeline and report:** The calculations live in the numbered scripts in `scripts/`, which run in order from `scripts/run_all.R` or one by one. The report in `documentation/methods/crop-pollination/index.qmd` is a narrative with no visible code. It weaves the formal method, with formulas and citations, the processing steps of each script, the findings that prompted each decision, the results and their limits. A footnote points to the script behind each step.
- **Method authority:** the source of truth is the technical report in `refs/manual/recreation_and_pollination_accounts_final_pubsy.pdf` (Vallecillo et al., 2018). Where it is silent or inconsistent, record the decision and its reason in `research/method-decisions.md` and in the document.
- **Language:** all calculation is in R, calling GDAL from R where `terra` is too slow for the 100 m grid. Never create auxiliary Python tools. Do not use `renv`.
- **Paths in R code:** `execute-dir: project`, so paths are relative to the project root wherever the `.qmd` lives. Never use `here::here()`.
- **Links and images in text:** resolved relative to the `.qmd`.
- **Tables:** with `flextable`, never `gt()`. The report renders to HTML and PDF, so tables must work in both. The Downloads page is HTML only, and it uses a markdown table with buttons.
- **Data:** `data/` (inputs in `data/inputs/`) and `data/outputs/` (exported results in `results/`, small tables for the report in `report/`, figures in `figures/`). Maps stay out of the repository, in `refs/maps_1km/` and `refs/maps_100m/`.
- **Scripts:** short, readable steps. Helper functions in `scripts/helpers_*.R`. Each script states why it exists, its inputs, outputs and how to run it, and it exports its results (rds and xlsx) to `data/outputs/results/`. Checks live in the scripts, which stop when one fails and record the result for the report. Use rds for tables that code reads, and keep CSV only for short files edited or read by hand.
- **Lean report:** the report does no calculation beyond formatting. It reads the small tables that the scripts write to `data/outputs/report/` and the figures in `data/outputs/figures/`. A new table or figure means adding its small dataset to the script that owns the step.
- **Numbers in the text:** every result quoted in the report comes from those small tables through inline code, so that the text follows the data. Sentences that interpret a number are reread after any change to the results.
- **Decisions:** each decision in the report gives its true reason. If a finding prompted it, the report shows the finding. If a source was unavailable or proprietary, it says so.
- **Scope of the text:** the documents present the results of an analysis, and they cite only public sources.
- **Rendering:** `docs/` is generated output, and a full `quarto render` replaces it. `quarto render --to html` also removes the PDFs, so a full render comes last before a commit. Do not render the project unless asked.
- **File size (GitHub):** never add large files to the repository. `data/` only contains compact data files (`.rds`, `.csv`, `.xlsx`, `.parquet`, plus compact GIS products such as small `.tif` and `.gpkg`) under 50 MB each. Never version official PDFs, zips or bulk downloads.
- **Downloads:** everything downloaded from the internet (PDFs, reports, heavy datasets) goes to `refs/` (already in `.gitignore`). Research that must stay available is summarised in `.md` files in `research/`, with source, page and verification level, never by copying the PDF. If a note needs a datum from a PDF, extract it to a small file in `data/inputs/`.
- **Heavy inputs:** when a source is too large for the repository, keep the original in `refs/`, list it in `data/inputs/manifest_heavy_inputs.csv` (URL, DOI, size and md5), and reduce it with a numbered script in `scripts/` that writes a compact product to `data/inputs/`. The stages `tables` and `maps_1km` of `scripts/run_all.R` read only the compact products, so they run without the heavy sources in `refs/`, and the report renders from the repository alone.
- **Encoding (UTF-8):** all text files are UTF-8. To edit `.qmd`, `.R`, `.md` and `.bib` files with accents, always use the `edit` (or `write`) tool, which preserves encoding. If `perl` or `sed` is needed in the shell, use `perl -CSDA -Mutf8 -0pi -e ...`. After any shell edit, verify with `iconv -f UTF-8 -t UTF-8 file >/dev/null && echo ok`. In R, read and write with `encoding = "UTF-8"`.

## Earlier work and reference code

- The k.LAB implementation of this service and the INCA plugin are cited as sources of orientation. State what was taken from them.
- When the method here differs from either, describe the choice made here and its reason.
- The results here come from the routine in this repository.

## Input routes

- Steps with a choice of input describe both routes, "using the harmonised catalogue layer" and "rebuilding from primary sources", and show a comparison table. The comparison of the two routes was run once and its result is kept in `data/outputs/report/route_comparison.rds`, so the pipeline does not repeat it.
- The baseline is the rebuilt route, unless the document states that a primary source was unavailable. Alternatives go in their own subfolders with a file name prefix, as `structure.md` describes.

## Fixed method statements

- **2024 demand:** spatial crop data end in 2018, so a decision was made to use the 2018 crop area and yield to represent 2024. Every document that shows 2024 demand, flow or unmet demand states this and its consequence, namely that changes between 2018 and 2024 in these results reflect pollination potential and national statistics, and not crop relocation.
- **Crop data sources:** the time series is not mixed across crop data sources with different methods and crop categories.

## Prose style

- **Self-standing documents:** the documents stand on their own. When a decision needs explaining, state it as a method choice with its reason (for example, "A decision was made to...", or simply the reasoning).
- Never use long dashes (em dashes) or sentences that need them.
- Write declarative sentences. Do not split a sentence with a semicolon or a colon when a comma, a linking phrase or a new sentence reads naturally.
- Write full sentences. Avoid fragments, telegraphic phrasing and stacked clauses.
- Never use the "It is not X, it is Y" construction or its derivatives.
- Do not use a colon to introduce an enumeration after an already complete sentence. Rewrite it as one fluent sentence that integrates the list through a linking phrase. Colons are reserved for definitions, verbatim quotes and formal lists.
- Explain terms and method steps in the text, so that each document is self-contained and does not depend on the cited manuals to be understood.
- These rules apply to new text and future edits. Existing documents are not rewritten unless asked.
