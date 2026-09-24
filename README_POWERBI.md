# Power BI dashboard – build guide (about 60–90 minutes)

> **Read this first.** A `.pbix` file can only be produced by Power BI Desktop, which is not available where this project was prepared,
> so the report itself is **not** included. Everything Power BI needs is: the cleaned star-schema data, the SQL database, the DAX measures
> (`measures.dax`), a colour theme (`theme.json`), a Power Query loader (`load_csv_tables.pq`) and the exact page/visual recipes below.
> `Vaccination_Dashboard_Preview.html` (in the project folder) is a working, interactive mock-up of the same pages with the real numbers, so you can see
> the target layout. The DAX has not been executed inside Power BI Desktop – after pasting, check the reference numbers in section 6 and adjust table names if you renamed anything.

---
## 1. Connect to the data (choose ONE option)

### Option A – CSV files (fastest, no server needed)
1. Power BI Desktop → **Home → Transform data → New Source → Blank Query → Advanced Editor**, paste `load_csv_tables.pq`, set `DataFolder` to the `cleaned_data` folder, name the query **fnCsv**.
2. For each table below add a Blank Query with `= fnCsv("table_name")` and rename it: `dim_country`, `dim_year`, `dim_disease`, `dim_antigen`, `dim_coverage_category`, `dim_group`, `dim_intro_vaccine`, `dim_intro_status`, `dim_schedule_vaccine`, `dim_target_pop`, `fact_coverage`, `fact_coverage_group`, `fact_disease_burden`, `fact_disease_burden_group`, `fact_vaccine_intro`, `fact_vaccine_schedule`, `mart_coverage_vs_incidence`, `mart_first_introduction`, and **`mart_coverage_best` → rename to `fact_coverage_best`**.
3. In `fact_coverage_best`, `mart_coverage_vs_incidence` and `mart_first_introduction` **remove** the text columns `country_name` and `who_region` (they come from `dim_country`). Keep `target_any`.
4. Add a key column for the group tables: in `dim_group`, `fact_coverage_group` and `fact_disease_burden_group` add a custom column `group_key = [group_type] & "|" & [group_code]`.
5. **Close & Apply.**

### Option B – SQL database (matches the brief: “Power BI connects to the SQL database”)
1. Create the schema: run `sql/01_create_schema.sql` on MySQL / PostgreSQL / SQL Server (SQLite is used only for the local demo `vaccination.db`).
2. Load the CSVs: `python sql/02_build_database.py --url "<sqlalchemy-url>"` (needs `sqlalchemy` + a driver), or use the server’s import wizard / `BULK INSERT` / `LOAD DATA` in the order of the DDL file.
3. Power BI → **Get Data → SQL Server / MySQL / PostgreSQL database** → Import mode → select the 17 tables plus the views **`vw_coverage_best` (rename to `fact_coverage_best`)**, `vw_coverage_vs_incidence` (rename to `mart_coverage_vs_incidence`) and `vw_first_introduction` (rename to `mart_first_introduction`).
4. **Scheduled refresh** (brief requirement): publish to the Power BI service → dataset settings → *Gateway connection* (on-premises gateway if the database is not cloud-hosted) → *Scheduled refresh* → daily. WHO updates the source data once a year, so a weekly or monthly refresh is sufficient.

---
## 2. Model view – relationships (all one-to-many, single direction, dimension → fact)

| From (one side) | To (many side) | Column |
|---|---|---|
| dim_country | fact_coverage_best, fact_coverage, fact_disease_burden, fact_vaccine_intro, fact_vaccine_schedule, mart_coverage_vs_incidence, mart_first_introduction | country_code |
| dim_year | fact_coverage_best, fact_coverage, fact_coverage_group, fact_disease_burden, fact_disease_burden_group, fact_vaccine_intro, fact_vaccine_schedule, mart_coverage_vs_incidence | year |
| dim_antigen | fact_coverage_best, fact_coverage, fact_coverage_group, mart_coverage_vs_incidence | antigen_code |
| dim_disease | fact_disease_burden, fact_disease_burden_group, mart_coverage_vs_incidence | disease_code |
| dim_coverage_category | fact_coverage, fact_coverage_group | category_code |
| dim_group | fact_coverage_group, fact_disease_burden_group | group_key (Option A) / group_type + group_code (Option B: add the `group_key` column too) |
| dim_intro_vaccine | fact_vaccine_intro | intro_vaccine_id |
| dim_intro_vaccine | mart_first_introduction | vaccine_description |
| dim_intro_status | fact_vaccine_intro | status_code |
| dim_schedule_vaccine | fact_vaccine_schedule | vaccine_code |
| dim_target_pop | fact_vaccine_schedule | target_pop_code |
| bridge_antigen_disease | *not needed in the model* – already applied inside `mart_coverage_vs_incidence` | – |

Housekeeping: set `year` columns to **Don’t summarize**; hide the key columns; sort `who_region` by a custom order (AFRO, AMRO, EMRO, EURO, SEARO, WPRO); set `dim_country[country_name]` data category = **Country/Region** (for the map).
**Never sum coverage.** Coverage is a percentage – always use the `Coverage %` measure (average) or the global measure.
**Important:** `fact_coverage` holds three sources (WUENIC, OFFICIAL, ADMIN) for the same country-year-antigen. It is used **only** for doses/targets with a category filter. All coverage visuals use `fact_coverage_best`.

## 3. Measures and theme
* Home → Enter data → create table `_Measures`, then paste every measure from `measures.dax` (New measure).
* Also create the calculated table `Goal Parameter` (first two lines of the file) and use it as a slicer called **“Coverage goal (%)”**.
* View → Themes → **Browse for themes** → `theme.json`.

---
## 4. The report pages

Canvas 1280 × 720. Global slicers on every page (sync slicers): **Year** (`dim_year[year]`, single-select slider), **WHO region** (`dim_country[who_region]`).

### Page 1 – Executive overview
| Visual | Fields | Notes |
|---|---|---|
| 5 KPI cards | `Global Coverage % (latest)` filtered to DTPCV3 / MCV1 / MCV2 (three cards, filter on `dim_antigen[antigen_code]`), `Countries Below 90% (DTP3)`, `Est. Unvaccinated Infants` | Add `Change vs 2019 (pts)` as the card subtitle (red if negative). |
| Line chart | X `dim_year[year]`; Y `Global Coverage %`; Legend `dim_antigen[antigen_code]` (DTPCV3, MCV1, MCV2, POL3, HEPB3, PCV3, ROTAC) | Add constant line at 90 (Analytics pane). Shade 2020–21. |
| Filled map | Location `dim_country[country_name]`; Color saturation `Coverage %` (filter antigen = DTPCV3) | Diverging colour: red < 70, yellow 70–90, green ≥ 90. |
| Clustered bar | Axis `who_region`; Values `Coverage %` (antigen slicer) | Sort ascending – the lowest region at the top. |
| Card | `Reported Cases` (disease = MEASLES) | – |

### Page 2 – Coverage & equity  *(brief: low-coverage areas, income gap, drop-off, boosters)*
| Visual | Fields |
|---|---|
| Matrix (heat-map) | Rows `who_region`, Columns `antigen_code` (BCG, DTPCV3, HEPB3, HIB3, MCV1, MCV2, PCV3, POL3, RCV1, ROTAC), Values `Coverage %` – *conditional formatting → background colour scale, min 50 red / mid 80 yellow / max 100 green* |
| Line chart | X `year`; Y `Group Coverage %`; Legend `dim_group[group_name]`; filter `dim_group[group_type] = WB_LONG`, `antigen_code = DTPCV3`, exclude “Not classified” |
| Clustered column | Axis `who_region`; Values `DTP Drop-off %`, `Measles Drop-off %` |
| Bar (top 15) | Axis `country_name`; Values `Est. Unvaccinated Infants`; Top N = 15 by that value (filter year = latest) |
| Line chart | Booster uptake: Y `Coverage %`, Legend antigen (DIPHCV4, DIPHCV5, DIPHCV6, MCV2) |
| Table | `country_name`, `Coverage %`, `Gap To Goal (pts)` with data bars, filter `Coverage % < Goal %` |
| Slicer | “Coverage goal (%)” (`Goal Parameter`) |

### Page 3 – Disease impact  *(brief: coverage vs incidence, disease reduction, regional prevalence)*
| Visual | Fields |
|---|---|
| Scatter | X `Pair Coverage %`; Y `Pair Incidence (per million)` (log axis); Details `country_name`; Legend `who_region`; Size `Reported Cases`; slicers on `mart_coverage_vs_incidence[antigen_code]` and `[disease_code]` (default MCV1 / MEASLES); Analytics pane → *Trend line* |
| Card | `Pearson r (coverage vs log incidence)` |
| Line chart | X `year`; Y `Cases Index (1980-82 = 100)`; Legend `disease_name` (MEASLES, PERTUSSIS, DIPHTHERIA, TTETANUS, NTETANUS, POLIO); log scale |
| Bar | Axis `disease_name`; Values `Reduction vs 1980-82 %` (year = latest) |
| Matrix | Rows `disease_name`; Columns `who_region`; Values `Incidence per 100k` – colour scale (regional prevalence) |
| Table | `High Coverage & High Incidence` list: country, MCV1, incidence (filter coverage ≥ goal and incidence > 100) |
| Card | `Share Missing Cases %` (data-quality note) |

### Page 4 – Vaccine introduction & schedule
| Visual | Fields |
|---|---|
| Bar | Axis `dim_intro_vaccine[vaccine_description]`; Values `Countries Introduced (nationwide)` (year slicer) |
| Matrix | Rows `vaccine_description`; Columns `who_region`; Values `Median First Introduction Year` (colour scale – late = red) |
| Column chart | Axis `year`; Values `Countries Introduced (any)`; filter one vaccine (e.g. Rotavirus) – adoption curve |
| Donut | Legend `dim_target_pop[target_pop_description]`; Values `Schedule Entries` |
| Table | vaccine family, `Max Doses In Schedule`, `Countries With Schedule` |
| Bar | Introduced-but-low-coverage: use the SQL result Q11 (`sql/03_analysis_queries.sql`) as an extra table or build a measure from `fact_vaccine_intro` × `fact_coverage_best` |

### Page 5 – Scenario explorer  *(brief: scenario-based questions)*
| Scenario | Visual |
|---|---|
| Agency: allocate resources | Top-15 `Est. Unvaccinated Infants` + map, region slicer |
| Measles campaign 5 years ago | Line `Reported Cases` / `Incidence per 100k` (disease = MEASLES) by year, add a vertical reference line at the launch year (Analytics → X-axis constant line); two cards comparing launch year vs +5 years |
| Manufacturer: demand forecast | Line `Doses Administered` by year, antigen slicer MCV1/MCV2 → **Analytics → Forecast** (1 year, 95 % confidence); card `Target Doses For Goal` |
| Influenza outbreak | Bar `% Countries Introduced` by `who_region` (vaccine = Seasonal Influenza); note that no influenza case data exist |
| Polio without coverage | Column chart: bin `Pair Coverage %` (Data groups: bins of 20) vs share of country-years with cases (disease = POLIO, antigen = POL3) |
| WHO 95 % measles by 2030 | Line `Global Coverage %` (MCV1, MCV2) with constant line 95 and forecast to 2030; `% Countries At Goal` with Goal = 95 |
| High-risk groups | Schedule entries by `target_pop_description`; flu coverage for elderly (`FLU_ELDERLY`) |
| Socioeconomic disparities | Same income-group line as page 2 |

### Page 6 – Data notes (text + KPI cards)
Cleaning steps (copy the table from the notebook, Section 3), `Records Flagged >100% Coverage`, `Records Recomputed`, definitions (WUENIC vs OFFICIAL vs ADMIN; incidence units), and the limitations list (annual data; no gender other than HPV; no education, urban/rural, density, seasonality or delivery-strategy fields).

### Extras (make it “interactive and user friendly”)
* **Drill-through page “Country profile”**: fields `country_name` → coverage trend, incidence trend, schedule table. Right-click any country → *Drill through*.
* **Report-page tooltip**: small chart of the coverage trend for the hovered country.
* **Bookmarks + buttons**: “Reset filters”, “Focus on Africa”, “Focus on low-income”.
* **Titles that answer the question** (e.g. “Which regions are furthest from the 90 % goal?”) and alt-text on every visual.

---
## 5. Design rules used
Red/orange = below goal or increase in disease, teal/green = at goal, navy for neutral series; one colour per WHO region everywhere (AFRO #e76f51, AMRO #2a9d8f, EMRO #e9c46a, EURO #264653, SEARO #8ab17d, WPRO #6a4c93); 90 % and 95 % goals shown as dotted reference lines; every chart title states the year or period.

## 6. Check your numbers (reference values, year 2023)
If your report shows these values, the model and measures are wired correctly.

| Check | Expected |
|---|---|
| `fact_coverage_best` rows | 94,535 |
| Global coverage (WUENIC): DTP3 / MCV1 / MCV2 / PCV3 / Rotavirus | 84 % / 83 % / 74 % / 65 % / 55 % |
| Countries with DTP3 in 2023 / below 90 % / below 70 % | 207 / 91 / 23 |
| Countries at 95 %: MCV1 / MCV2 | 73 of 207 / 41 of 203 |
| Estimated unvaccinated infants (DTP1, 180 countries with a target) | ≈ 15.2 million of 125.8 million targeted; Nigeria ≈ 2.53 million is the largest |
| Global reported measles cases 1980 / 2019 / 2023 | 3,852,242 / 873,373 / 663,830 |
| DTP3 low-income vs high-income (OECD) | 68 % vs 94 % |
| Countries with MCV1 ≥ 90 % and measles > 100 per million | 8 |
| `fact_coverage` / `fact_disease_burden` / `fact_vaccine_intro` / `fact_vaccine_schedule` rows | 215,380 / 62,655 / 138,320 / 8,052 |
