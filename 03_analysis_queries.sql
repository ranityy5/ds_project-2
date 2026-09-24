-- =====================================================================================
-- Analysis queries  (tested on SQLite; ANSI SQL, works on MySQL 8 / PostgreSQL with minor syntax changes)
-- Each query answers one question from the project brief. Latest data year = 2023.
-- =====================================================================================

-- Q1. Global coverage trend for the key vaccines (WHO/UNICEF global estimate)
SELECT g.year, g.antigen_code, g.coverage_pct
FROM fact_coverage_group g
WHERE g.group_type = 'GLOBAL' AND g.category_code = 'WUENIC'
  AND g.antigen_code IN ('DTPCV3','MCV1','MCV2','POL3','PCV3','ROTAC') AND g.year >= 2000
ORDER BY g.antigen_code, g.year;

-- Q2. Which regions have low coverage? Mean country coverage by WHO region, 2023 (resource allocation)
SELECT c.who_region, v.antigen_code, ROUND(AVG(v.coverage_pct), 1) AS mean_coverage, COUNT(*) AS countries
FROM vw_coverage_best v JOIN dim_country c ON c.country_code = v.country_code
WHERE v.year = 2023 AND v.antigen_code IN ('DTPCV3','MCV1','MCV2','PCV3','ROTAC','HEPB3')
GROUP BY c.who_region, v.antigen_code
ORDER BY v.antigen_code, mean_coverage;

-- Q3. Countries below the 90% DTP3 goal in 2023, lowest first
SELECT c.country_name, c.who_region, v.coverage_pct AS dtp3_coverage
FROM vw_coverage_best v JOIN dim_country c ON c.country_code = v.country_code
WHERE v.year = 2023 AND v.antigen_code = 'DTPCV3' AND v.coverage_pct < 90
ORDER BY v.coverage_pct
LIMIT 25;

-- Q4. Estimated unvaccinated infants (zero-dose proxy = target x (1 - DTP1 coverage)), top 15 countries
SELECT c.country_name, c.who_region,
       ROUND(t.target_number)                                     AS infants_targeted,
       v.coverage_pct                                             AS dtp1_coverage,
       ROUND(t.target_number * (1 - v.coverage_pct / 100.0))       AS est_unvaccinated_infants
FROM vw_coverage_best v
JOIN dim_country c ON c.country_code = v.country_code
JOIN (SELECT country_code, MAX(target_number) AS target_number
      FROM fact_coverage WHERE antigen_code = 'DTPCV1' AND year = 2023 AND target_number IS NOT NULL
      GROUP BY country_code) t ON t.country_code = v.country_code
WHERE v.year = 2023 AND v.antigen_code = 'DTPCV1'
ORDER BY est_unvaccinated_infants DESC
LIMIT 15;

-- Q5. Drop-off between first and third DTP dose by WHO region, 2023
SELECT c.who_region,
       ROUND(AVG(d1.coverage_pct), 1) AS dtp1, ROUND(AVG(d3.coverage_pct), 1) AS dtp3,
       ROUND(AVG((d1.coverage_pct - d3.coverage_pct) * 100.0 / d1.coverage_pct), 1) AS mean_dropout_pct
FROM vw_coverage_best d1
JOIN vw_coverage_best d3 ON d3.country_code = d1.country_code AND d3.year = d1.year AND d3.antigen_code = 'DTPCV3'
JOIN dim_country c ON c.country_code = d1.country_code
WHERE d1.antigen_code = 'DTPCV1' AND d1.year = 2023 AND d1.coverage_pct > 0
GROUP BY c.who_region ORDER BY mean_dropout_pct DESC;

-- Q6. Does higher measles coverage go with lower incidence? Average incidence by MCV1 coverage band (2000+)
SELECT CASE WHEN coverage_pct < 50 THEN '1: <50' WHEN coverage_pct < 70 THEN '2: 50-70' WHEN coverage_pct < 80 THEN '3: 70-80'
            WHEN coverage_pct < 90 THEN '4: 80-90' WHEN coverage_pct < 95 THEN '5: 90-95' ELSE '6: 95-100' END AS mcv1_band,
       COUNT(*) AS country_years,
       ROUND(AVG(incidence_reported), 1) AS mean_incidence_per_million,
       ROUND(SUM(cases) * 1.0 / COUNT(cases), 0) AS mean_cases
FROM vw_coverage_vs_incidence
WHERE antigen_code = 'MCV1' AND disease_code = 'MEASLES' AND year >= 2000 AND incidence_reported IS NOT NULL
GROUP BY mcv1_band ORDER BY mcv1_band;

-- Q7. High incidence despite high coverage: measles, MCV1 >= 90% and > 100 cases per million (2023)
SELECT c.country_name, c.who_region, v.coverage_pct AS mcv1, v.incidence_reported AS measles_per_million, v.cases
FROM vw_coverage_vs_incidence v JOIN dim_country c ON c.country_code = v.country_code
WHERE v.antigen_code = 'MCV1' AND v.disease_code = 'MEASLES' AND v.year = 2023
  AND v.coverage_pct >= 90 AND v.incidence_reported > 100
ORDER BY v.incidence_reported DESC;

-- Q8. Diseases with the largest reduction: global reported cases, 1980-82 average vs 2023
WITH base AS (SELECT disease_code, AVG(cases) AS avg_1980_82 FROM fact_disease_burden_group
              WHERE group_type = 'GLOBAL' AND year BETWEEN 1980 AND 1982 GROUP BY disease_code),
     now_ AS (SELECT disease_code, cases AS cases_2023 FROM fact_disease_burden_group WHERE group_type = 'GLOBAL' AND year = 2023)
SELECT d.disease_name, ROUND(b.avg_1980_82) AS cases_1980_82, n.cases_2023,
       ROUND((1 - n.cases_2023 / b.avg_1980_82) * 100, 1) AS pct_reduction
FROM base b JOIN now_ n ON n.disease_code = b.disease_code JOIN dim_disease d ON d.disease_code = b.disease_code
WHERE b.avg_1980_82 > 0
ORDER BY pct_reduction DESC;

-- Q9. Before / after vaccine introduction: mean measles incidence 3 years before vs 3 years after MCV2 introduction
SELECT COUNT(*) AS countries, ROUND(AVG(before_inc), 1) AS mean_before, ROUND(AVG(after_inc), 1) AS mean_after
FROM (
    SELECT fi.country_code,
           (SELECT AVG(b.incidence_reported) FROM fact_disease_burden b WHERE b.country_code = fi.country_code AND b.disease_code = 'MEASLES'
              AND b.year BETWEEN fi.first_year - 3 AND fi.first_year - 1) AS before_inc,
           (SELECT AVG(b.incidence_reported) FROM fact_disease_burden b WHERE b.country_code = fi.country_code AND b.disease_code = 'MEASLES'
              AND b.year BETWEEN fi.first_year + 1 AND fi.first_year + 3) AS after_inc
    FROM vw_first_introduction fi
    WHERE fi.vaccine_description = 'Measles-containing vaccine 2nd dose' AND fi.first_year BETWEEN 1985 AND 2019
) x
WHERE before_inc IS NOT NULL AND after_inc IS NOT NULL AND before_inc > 0;

-- Q10. Introduction timeline disparities: average first-introduction year by WHO region and vaccine
SELECT fi.vaccine_description, c.who_region, ROUND(AVG(fi.first_year), 0) AS mean_intro_year, COUNT(*) AS countries
FROM vw_first_introduction fi JOIN dim_country c ON c.country_code = fi.country_code
WHERE fi.vaccine_description IN ('Hepatitis B vaccine','Measles-containing vaccine 2nd dose','Rubella vaccine','PCV (Pneumococcal conjugate vaccine)',
                                 'Rotavirus vaccine','HPV (Human Papilloma Virus) vaccine')
GROUP BY fi.vaccine_description, c.who_region ORDER BY fi.vaccine_description, mean_intro_year;

-- Q11. Vaccine available but coverage low: nationwide introduction in 2023 yet coverage < 70%
SELECT iv.vaccine_description, COUNT(*) AS countries_introduced,
       SUM(CASE WHEN v.coverage_pct < 70 THEN 1 ELSE 0 END) AS below_70,
       ROUND(100.0 * SUM(CASE WHEN v.coverage_pct < 70 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_below_70
FROM fact_vaccine_intro f
JOIN dim_intro_status s  ON s.status_code = f.status_code AND s.is_nationwide = 1
JOIN dim_intro_vaccine iv ON iv.intro_vaccine_id = f.intro_vaccine_id AND iv.linked_antigen_code IS NOT NULL
JOIN vw_coverage_best v   ON v.country_code = f.country_code AND v.year = f.year AND v.antigen_code = iv.linked_antigen_code
WHERE f.year = 2023
GROUP BY iv.vaccine_description HAVING COUNT(*) >= 30
ORDER BY pct_below_70 DESC;

-- Q12. Coverage gaps for TB (BCG) and Hepatitis B: countries below 80% in 2023
SELECT v.antigen_code, COUNT(*) AS countries_reporting,
       SUM(CASE WHEN v.coverage_pct < 80 THEN 1 ELSE 0 END) AS below_80,
       SUM(CASE WHEN v.coverage_pct < 50 THEN 1 ELSE 0 END) AS below_50
FROM vw_coverage_best v
WHERE v.year = 2023 AND v.antigen_code IN ('BCG','HEPB3','HEPB_BD')
GROUP BY v.antigen_code;

-- Q13. Income-group disparity in DTP3 coverage (World-Bank groups), 2019 vs 2023
SELECT g.group_name, MAX(CASE WHEN f.year = 2019 THEN f.coverage_pct END) AS dtp3_2019,
                     MAX(CASE WHEN f.year = 2023 THEN f.coverage_pct END) AS dtp3_2023
FROM fact_coverage_group f JOIN dim_group g ON g.group_type = f.group_type AND g.group_code = f.group_code
WHERE f.group_type = 'WB_LONG' AND f.category_code = 'WUENIC' AND f.antigen_code = 'DTPCV3' AND f.year IN (2019, 2023)
  AND g.group_name <> 'Not classified'
GROUP BY g.group_name ORDER BY dtp3_2023;

-- Q14. Schedule design: number of routine measles-containing doses per country vs MCV1 / MCV2 coverage (2023)
SELECT sc.max_round AS doses_in_schedule, COUNT(*) AS countries,
       ROUND(AVG(m1.coverage_pct), 1) AS mean_mcv1, ROUND(AVG(m2.coverage_pct), 1) AS mean_mcv2
FROM (SELECT country_code, MAX(schedule_round) AS max_round
      FROM fact_vaccine_schedule
      WHERE year = 2023 AND target_pop_code = 'ROUTINE' AND vaccine_code IN ('MEASLES','MR','MMR','MMRV','MM')
      GROUP BY country_code) sc
LEFT JOIN vw_coverage_best m1 ON m1.country_code = sc.country_code AND m1.year = 2023 AND m1.antigen_code = 'MCV1'
LEFT JOIN vw_coverage_best m2 ON m2.country_code = sc.country_code AND m2.year = 2023 AND m2.antigen_code = 'MCV2'
GROUP BY sc.max_round ORDER BY sc.max_round;

-- Q15. Progress to the 95% measles target: countries at or above 95% (2023)
SELECT antigen_code, COUNT(*) AS countries, SUM(CASE WHEN coverage_pct >= 95 THEN 1 ELSE 0 END) AS at_or_above_95,
       ROUND(100.0 * SUM(CASE WHEN coverage_pct >= 95 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_countries
FROM vw_coverage_best WHERE year = 2023 AND antigen_code IN ('MCV1','MCV2') GROUP BY antigen_code;

-- Q16. Influenza readiness: countries with a national seasonal-influenza programme by WHO region (2023)
SELECT c.who_region, COUNT(*) AS countries, SUM(s.is_introduced) AS with_programme,
       ROUND(100.0 * SUM(s.is_introduced) / COUNT(*), 0) AS pct
FROM fact_vaccine_intro f
JOIN dim_intro_vaccine iv ON iv.intro_vaccine_id = f.intro_vaccine_id AND iv.vaccine_description = 'Seasonal Influenza vaccine'
JOIN dim_intro_status s ON s.status_code = f.status_code
JOIN dim_country c ON c.country_code = f.country_code
WHERE f.year = 2023 GROUP BY c.who_region ORDER BY pct;

-- Q17. Polio: share of country-years reporting polio cases by polio-vaccine (POL3) coverage band
SELECT CASE WHEN coverage_pct <= 20 THEN '1: 0-20' WHEN coverage_pct <= 50 THEN '2: 21-50' WHEN coverage_pct <= 80 THEN '3: 51-80'
            WHEN coverage_pct <= 90 THEN '4: 81-90' ELSE '5: 91-100' END AS pol3_band,
       COUNT(*) AS country_years, SUM(CASE WHEN cases > 0 THEN 1 ELSE 0 END) AS with_cases,
       ROUND(100.0 * SUM(CASE WHEN cases > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_with_cases
FROM vw_coverage_vs_incidence WHERE antigen_code = 'POL3' AND disease_code = 'POLIO' AND cases IS NOT NULL
GROUP BY pol3_band ORDER BY pol3_band;
