-- =====================================================================================
-- Vaccination Data Analysis  |  Normalised star schema (WHO / UNICEF immunization data)
-- Portable SQL: runs as-is on SQLite / MySQL 8 / PostgreSQL. For SQL Server replace
-- "DECIMAL" precision as needed and run each CREATE separately (no IF NOT EXISTS needed).
-- Load order = order of this file (dimensions first, then facts).
-- =====================================================================================

-- ---------------------------------------------------------------- DIMENSIONS
CREATE TABLE dim_country (
    country_code     CHAR(3)       NOT NULL PRIMARY KEY,          -- ISO alpha-3
    country_name     VARCHAR(100)  NOT NULL,
    who_region       VARCHAR(5)    NOT NULL,                      -- AFRO, AMRO, EMRO, EURO, SEARO, WPRO
    who_region_name  VARCHAR(30)   NOT NULL
);

CREATE TABLE dim_year (
    year             INT           NOT NULL PRIMARY KEY,
    decade           VARCHAR(6)    NOT NULL,
    is_covid_period  SMALLINT      NOT NULL                       -- 1 for 2020-2021
);

CREATE TABLE dim_disease (
    disease_code           VARCHAR(20)   NOT NULL PRIMARY KEY,
    disease_name           VARCHAR(80)   NOT NULL,
    incidence_denominator  VARCHAR(40)   NOT NULL,                -- unit the WHO publishes the rate in
    denominator_base       VARCHAR(30)   NOT NULL,                -- population the rate refers to
    to_per_100k_factor     DECIMAL(12,4) NOT NULL,                -- multiply published rate to get "per 100,000"
    disease_group          VARCHAR(40)
);

CREATE TABLE dim_antigen (
    antigen_code             VARCHAR(20)  NOT NULL PRIMARY KEY,
    antigen_description      VARCHAR(200) NOT NULL,
    antigen_family           VARCHAR(30)  NOT NULL,
    is_booster_or_later_dose SMALLINT     NOT NULL
);

CREATE TABLE bridge_antigen_disease (                             -- which vaccine protects against which disease (many-to-many)
    antigen_code  VARCHAR(20) NOT NULL,
    disease_code  VARCHAR(20) NOT NULL,
    PRIMARY KEY (antigen_code, disease_code),
    FOREIGN KEY (antigen_code) REFERENCES dim_antigen (antigen_code),
    FOREIGN KEY (disease_code) REFERENCES dim_disease (disease_code)
);

CREATE TABLE dim_coverage_category (
    category_code         VARCHAR(10)  NOT NULL PRIMARY KEY,      -- WUENIC, OFFICIAL, ADMIN, HPV, PAB
    category_description  VARCHAR(100) NOT NULL,
    priority_rank         INT          NOT NULL                   -- 1 = most trusted source
);

CREATE TABLE dim_group (                                          -- aggregate entities: WHO regions, income groups, Gavi, global ...
    group_type  VARCHAR(30)  NOT NULL,
    group_code  VARCHAR(40)  NOT NULL,
    group_name  VARCHAR(120) NOT NULL,
    who_region  VARCHAR(5),                                       -- filled only for WHO_REGIONS rows
    PRIMARY KEY (group_type, group_code)
);

CREATE TABLE dim_intro_vaccine (
    intro_vaccine_id     INT          NOT NULL PRIMARY KEY,
    vaccine_description  VARCHAR(100) NOT NULL,
    linked_antigen_code  VARCHAR(20),
    linked_disease_code  VARCHAR(20),
    FOREIGN KEY (linked_antigen_code) REFERENCES dim_antigen (antigen_code),
    FOREIGN KEY (linked_disease_code) REFERENCES dim_disease (disease_code)
);

CREATE TABLE dim_intro_status (
    status_code    VARCHAR(20) NOT NULL PRIMARY KEY,
    status_label   VARCHAR(60) NOT NULL,
    is_introduced  SMALLINT    NOT NULL,
    is_nationwide  SMALLINT    NOT NULL
);

CREATE TABLE dim_schedule_vaccine (
    vaccine_code         VARCHAR(30)  NOT NULL PRIMARY KEY,
    vaccine_description  VARCHAR(200) NOT NULL,
    vaccine_family       VARCHAR(40)  NOT NULL
);

CREATE TABLE dim_target_pop (
    target_pop_code         VARCHAR(20) NOT NULL PRIMARY KEY,
    target_pop_description  VARCHAR(60) NOT NULL
);

-- ---------------------------------------------------------------- FACTS
CREATE TABLE fact_coverage (
    country_code             CHAR(3)      NOT NULL,
    year                     INT          NOT NULL,
    antigen_code             VARCHAR(20)  NOT NULL,
    category_code            VARCHAR(10)  NOT NULL,
    target_number            DECIMAL(16,0),                       -- people targeted (NULL for WUENIC rows)
    doses                    DECIMAL(16,0),
    coverage_raw             DECIMAL(14,2),                       -- as reported / recomputed (can exceed 100)
    coverage_was_recomputed  SMALLINT     NOT NULL,
    coverage_gt100_flag      SMALLINT     NOT NULL,
    coverage_pct             DECIMAL(6,2),                        -- analysis column, capped at 100
    PRIMARY KEY (country_code, year, antigen_code, category_code),
    FOREIGN KEY (country_code)  REFERENCES dim_country (country_code),
    FOREIGN KEY (year)          REFERENCES dim_year (year),
    FOREIGN KEY (antigen_code)  REFERENCES dim_antigen (antigen_code),
    FOREIGN KEY (category_code) REFERENCES dim_coverage_category (category_code)
);

CREATE TABLE fact_coverage_group (
    group_type               VARCHAR(30)  NOT NULL,
    group_code               VARCHAR(40)  NOT NULL,
    year                     INT          NOT NULL,
    antigen_code             VARCHAR(20)  NOT NULL,
    category_code            VARCHAR(10)  NOT NULL,
    target_number            DECIMAL(16,0),
    doses                    DECIMAL(16,0),
    coverage_raw             DECIMAL(14,2),
    coverage_was_recomputed  SMALLINT     NOT NULL,
    coverage_gt100_flag      SMALLINT     NOT NULL,
    coverage_pct             DECIMAL(6,2),
    PRIMARY KEY (group_type, group_code, year, antigen_code, category_code),
    FOREIGN KEY (group_type, group_code) REFERENCES dim_group (group_type, group_code),
    FOREIGN KEY (year)          REFERENCES dim_year (year),
    FOREIGN KEY (antigen_code)  REFERENCES dim_antigen (antigen_code),
    FOREIGN KEY (category_code) REFERENCES dim_coverage_category (category_code)
);

CREATE TABLE fact_disease_burden (                                -- incidence + cases (same grain: country x year x disease)
    country_code        CHAR(3)     NOT NULL,
    year                INT         NOT NULL,
    disease_code        VARCHAR(20) NOT NULL,
    incidence_reported  DECIMAL(16,2),                            -- in the disease's own unit (see dim_disease)
    cases               DECIMAL(16,0),                            -- NULL = not reported (NOT zero)
    incidence_per_100k  DECIMAL(18,4),                            -- normalised unit
    PRIMARY KEY (country_code, year, disease_code),
    FOREIGN KEY (country_code) REFERENCES dim_country (country_code),
    FOREIGN KEY (year)         REFERENCES dim_year (year),
    FOREIGN KEY (disease_code) REFERENCES dim_disease (disease_code)
);

CREATE TABLE fact_disease_burden_group (
    group_type          VARCHAR(30) NOT NULL,
    group_code          VARCHAR(40) NOT NULL,
    year                INT         NOT NULL,
    disease_code        VARCHAR(20) NOT NULL,
    incidence_reported  DECIMAL(16,2),
    cases               DECIMAL(16,0),
    incidence_per_100k  DECIMAL(18,4),
    PRIMARY KEY (group_type, group_code, year, disease_code),
    FOREIGN KEY (group_type, group_code) REFERENCES dim_group (group_type, group_code),
    FOREIGN KEY (year)         REFERENCES dim_year (year),
    FOREIGN KEY (disease_code) REFERENCES dim_disease (disease_code)
);

CREATE TABLE fact_vaccine_intro (
    country_code      CHAR(3)     NOT NULL,
    year              INT         NOT NULL,
    intro_vaccine_id  INT         NOT NULL,
    status_code       VARCHAR(20) NOT NULL,
    PRIMARY KEY (country_code, year, intro_vaccine_id),
    FOREIGN KEY (country_code)     REFERENCES dim_country (country_code),
    FOREIGN KEY (year)             REFERENCES dim_year (year),
    FOREIGN KEY (intro_vaccine_id) REFERENCES dim_intro_vaccine (intro_vaccine_id),
    FOREIGN KEY (status_code)      REFERENCES dim_intro_status (status_code)
);

CREATE TABLE fact_vaccine_schedule (
    schedule_id      INT          NOT NULL PRIMARY KEY,
    country_code     CHAR(3)      NOT NULL,
    year             INT          NOT NULL,
    vaccine_code     VARCHAR(30)  NOT NULL,
    schedule_round   INT          NOT NULL,                       -- dose number
    target_pop_code  VARCHAR(20)  NOT NULL,
    geo_area         VARCHAR(15)  NOT NULL,                       -- NATIONAL / SUBNATIONAL
    age_administered VARCHAR(20)  NOT NULL,                       -- as published (M2, W6, Y6, B, +M1 ...)
    age_months       DECIMAL(8,2),                                -- parsed age in months (NULL when relative / unknown)
    age_kind         VARCHAR(10)  NOT NULL,                       -- absolute | interval | contact | other | unknown
    source_comment   VARCHAR(500),
    FOREIGN KEY (country_code)    REFERENCES dim_country (country_code),
    FOREIGN KEY (year)            REFERENCES dim_year (year),
    FOREIGN KEY (vaccine_code)    REFERENCES dim_schedule_vaccine (vaccine_code),
    FOREIGN KEY (target_pop_code) REFERENCES dim_target_pop (target_pop_code)
);

-- ---------------------------------------------------------------- INDEXES (speed up Power BI / joins)
CREATE INDEX ix_cov_country_year   ON fact_coverage (country_code, year);
CREATE INDEX ix_cov_antigen_year   ON fact_coverage (antigen_code, year);
CREATE INDEX ix_burden_dis_year    ON fact_disease_burden (disease_code, year);
CREATE INDEX ix_intro_vaccine      ON fact_vaccine_intro (intro_vaccine_id, year);
CREATE INDEX ix_sched_country_year ON fact_vaccine_schedule (country_code, year);

-- ---------------------------------------------------------------- VIEWS (analysis-ready, same logic as the notebook)
-- Best available coverage per country-year-antigen: WUENIC > OFFICIAL > ADMIN > (HPV, PAB)
-- target_any = the target population reported by ANY source (WUENIC rows carry no target, ADMIN/OFFICIAL do)
CREATE VIEW vw_coverage_best AS
SELECT country_code, year, antigen_code, category_code AS source_category, coverage_pct, target_any
FROM (
    SELECT f.country_code, f.year, f.antigen_code, f.category_code, f.coverage_pct,
           MAX(f.target_number) OVER (PARTITION BY f.country_code, f.year, f.antigen_code) AS target_any,
           ROW_NUMBER() OVER (PARTITION BY f.country_code, f.year, f.antigen_code
                              ORDER BY CASE WHEN f.coverage_pct IS NULL THEN 1 ELSE 0 END, c.priority_rank) AS rn
    FROM fact_coverage f
    JOIN dim_coverage_category c ON c.category_code = f.category_code
) ranked
WHERE rn = 1 AND coverage_pct IS NOT NULL;

-- Coverage of a vaccine joined with incidence of the disease it prevents (biologically meaningful pairs only)
CREATE VIEW vw_coverage_vs_incidence AS
SELECT b.antigen_code, b.disease_code, v.country_code, v.year, v.coverage_pct,
       d.incidence_reported, d.incidence_per_100k, d.cases
FROM bridge_antigen_disease b
JOIN vw_coverage_best v        ON v.antigen_code = b.antigen_code
JOIN fact_disease_burden d     ON d.country_code = v.country_code AND d.year = v.year AND d.disease_code = b.disease_code;

-- First year a country introduced each vaccine (any 'Yes' variant)
CREATE VIEW vw_first_introduction AS
SELECT f.country_code, iv.vaccine_description, MIN(f.year) AS first_year
FROM fact_vaccine_intro f
JOIN dim_intro_status s  ON s.status_code = f.status_code AND s.is_introduced = 1
JOIN dim_intro_vaccine iv ON iv.intro_vaccine_id = f.intro_vaccine_id
GROUP BY f.country_code, iv.vaccine_description;
