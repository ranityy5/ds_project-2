# Vaccination Data Analysis and Visualization

WHO / UNICEF immunization data (coverage, incidence, cases, vaccine introduction, vaccine schedule; 1940-2023).

| Folder / file | What it is |
|---|---|
| `Vaccination_EDA_Project.ipynb` | Full EDA following the submission template: data profiling, cleaning, 30 charts (each with why / insight / business impact), answers to every question in the brief, recommendations. Already executed (outputs saved). |
| `cleaned_data/` | Cleaned star schema as CSV: 11 dimension tables, 6 fact tables, 3 analysis views. Written by the notebook (section 3). |
| `sql/01_create_schema.sql` | Tables with primary and foreign keys and the 3 views (MySQL / PostgreSQL style; SQL Server notes inside). |
| `sql/02_build_database.py` | Loads the CSVs into a database. Default = SQLite (`vaccination.db`, included); `--url` for MySQL / PostgreSQL / SQL Server via SQLAlchemy. |
| `sql/03_analysis_queries.sql` | 16 analysis queries (coverage, disease impact, introduction, gaps, scenarios). |
| `powerbi/` | Everything needed to build the Power BI report: `README_POWERBI.md` (model, relationships, every page and visual), `measures.dax`, `theme.json`, `load_csv_tables.pq`. |
| `Vaccination_Dashboard_Preview.html` | Interactive browser mock-up of the 5 report pages with the real numbers (open in any browser). |

## Run order
1. Put the 5 original `.xlsx` files in `data/` next to the notebook (or set `VACCINE_DATA_DIR`).
2. Run the notebook top to bottom (about 1-2 minutes; the coverage workbook is slow to read). It rewrites `cleaned_data/`.
3. `python sql/02_build_database.py` (optional; rebuilds `vaccination.db`).
4. Follow `powerbi/README_POWERBI.md` to build the report (60-90 minutes).

## Honest limits
* **No `.pbix` file is included** - Power BI Desktop is required to create one. The guide, DAX and theme are provided; the DAX was not run inside Power BI Desktop, so check the reference numbers in section 6 of the guide.
* SQL was tested on SQLite only (all keys and 16 queries pass); the MySQL / PostgreSQL / SQL Server DDL was not run on those servers.
* The dataset has no gender (except HPV), education, urban/rural, population density, monthly or delivery-strategy data, so those questions are answered with the closest proxy or marked as not answerable.
* Results are associations between countries, not proof of cause.
