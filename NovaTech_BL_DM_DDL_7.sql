-- BL_DM schema — dimensional model (star schema) layer
-- Task 7: DDL for DM layer objects

-- BL_DM sits on top of BL_3NF and holds the star schema used for reporting.
-- A few design choices worth noting:
--   - Surrogate keys come from named sequences (SEQ_DIM_<TABLE>_ID), not SERIAL.
--   - Date columns follow the _DT postfix rule (hire_date_dt, date_of_birth_dt etc.).
--   - The product hierarchy (categories -> types -> products) is flattened into
--     DIM_PRODUCTS so analysts don't need extra joins to get type or category info.
--   - City and country are embedded into DIM_CUSTOMERS_SCD for the same reason.
--   - DIM_CUSTOMERS_SCD is SCD Type 2: each historical version gets its own
--     surrogate key. is_active uses 'Y'/'N' and end_dt = '9999-12-31' for the
--     current version.
--   - FCT_SALES_DD metric columns (fct_*) are nullable — this is intentional,
--     since the naming convention excludes KPIs from the NOT NULL rule.
--   - The FK from FCT_SALES_DD to DIM_CUSTOMERS_SCD targets customer_surr_id
--     directly, which is allowed on the DM layer for SCD2 tables.
--   - All objects use CREATE ... IF NOT EXISTS, so the script is safe to re-run.
--   - Default rows (surr_id = -1) are inserted via the companion DML script.

CREATE SCHEMA IF NOT EXISTS BL_DM;

BEGIN;

-- Sequences — one per dimension table, never SERIAL
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_PRODUCTS_ID           START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_EMPLOYEES_ID          START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_CHANNELS_ID           START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_PAYMENT_METHODS_ID    START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_SHIPPING_TYPES_ID     START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_PAYMENT_TERMS_ID      START WITH 1;
CREATE SEQUENCE IF NOT EXISTS BL_DM.SEQ_DIM_CUSTOMERS_SCD_ID      START WITH 1;

-- DIM_PRODUCTS (SCD Type 1)
-- Flattened from CE_PRODUCTS + CE_PRODUCT_TYPES + CE_PRODUCT_CATEGORIES.
-- Type and category attributes are stored directly here to avoid extra joins.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_PRODUCTS
(
    product_surr_id           BIGINT          NOT NULL,
    product_src_id            VARCHAR(20)     NOT NULL,
    source_system             VARCHAR(40)     NOT NULL,
    source_entity             VARCHAR(60)     NOT NULL,
    sku                       VARCHAR(20)     NOT NULL,
    brand                     VARCHAR(50)     NOT NULL,
    warranty_period_months    INT             NOT NULL,
    launch_year               INT             NOT NULL,
    bulk_packaging_unit       VARCHAR(50)     NOT NULL,
    minimum_order_quantity    INT             NOT NULL,
    product_status            VARCHAR(20)     NOT NULL,
    product_type_id           INT             NOT NULL,
    product_type_name         VARCHAR(50)     NOT NULL,
    product_category_id       INT             NOT NULL,
    product_category_name     VARCHAR(50)     NOT NULL,
    insert_dt                 DATE            NOT NULL,
    update_dt                 DATE            NOT NULL,
    CONSTRAINT PK_DIM_PRODUCTS PRIMARY KEY (product_surr_id)
);

-- DIM_EMPLOYEES (SCD Type 1)
-- B2B-only dimension. B2C fact rows point to the -1 default row.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_EMPLOYEES
(
    employee_surr_id      BIGINT          NOT NULL,
    employee_src_id       VARCHAR(60)     NOT NULL,
    source_system         VARCHAR(40)     NOT NULL,
    source_entity         VARCHAR(60)     NOT NULL,
    employee_name         VARCHAR(255)    NOT NULL,
    department            VARCHAR(50)     NOT NULL,
    region_assigned       VARCHAR(50)     NOT NULL,
    hire_date_dt          DATE            NOT NULL,
    email                 VARCHAR(255)    NOT NULL,
    sales_quota           NUMERIC(12,2)   NOT NULL,
    performance_tier      VARCHAR(20)     NOT NULL,
    insert_dt             DATE            NOT NULL,
    update_dt             DATE            NOT NULL,
    CONSTRAINT PK_DIM_EMPLOYEES PRIMARY KEY (employee_surr_id)
);

-- DIM_CHANNELS (SCD Type 1)
-- Two real channels (B2C / B2B) plus the -1 default row.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_CHANNELS
(
    channel_surr_id          INT             NOT NULL,
    channel_src_id           VARCHAR(10)     NOT NULL,
    source_system            VARCHAR(40)     NOT NULL,
    source_entity            VARCHAR(60)     NOT NULL,
    channel_name             VARCHAR(10)     NOT NULL,
    originating_system_name  VARCHAR(60)     NOT NULL,
    insert_dt                DATE            NOT NULL,
    update_dt                DATE            NOT NULL,
    CONSTRAINT PK_DIM_CHANNELS PRIMARY KEY (channel_surr_id)
);

-- DIM_PAYMENT_METHODS (SCD Type 1)
-- B2C-only. B2B fact rows use the -1 default row.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_PAYMENT_METHODS
(
    payment_method_surr_id         INT             NOT NULL,
    payment_method_src_id          VARCHAR(20)     NOT NULL,
    source_system                  VARCHAR(40)     NOT NULL,
    source_entity                  VARCHAR(60)     NOT NULL,
    payment_method_name            VARCHAR(20)     NOT NULL,
    payment_channel_type           VARCHAR(20)     NOT NULL,
    processing_fee_percent         NUMERIC(5,2)    NOT NULL,
    settlement_period_days         INT             NOT NULL,
    refundable                     VARCHAR(10)     NOT NULL,
    currency_accepted              VARCHAR(10)     NOT NULL,
    minimum_transaction_amount     NUMERIC(10,2)   NOT NULL,
    availability_channel           VARCHAR(30)     NOT NULL,
    insert_dt                      DATE            NOT NULL,
    update_dt                      DATE            NOT NULL,
    CONSTRAINT PK_DIM_PAYMENT_METHODS PRIMARY KEY (payment_method_surr_id)
);

-- DIM_SHIPPING_TYPES (SCD Type 1)
-- B2C-only. B2B fact rows use the -1 default row.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_SHIPPING_TYPES
(
    shipping_type_surr_id                  INT             NOT NULL,
    shipping_type_src_id                   VARCHAR(20)     NOT NULL,
    source_system                          VARCHAR(40)     NOT NULL,
    source_entity                          VARCHAR(60)     NOT NULL,
    shipping_type_name                     VARCHAR(20)     NOT NULL,
    shipping_carrier                       VARCHAR(30)     NOT NULL,
    estimated_delivery_days                VARCHAR(10)     NOT NULL,
    shipping_cost_tier                     VARCHAR(10)     NOT NULL,
    free_shipping_eligible                 VARCHAR(10)     NOT NULL,
    tracking_available                     VARCHAR(10)     NOT NULL,
    max_package_weight_kg                  INT             NOT NULL,
    international_shipping_available       VARCHAR(10)     NOT NULL,
    insert_dt                              DATE            NOT NULL,
    update_dt                              DATE            NOT NULL,
    CONSTRAINT PK_DIM_SHIPPING_TYPES PRIMARY KEY (shipping_type_surr_id)
);

-- DIM_PAYMENT_TERMS (SCD Type 1)
-- B2B-only. B2C fact rows use the -1 default row.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_PAYMENT_TERMS
(
    payment_terms_surr_id          INT             NOT NULL,
    payment_terms_src_id           VARCHAR(10)     NOT NULL,
    source_system                  VARCHAR(40)     NOT NULL,
    source_entity                  VARCHAR(60)     NOT NULL,
    payment_terms_name             VARCHAR(10)     NOT NULL,
    payment_due_days               INT             NOT NULL,
    early_payment_discount_pct     NUMERIC(5,2)    NOT NULL,
    late_payment_penalty_pct       NUMERIC(5,2)    NOT NULL,
    currency                       VARCHAR(10)     NOT NULL,
    preferred_payment_method       VARCHAR(20)     NOT NULL,
    terms_effective_date_dt        DATE            NOT NULL,
    insert_dt                      DATE            NOT NULL,
    update_dt                      DATE            NOT NULL,
    CONSTRAINT PK_DIM_PAYMENT_TERMS PRIMARY KEY (payment_terms_surr_id)
);

-- DIM_CUSTOMERS_SCD (SCD Type 2)
-- Each historical version of a customer gets its own customer_surr_id.
-- City and country are embedded here (flattened from CE_CITIES + CE_COUNTRIES).
-- is_active: 'Y' for the current version, 'N' for historical ones.
-- end_dt = '9999-12-31' marks the active version; no update_dt since changes
-- create a new row rather than overwriting the old one.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_CUSTOMERS_SCD
(
    customer_surr_id      BIGINT          NOT NULL,
    customer_src_id       VARCHAR(60)     NOT NULL,
    source_system         VARCHAR(40)     NOT NULL,
    source_entity         VARCHAR(60)     NOT NULL,
    customer_type         VARCHAR(10)     NOT NULL,
    customer_name         VARCHAR(255)    NOT NULL,
    date_of_birth_dt      DATE            NOT NULL,
    gender                VARCHAR(10)     NOT NULL,
    loyalty_member        VARCHAR(10)     NOT NULL,
    customer_segment      VARCHAR(20)     NOT NULL,
    industry              VARCHAR(50)     NOT NULL,
    account_tier          VARCHAR(10)     NOT NULL,
    company_size          VARCHAR(20)     NOT NULL,
    onboarding_date_dt    DATE            NOT NULL,
    credit_limit          NUMERIC(12,2)   NOT NULL,
    approver_name         VARCHAR(255)    NOT NULL,
    budget_code           VARCHAR(20)     NOT NULL,
    city_id               BIGINT          NOT NULL,
    city_name             VARCHAR(100)    NOT NULL,
    country_id            INT             NOT NULL,
    country_name          VARCHAR(100)    NOT NULL,
    start_dt              DATE            NOT NULL,
    end_dt                DATE            NOT NULL,
    is_active             VARCHAR(1)      NOT NULL,
    insert_dt             DATE            NOT NULL,
    CONSTRAINT PK_DIM_CUSTOMERS_SCD PRIMARY KEY (customer_surr_id)
);

-- DIM_TIME_DAY
-- Calendar dimension at daily granularity. Populated by generate_series in the
-- DML script (2015-01-01 to 2030-12-31). The UNIQUE constraint on date_dt
-- prevents duplicates on re-runs.
CREATE TABLE IF NOT EXISTS BL_DM.DIM_TIME_DAY
(
    time_day_surr_id   BIGINT        NOT NULL,
    date_dt            DATE          NOT NULL,
    day_no             INT           NOT NULL,
    month_no           INT           NOT NULL,
    quarter_no         INT           NOT NULL,
    year_no            INT           NOT NULL,
    week_no            INT           NOT NULL,
    day_name           VARCHAR(15)   NOT NULL,
    month_name         VARCHAR(15)   NOT NULL,
    is_weekend         VARCHAR(1)    NOT NULL,
    insert_dt          DATE          NOT NULL,
    update_dt          DATE          NOT NULL,
    CONSTRAINT PK_DIM_TIME_DAY       PRIMARY KEY (time_day_surr_id),
    CONSTRAINT UQ_DIM_TIME_DAY_DATE  UNIQUE      (date_dt)
);

-- FCT_SALES_DD — daily sales fact table
-- One row per order line (same grain as CE_SALES).
-- fct_* metric columns are nullable — KPIs are exempt from NOT NULL per the
-- column naming convention.
-- The FK to DIM_CUSTOMERS_SCD works because on the DM layer each version has
-- its own single-column PK (customer_surr_id), so a standard FK is fine.
-- The composite PK on (sales_src_id, source_system, source_entity) is what
-- makes the NOT EXISTS idempotency checks in the DML work correctly.
CREATE TABLE IF NOT EXISTS BL_DM.FCT_SALES_DD
(
    event_dt                   DATE            NOT NULL,
    product_surr_id            BIGINT          NOT NULL,
    customer_surr_id           BIGINT          NOT NULL,
    employee_surr_id           BIGINT          NOT NULL,
    channel_surr_id            INT             NOT NULL,
    payment_method_surr_id     INT             NOT NULL,
    shipping_type_surr_id      INT             NOT NULL,
    payment_terms_surr_id      INT             NOT NULL,
    sales_src_id               VARCHAR(60)     NOT NULL,
    source_system              VARCHAR(40)     NOT NULL,
    source_entity              VARCHAR(60)     NOT NULL,
    order_id                   BIGINT          NOT NULL,
    order_status               VARCHAR(20)     NOT NULL,
    fct_quantity               INT,
    fct_unit_price             NUMERIC(10,2),
    fct_unit_cost              NUMERIC(10,2),
    fct_total_sales            NUMERIC(12,2),
    fct_total_cost             NUMERIC(12,2),
    fct_rating                 INT,
    fct_add_on_total           NUMERIC(10,2),
    fct_refund_amount          NUMERIC(10,2),
    insert_dt                  DATE            NOT NULL,
    update_dt                  DATE            NOT NULL,
    CONSTRAINT PK_FCT_SALES_DD
        PRIMARY KEY (sales_src_id, source_system, source_entity),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_PRODUCTS
        FOREIGN KEY (product_surr_id)
        REFERENCES BL_DM.DIM_PRODUCTS        (product_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_CUSTOMERS_SCD
        FOREIGN KEY (customer_surr_id)
        REFERENCES BL_DM.DIM_CUSTOMERS_SCD   (customer_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_EMPLOYEES
        FOREIGN KEY (employee_surr_id)
        REFERENCES BL_DM.DIM_EMPLOYEES       (employee_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_CHANNELS
        FOREIGN KEY (channel_surr_id)
        REFERENCES BL_DM.DIM_CHANNELS        (channel_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_PAYMENT_METHODS
        FOREIGN KEY (payment_method_surr_id)
        REFERENCES BL_DM.DIM_PAYMENT_METHODS (payment_method_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_SHIPPING_TYPES
        FOREIGN KEY (shipping_type_surr_id)
        REFERENCES BL_DM.DIM_SHIPPING_TYPES  (shipping_type_surr_id),
    CONSTRAINT FK_FCT_SALES_DD_2_DIM_PAYMENT_TERMS
        FOREIGN KEY (payment_terms_surr_id)
        REFERENCES BL_DM.DIM_PAYMENT_TERMS   (payment_terms_surr_id)
);

COMMIT;

-- Indexes — functional indexes on UPPER(src_id, source_system, source_entity)
-- match the UPPER() comparisons used in the DML NOT EXISTS checks and FCT joins.
BEGIN;

CREATE INDEX IF NOT EXISTS IX_DIM_PRODUCTS_SRC
    ON BL_DM.DIM_PRODUCTS
        (UPPER(product_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_DIM_EMPLOYEES_SRC
    ON BL_DM.DIM_EMPLOYEES
        (UPPER(employee_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_DIM_CHANNELS_SRC
    ON BL_DM.DIM_CHANNELS
        (UPPER(channel_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_DIM_PAYMENT_METHODS_SRC
    ON BL_DM.DIM_PAYMENT_METHODS
        (UPPER(payment_method_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_DIM_SHIPPING_TYPES_SRC
    ON BL_DM.DIM_SHIPPING_TYPES
        (UPPER(shipping_type_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_DIM_PAYMENT_TERMS_SRC
    ON BL_DM.DIM_PAYMENT_TERMS
        (UPPER(payment_terms_src_id), UPPER(source_system), UPPER(source_entity));

-- SCD2 index includes start_dt to separate individual versions of the same customer
CREATE INDEX IF NOT EXISTS IX_DIM_CUSTOMERS_SCD_SRC
    ON BL_DM.DIM_CUSTOMERS_SCD
        (UPPER(customer_src_id), UPPER(source_system), UPPER(source_entity), start_dt);

-- Fact table indexes
CREATE INDEX IF NOT EXISTS IX_FCT_SALES_DD_SRC
    ON BL_DM.FCT_SALES_DD
        (UPPER(sales_src_id), UPPER(source_system), UPPER(source_entity));

CREATE INDEX IF NOT EXISTS IX_FCT_SALES_DD_EVENT_DT
    ON BL_DM.FCT_SALES_DD (event_dt);

CREATE INDEX IF NOT EXISTS IX_FCT_SALES_DD_PRODUCT
    ON BL_DM.FCT_SALES_DD (product_surr_id);

CREATE INDEX IF NOT EXISTS IX_FCT_SALES_DD_CUSTOMER
    ON BL_DM.FCT_SALES_DD (customer_surr_id);

COMMIT;
