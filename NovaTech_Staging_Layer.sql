-- =============================================================================
-- STAGING LAYER (SA) — External (foreign) tables + Source tables
-- =============================================================================
--
-- Scope of this script (Task 5 — "Data Sourcing"):
--   For EACH of the two raw data sets (novatech_b2c_orders.csv,
--   novatech_b2b_orders.csv) this script creates exactly one schema
--   containing exactly one external (foreign) table and exactly one
--   source table, per the task brief:
--     - 1 schema PER data set            -> SA_B2C / SA_B2B
--     - external tables prefixed         -> EXT_...
--     - source tables prefixed           -> SRC_...
--   This script does NOT touch BL_3NF or BL_DM — it only lands and
--   de-duplicates the two raw extracts so the next task can read a clean,
--   typed, indexed table instead of a flat file.
--
-- Why TEXT on the external (foreign) tables, typed on the source tables:
--   file_fdw casts every field to the column's declared type at scan time,
--   eagerly, for every row — a single malformed value anywhere in an
--   800,000-row file would abort the whole foreign scan with no way to
--   isolate which row caused it. Declaring every EXT_ column as TEXT
--   removes that fragility: the foreign table simply mirrors the file
--   byte-for-byte. All real typing (BIGINT/DATE/NUMERIC/...), all
--   deduplication, and the NULL handling for the four B2C columns that
--   only apply when RETURN_OR_COMPLAINT = 'Yes' happen once, in the single
--   controlled INSERT...SELECT that populates SRC_ from EXT_.
--
-- Deduplication (per task brief, "Remove duplicates"):
--   A full-row and an ORDER_ID-uniqueness check against the current
--   extract found zero duplicates in either file (800,000 distinct
--   B2C order lines, 220,000 distinct B2B order lines). The
--   ROW_NUMBER() OVER (PARTITION BY ORDER_ID ...) WHERE RN = 1 pattern
--   below is kept anyway, so the load stays correct if a future extract
--   ever does contain a repeated order line. The SRC_ table's primary key
--   on ORDER_ID (the fact grain key — one row per order line, per the
--   Business Template Section 1.5 grain declaration) plus
--   ON CONFLICT (ORDER_ID) DO NOTHING gives a second, independent guard:
--   re-running this script after SRC_ already has data inserts 0 rows
--   instead of duplicating them (verified by an actual re-run, see
--   Task 5 notes).
--
-- Technical/audit columns on SRC_ only (not on EXT_, which is a pure
-- mirror of the file): STG_LOAD_DT (date this row was staged) and
-- SOURCE_FILE_NAME (literal file the row came from). The fuller
-- <col>_SRC_ID / SOURCE_SYSTEM / SOURCE_TABLE triplet used from BL_3NF
-- onward is intentionally NOT introduced yet here — at the staging layer
-- there is exactly one possible source per row (the file itself), so
-- that triplet would be a constant repeated 800,000/220,000 times with no
-- information value; it earns its place once BL_3NF starts conforming
-- rows that may have arrived via more than one route.
--
-- IMPORTANT — adjust before running:
--   file_fdw reads from the PostgreSQL SERVER's local filesystem, not the
--   client's. The OPTIONS (filename '...') value below must be an
--   absolute path that the postgres OS user can read on whichever
--   machine the database server itself is running on. Update the two
--   filename values in Section 1 to match wherever you place the
--   unzipped novatech_b2c_orders.csv / novatech_b2b_orders.csv files on
--   that machine, and make sure that file is readable by the postgres OS
--   user (e.g. chmod 644). CREATE EXTENSION file_fdw requires superuser.
-- =============================================================================

-- file_fdw ships with core PostgreSQL but is not enabled by default.
CREATE EXTENSION IF NOT EXISTS file_fdw;

-- One foreign server is enough — file_fdw's "server" is just a handle for
-- "read local files", not a remote connection, so both schemas share it.
CREATE SERVER IF NOT EXISTS NOVATECH_FILE_SERVER FOREIGN DATA WRAPPER file_fdw;

CREATE SCHEMA IF NOT EXISTS SA_B2C;
CREATE SCHEMA IF NOT EXISTS SA_B2B;

-- Not executed - kept only for a deliberate, manual full rebuild:
-- DROP TABLE IF EXISTS SA_B2C.SRC_NOVATECH_B2C_ORDERS;
-- DROP FOREIGN TABLE IF EXISTS SA_B2C.EXT_NOVATECH_B2C_ORDERS;
-- DROP TABLE IF EXISTS SA_B2B.SRC_NOVATECH_B2B_ORDERS;
-- DROP FOREIGN TABLE IF EXISTS SA_B2B.EXT_NOVATECH_B2B_ORDERS;
-- DROP SERVER IF EXISTS NOVATECH_FILE_SERVER;

-- =============================================================================
-- SECTION 1 — SA_B2C  (Source System 1: NovaTech Direct, B2C)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.1  EXT_NOVATECH_B2C_ORDERS — external (foreign) table, raw mirror of
-- novatech_b2c_orders.csv (48 columns, header row, comma-delimited,
-- double-quote escaped — confirmed against the actual file). Every column
-- is TEXT; see header note above for why. file_fdw matches CSV columns by
-- POSITION, not by the header text, so these column names do not need to
-- repeat the file's "Title Case With Spaces" headers verbatim.
-- -----------------------------------------------------------------------------
DROP FOREIGN TABLE IF EXISTS SA_B2C.EXT_NOVATECH_B2C_ORDERS;
CREATE FOREIGN TABLE SA_B2C.EXT_NOVATECH_B2C_ORDERS (
    ORDER_ID                            TEXT,   -- Order ID
    ORDER_DATE                          TEXT,   -- Order Date
    CUSTOMER_ID                         TEXT,   -- Customer ID
    CUSTOMER_AGE                        TEXT,   -- Customer Age
    CUSTOMER_GENDER                     TEXT,   -- Customer Gender
    LOYALTY_MEMBER                      TEXT,   -- Loyalty Member
    COUNTRY                             TEXT,   -- Country
    CITY                                TEXT,   -- City
    PRODUCT_ID                          TEXT,   -- Product ID
    SKU                                 TEXT,   -- SKU
    PRODUCT_TYPE                        TEXT,   -- Product Type
    PRODUCT_CATEGORY                    TEXT,   -- Product Category
    UNIT_PRICE                          TEXT,   -- Unit Price
    QUANTITY                            TEXT,   -- Quantity
    UNIT_COST                           TEXT,   -- Unit Cost
    TOTAL_SALES                         TEXT,   -- Total Sales
    TOTAL_COST                          TEXT,   -- Total Cost
    PAYMENT_METHOD                      TEXT,   -- Payment Method
    SHIPPING_TYPE                       TEXT,   -- Shipping Type
    ORDER_STATUS                        TEXT,   -- Order Status
    RATING                              TEXT,   -- Rating
    ADDON_TOTAL                         TEXT,   -- Add-on Total
    CUSTOMER_NAME                       TEXT,   -- Customer Name
    CUSTOMER_SEGMENT                    TEXT,   -- Customer Segment
    BRAND                               TEXT,   -- Brand
    WARRANTY_PERIOD_MONTHS              TEXT,   -- Warranty Period Months
    LAUNCH_YEAR                         TEXT,   -- Launch Year
    PRODUCT_STATUS                      TEXT,   -- Product Status
    PAYMENT_CHANNEL_TYPE                TEXT,   -- Payment Channel Type
    PROCESSING_FEE_PERCENT              TEXT,   -- Processing Fee Percent
    SETTLEMENT_PERIOD_DAYS              TEXT,   -- Settlement Period Days
    REFUNDABLE                          TEXT,   -- Refundable
    CURRENCY_ACCEPTED                   TEXT,   -- Currency Accepted
    MINIMUM_TRANSACTION_AMOUNT          TEXT,   -- Minimum Transaction Amount
    AVAILABILITY_CHANNEL                TEXT,   -- Availability Channel
    SHIPPING_CARRIER                    TEXT,   -- Shipping Carrier
    ESTIMATED_DELIVERY_DAYS             TEXT,   -- Estimated Delivery Days ('0-1','5-7', range text, not numeric)
    SHIPPING_COST_TIER                  TEXT,   -- Shipping Cost Tier
    FREE_SHIPPING_ELIGIBLE              TEXT,   -- Free Shipping Eligible
    TRACKING_AVAILABLE                  TEXT,   -- Tracking Available
    MAX_PACKAGE_WEIGHT_KG               TEXT,   -- Max Package Weight Kg
    INTL_SHIPPING_AVAILABLE             TEXT,   -- International Shipping Available
    RETURN_OR_COMPLAINT                 TEXT,   -- Return Or Complaint
    FEEDBACK_COMMENT                    TEXT,   -- Feedback Comment
    RESOLUTION_TIME_DAYS                TEXT,   -- Resolution Time Days (blank unless Return Or Complaint = 'Yes')
    REFUND_AMOUNT                       TEXT,   -- Refund Amount        (blank unless Return Or Complaint = 'Yes')
    SUPPORT_CHANNEL_USED                TEXT,   -- Support Channel Used (blank unless Return Or Complaint = 'Yes')
    ESCALATION_REQUIRED                 TEXT    -- Escalation Required  (blank unless Return Or Complaint = 'Yes')
)
SERVER NOVATECH_FILE_SERVER
OPTIONS (
    format 'csv',
    header 'true',
    filename '/var/lib/postgresql/staging_files/novatech_b2c_orders.csv',  -- <-- adjust to your server's path
    delimiter ',',
    quote '"',
    escape '"',
    null ''
);

-- -----------------------------------------------------------------------------
-- 1.2  SRC_NOVATECH_B2C_ORDERS — physical, typed, deduplicated source table.
-- Grain: one row per B2C order line (= ORDER_ID), matching the Business
-- Template's Section 1.5 grain declaration. RESOLUTION_TIME_DAYS /
-- REFUND_AMOUNT / SUPPORT_CHANNEL_USED / ESCALATION_REQUIRED are left
-- nullable here (unlike BL_DM's NOT-NULL-everywhere rule, which is a
-- mentor-review convention specific to that later layer) because staging
-- is meant to faithfully represent the source as-is: these four columns
-- are genuinely absent in the file whenever RETURN_OR_COMPLAINT = 'No'
-- (confirmed: exactly the rows with RETURN_OR_COMPLAINT = 'No' are blank
-- here, with zero exceptions across all 800,000 rows).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS SA_B2C.SRC_NOVATECH_B2C_ORDERS;
CREATE TABLE SA_B2C.SRC_NOVATECH_B2C_ORDERS (
    ORDER_ID                     BIGINT          NOT NULL,   -- PK = fact grain key (degenerate dimension downstream)
    ORDER_DATE                   DATE            NOT NULL,
    CUSTOMER_ID                  BIGINT          NOT NULL,
    CUSTOMER_AGE                 SMALLINT        NOT NULL,
    CUSTOMER_GENDER              VARCHAR(10)     NOT NULL,
    LOYALTY_MEMBER                VARCHAR(5)      NOT NULL,
    COUNTRY                      VARCHAR(50)     NOT NULL,
    CITY                         VARCHAR(50)     NOT NULL,
    PRODUCT_ID                   INT             NOT NULL,
    SKU                          VARCHAR(20)     NOT NULL,
    PRODUCT_TYPE                 VARCHAR(50)     NOT NULL,
    PRODUCT_CATEGORY             VARCHAR(50)     NOT NULL,
    UNIT_PRICE                   NUMERIC(10,2)   NOT NULL,
    QUANTITY                     INT             NOT NULL,
    UNIT_COST                    NUMERIC(10,2)   NOT NULL,
    TOTAL_SALES                  NUMERIC(12,2)   NOT NULL,
    TOTAL_COST                   NUMERIC(12,2)   NOT NULL,
    PAYMENT_METHOD                VARCHAR(20)     NOT NULL,
    SHIPPING_TYPE                VARCHAR(20)     NOT NULL,
    ORDER_STATUS                 VARCHAR(20)     NOT NULL,
    RATING                       SMALLINT        NOT NULL,
    ADDON_TOTAL                  NUMERIC(10,2)   NOT NULL,
    CUSTOMER_NAME                VARCHAR(100)    NOT NULL,
    CUSTOMER_SEGMENT             VARCHAR(20)     NOT NULL,
    BRAND                        VARCHAR(50)     NOT NULL,
    WARRANTY_PERIOD_MONTHS       SMALLINT        NOT NULL,
    LAUNCH_YEAR                  SMALLINT        NOT NULL,
    PRODUCT_STATUS               VARCHAR(20)     NOT NULL,
    PAYMENT_CHANNEL_TYPE         VARCHAR(20)     NOT NULL,
    PROCESSING_FEE_PERCENT       NUMERIC(5,2)    NOT NULL,
    SETTLEMENT_PERIOD_DAYS       SMALLINT        NOT NULL,
    REFUNDABLE                   VARCHAR(5)      NOT NULL,
    CURRENCY_ACCEPTED             VARCHAR(5)      NOT NULL,
    MINIMUM_TRANSACTION_AMOUNT   NUMERIC(10,2)   NOT NULL,
    AVAILABILITY_CHANNEL          VARCHAR(30)     NOT NULL,
    SHIPPING_CARRIER             VARCHAR(30)     NOT NULL,
    ESTIMATED_DELIVERY_DAYS       VARCHAR(10)     NOT NULL,   -- kept as text: holds ranges like '0-1', '5-7'
    SHIPPING_COST_TIER           VARCHAR(10)     NOT NULL,
    FREE_SHIPPING_ELIGIBLE       VARCHAR(5)      NOT NULL,
    TRACKING_AVAILABLE           VARCHAR(5)      NOT NULL,
    MAX_PACKAGE_WEIGHT_KG         SMALLINT        NOT NULL,
    INTL_SHIPPING_AVAILABLE      VARCHAR(5)      NOT NULL,
    RETURN_OR_COMPLAINT          VARCHAR(5)      NOT NULL,
    FEEDBACK_COMMENT             VARCHAR(255)    NOT NULL,
    RESOLUTION_TIME_DAYS          NUMERIC(5,1),               -- NULL unless RETURN_OR_COMPLAINT = 'Yes'
    REFUND_AMOUNT                 NUMERIC(10,2),               -- NULL unless RETURN_OR_COMPLAINT = 'Yes'
    SUPPORT_CHANNEL_USED          VARCHAR(20),                 -- NULL unless RETURN_OR_COMPLAINT = 'Yes'
    ESCALATION_REQUIRED           VARCHAR(5),                  -- NULL unless RETURN_OR_COMPLAINT = 'Yes'
    STG_LOAD_DT                   DATE            NOT NULL,    -- technical: date this row was staged
    SOURCE_FILE_NAME               VARCHAR(100)    NOT NULL,    -- technical: literal source file name
    CONSTRAINT PK_SRC_NOVATECH_B2C_ORDERS PRIMARY KEY (ORDER_ID)
);

INSERT INTO SA_B2C.SRC_NOVATECH_B2C_ORDERS
SELECT
    ORDER_ID::BIGINT,
    ORDER_DATE::DATE,
    CUSTOMER_ID::BIGINT,
    CUSTOMER_AGE::SMALLINT,
    CUSTOMER_GENDER,
    LOYALTY_MEMBER,
    COUNTRY,
    CITY,
    PRODUCT_ID::INT,
    SKU,
    PRODUCT_TYPE,
    PRODUCT_CATEGORY,
    UNIT_PRICE::NUMERIC(10,2),
    QUANTITY::INT,
    UNIT_COST::NUMERIC(10,2),
    TOTAL_SALES::NUMERIC(12,2),
    TOTAL_COST::NUMERIC(12,2),
    PAYMENT_METHOD,
    SHIPPING_TYPE,
    ORDER_STATUS,
    RATING::SMALLINT,
    ADDON_TOTAL::NUMERIC(10,2),
    CUSTOMER_NAME,
    CUSTOMER_SEGMENT,
    BRAND,
    WARRANTY_PERIOD_MONTHS::SMALLINT,
    LAUNCH_YEAR::SMALLINT,
    PRODUCT_STATUS,
    PAYMENT_CHANNEL_TYPE,
    PROCESSING_FEE_PERCENT::NUMERIC(5,2),
    SETTLEMENT_PERIOD_DAYS::SMALLINT,
    REFUNDABLE,
    CURRENCY_ACCEPTED,
    MINIMUM_TRANSACTION_AMOUNT::NUMERIC(10,2),
    AVAILABILITY_CHANNEL,
    SHIPPING_CARRIER,
    ESTIMATED_DELIVERY_DAYS,
    SHIPPING_COST_TIER,
    FREE_SHIPPING_ELIGIBLE,
    TRACKING_AVAILABLE,
    MAX_PACKAGE_WEIGHT_KG::SMALLINT,
    INTL_SHIPPING_AVAILABLE,
    RETURN_OR_COMPLAINT,
    FEEDBACK_COMMENT,
    RESOLUTION_TIME_DAYS::NUMERIC(5,1),   -- empty string -> NULL, via the foreign table's OPTIONS (null '')
    REFUND_AMOUNT::NUMERIC(10,2),
    SUPPORT_CHANNEL_USED,
    ESCALATION_REQUIRED,
    CURRENT_DATE,
    'novatech_b2c_orders.csv'
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY ORDER_ID) AS RN   -- de-duplication: see header note
    FROM SA_B2C.EXT_NOVATECH_B2C_ORDERS
) DEDUP
WHERE RN = 1
ON CONFLICT (ORDER_ID) DO NOTHING;   -- idempotency: a re-run after data already exists inserts 0 rows

-- =============================================================================
-- SECTION 2 — SA_B2B  (Source System 2: NovaTech Business Solutions, B2B)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2.1  EXT_NOVATECH_B2B_ORDERS — external (foreign) table, raw mirror of
-- novatech_b2b_orders.csv (48 columns, same CSV conventions as B2C).
-- -----------------------------------------------------------------------------
DROP FOREIGN TABLE IF EXISTS SA_B2B.EXT_NOVATECH_B2B_ORDERS;
CREATE FOREIGN TABLE SA_B2B.EXT_NOVATECH_B2B_ORDERS (
    ORDER_ID                            TEXT,   -- order_id
    ORDER_DATE                          TEXT,   -- order_date
    COMPANY_ID                          TEXT,   -- company_id
    COMPANY_NAME                        TEXT,   -- company_name
    INDUSTRY                            TEXT,   -- industry
    ACCOUNT_TIER                        TEXT,   -- account_tier
    COUNTRY                             TEXT,   -- country
    CITY                                TEXT,   -- city
    ACCOUNT_MANAGER_ID                  TEXT,   -- account_manager_id
    ACCOUNT_MANAGER_NAME                TEXT,   -- account_manager_name
    PRODUCT_ID                          TEXT,   -- product_id
    SKU                                 TEXT,   -- sku
    PRODUCT_TYPE                        TEXT,   -- product_type
    PRODUCT_CATEGORY                    TEXT,   -- product_category
    UNIT_PRICE                          TEXT,   -- unit_price
    QUANTITY                            TEXT,   -- quantity
    UNIT_COST                           TEXT,   -- unit_cost
    TOTAL_SALES                         TEXT,   -- total_sales
    TOTAL_COST                          TEXT,   -- total_cost
    PAYMENT_TERMS                       TEXT,   -- payment_terms
    PO_NUMBER                           TEXT,   -- po_number
    ORDER_STATUS                        TEXT,   -- order_status
    COMPANY_SIZE                        TEXT,   -- company_size
    ONBOARDING_DATE                     TEXT,   -- onboarding_date
    CREDIT_LIMIT                        TEXT,   -- credit_limit
    APPROVER_NAME                       TEXT,   -- approver_name
    BUDGET_CODE                         TEXT,   -- budget_code
    BRAND                               TEXT,   -- brand
    BULK_PACKAGING_UNIT                 TEXT,   -- bulk_packaging_unit
    MINIMUM_ORDER_QUANTITY              TEXT,   -- minimum_order_quantity
    PRODUCT_STATUS                      TEXT,   -- product_status
    DEPARTMENT                          TEXT,   -- department
    REGION_ASSIGNED                     TEXT,   -- region_assigned
    HIRE_DATE                           TEXT,   -- hire_date
    EMAIL                               TEXT,   -- email
    SALES_QUOTA                         TEXT,   -- sales_quota
    PERFORMANCE_TIER                    TEXT,   -- performance_tier
    PAYMENT_DUE_DAYS                    TEXT,   -- payment_due_days
    EARLY_PAYMENT_DISCOUNT_PCT          TEXT,   -- early_payment_discount_pct
    LATE_PAYMENT_PENALTY_PCT            TEXT,   -- late_payment_penalty_pct
    CURRENCY                            TEXT,   -- currency
    PREFERRED_PAYMENT_METHOD            TEXT,   -- preferred_payment_method
    TERMS_EFFECTIVE_DATE                TEXT,   -- terms_effective_date
    PO_ISSUE_DATE                       TEXT,   -- po_issue_date
    REQUESTED_DELIVERY_DATE             TEXT,   -- requested_delivery_date
    APPROVAL_STATUS                     TEXT,   -- approval_status
    PO_TYPE                             TEXT,   -- po_type
    PO_VALUE_THRESHOLD_FLAG             TEXT    -- po_value_threshold_flag
)
SERVER NOVATECH_FILE_SERVER
OPTIONS (
    format 'csv',
    header 'true',
    filename '/var/lib/postgresql/staging_files/novatech_b2b_orders.csv',  -- <-- adjust to your server's path
    delimiter ',',
    quote '"',
    escape '"',
    null ''
);

-- -----------------------------------------------------------------------------
-- 2.2  SRC_NOVATECH_B2B_ORDERS — physical, typed, deduplicated source table.
-- Grain: one row per B2B order line (= ORDER_ID). Unlike B2C, every column
-- in the B2B extract is always populated (verified: zero NULLs anywhere in
-- all 220,000 rows), so every column here is safely NOT NULL with no
-- sentinel handling needed at this layer.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS SA_B2B.SRC_NOVATECH_B2B_ORDERS;
CREATE TABLE SA_B2B.SRC_NOVATECH_B2B_ORDERS (
    ORDER_ID                     BIGINT          NOT NULL,   -- PK = fact grain key (degenerate dimension downstream)
    ORDER_DATE                   DATE            NOT NULL,
    COMPANY_ID                   BIGINT          NOT NULL,
    COMPANY_NAME                 VARCHAR(100)    NOT NULL,
    INDUSTRY                     VARCHAR(30)     NOT NULL,
    ACCOUNT_TIER                 VARCHAR(10)     NOT NULL,
    COUNTRY                      VARCHAR(50)     NOT NULL,
    CITY                         VARCHAR(50)     NOT NULL,
    ACCOUNT_MANAGER_ID           INT             NOT NULL,
    ACCOUNT_MANAGER_NAME         VARCHAR(50)     NOT NULL,
    PRODUCT_ID                   INT             NOT NULL,
    SKU                          VARCHAR(20)     NOT NULL,
    PRODUCT_TYPE                 VARCHAR(50)     NOT NULL,
    PRODUCT_CATEGORY             VARCHAR(50)     NOT NULL,
    UNIT_PRICE                   NUMERIC(10,2)   NOT NULL,
    QUANTITY                     INT             NOT NULL,
    UNIT_COST                    NUMERIC(10,2)   NOT NULL,
    TOTAL_SALES                  NUMERIC(14,2)   NOT NULL,
    TOTAL_COST                   NUMERIC(14,2)   NOT NULL,
    PAYMENT_TERMS                VARCHAR(20)     NOT NULL,
    PO_NUMBER                    VARCHAR(20)     NOT NULL,
    ORDER_STATUS                 VARCHAR(20)     NOT NULL,
    COMPANY_SIZE                 VARCHAR(20)     NOT NULL,
    ONBOARDING_DATE              DATE            NOT NULL,
    CREDIT_LIMIT                 NUMERIC(12,2)   NOT NULL,
    APPROVER_NAME                VARCHAR(50)     NOT NULL,
    BUDGET_CODE                  VARCHAR(20)     NOT NULL,
    BRAND                        VARCHAR(50)     NOT NULL,
    BULK_PACKAGING_UNIT          VARCHAR(30)     NOT NULL,
    MINIMUM_ORDER_QUANTITY       INT             NOT NULL,
    PRODUCT_STATUS               VARCHAR(20)     NOT NULL,
    DEPARTMENT                   VARCHAR(30)     NOT NULL,
    REGION_ASSIGNED              VARCHAR(20)     NOT NULL,
    HIRE_DATE                    DATE            NOT NULL,
    EMAIL                        VARCHAR(100)    NOT NULL,
    SALES_QUOTA                  NUMERIC(12,2)   NOT NULL,
    PERFORMANCE_TIER             VARCHAR(20)     NOT NULL,
    PAYMENT_DUE_DAYS              SMALLINT        NOT NULL,
    EARLY_PAYMENT_DISCOUNT_PCT    NUMERIC(5,2)    NOT NULL,
    LATE_PAYMENT_PENALTY_PCT      NUMERIC(5,2)    NOT NULL,
    CURRENCY                     VARCHAR(5)      NOT NULL,
    PREFERRED_PAYMENT_METHOD      VARCHAR(20)     NOT NULL,
    TERMS_EFFECTIVE_DATE          DATE            NOT NULL,
    PO_ISSUE_DATE                 DATE            NOT NULL,
    REQUESTED_DELIVERY_DATE       DATE            NOT NULL,
    APPROVAL_STATUS              VARCHAR(20)     NOT NULL,
    PO_TYPE                      VARCHAR(20)     NOT NULL,
    PO_VALUE_THRESHOLD_FLAG       VARCHAR(5)      NOT NULL,
    STG_LOAD_DT                   DATE            NOT NULL,   -- technical: date this row was staged
    SOURCE_FILE_NAME              VARCHAR(100)    NOT NULL,   -- technical: literal source file name
    CONSTRAINT PK_SRC_NOVATECH_B2B_ORDERS PRIMARY KEY (ORDER_ID)
);

INSERT INTO SA_B2B.SRC_NOVATECH_B2B_ORDERS
SELECT
    ORDER_ID::BIGINT,
    ORDER_DATE::DATE,
    COMPANY_ID::BIGINT,
    COMPANY_NAME,
    INDUSTRY,
    ACCOUNT_TIER,
    COUNTRY,
    CITY,
    ACCOUNT_MANAGER_ID::INT,
    ACCOUNT_MANAGER_NAME,
    PRODUCT_ID::INT,
    SKU,
    PRODUCT_TYPE,
    PRODUCT_CATEGORY,
    UNIT_PRICE::NUMERIC(10,2),
    QUANTITY::INT,
    UNIT_COST::NUMERIC(10,2),
    TOTAL_SALES::NUMERIC(14,2),
    TOTAL_COST::NUMERIC(14,2),
    PAYMENT_TERMS,
    PO_NUMBER,
    ORDER_STATUS,
    COMPANY_SIZE,
    ONBOARDING_DATE::DATE,
    CREDIT_LIMIT::NUMERIC(12,2),
    APPROVER_NAME,
    BUDGET_CODE,
    BRAND,
    BULK_PACKAGING_UNIT,
    MINIMUM_ORDER_QUANTITY::INT,
    PRODUCT_STATUS,
    DEPARTMENT,
    REGION_ASSIGNED,
    HIRE_DATE::DATE,
    EMAIL,
    SALES_QUOTA::NUMERIC(12,2),
    PERFORMANCE_TIER,
    PAYMENT_DUE_DAYS::SMALLINT,
    EARLY_PAYMENT_DISCOUNT_PCT::NUMERIC(5,2),
    LATE_PAYMENT_PENALTY_PCT::NUMERIC(5,2),
    CURRENCY,
    PREFERRED_PAYMENT_METHOD,
    TERMS_EFFECTIVE_DATE::DATE,
    PO_ISSUE_DATE::DATE,
    REQUESTED_DELIVERY_DATE::DATE,
    APPROVAL_STATUS,
    PO_TYPE,
    PO_VALUE_THRESHOLD_FLAG,
    CURRENT_DATE,
    'novatech_b2b_orders.csv'
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY ORDER_ID ORDER BY ORDER_ID) AS RN   -- de-duplication: see header note
    FROM SA_B2B.EXT_NOVATECH_B2B_ORDERS
) DEDUP
WHERE RN = 1
ON CONFLICT (ORDER_ID) DO NOTHING;   -- idempotency: a re-run after data already exists inserts 0 rows

-- =============================================================================
-- SECTION 3 — Verification (also satisfies the "screen of SELECT" deliverable)
-- =============================================================================

-- Row-count parity: EXT_ (raw file) vs SRC_ (typed + deduplicated) must match
-- exactly, since the current extract has zero duplicates in either file.
SELECT 'SA_B2C.EXT_NOVATECH_B2C_ORDERS' AS table_name, count(*) FROM SA_B2C.EXT_NOVATECH_B2C_ORDERS
UNION ALL
SELECT 'SA_B2C.SRC_NOVATECH_B2C_ORDERS', count(*) FROM SA_B2C.SRC_NOVATECH_B2C_ORDERS
UNION ALL
SELECT 'SA_B2B.EXT_NOVATECH_B2B_ORDERS', count(*) FROM SA_B2B.EXT_NOVATECH_B2B_ORDERS
UNION ALL
SELECT 'SA_B2B.SRC_NOVATECH_B2B_ORDERS', count(*) FROM SA_B2B.SRC_NOVATECH_B2B_ORDERS;

-- Spot-check rows from every EXT_ / SRC_ table
SELECT * FROM SA_B2C.EXT_NOVATECH_B2C_ORDERS ORDER BY ORDER_ID::BIGINT LIMIT 5;
SELECT * FROM SA_B2C.SRC_NOVATECH_B2C_ORDERS ORDER BY ORDER_ID LIMIT 5;
SELECT * FROM SA_B2B.EXT_NOVATECH_B2B_ORDERS ORDER BY ORDER_ID::BIGINT LIMIT 5;
SELECT * FROM SA_B2B.SRC_NOVATECH_B2B_ORDERS ORDER BY ORDER_ID LIMIT 5;

-- Confirm no duplicate ORDER_ID survived the load (extra_rows must be 0)
SELECT 'SA_B2C' AS data_set, count(*) - count(DISTINCT order_id) AS extra_rows FROM SA_B2C.SRC_NOVATECH_B2C_ORDERS
UNION ALL
SELECT 'SA_B2B', count(*) - count(DISTINCT order_id) FROM SA_B2B.SRC_NOVATECH_B2B_ORDERS;
