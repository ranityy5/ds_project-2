// Power Query (M) - load the cleaned CSV tables with the right data types.
// 1) Home > Transform data > New Source > Blank Query > Advanced Editor > paste this code, name the query  fnCsv
// 2) For every table: New Source > Blank Query, and type in the formula bar:   = fnCsv("dim_country")   (then rename the query)
//    Tables: dim_country, dim_year, dim_disease, dim_antigen, dim_coverage_category, dim_group, dim_intro_vaccine, dim_intro_status,
//            dim_schedule_vaccine, dim_target_pop, fact_coverage, fact_coverage_group, fact_disease_burden, fact_disease_burden_group,
//            fact_vaccine_intro, fact_vaccine_schedule, mart_coverage_vs_incidence, mart_first_introduction, and mart_coverage_best
//            (rename mart_coverage_best -> fact_coverage_best)
// 3) Change DataFolder to the folder that holds the CSV files.  (Not needed if you connect to the SQL database instead.)
let
    DataFolder = "C:\Users\ranit\Downloads\Vaccination_Project_Package\cleaned_data\",
    IntCols    = {"year", "first_year", "schedule_round", "schedule_id", "intro_vaccine_id", "priority_rank", "is_covid_period",
                  "is_introduced", "is_nationwide", "is_booster_or_later_dose", "coverage_was_recomputed", "coverage_gt100_flag"},
    NumCols    = {"target_number", "target_any", "doses", "coverage_raw", "coverage_pct", "incidence_reported", "cases",
                  "incidence_per_100k", "to_per_100k_factor", "age_months"},
    fnCsv = (name as text) as table =>
        let
            Source  = Csv.Document(File.Contents(DataFolder & name & ".csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
            Headers = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),
            Types   = List.Transform(Table.ColumnNames(Headers),
                        each {_, if List.Contains(IntCols, _) then Int64.Type else if List.Contains(NumCols, _) then type number else type text}),
            Typed   = Table.TransformColumnTypes(Headers, Types, "en-US")
        in
            Typed
in
    fnCsv
