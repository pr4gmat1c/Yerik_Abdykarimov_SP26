-- ============================================================================
-- NovaTech DWH — Task 8: PL/pgSQL — Loading BL_DM Dimensions
-- ============================================================================
--
-- PL/pgSQL features demonstrated (per task requirements):
--   ✓ Composite types        — t_dim_product_row  (prc_load_dim_products)
--                              t_dim_customer_row  (prc_load_dim_customers_scd)
--   ✓ Cursor variable        — DECLARE cur CURSOR FOR … / OPEN / FETCH / CLOSE
--                              (prc_load_dim_products)
--   ✓ Cursor FOR loop        — FOR rec IN SELECT … LOOP
--                              (prc_load_dim_employees, channels,
--                               payment_methods, shipping_types, payment_terms)
--   ✓ EXECUTE dynamic SQL    — EXECUTE v_sql USING … (prc_load_dim_products)
--   ✓ Upsert                 — INSERT … ON CONFLICT … DO UPDATE
--                              (all SCD-1 procedures)
--
-- Run order:
--   1. Section 1  — Setup  (grants, log table, types, unique constraints)
--   2. Section 2  — prc_log_insert
--   3. Section 3  — individual dimension procedures (any order)
--   4. Section 4  — prc_load_all_dm_dims  (master wrapper)
--   Then: CALL BL_CL.prc_load_all_dm_dims();
-- ============================================================================


-- ============================================================================
-- SECTION 1: SETUP
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1.a  Grants
-- ----------------------------------------------------------------------------
GRANT USAGE  ON SCHEMA BL_3NF TO CURRENT_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA BL_3NF TO CURRENT_USER;

GRANT USAGE  ON SCHEMA BL_DM TO CURRENT_USER;
GRANT ALL    ON ALL TABLES    IN SCHEMA BL_DM TO CURRENT_USER;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA BL_DM TO CURRENT_USER;

-- ----------------------------------------------------------------------------
-- 1.b  Logging / metadata table
-- MTA_ prefix = Metadata Table (per Naming Conventions).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BL_CL.MTA_LOAD_LOG (
    log_id          BIGSERIAL    NOT NULL,
    procedure_name  VARCHAR(100) NOT NULL,
    load_dt         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    rows_inserted   INT          NOT NULL DEFAULT 0,
    rows_updated    INT          NOT NULL DEFAULT 0,
    status          VARCHAR(20)  NOT NULL DEFAULT 'SUCCESS',
    error_message   TEXT,
    CONSTRAINT PK_MTA_LOAD_LOG PRIMARY KEY (log_id)
);

-- ----------------------------------------------------------------------------
-- 1.c  Composite types
-- Required by the task ("Use composite types — one or more procedures").
-- ----------------------------------------------------------------------------
DROP TYPE IF EXISTS BL_CL.t_dim_product_row CASCADE;
CREATE TYPE BL_CL.t_dim_product_row AS (
    v_product_src_id         VARCHAR(20),
    v_source_system          VARCHAR(40),
    v_source_entity          VARCHAR(60),
    v_sku                    VARCHAR(20),
    v_brand                  VARCHAR(50),
    v_warranty_period_months INT,
    v_launch_year            INT,
    v_bulk_packaging_unit    VARCHAR(50),
    v_minimum_order_quantity INT,
    v_product_status         VARCHAR(20),
    v_product_type_id        INT,
    v_product_type_name      VARCHAR(50),
    v_product_category_id    INT,
    v_product_category_name  VARCHAR(50)
);

DROP TYPE IF EXISTS BL_CL.t_dim_customer_row CASCADE;
CREATE TYPE BL_CL.t_dim_customer_row AS (
    v_customer_src_id      VARCHAR(60),
    v_source_system        VARCHAR(40),
    v_source_entity        VARCHAR(60),
    v_customer_type        VARCHAR(10),
    v_customer_name        VARCHAR(255),
    v_date_of_birth_dt     DATE,
    v_gender               VARCHAR(10),
    v_loyalty_member       VARCHAR(10),
    v_customer_segment     VARCHAR(20),
    v_industry              VARCHAR(50),
    v_account_tier         VARCHAR(10),
    v_company_size         VARCHAR(20),
    v_onboarding_date_dt   DATE,
    v_credit_limit         NUMERIC(12,2),
    v_approver_name        VARCHAR(255),
    v_budget_code          VARCHAR(20),
    v_city_id              BIGINT,
    v_city_name            VARCHAR(100),
    v_country_id           INT,
    v_country_name         VARCHAR(100),
    v_start_dt             DATE,
    v_end_dt               DATE,
    v_is_active            VARCHAR(1)
);

-- ----------------------------------------------------------------------------
-- 1.d  UNIQUE constraints on DIM source triplets
-- Required as ON CONFLICT ON CONSTRAINT targets for the SCD-1 upserts below.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_products_src') THEN
        ALTER TABLE BL_DM.DIM_PRODUCTS
            ADD CONSTRAINT uq_dim_products_src
            UNIQUE (product_src_id, source_system, source_entity);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_employees_src') THEN
        ALTER TABLE BL_DM.DIM_EMPLOYEES
            ADD CONSTRAINT uq_dim_employees_src
            UNIQUE (employee_src_id, source_system, source_entity);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_channels_src') THEN
        ALTER TABLE BL_DM.DIM_CHANNELS
            ADD CONSTRAINT uq_dim_channels_src
            UNIQUE (channel_src_id, source_system, source_entity);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_payment_methods_src') THEN
        ALTER TABLE BL_DM.DIM_PAYMENT_METHODS
            ADD CONSTRAINT uq_dim_payment_methods_src
            UNIQUE (payment_method_src_id, source_system, source_entity);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_shipping_types_src') THEN
        ALTER TABLE BL_DM.DIM_SHIPPING_TYPES
            ADD CONSTRAINT uq_dim_shipping_types_src
            UNIQUE (shipping_type_src_id, source_system, source_entity);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_dim_payment_terms_src') THEN
        ALTER TABLE BL_DM.DIM_PAYMENT_TERMS
            ADD CONSTRAINT uq_dim_payment_terms_src
            UNIQUE (payment_terms_src_id, source_system, source_entity);
    END IF;
END $$;


-- ============================================================================
-- SECTION 2: LOGGING PROCEDURE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- prc_log_insert
-- Called by every dimension procedure to write one audit row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_log_insert (
    p_procedure_name  VARCHAR,
    p_rows_inserted   INT     DEFAULT 0,
    p_rows_updated    INT     DEFAULT 0,
    p_status          VARCHAR DEFAULT 'SUCCESS',
    p_error_message   TEXT    DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO BL_CL.MTA_LOAD_LOG (
        procedure_name, load_dt,
        rows_inserted, rows_updated,
        status, error_message
    ) VALUES (
        p_procedure_name, CURRENT_TIMESTAMP,
        p_rows_inserted, p_rows_updated,
        p_status, p_error_message
    );
END;
$$;


-- ============================================================================
-- SECTION 3: DIMENSION LOADING PROCEDURES
-- ============================================================================

-- ============================================================================
-- 3.1  prc_load_dim_products
-- Target : BL_DM.DIM_PRODUCTS  (SCD Type 1)
-- Source : BL_3NF.CE_PRODUCTS JOIN CE_PRODUCT_TYPES JOIN CE_PRODUCT_CATEGORIES
--
-- PL/pgSQL features:
--   ① Composite type  — t_dim_product_row  (variable v_row)
--   ② Cursor variable — explicit named cursor: DECLARE / OPEN / FETCH / CLOSE
--   ③ EXECUTE         — dynamic INSERT … ON CONFLICT SQL built once, executed
--                        per row with parameter binding
--   ④ Upsert          — ON CONFLICT ON CONSTRAINT uq_dim_products_src DO UPDATE
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_products()
LANGUAGE plpgsql AS $$
DECLARE
    -- ② Explicit cursor variable
    cur_products CURSOR FOR
        SELECT
            p.product_id::VARCHAR(20)                         AS product_src_id,
            'BL_3NF'::VARCHAR(40)                             AS source_system,
            'CE_PRODUCTS'::VARCHAR(60)                        AS source_entity,
            COALESCE(p.sku,                   'Manual')       AS sku,
            COALESCE(p.brand,                 'Manual')       AS brand,
            COALESCE(p.warranty_period_months, -1)            AS warranty_period_months,
            COALESCE(p.launch_year,            -1)            AS launch_year,
            COALESCE(p.bulk_packaging_unit,   'Manual')       AS bulk_packaging_unit,
            COALESCE(p.minimum_order_quantity, -1)            AS minimum_order_quantity,
            COALESCE(p.product_status,        'Manual')       AS product_status,
            COALESCE(pt.product_type_id,       -1)            AS product_type_id,
            COALESCE(pt.product_type_name,    'Manual')       AS product_type_name,
            COALESCE(pc.product_category_id,   -1)            AS product_category_id,
            COALESCE(pc.product_category_name,'Manual')       AS product_category_name
        FROM BL_3NF.CE_PRODUCTS p
        LEFT JOIN BL_3NF.CE_PRODUCT_TYPES      pt
               ON p.product_type_id       = pt.product_type_id
        LEFT JOIN BL_3NF.CE_PRODUCT_CATEGORIES pc
               ON pt.product_category_id  = pc.product_category_id
        WHERE p.product_id <> -1;

    -- ① Composite type variable — holds one fetched product row
    v_row       BL_CL.t_dim_product_row;
    -- ③ Dynamic SQL string — built once before the loop
    v_sql       TEXT;
    v_inserted  INT := 0;
    v_count     INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_PRODUCTS (
        product_surr_id, product_src_id, source_system, source_entity,
        sku, brand, warranty_period_months, launch_year,
        bulk_packaging_unit, minimum_order_quantity, product_status,
        product_type_id, product_type_name,
        product_category_id, product_category_name,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Manual', 'Manual', -1, -1, 'Manual', -1, 'Manual',
        -1, 'Manual', -1, 'Manual',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    -- ③ Assemble the dynamic upsert string once outside the loop.
    v_sql :=
        'INSERT INTO BL_DM.DIM_PRODUCTS (
             product_surr_id, product_src_id, source_system, source_entity,
             sku, brand, warranty_period_months, launch_year,
             bulk_packaging_unit, minimum_order_quantity, product_status,
             product_type_id, product_type_name,
             product_category_id, product_category_name,
             insert_dt, update_dt
         ) VALUES (
             NEXTVAL(''BL_DM.SEQ_DIM_PRODUCTS_ID''),
             $1,  $2,  $3,
             $4,  $5,  $6,  $7,  $8,  $9,  $10,
             $11, $12, $13, $14,
             CURRENT_DATE, CURRENT_DATE
         )
         ON CONFLICT ON CONSTRAINT uq_dim_products_src DO UPDATE SET
             sku                    = EXCLUDED.sku,
             brand                  = EXCLUDED.brand,
             warranty_period_months = EXCLUDED.warranty_period_months,
             launch_year            = EXCLUDED.launch_year,
             bulk_packaging_unit    = EXCLUDED.bulk_packaging_unit,
             minimum_order_quantity = EXCLUDED.minimum_order_quantity,
             product_status         = EXCLUDED.product_status,
             product_type_id        = EXCLUDED.product_type_id,
             product_type_name      = EXCLUDED.product_type_name,
             product_category_id    = EXCLUDED.product_category_id,
             product_category_name  = EXCLUDED.product_category_name,
             update_dt              = CURRENT_DATE
         WHERE
             BL_DM.DIM_PRODUCTS.sku                    IS DISTINCT FROM EXCLUDED.sku
          OR BL_DM.DIM_PRODUCTS.brand                  IS DISTINCT FROM EXCLUDED.brand
          OR BL_DM.DIM_PRODUCTS.warranty_period_months IS DISTINCT FROM EXCLUDED.warranty_period_months
          OR BL_DM.DIM_PRODUCTS.product_status         IS DISTINCT FROM EXCLUDED.product_status
          OR BL_DM.DIM_PRODUCTS.product_type_id        IS DISTINCT FROM EXCLUDED.product_type_id
          OR BL_DM.DIM_PRODUCTS.product_category_id    IS DISTINCT FROM EXCLUDED.product_category_id';

    -- ② Open the explicit cursor
    OPEN cur_products;
    LOOP
        -- ② Fetch one row into the composite type variable (field by field)
        FETCH cur_products INTO
            v_row.v_product_src_id,          v_row.v_source_system,
            v_row.v_source_entity,            v_row.v_sku,
            v_row.v_brand,                    v_row.v_warranty_period_months,
            v_row.v_launch_year,              v_row.v_bulk_packaging_unit,
            v_row.v_minimum_order_quantity,   v_row.v_product_status,
            v_row.v_product_type_id,          v_row.v_product_type_name,
            v_row.v_product_category_id,      v_row.v_product_category_name;

        EXIT WHEN NOT FOUND;

        -- ③ Execute the dynamic SQL with bound parameters from composite type
        EXECUTE v_sql
            USING
                v_row.v_product_src_id,          v_row.v_source_system,
                v_row.v_source_entity,            v_row.v_sku,
                v_row.v_brand,                    v_row.v_warranty_period_months,
                v_row.v_launch_year,              v_row.v_bulk_packaging_unit,
                v_row.v_minimum_order_quantity,   v_row.v_product_status,
                v_row.v_product_type_id,          v_row.v_product_type_name,
                v_row.v_product_category_id,      v_row.v_product_category_name;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;
    -- ② Close the explicit cursor
    CLOSE cur_products;

    CALL BL_CL.prc_log_insert('prc_load_dim_products', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.2  prc_load_dim_employees
-- Target : BL_DM.DIM_EMPLOYEES  (SCD Type 1)
-- Source : BL_3NF.CE_EMPLOYEES  (B2B account managers only)
-- Features: cursor FOR loop + ON CONFLICT upsert
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_employees()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec      RECORD;
    v_inserted INT := 0;
    v_count    INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_EMPLOYEES (
        employee_surr_id, employee_src_id, source_system, source_entity,
        employee_name, department, region_assigned, hire_date_dt,
        email, sales_quota, performance_tier,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Not Applicable', 'Manual', 'Manual', DATE '1900-01-01',
        'Manual', -1, 'Manual',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    -- Cursor FOR loop — implicit cursor; OPEN / FETCH / CLOSE handled by PG
    FOR v_rec IN
        SELECT
            e.employee_id::VARCHAR(60)                           AS employee_src_id,
            'BL_3NF'::VARCHAR(40)                                AS source_system,
            'CE_EMPLOYEES'::VARCHAR(60)                          AS source_entity,
            COALESCE(e.employee_name,    'Manual')               AS employee_name,
            COALESCE(e.department,       'Manual')               AS department,
            COALESCE(e.region_assigned,  'Manual')               AS region_assigned,
            COALESCE(e.hire_date,        DATE '1900-01-01')      AS hire_date_dt,
            COALESCE(e.email,            'Manual')               AS email,
            COALESCE(e.sales_quota,      -1)                     AS sales_quota,
            COALESCE(e.performance_tier, 'Manual')               AS performance_tier
        FROM BL_3NF.CE_EMPLOYEES e
        WHERE e.employee_id <> -1
    LOOP
        INSERT INTO BL_DM.DIM_EMPLOYEES (
            employee_surr_id, employee_src_id, source_system, source_entity,
            employee_name, department, region_assigned, hire_date_dt,
            email, sales_quota, performance_tier,
            insert_dt, update_dt
        ) VALUES (
            NEXTVAL('BL_DM.SEQ_DIM_EMPLOYEES_ID'),
            v_rec.employee_src_id, v_rec.source_system, v_rec.source_entity,
            v_rec.employee_name,  v_rec.department,     v_rec.region_assigned,
            v_rec.hire_date_dt,   v_rec.email,          v_rec.sales_quota,
            v_rec.performance_tier,
            CURRENT_DATE, CURRENT_DATE
        )
        ON CONFLICT ON CONSTRAINT uq_dim_employees_src DO UPDATE SET
            employee_name    = EXCLUDED.employee_name,
            department       = EXCLUDED.department,
            region_assigned  = EXCLUDED.region_assigned,
            hire_date_dt     = EXCLUDED.hire_date_dt,
            email            = EXCLUDED.email,
            sales_quota      = EXCLUDED.sales_quota,
            performance_tier = EXCLUDED.performance_tier,
            update_dt        = CURRENT_DATE
        WHERE
            BL_DM.DIM_EMPLOYEES.employee_name    IS DISTINCT FROM EXCLUDED.employee_name
         OR BL_DM.DIM_EMPLOYEES.department       IS DISTINCT FROM EXCLUDED.department
         OR BL_DM.DIM_EMPLOYEES.region_assigned  IS DISTINCT FROM EXCLUDED.region_assigned
         OR BL_DM.DIM_EMPLOYEES.sales_quota      IS DISTINCT FROM EXCLUDED.sales_quota
         OR BL_DM.DIM_EMPLOYEES.performance_tier IS DISTINCT FROM EXCLUDED.performance_tier;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;

    CALL BL_CL.prc_log_insert('prc_load_dim_employees', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.3  prc_load_dim_channels
-- Target : BL_DM.DIM_CHANNELS  (Type 0 — static reference)
-- Source : BL_3NF.CE_CHANNELS
-- Features: cursor FOR loop + ON CONFLICT upsert
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_channels()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec      RECORD;
    v_inserted INT := 0;
    v_count    INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_CHANNELS (
        channel_surr_id, channel_src_id, source_system, source_entity,
        channel_name, originating_system_name,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual', 'Manual', 'Manual',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    FOR v_rec IN
        SELECT
            c.channel_id::VARCHAR(10)                              AS channel_src_id,
            'BL_3NF'::VARCHAR(40)                                  AS source_system,
            'CE_CHANNELS'::VARCHAR(60)                             AS source_entity,
            COALESCE(c.channel_name,             'Manual')         AS channel_name,
            COALESCE(c.originating_system_name,  'Manual')         AS originating_system_name
        FROM BL_3NF.CE_CHANNELS c
        WHERE c.channel_id <> -1
    LOOP
        INSERT INTO BL_DM.DIM_CHANNELS (
            channel_surr_id, channel_src_id, source_system, source_entity,
            channel_name, originating_system_name,
            insert_dt, update_dt
        ) VALUES (
            NEXTVAL('BL_DM.SEQ_DIM_CHANNELS_ID'),
            v_rec.channel_src_id, v_rec.source_system, v_rec.source_entity,
            v_rec.channel_name,   v_rec.originating_system_name,
            CURRENT_DATE, CURRENT_DATE
        )
        ON CONFLICT ON CONSTRAINT uq_dim_channels_src DO UPDATE SET
            channel_name            = EXCLUDED.channel_name,
            originating_system_name = EXCLUDED.originating_system_name,
            update_dt               = CURRENT_DATE
        WHERE
            BL_DM.DIM_CHANNELS.channel_name            IS DISTINCT FROM EXCLUDED.channel_name
         OR BL_DM.DIM_CHANNELS.originating_system_name IS DISTINCT FROM EXCLUDED.originating_system_name;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;

    CALL BL_CL.prc_log_insert('prc_load_dim_channels', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.4  prc_load_dim_payment_methods
-- Target : BL_DM.DIM_PAYMENT_METHODS  (SCD Type 1, B2C only)
-- Source : BL_3NF.CE_PAYMENT_METHODS
-- Features: cursor FOR loop + ON CONFLICT upsert
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_payment_methods()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec      RECORD;
    v_inserted INT := 0;
    v_count    INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_PAYMENT_METHODS (
        payment_method_surr_id, payment_method_src_id, source_system, source_entity,
        payment_method_name, payment_channel_type, processing_fee_percent,
        settlement_period_days, refundable, currency_accepted,
        minimum_transaction_amount, availability_channel,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Manual', 'Manual', -1, -1, 'Manual', 'Manual', -1, 'Manual',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    FOR v_rec IN
        SELECT
            pm.payment_method_id::VARCHAR(20)                      AS payment_method_src_id,
            'BL_3NF'::VARCHAR(40)                                  AS source_system,
            'CE_PAYMENT_METHODS'::VARCHAR(60)                      AS source_entity,
            COALESCE(pm.payment_method_name,         'Manual')     AS payment_method_name,
            COALESCE(pm.payment_channel_type,        'Manual')     AS payment_channel_type,
            COALESCE(pm.processing_fee_percent,      -1)           AS processing_fee_percent,
            COALESCE(pm.settlement_period_days,      -1)           AS settlement_period_days,
            COALESCE(pm.refundable,                  'Manual')     AS refundable,
            COALESCE(pm.currency_accepted,           'Manual')     AS currency_accepted,
            COALESCE(pm.minimum_transaction_amount,  -1)           AS minimum_transaction_amount,
            COALESCE(pm.availability_channel,        'Manual')     AS availability_channel
        FROM BL_3NF.CE_PAYMENT_METHODS pm
        WHERE pm.payment_method_id <> -1
    LOOP
        INSERT INTO BL_DM.DIM_PAYMENT_METHODS (
            payment_method_surr_id, payment_method_src_id, source_system, source_entity,
            payment_method_name, payment_channel_type, processing_fee_percent,
            settlement_period_days, refundable, currency_accepted,
            minimum_transaction_amount, availability_channel,
            insert_dt, update_dt
        ) VALUES (
            NEXTVAL('BL_DM.SEQ_DIM_PAYMENT_METHODS_ID'),
            v_rec.payment_method_src_id, v_rec.source_system, v_rec.source_entity,
            v_rec.payment_method_name,   v_rec.payment_channel_type,
            v_rec.processing_fee_percent, v_rec.settlement_period_days,
            v_rec.refundable,            v_rec.currency_accepted,
            v_rec.minimum_transaction_amount, v_rec.availability_channel,
            CURRENT_DATE, CURRENT_DATE
        )
        ON CONFLICT ON CONSTRAINT uq_dim_payment_methods_src DO UPDATE SET
            payment_method_name        = EXCLUDED.payment_method_name,
            payment_channel_type       = EXCLUDED.payment_channel_type,
            processing_fee_percent     = EXCLUDED.processing_fee_percent,
            settlement_period_days     = EXCLUDED.settlement_period_days,
            refundable                 = EXCLUDED.refundable,
            currency_accepted          = EXCLUDED.currency_accepted,
            minimum_transaction_amount = EXCLUDED.minimum_transaction_amount,
            availability_channel       = EXCLUDED.availability_channel,
            update_dt                  = CURRENT_DATE
        WHERE
            BL_DM.DIM_PAYMENT_METHODS.payment_method_name    IS DISTINCT FROM EXCLUDED.payment_method_name
         OR BL_DM.DIM_PAYMENT_METHODS.processing_fee_percent IS DISTINCT FROM EXCLUDED.processing_fee_percent
         OR BL_DM.DIM_PAYMENT_METHODS.settlement_period_days IS DISTINCT FROM EXCLUDED.settlement_period_days;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;

    CALL BL_CL.prc_log_insert('prc_load_dim_payment_methods', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.5  prc_load_dim_shipping_types
-- Target : BL_DM.DIM_SHIPPING_TYPES  (SCD Type 1, B2C only)
-- Source : BL_3NF.CE_SHIPPING_TYPES
-- Features: cursor FOR loop + ON CONFLICT upsert
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_shipping_types()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec      RECORD;
    v_inserted INT := 0;
    v_count    INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_SHIPPING_TYPES (
        shipping_type_surr_id, shipping_type_src_id, source_system, source_entity,
        shipping_type_name, shipping_carrier, estimated_delivery_days,
        shipping_cost_tier, free_shipping_eligible, tracking_available,
        max_package_weight_kg, international_shipping_available,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Manual', 'Manual', 'Manual', 'Manual', 'Manual', 'Manual', -1, 'Manual',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    FOR v_rec IN
        SELECT
            st.shipping_type_id::VARCHAR(20)                          AS shipping_type_src_id,
            'BL_3NF'::VARCHAR(40)                                     AS source_system,
            'CE_SHIPPING_TYPES'::VARCHAR(60)                          AS source_entity,
            COALESCE(st.shipping_type_name,               'Manual')   AS shipping_type_name,
            COALESCE(st.shipping_carrier,                 'Manual')   AS shipping_carrier,
            COALESCE(st.estimated_delivery_days,          'Manual')   AS estimated_delivery_days,
            COALESCE(st.shipping_cost_tier,               'Manual')   AS shipping_cost_tier,
            COALESCE(st.free_shipping_eligible,           'Manual')   AS free_shipping_eligible,
            COALESCE(st.tracking_available,               'Manual')   AS tracking_available,
            COALESCE(st.max_package_weight_kg,            -1)         AS max_package_weight_kg,
            COALESCE(st.international_shipping_available, 'Manual')   AS international_shipping_available
        FROM BL_3NF.CE_SHIPPING_TYPES st
        WHERE st.shipping_type_id <> -1
    LOOP
        INSERT INTO BL_DM.DIM_SHIPPING_TYPES (
            shipping_type_surr_id, shipping_type_src_id, source_system, source_entity,
            shipping_type_name, shipping_carrier, estimated_delivery_days,
            shipping_cost_tier, free_shipping_eligible, tracking_available,
            max_package_weight_kg, international_shipping_available,
            insert_dt, update_dt
        ) VALUES (
            NEXTVAL('BL_DM.SEQ_DIM_SHIPPING_TYPES_ID'),
            v_rec.shipping_type_src_id, v_rec.source_system,  v_rec.source_entity,
            v_rec.shipping_type_name,   v_rec.shipping_carrier,
            v_rec.estimated_delivery_days, v_rec.shipping_cost_tier,
            v_rec.free_shipping_eligible,  v_rec.tracking_available,
            v_rec.max_package_weight_kg,   v_rec.international_shipping_available,
            CURRENT_DATE, CURRENT_DATE
        )
        ON CONFLICT ON CONSTRAINT uq_dim_shipping_types_src DO UPDATE SET
            shipping_type_name             = EXCLUDED.shipping_type_name,
            shipping_carrier               = EXCLUDED.shipping_carrier,
            estimated_delivery_days        = EXCLUDED.estimated_delivery_days,
            shipping_cost_tier             = EXCLUDED.shipping_cost_tier,
            free_shipping_eligible         = EXCLUDED.free_shipping_eligible,
            tracking_available             = EXCLUDED.tracking_available,
            max_package_weight_kg          = EXCLUDED.max_package_weight_kg,
            international_shipping_available = EXCLUDED.international_shipping_available,
            update_dt                      = CURRENT_DATE
        WHERE
            BL_DM.DIM_SHIPPING_TYPES.shipping_type_name    IS DISTINCT FROM EXCLUDED.shipping_type_name
         OR BL_DM.DIM_SHIPPING_TYPES.shipping_carrier      IS DISTINCT FROM EXCLUDED.shipping_carrier
         OR BL_DM.DIM_SHIPPING_TYPES.max_package_weight_kg IS DISTINCT FROM EXCLUDED.max_package_weight_kg;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;

    CALL BL_CL.prc_log_insert('prc_load_dim_shipping_types', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.6  prc_load_dim_payment_terms
-- Target : BL_DM.DIM_PAYMENT_TERMS  (SCD Type 1, B2B only)
-- Source : BL_3NF.CE_PAYMENT_TERMS
-- Features: cursor FOR loop + ON CONFLICT upsert
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_payment_terms()
LANGUAGE plpgsql AS $$
DECLARE
    v_rec      RECORD;
    v_inserted INT := 0;
    v_count    INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_PAYMENT_TERMS (
        payment_terms_surr_id, payment_terms_src_id, source_system, source_entity,
        payment_terms_name, payment_due_days, early_payment_discount_pct,
        late_payment_penalty_pct, currency, preferred_payment_method,
        terms_effective_date_dt,
        insert_dt, update_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Manual', -1, -1, -1, 'Manual', 'Manual', DATE '1900-01-01',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    FOR v_rec IN
        SELECT
            pt.payment_terms_id::VARCHAR(10)                           AS payment_terms_src_id,
            'BL_3NF'::VARCHAR(40)                                      AS source_system,
            'CE_PAYMENT_TERMS'::VARCHAR(60)                            AS source_entity,
            COALESCE(pt.payment_terms_name,           'Manual')        AS payment_terms_name,
            COALESCE(pt.payment_due_days,             -1)              AS payment_due_days,
            COALESCE(pt.early_payment_discount_pct,   -1)              AS early_payment_discount_pct,
            COALESCE(pt.late_payment_penalty_pct,     -1)              AS late_payment_penalty_pct,
            COALESCE(pt.currency,                     'Manual')        AS currency,
            COALESCE(pt.preferred_payment_method,     'Manual')        AS preferred_payment_method,
            COALESCE(pt.terms_effective_date, DATE '1900-01-01')       AS terms_effective_date_dt
        FROM BL_3NF.CE_PAYMENT_TERMS pt
        WHERE pt.payment_terms_id <> -1
    LOOP
        INSERT INTO BL_DM.DIM_PAYMENT_TERMS (
            payment_terms_surr_id, payment_terms_src_id, source_system, source_entity,
            payment_terms_name, payment_due_days, early_payment_discount_pct,
            late_payment_penalty_pct, currency, preferred_payment_method,
            terms_effective_date_dt,
            insert_dt, update_dt
        ) VALUES (
            NEXTVAL('BL_DM.SEQ_DIM_PAYMENT_TERMS_ID'),
            v_rec.payment_terms_src_id,       v_rec.source_system, v_rec.source_entity,
            v_rec.payment_terms_name,         v_rec.payment_due_days,
            v_rec.early_payment_discount_pct, v_rec.late_payment_penalty_pct,
            v_rec.currency,                   v_rec.preferred_payment_method,
            v_rec.terms_effective_date_dt,
            CURRENT_DATE, CURRENT_DATE
        )
        ON CONFLICT ON CONSTRAINT uq_dim_payment_terms_src DO UPDATE SET
            payment_terms_name         = EXCLUDED.payment_terms_name,
            payment_due_days           = EXCLUDED.payment_due_days,
            early_payment_discount_pct = EXCLUDED.early_payment_discount_pct,
            late_payment_penalty_pct   = EXCLUDED.late_payment_penalty_pct,
            currency                   = EXCLUDED.currency,
            preferred_payment_method   = EXCLUDED.preferred_payment_method,
            terms_effective_date_dt    = EXCLUDED.terms_effective_date_dt,
            update_dt                  = CURRENT_DATE
        WHERE
            BL_DM.DIM_PAYMENT_TERMS.payment_terms_name         IS DISTINCT FROM EXCLUDED.payment_terms_name
         OR BL_DM.DIM_PAYMENT_TERMS.payment_due_days           IS DISTINCT FROM EXCLUDED.payment_due_days
         OR BL_DM.DIM_PAYMENT_TERMS.early_payment_discount_pct IS DISTINCT FROM EXCLUDED.early_payment_discount_pct
         OR BL_DM.DIM_PAYMENT_TERMS.late_payment_penalty_pct   IS DISTINCT FROM EXCLUDED.late_payment_penalty_pct;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        v_inserted := v_inserted + v_count;
    END LOOP;

    CALL BL_CL.prc_log_insert('prc_load_dim_payment_terms', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.7  prc_load_dim_customers_scd
-- Target : BL_DM.DIM_CUSTOMERS_SCD  (SCD Type 2)
-- Source : BL_3NF.CE_CUSTOMERS_SCD JOIN CE_CITIES JOIN CE_COUNTRIES
-- SCD-2 loading logic (two-step, both batch operations):
--   Step 1 — Close any open DM version superseded by a new 3NF version.
--   Step 2 — Insert any CE_CUSTOMERS_SCD version not yet present in DIM.
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_customers_scd()
LANGUAGE plpgsql AS $$
DECLARE
    v_inserted INT;
    v_updated  INT;
BEGIN
    -- Default (-1) row
    INSERT INTO BL_DM.DIM_CUSTOMERS_SCD (
        customer_surr_id, customer_src_id, source_system, source_entity,
        customer_type, customer_name, date_of_birth_dt, gender,
        loyalty_member, customer_segment, industry, account_tier, company_size,
        onboarding_date_dt, credit_limit, approver_name, budget_code,
        city_id, city_name, country_id, country_name,
        start_dt, end_dt, is_active, insert_dt
    ) VALUES (
        -1, '-1', 'Manual', 'Manual',
        'Manual', 'Not Applicable', DATE '1900-01-01', 'Manual',
        'Manual', 'Manual', 'Manual', 'Manual', 'Manual',
        DATE '1900-01-01', -1, 'Manual', 'Manual',
        -1, 'Manual', -1, 'Manual',
        DATE '1900-01-01', DATE '9999-12-31', 'Y', CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    -- Step 1: Close outdated open DM versions (batch UPDATE)
    UPDATE BL_DM.DIM_CUSTOMERS_SCD dm
    SET
        end_dt    = src.end_dt::DATE,
        is_active = CASE WHEN src.is_active THEN 'Y' ELSE 'N' END
    FROM BL_3NF.CE_CUSTOMERS_SCD src
    WHERE dm.customer_src_id = src.customer_id::VARCHAR
      AND dm.source_system   = 'BL_3NF'
      AND dm.source_entity   = 'CE_CUSTOMERS_SCD'
      AND dm.start_dt        = src.start_dt::DATE
      AND (
              dm.end_dt    IS DISTINCT FROM src.end_dt::DATE
           OR dm.is_active IS DISTINCT FROM CASE WHEN src.is_active THEN 'Y' ELSE 'N' END
          );
    GET DIAGNOSTICS v_updated = ROW_COUNT;

    -- Step 2: Insert new versions not yet present in DIM (batch INSERT)
    INSERT INTO BL_DM.DIM_CUSTOMERS_SCD (
        customer_surr_id, customer_src_id, source_system, source_entity,
        customer_type, customer_name, date_of_birth_dt, gender,
        loyalty_member, customer_segment, industry, account_tier, company_size,
        onboarding_date_dt, credit_limit, approver_name, budget_code,
        city_id, city_name, country_id, country_name,
        start_dt, end_dt, is_active, insert_dt
    )
    SELECT
        NEXTVAL('BL_DM.SEQ_DIM_CUSTOMERS_SCD_ID'),
        src.customer_id::VARCHAR(60),
        'BL_3NF',
        'CE_CUSTOMERS_SCD',
        COALESCE(src.customer_type,    'Manual'),
        COALESCE(src.customer_name,    'Manual'),
        COALESCE(src.date_of_birth,    DATE '1900-01-01')::DATE,
        COALESCE(src.gender,           'Manual'),
        COALESCE(src.loyalty_member,   'Manual'),
        COALESCE(src.customer_segment, 'Manual'),
        COALESCE(src.industry,         'Manual'),
        COALESCE(src.account_tier,     'Manual'),
        COALESCE(src.company_size,     'Manual'),
        COALESCE(src.onboarding_date,  DATE '1900-01-01')::DATE,
        COALESCE(src.credit_limit,     -1)::NUMERIC(12,2),
        COALESCE(src.approver_name,    'Manual'),
        COALESCE(src.budget_code,      'Manual'),
        COALESCE(ci.city_id,    -1)::BIGINT,
        COALESCE(ci.city_name,  'Manual')::VARCHAR(100),
        COALESCE(co.country_id, -1)::INT,
        COALESCE(co.country_name, 'Manual')::VARCHAR(100),
        src.start_dt::DATE,
        src.end_dt::DATE,
        CASE WHEN src.is_active THEN 'Y' ELSE 'N' END,
        CURRENT_DATE
    FROM BL_3NF.CE_CUSTOMERS_SCD src
    LEFT JOIN BL_3NF.CE_CITIES    ci ON ci.city_id    = src.city_id    AND ci.city_id    <> -1
    LEFT JOIN BL_3NF.CE_COUNTRIES co ON co.country_id = ci.country_id  AND co.country_id <> -1
    WHERE src.customer_id <> -1
      AND NOT EXISTS (
          SELECT 1
          FROM BL_DM.DIM_CUSTOMERS_SCD dm
          WHERE dm.customer_src_id = src.customer_id::VARCHAR
            AND dm.source_system   = 'BL_3NF'
            AND dm.source_entity   = 'CE_CUSTOMERS_SCD'
            AND dm.start_dt        = src.start_dt::DATE
      );
    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    CALL BL_CL.prc_log_insert('prc_load_dim_customers_scd', v_inserted, v_updated, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- 3.8  prc_load_dim_time_day
-- Target : BL_DM.DIM_TIME_DAY  (Type 0 — generated once, never re-sourced)
-- Source : generate_series (no 3NF source table)
-- Range  : 2015-01-01 … 2030-12-31
-- ============================================================================
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_dim_time_day()
LANGUAGE plpgsql AS $$
DECLARE
    v_inserted INT;
BEGIN
    -- Default row
    INSERT INTO BL_DM.DIM_TIME_DAY (
        time_day_surr_id, date_dt,
        day_no, month_no, quarter_no, year_no, week_no,
        day_name, month_name, is_weekend,
        insert_dt, update_dt
    ) VALUES (
        -1, DATE '1900-01-01',
        -1, -1, -1, -1, -1,
        'n.a.', 'n.a.', 'N',
        CURRENT_DATE, CURRENT_DATE
    ) ON CONFLICT DO NOTHING;

    -- Single batch INSERT for all dates (2015-01-01 … 2030-12-31)
    INSERT INTO BL_DM.DIM_TIME_DAY (
        time_day_surr_id, date_dt,
        day_no, month_no, quarter_no, year_no, week_no,
        day_name, month_name, is_weekend,
        insert_dt, update_dt
    )
    SELECT
        NEXTVAL('BL_DM.SEQ_DIM_TIME_DAY_ID'),
        gs::DATE,
        EXTRACT(DAY     FROM gs)::INT,
        EXTRACT(MONTH   FROM gs)::INT,
        EXTRACT(QUARTER FROM gs)::INT,
        EXTRACT(YEAR    FROM gs)::INT,
        EXTRACT(WEEK    FROM gs)::INT,
        TRIM(TO_CHAR(gs, 'Day')),
        TRIM(TO_CHAR(gs, 'Month')),
        CASE WHEN EXTRACT(ISODOW FROM gs) IN (6, 7) THEN 'Y' ELSE 'N' END,
        CURRENT_DATE, CURRENT_DATE
    FROM generate_series('2015-01-01'::DATE, '2030-12-31'::DATE,
                         INTERVAL '1 day') AS gs
    ON CONFLICT (date_dt) DO NOTHING;   -- idempotent: skip already-loaded dates

    GET DIAGNOSTICS v_inserted = ROW_COUNT;

    CALL BL_CL.prc_log_insert('prc_load_dim_time_day', v_inserted, 0, 'SUCCESS');
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- SECTION 4: MASTER WRAPPER PROCEDURE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- prc_load_all_dm_dims
-- Calls all dimension procedures in dependency order:
--   calendar first (no FK dependencies)
--   → simple lookup dimensions
--   → DIM_PRODUCTS (depends on BL_3NF hierarchy tables)
--   → DIM_CUSTOMERS_SCD last (depends on CE_CITIES + CE_COUNTRIES)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_all_dm_dims()
LANGUAGE plpgsql AS $$
BEGIN
    CALL BL_CL.prc_load_dim_time_day();
    CALL BL_CL.prc_load_dim_channels();
    CALL BL_CL.prc_load_dim_payment_methods();
    CALL BL_CL.prc_load_dim_shipping_types();
    CALL BL_CL.prc_load_dim_payment_terms();
    CALL BL_CL.prc_load_dim_employees();
    CALL BL_CL.prc_load_dim_products();
    CALL BL_CL.prc_load_dim_customers_scd();

    CALL BL_CL.prc_log_insert(
        'prc_load_all_dm_dims', 0, 0, 'SUCCESS',
        'All BL_DM dimension procedures completed successfully.'
    );
EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================================
-- EXECUTION
-- ============================================================================
-- Run the master procedure to load all dimensions (make sure Auto Commit
-- is enabled in the pgAdmin Query Tool toolbar before running):
CALL BL_CL.prc_load_all_dm_dims();

-- ============================================================================
-- REPEATABILITY TEST
-- ============================================================================
-- First run: rows_inserted > 0 for each procedure.
SELECT procedure_name, load_dt, rows_inserted, rows_updated, status
FROM BL_CL.MTA_LOAD_LOG
ORDER BY log_id;

-- Second run (same source data): rows_inserted = 0 for every procedure,
-- because ON CONFLICT … DO UPDATE WHERE (IS DISTINCT FROM) skips unchanged
-- rows, and ON CONFLICT (date_dt) DO NOTHING skips already-loaded dates.
CALL BL_CL.prc_load_all_dm_dims();

SELECT procedure_name, load_dt, rows_inserted, rows_updated, status
FROM BL_CL.MTA_LOAD_LOG
ORDER BY log_id;

-- ============================================================================
-- SPOT-CHECK QUERIES
-- ============================================================================
SELECT COUNT(*) AS dim_products_rows      FROM BL_DM.DIM_PRODUCTS;
SELECT COUNT(*) AS dim_employees_rows     FROM BL_DM.DIM_EMPLOYEES;
SELECT COUNT(*) AS dim_channels_rows      FROM BL_DM.DIM_CHANNELS;
SELECT COUNT(*) AS dim_paymethod_rows     FROM BL_DM.DIM_PAYMENT_METHODS;
SELECT COUNT(*) AS dim_shipping_rows      FROM BL_DM.DIM_SHIPPING_TYPES;
SELECT COUNT(*) AS dim_payterms_rows      FROM BL_DM.DIM_PAYMENT_TERMS;
SELECT COUNT(*) AS dim_customers_scd_rows FROM BL_DM.DIM_CUSTOMERS_SCD;
SELECT COUNT(*) AS dim_time_day_rows      FROM BL_DM.DIM_TIME_DAY;

-- SCD2 version check — shows open vs closed versions per customer
SELECT
    customer_src_id,
    customer_type,
    account_tier,
    loyalty_member,
    start_dt,
    end_dt,
    is_active
FROM BL_DM.DIM_CUSTOMERS_SCD
WHERE customer_surr_id <> -1
ORDER BY customer_src_id, start_dt
LIMIT 20;
