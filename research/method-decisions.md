# Method decisions

The reference method is Vallecillo et al. (2018), cited as "the report". Page numbers are the printed page numbers of the report. The INCA plugin and the k.LAB implementation are sources of orientation only.

| Topic | Report | Decision here | Verification |
|---|---|---|---|
| Land cover | Corine accounting layers, p. 76 and 77 | Version 21 for all five years (EEA, September 2026). Version 20 is marked superseded by the EEA and stops at 2018. | Verified online |
| Roads | TeleAtlas categories 0, 1 and 2, p. 77 | OpenStreetMap motorway, trunk and primary with links. TeleAtlas is proprietary. Applied to all land, static, as in the report's table of inputs. | Verified in text. OSM correspondence inferred from the k.LAB project notes. |
| Scores | Zulian et al. (2013), p. 77 | Table transcribed from the k.LAB project, which cites Zulian et al. (2013). Compared by script with Table S1 of the supplement (`refs/literature/land-02-00472-s001.docx`): all 43 classes agree. Olive groves (0.4 and 0.5) take the average of intensive (0.2, 0.4) and extensive (0.6, 0.6), which the note to Table S1 suggests for readers using Corine only. The crop, forest, high nature value, riparian and road side refinements of the article are not applied, because the report works from Corine alone. | Verified in text |
| Mean of scores | Mean of floral and nesting, p. 78 | As in the report. | Verified in text |
| Forest edge | 100 m edge keeps its score and the core scores 0, p. 77 and 78 | One cell ring of forest classes 311, 312 and 313, eight directions. The edge keeps its Table S1 score. The report says edges take "the corresponding expert score" as described in Zulian et al. (2013), and Table S3 of that supplement gives edge scores 0.1 higher on both indicators (broad-leaved 1 and 0.9, coniferous 0.4 and 0.9, mixed 0.7 and 0.9) for a 50 m edge. **Open question:** which scores are meant. Using Table S3 would mean rerunning scripts 07 and 10 to 15. | Verified in text |
| Distance decay | exp(ln(score) - 0.00046 d), 20 km limit, p. 79 and 80 | As in the report. Euclidean distance between cell centres, computed with GDAL. | Verified in text |
| Temperature in the activity index | Text on p. 78 says minimum temperature, table on p. 77 says mean temperature | Mean temperature. The plugin and k.LAB also use it. | Verified in text |
| Climate source | Agri4Cast, p. 77 | ERA5 2 m temperature and C3S solar radiation from the public catalogue, which serves monthly means for the same three-year periods at an open address, so anyone can repeat the step with no account. The catalogue reaches 2025 and its radiation is already expressed over day length. | Verified online |
| Monthly limit of the activity index | Silent | Each month limited to 0 to 100 before the mean. Zulian et al. (2013) adjust values below 0% and above 100% in the same way, and their equations 1 and 2 match the coefficients used here. | Verified in text |
| Bumblebee model | Yearly projection of 47 species, p. 80 to 83 | One static layer (Polce et al., 2018) for all years, since the Maxent lambdas and thresholds were not available. Values run from 0.04 to 0.74 and are used as probabilities, in spite of the word "richness" in the catalogue metadata. | Verified by reading the raster |
| Potential classes | High above 0.3, medium 0.2 to 0.3, low 0.1 to 0.2, none below 0.1, p. 83 | As in the report. Service area is 0.2 and above. | Verified in text |
| Crop years | 2004 and 2008, p. 35 | Exact reporting years from the 2000 to 2018 CAPRI series (Koeble et al., 2024). | Verified online |
| 2024 crops | Not covered | 2018 crop area and yield represent 2024. Data sources with different crop categories are not mixed. | Decision |
| Contribution | CAPRI flow over CAPRI production, p. 43 | As in the report, production-weighted, by crop and country. | Verified in text |
| Physical flow | Yield x dependency, p. 39 | CAPRI pattern scaled to the Eurostat 3-year production of the crop and country, so maps and tables agree. | Decision |
| Unmet tonnes | Factsheet p. 86 defines unmet demand by area | Production outside the service area x dependency. Total production outside is reported alongside. **Open question.** | Decision |
| Monetary | aact_eaa02, 3-year mean, p. 42 | As in the report, then expressed in constant 2010 prices with the HICP, as in the carbon and wood accounts. | Verified in text |
| Croatia, Malta, Cyprus | No CAPRI data, footnote 6, p. 36 | No crop maps. Table values are flagged estimates based on the farmland share inside the service area. Reading the CAPRI series shows that only Croatia is absent (30 ha in 2018, from border cells, against 202 780 ha in Eurostat). Cyprus holds 8 172 ha against 8 770 ha in Eurostat, and Malta 466 ha. All three stay out of the crop maps as the report prescribes, and together Cyprus and Malta hold under 0.1% of the flow. **Open question:** whether Cyprus and Malta should enter the maps. | Verified by reading the raster |
| All ecosystems and agroecosystems | Factsheet p. 86 | Same flow total. The agro maps allocate to farmland cells and the all-types map allocates by suitability over all land cells. **Open question.** | Decision |
| Outermost regions | Silent | Canary Islands, Azores, Madeira and overseas regions are outside the climate data and the analysis window. | Verified by reading the raster |

## Notes on results

- Route comparison: run for 2000 and 2018 by `scripts/07b_compare_routes.R`, and kept as a saved table. The pipeline does not repeat it. The two catalogue reductions it reads are in `refs/ebm_catalogue/`, outside the repository.

- Pome fruit value: Table 4.4 of the report shows 2 240 M EUR for the EU in 2006. The sum of apples, pears and peaches in `aact_eaa02` gives 6 620 M EUR for the EU27, close to three times that figure. The other crops are close to the report. Summing is the choice here. **Open question**, since it explains most of the difference with the published total of 3 billion euro. Inferred.
- Other fruits, 2012: about 0.9 million ha in CAPRI and Eurostat against about 2 million in other years. Likely a data gap.
- Flax and hemp: CAPRI area is about three times the Eurostat area.
- 100 m cells: allocation to few agricultural cells can place more than 1 ha or implausible tonnes in one cell. Totals by kilometre are conserved within rounding, checked from disk for all maps and years with `scripts/15_check_maps_100m.R`. Totals of demand, flow and unmet demand stay within 0.04% of the 1 km totals. Verified by reading the rasters.
- 100 m agricultural potential: the mean over the map is about 5% below the 1 km map, since the 100 m mean counts agricultural cells and the 1 km mean counts kilometres. The two differ by at most 0.023 in any kilometre, and weighting the 1 km map by agricultural cells reproduces the 100 m mean (0.1988 in 2000, 0.2035 in 2024). Verified by reading the rasters.

## Open items

1. If the treatment of Cyprus and Malta or the forest edge scores is revisited, rerun the affected scripts.
2. If Maxent lambdas and `MinimumTrainingThresholds.csv` become available, project the bumblebee model for each period.
3. Partial validation of the 2024 crop assumption with IACS data for the countries where it is available.
