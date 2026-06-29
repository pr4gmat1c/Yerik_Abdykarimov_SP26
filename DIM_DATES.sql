-- =============================================================================
-- BL_DM.DIM_DATES — Calendar Date Dimension
-- =============================================================================
-- Grain: one row per calendar day.
--
-- Why this table is built differently from every other DIM_ table:
--   The Date dimension has no outside source and never changes once loaded
--   (Type 0) - per the courseware ("Introduction to DWH and ETL — Dimension &
--   Fact Table Techniques", Section 2.3), it is generated once by the ETL system
--   itself and is never re-populated from BL_3NF on a nightly load like
--   DIM_PRODUCTS, DIM_CUSTOMERS_SCD, etc.
--   The same courseware section also notes that on PostgreSQL there is no
--   need for a YYYYMMDD smart-key integer: the native DATE type is used
--   directly as the primary key (DATE_KEY), because PostgreSQL already
--   represents and indexes DATE efficiently.
--   The table is still named DIM_DATES (rather than the Naming Conventions'
--   generic DIM_TIME_<Level> pattern) because that is the literal table name
--   required by this assignment; grain = Day, so an equivalent alias would be
--   DIM_TIME_DAY.
--
-- Range loaded: 2020-01-01 .. 2030-12-31 (4,018 days). This comfortably
-- covers both source extracts' order-date range (19-Jun-2024 .. 18-Jun-2026)
-- with multi-year buffer on both sides for re-runs, backfills and future
-- loads, without having to re-run this script again soon.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS BL_DM;

DROP TABLE IF EXISTS BL_DM.DIM_DATES;

CREATE TABLE BL_DM.DIM_DATES (
    DATE_KEY               DATE          NOT NULL,   -- PK. Native PostgreSQL DATE, not a YYYYMMDD smart key
    DAY_OF_WEEK_NUMBER      INT           NOT NULL,   -- 1 = Sunday ... 7 = Saturday
    DAY_OF_WEEK_DESC        VARCHAR(25)   NOT NULL,   -- 'Sunday' ... 'Saturday'
    WEEKEND_FLAG            INT           NOT NULL,   -- 1 = Saturday/Sunday, 0 = weekday
    ISO_WEEK_NUMBER         INT           NOT NULL,   -- 1..53, ISO-8601 week-of-year
    DAY_OF_MONTH_NUMBER     INT           NOT NULL,   -- 1..31
    MONTH_VALUE             VARCHAR(2)    NOT NULL,   -- '01'..'12'
    MONTH_DESC              VARCHAR(25)   NOT NULL,   -- 'January'..'December'
    QUARTER_VALUE           VARCHAR(1)    NOT NULL,   -- '1'..'4'
    QUARTER_DESC            VARCHAR(2)    NOT NULL,   -- 'Q1'..'Q4'
    YEAR_VALUE              VARCHAR(4)    NOT NULL,   -- '2020'..'2030'
    INSERT_DT               DATE          NOT NULL,   -- date this row was generated (Type 0: no UPDATE_DT — the table is never updated)
    SOURCE_SYSTEM           VARCHAR(60)   NOT NULL,   -- 'MANUAL' — built by the ETL system itself, no outside source
    SOURCE_TABLE            VARCHAR(60)   NOT NULL,   -- 'MANUAL'
    CONSTRAINT PK_DIM_DATES PRIMARY KEY (DATE_KEY)
);

-- -----------------------------------------------------------------------------
-- Populate: one row per calendar day, 2020-01-01 .. 2030-12-31
-- -----------------------------------------------------------------------------
INSERT INTO BL_DM.DIM_DATES (
    DATE_KEY, DAY_OF_WEEK_NUMBER, DAY_OF_WEEK_DESC, WEEKEND_FLAG,
    ISO_WEEK_NUMBER, DAY_OF_MONTH_NUMBER, MONTH_VALUE, MONTH_DESC,
    QUARTER_VALUE, QUARTER_DESC, YEAR_VALUE, INSERT_DT, SOURCE_SYSTEM, SOURCE_TABLE
)
SELECT
    gs::DATE                                            AS DATE_KEY,
    (EXTRACT(DOW FROM gs)::INT + 1)                     AS DAY_OF_WEEK_NUMBER,   -- PostgreSQL DOW: 0=Sun..6=Sat, so +1 gives 1=Sun..7=Sat
    TRIM(TO_CHAR(gs, 'Day'))                            AS DAY_OF_WEEK_DESC,
    CASE WHEN EXTRACT(ISODOW FROM gs) IN (6, 7)
         THEN 1 ELSE 0 END                              AS WEEKEND_FLAG,         -- ISODOW: 6=Saturday, 7=Sunday
    EXTRACT(WEEK FROM gs)::INT                          AS ISO_WEEK_NUMBER,
    EXTRACT(DAY FROM gs)::INT                           AS DAY_OF_MONTH_NUMBER,
    TO_CHAR(gs, 'MM')                                   AS MONTH_VALUE,
    TRIM(TO_CHAR(gs, 'Month'))                          AS MONTH_DESC,
    EXTRACT(QUARTER FROM gs)::VARCHAR(1)                AS QUARTER_VALUE,
    'Q' || EXTRACT(QUARTER FROM gs)::VARCHAR(1)         AS QUARTER_DESC,
    TO_CHAR(gs, 'YYYY')                                 AS YEAR_VALUE,
    CURRENT_DATE                                        AS INSERT_DT,
    'MANUAL'                                            AS SOURCE_SYSTEM,
    'MANUAL'                                            AS SOURCE_TABLE
FROM generate_series('2020-01-01'::DATE, '2030-12-31'::DATE, INTERVAL '1 day') AS gs;

-- -----------------------------------------------------------------------------
-- Dedicated default row for unknown / to-be-determined dates
-- (courseware Section 2.3: "the date dimension table needs a special row to
-- represent unknown or to-be-determined dates"). 1900-01-01 is used purely
-- as a recognisable sentinel value, consistent with this project's existing
-- -1 / 'n.a.' default-row convention (BL_3NF Section 2) adapted to a DATE
-- column that cannot itself hold -1 or 'n.a.'.
-- -----------------------------------------------------------------------------
INSERT INTO BL_DM.DIM_DATES (
    DATE_KEY, DAY_OF_WEEK_NUMBER, DAY_OF_WEEK_DESC, WEEKEND_FLAG,
    ISO_WEEK_NUMBER, DAY_OF_MONTH_NUMBER, MONTH_VALUE, MONTH_DESC,
    QUARTER_VALUE, QUARTER_DESC, YEAR_VALUE, INSERT_DT, SOURCE_SYSTEM, SOURCE_TABLE
) VALUES (
    '1900-01-01', -1, 'n.a.', -1, -1, -1, '00', 'n.a.', '0', 'NA', '0000',
    CURRENT_DATE, 'MANUAL', 'MANUAL'
);

-- -----------------------------------------------------------------------------
-- Sanity checks
-- -----------------------------------------------------------------------------
-- Expect 4,019 rows: 4,018 calendar days (2020-01-01..2030-12-31 inclusive) + 1 default row
SELECT COUNT(*) AS row_count FROM BL_DM.DIM_DATES;

-- Spot-check a known date
SELECT * FROM BL_DM.DIM_DATES WHERE DATE_KEY = '2025-12-25';
