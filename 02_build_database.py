"""Build the vaccination SQL database from the cleaned CSVs.

Usage
-----
    python 02_build_database.py                      # creates vaccination.db (SQLite) next to this file
    python 02_build_database.py --csv ../cleaned_data --db vaccination.db

For MySQL / PostgreSQL / SQL Server: run 01_create_schema.sql on the server, then load the CSVs
(see ../powerbi/README_POWERBI.md, section "Connect to a server database"), or use
    python 02_build_database.py --url "mysql+pymysql://user:pass@host/vaccination"      (needs sqlalchemy + a driver)
"""
import argparse, os, sqlite3, sys
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ["dim_country", "dim_year", "dim_disease", "dim_antigen", "bridge_antigen_disease", "dim_coverage_category", "dim_group",
         "dim_intro_vaccine", "dim_intro_status", "dim_schedule_vaccine", "dim_target_pop",
         "fact_coverage", "fact_coverage_group", "fact_disease_burden", "fact_disease_burden_group", "fact_vaccine_intro", "fact_vaccine_schedule"]


def read_table(csv_dir, name):
    df = pd.read_csv(os.path.join(csv_dir, f"{name}.csv"))
    # SQL integers: pandas turns integer columns with blanks into floats -> keep them clean
    for col in df.columns:
        if col in ("year", "schedule_round", "schedule_id", "intro_vaccine_id", "is_covid_period", "is_introduced", "is_nationwide",
                   "priority_rank", "is_booster_or_later_dose", "coverage_was_recomputed", "coverage_gt100_flag"):
            df[col] = df[col].astype("Int64")
    return df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=os.path.join(HERE, "..", "cleaned_data"))
    ap.add_argument("--db", default=os.path.join(HERE, "vaccination.db"))
    ap.add_argument("--url", default=None, help="optional SQLAlchemy URL for a server database (schema must already exist)")
    a = ap.parse_args()

    if a.url:
        from sqlalchemy import create_engine          # only needed for server databases
        eng = create_engine(a.url)
        for t in ORDER:
            df = read_table(a.csv, t); df.to_sql(t, eng, if_exists="append", index=False, chunksize=20000)
            print(f"loaded {t:28s} {len(df):>8,}")
        return

    if os.path.exists(a.db):
        os.remove(a.db)
    con = sqlite3.connect(a.db)
    con.execute("PRAGMA foreign_keys = ON")           # enforce the foreign keys while loading
    con.executescript(open(os.path.join(HERE, "01_create_schema.sql"), encoding="utf-8").read())
    for t in ORDER:
        df = read_table(a.csv, t)
        df = df.astype(object).where(df.notna(), None)   # NaN -> NULL
        cols = ",".join(df.columns); ph = ",".join("?" * len(df.columns))
        con.executemany(f"INSERT INTO {t} ({cols}) VALUES ({ph})", df.itertuples(index=False, name=None))
        print(f"loaded {t:28s} {len(df):>8,} rows")
    con.commit()
    bad = con.execute("PRAGMA foreign_key_check").fetchall()
    print("foreign key violations:", len(bad))
    con.execute("VACUUM"); con.close()
    print("database written to", a.db, f"({os.path.getsize(a.db) / 1e6:.1f} MB)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
