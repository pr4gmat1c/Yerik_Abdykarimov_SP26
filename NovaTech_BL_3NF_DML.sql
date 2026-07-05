-- =============================================================================
-- Business Layer 3NF (schema BL_3NF)
-- =============================================================================
--
-- This file is divided into two sections:
--   SECTION A — default "Not Applicable" row for every dimension table.
--               Run once after the DDL script; safe to re-run via
--               ON CONFLICT DO NOTHING.
--   SECTION B — regular loads from the staging layer (sa_b2c / sa_b2b)
--               into BL_3NF. Safe to re-run (NOT EXISTS-guarded); intended
--               to be scheduled on every extract cycle.
--
-- Load order: hierarchy parents before children
--   CE_PRODUCT_CATEGORIES -> CE_PRODUCT_TYPES -> CE_PRODUCTS
--   CE_COUNTRIES -> CE_CITIES -> CE_CUSTOMERS_SCD
--   remaining reference tables (CE_EMPLOYEES, CE_CHANNELS, CE_PAYMENT_METHODS,
--   CE_SHIPPING_TYPES, CE_PAYMENT_TERMS)
--   CE_SALES last — it requires every dimension's surrogate key to already
--   be in place.
--
-- NULL handling: every attribute is NOT NULL in BL_3NF (see DDL). Every
-- value read from staging or computed during the load is wrapped in
-- COALESCE with a fixed sentinel — -1 for numeric/surrogate columns,
-- DATE '1900-01-01' for dates — so no NULL is ever written. Text sentinel
-- choice: 'Manual' is used exclusively for the source triplet columns of
-- records that are manually introduced into the model (Section A default
-- rows). 'n.a.' is used for all attribute values that are not available
-- or not applicable (e.g. a B2B-only attribute on a B2C-sourced row).
--
-- Idempotency: every INSERT uses a NOT EXISTS guard on the full source
-- triplet of the target table, so a re-run against unchanged staging data
-- inserts 0 new rows. Every section ends with an explicit COMMIT.
--
-- Type conversion: all staging columns are VARCHAR(1000). BL_3NF is where
-- the correct data types are assigned. Every value pulled from staging is
-- explicitly cast (::DATE, ::INT, ::NUMERIC(p,s), ::BIGINT) to the
-- BL_3NF column's declared type at the point it is selected.
-- =============================================================================


-- #############################################################################
-- SECTION A — DEFAULT ROWS
-- #############################################################################
-- Each BL_3NF dimension table receives one "Not Applicable" row:
--   - Numeric/surrogate keys = -1
--   - Source triplet (_src_id, source_system, source_table) = 'Manual'
--     ('Manual' means this record was manually introduced, not extracted)
--   - Attribute values = 'n.a.' (not applicable / not available)
--   - Dates = DATE '1900-01-01'
-- CE_SALES does not receive a default row (it is a fact table).

BEGIN;

-- CE_PRODUCT_CATEGORIES
INSERT INTO BL_3NF.CE_PRODUCT_CATEGORIES
    (product_category_id, source_id, source_system, source_table, product_category_name, insert_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (product_category_id) DO NOTHING;

-- CE_PRODUCT_TYPES
INSERT INTO BL_3NF.CE_PRODUCT_TYPES
    (product_type_id, source_id, source_system, source_table, product_type_name, product_category_id, insert_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', -1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (product_type_id) DO NOTHING;

-- CE_PRODUCTS
INSERT INTO BL_3NF.CE_PRODUCTS
    (product_id, source_id, source_system, source_table, sku, product_type_id, brand, product_status, insert_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', -1, 'n.a.', -1, -1, 'n.a.', -1, 'n.a.',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (product_id) DO NOTHING;

-- CE_COUNTRIES
INSERT INTO BL_3NF.CE_COUNTRIES
    (country_id, country_src_id, source_id, source_system, source_table, country_name, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (country_id) DO NOTHING;

-- CE_CITIES
INSERT INTO BL_3NF.CE_CITIES
    (city_id, city_src_id, source_system, source_table, city_name, country_id, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', -1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (city_id) DO NOTHING;

-- CE_EMPLOYEES — the row every B2C sale points to (B2C orders have no account manager)
INSERT INTO BL_3NF.CE_EMPLOYEES
    (employee_id, employee_src_id, source_system, source_table, employee_name, department,
     region_assigned, hire_date, email, sales_quota, performance_tier, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', 'n.a.', 'n.a.', DATE '1900-01-01',
     'n.a.', -1, 'n.a.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (employee_id) DO NOTHING;

-- CE_CHANNELS — the channel set is small and fixed, so both real channel rows
-- (B2C = 1, B2B = 2) are seeded here alongside the default row.
INSERT INTO BL_3NF.CE_CHANNELS
    (channel_id, channel_src_id, source_system, source_table, channel_name, originating_system_name, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', 'n.a.', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    (1, 'B2C',  'MANUAL', 'MANUAL', 'B2C',  'NovaTech Direct',            CURRENT_TIMESTAMP),
    (2, 'B2B',  'MANUAL', 'MANUAL', 'B2B',  'NovaTech Business Solutions', CURRENT_TIMESTAMP)
ON CONFLICT (channel_id) DO NOTHING;

-- CE_PAYMENT_METHODS — the row every B2B sale points to (B2B uses invoicing terms,
-- not a per-transaction payment method)
INSERT INTO BL_3NF.CE_PAYMENT_METHODS
    (payment_method_id, payment_method_src_id, source_system, source_table, payment_method_name,
     payment_channel_type, processing_fee_percent, settlement_period_days, refundable, currency_accepted,
     minimum_transaction_amount, availability_channel, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', 'n.a.', -1, -1, 'n.a.', 'n.a.', -1, 'n.a.',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (payment_method_id) DO NOTHING;

-- CE_SHIPPING_TYPES — the row every B2B sale points to (B2B orders carry no
-- per-line shipping type in this dataset)
INSERT INTO BL_3NF.CE_SHIPPING_TYPES
    (shipping_type_id, shipping_type_src_id, source_system, source_table, shipping_type_name,
     shipping_carrier, estimated_delivery_days, shipping_cost_tier, free_shipping_eligible,
     tracking_available, max_package_weight_kg, international_shipping_available, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', 'n.a.', 'n.a.', 'n.a.', 'n.a.', 'n.a.', -1, 'n.a.',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (shipping_type_id) DO NOTHING;

-- CE_PAYMENT_TERMS — the row every B2C sale points to (B2C customers pay per
-- transaction, not on invoicing terms)
INSERT INTO BL_3NF.CE_PAYMENT_TERMS
    (payment_terms_id, payment_terms_src_id, source_system, source_table, payment_terms_name,
     payment_due_days, early_payment_discount_pct, late_payment_penalty_pct, currency,
     preferred_payment_method, terms_effective_date, insert_dt, update_dt)
VALUES
    (-1, 'Manual', 'Manual', 'Manual', 'n.a.', -1, -1, -1, 'n.a.', 'n.a.', DATE '1900-01-01',
     CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT (payment_terms_id) DO NOTHING;

-- CE_CUSTOMERS_SCD — every sale always has a real customer or company, so
-- this default row exists only for structural completeness.
INSERT INTO BL_3NF.CE_CUSTOMERS_SCD
    (customer_id, start_dt, customer_src_id, source_system, source_table, customer_type, customer_name,
     date_of_birth, gender, loyalty_member, customer_segment, industry, account_tier, company_size,
     onboarding_date, credit_limit, approver_name, budget_code, city_id, end_dt, is_active, insert_dt)
VALUES
    (-1, TIMESTAMP '1900-01-01', 'Manual', 'Manual', 'Manual', 'n.a.', 'n.a.',
     DATE '1900-01-01', 'n.a.', 'n.a.', 'n.a.', 'n.a.', 'n.a.', 'n.a.',
     DATE '1900-01-01', -1, 'n.a.', 'n.a.', -1, TIMESTAMP '9999-12-31 00:00:00', TRUE, CURRENT_TIMESTAMP)
ON CONFLICT (customer_id, start_dt) DO NOTHING;

COMMIT;
-- #############################################################################
-- SECTION B — REGULAR LOADS
-- #############################################################################

BEGIN;

-- =============================================================================
-- B.1  CE_PRODUCT_CATEGORIES  <-  distinct product_category values, loaded
-- separately per source and combined with UNION ALL. A category present in
-- both files produces one row per source (source_system differs), since
-- cross-source conforming is not performed at this layer.
-- =============================================================================
INSERT INTO BL_3NF.CE_PRODUCT_CATEGORIES
    (product_category_id, product_category_src_id, source_system, source_table, product_category_name, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_CATEGORY_ID'),
    COALESCE(x.product_category_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.product_category_name, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT product_category AS product_category_src_id,
                    product_category AS product_category_name,
           'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT product_category AS product_category_src_id,
                    product_category AS product_category_name,
           'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_PRODUCT_CATEGORIES t
    WHERE UPPER(t.product_category_src_id) = UPPER(x.product_category_src_id)
      AND UPPER(t.source_system)            = UPPER(x.source_system)
      AND UPPER(t.source_table)              = UPPER(x.source_table)
);

-- =============================================================================
-- B.2  CE_PRODUCT_TYPES  <-  distinct (product_type, product_category) pairs
-- per source, combined with UNION ALL. product_category_id is resolved by
-- joining to the category row from the SAME source triplet.
-- =============================================================================
INSERT INTO BL_3NF.CE_PRODUCT_TYPES
    (product_type_id, product_type_src_id, source_system, source_table, product_type_name, product_category_id, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_TYPE_ID'),
    COALESCE(x.product_type_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.product_type_name, 'n.a.'),
    COALESCE(cat.product_category_id, -1),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT product_type    AS product_type_src_id,
                    product_type    AS product_type_name,
                    product_category AS product_category_src_id,
           'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT product_type    AS product_type_src_id,
                    product_type    AS product_type_name,
                    product_category AS product_category_src_id,
           'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
) x
LEFT JOIN BL_3NF.CE_PRODUCT_CATEGORIES cat
    ON UPPER(cat.product_category_src_id) = UPPER(x.product_category_src_id)
   AND UPPER(cat.source_system)            = UPPER(x.source_system)
   AND UPPER(cat.source_table)              = UPPER(x.source_table)
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_PRODUCT_TYPES t
    WHERE UPPER(t.product_type_src_id) = UPPER(x.product_type_src_id)
      AND UPPER(t.source_system)        = UPPER(x.source_system)
      AND UPPER(t.source_table)          = UPPER(x.source_table)
);

-- =============================================================================
-- B.3  CE_PRODUCTS  <-  one row per SKU per source, combined with UNION ALL.
-- Each branch keeps only the attributes its own source provides;
-- attributes that belong to the other channel are populated with
-- sentinels (-1 / 'Manual'). product_type_id is resolved by joining to the
-- type row from the SAME source triplet. DISTINCT ON (sku) within each
-- branch picks one representative row per SKU from that source's raw order
-- lines (a mechanical pick, not a cross-source merge).
-- =============================================================================
INSERT INTO BL_3NF.CE_PRODUCTS
    (product_id, product_src_id, source_system, source_table, sku, product_type_id, brand,
     warranty_period_months, launch_year, bulk_packaging_unit, minimum_order_quantity,
     product_status, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_ID'),
    COALESCE(x.product_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.product_src_id, 'n.a.'),
    COALESCE(pt.product_type_id, -1),
    COALESCE(x.brand, 'n.a.'),
    COALESCE(x.warranty_period_months, -1),
    COALESCE(x.launch_year, -1),
    COALESCE(x.bulk_packaging_unit, 'n.a.'),
    COALESCE(x.minimum_order_quantity, -1),
    COALESCE(x.product_status, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    (SELECT DISTINCT ON (sku)
        sku                     AS product_src_id,
        product_type            AS product_type_src_id,
        brand,
        warranty_period_months::INT AS warranty_period_months,
        launch_year::INT            AS launch_year,
        NULL::VARCHAR(50)           AS bulk_packaging_unit,
        NULL::INT                   AS minimum_order_quantity,
        product_status,
        'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    ORDER BY sku, order_id::BIGINT)
    UNION ALL
    (SELECT DISTINCT ON (sku)
        sku                     AS product_src_id,
        product_type            AS product_type_src_id,
        brand,
        NULL::INT                        AS warranty_period_months,
        NULL::INT                        AS launch_year,
        bulk_packaging_unit,
        minimum_order_quantity::INT      AS minimum_order_quantity,
        product_status,
        'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY sku, order_id::BIGINT)
) x
LEFT JOIN BL_3NF.CE_PRODUCT_TYPES pt
    ON UPPER(pt.product_type_src_id) = UPPER(x.product_type_src_id)
   AND UPPER(pt.source_system)        = UPPER(x.source_system)
   AND UPPER(pt.source_table)          = UPPER(x.source_table)
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_PRODUCTS t
    WHERE UPPER(t.product_src_id) = UPPER(x.product_src_id)
      AND UPPER(t.source_system)   = UPPER(x.source_system)
      AND UPPER(t.source_table)     = UPPER(x.source_table)
);
-- =============================================================================
-- B.4  CE_COUNTRIES  <-  distinct country values per source, combined with
-- UNION ALL.
-- =============================================================================
INSERT INTO BL_3NF.CE_COUNTRIES
    (country_id, country_src_id, source_system, source_table, country_name, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_COUNTRY_ID'),
    COALESCE(x.country_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.country_name, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT country AS country_src_id,
                    country AS country_name,
           'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT country AS country_src_id,
                    country AS country_name,
           'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_COUNTRIES t
    WHERE UPPER(t.country_src_id) = UPPER(x.country_src_id)
      AND UPPER(t.source_system)   = UPPER(x.source_system)
      AND UPPER(t.source_table)     = UPPER(x.source_table)
);

-- =============================================================================
-- B.5  CE_CITIES  <-  distinct (city, country) pairs per source, combined
-- with UNION ALL. city_src_id stores 'city|country' so cities sharing a
-- name across different countries stay distinct. country_id is resolved by
-- joining to the country row from the SAME source triplet.
-- =============================================================================
INSERT INTO BL_3NF.CE_CITIES
    (city_id, city_src_id, source_system, source_table, city_name, country_id, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_CITY_ID'),
    COALESCE(x.city_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.city_name, 'n.a.'),
    COALESCE(co.country_id, -1),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT city || '|' || country AS city_src_id,
                    city                    AS city_name,
                    country                 AS country_src_id,
           'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT city || '|' || country AS city_src_id,
                    city                    AS city_name,
                    country                 AS country_src_id,
           'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
) x
LEFT JOIN BL_3NF.CE_COUNTRIES co
    ON UPPER(co.country_src_id) = UPPER(x.country_src_id)
   AND UPPER(co.source_system)   = UPPER(x.source_system)
   AND UPPER(co.source_table)     = UPPER(x.source_table)
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_CITIES t
    WHERE UPPER(t.city_src_id) = UPPER(x.city_src_id)
      AND UPPER(t.source_system) = UPPER(x.source_system)
      AND UPPER(t.source_table)   = UPPER(x.source_table)
);

COMMIT;
-- =============================================================================
-- B.6  CE_EMPLOYEES  <-  distinct account managers from the B2B source only
-- (B2C has no employee involved; those sales resolve to the default row,
-- employee_id = -1).
-- =============================================================================
BEGIN;

INSERT INTO BL_3NF.CE_EMPLOYEES
    (employee_id, employee_src_id, source_system, source_table, employee_name, department,
     region_assigned, hire_date, email, sales_quota, performance_tier, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_EMPLOYEE_ID'),
    COALESCE(x.employee_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.employee_name, 'n.a.'),
    COALESCE(x.department, 'n.a.'),
    COALESCE(x.region_assigned, 'n.a.'),
    COALESCE(x.hire_date, DATE '1900-01-01'),
    COALESCE(x.email, 'n.a.'),
    COALESCE(x.sales_quota, -1),
    COALESCE(x.performance_tier, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT ON (account_manager_id)
        account_manager_id AS employee_src_id, account_manager_name AS employee_name,
        department, region_assigned,
        hire_date::DATE            AS hire_date,
        email,
        sales_quota::NUMERIC(12,2) AS sales_quota,
        performance_tier,
        'SA_NOVATECH_BUSINESS' AS source_system, 'src_novatech_b2b_orders' AS source_table
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY account_manager_id, order_id::BIGINT
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_EMPLOYEES t
    WHERE UPPER(t.employee_src_id) = UPPER(x.employee_src_id)
      AND UPPER(t.source_system)    = UPPER(x.source_system)
      AND UPPER(t.source_table)      = UPPER(x.source_table)
);
-- =============================================================================
-- B.7  CE_PAYMENT_METHODS  <-  distinct payment methods from the B2C source
-- only (B2B always resolves to the default row, payment_method_id = -1).
-- INITCAP() normalizes casing inconsistencies in the source (e.g. 'PayPal'
-- and 'Paypal' are treated as the same value).
-- =============================================================================
INSERT INTO BL_3NF.CE_PAYMENT_METHODS
    (payment_method_id, payment_method_src_id, source_system, source_table, payment_method_name,
     payment_channel_type, processing_fee_percent, settlement_period_days, refundable, currency_accepted,
     minimum_transaction_amount, availability_channel, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PAYMENT_METHOD_ID'),
    COALESCE(x.payment_method_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.payment_method_name, 'n.a.'),
    COALESCE(x.payment_channel_type, 'n.a.'),
    COALESCE(x.processing_fee_percent, -1),
    COALESCE(x.settlement_period_days, -1),
    COALESCE(x.refundable, 'n.a.'),
    COALESCE(x.currency_accepted, 'n.a.'),
    COALESCE(x.minimum_transaction_amount, -1),
    COALESCE(x.availability_channel, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT ON (payment_method_src_id)
        payment_method_src_id,
        payment_method_src_id AS payment_method_name,
        payment_channel_type,
        processing_fee_percent::NUMERIC(5,2)    AS processing_fee_percent,
        settlement_period_days::INT              AS settlement_period_days,
        refundable, currency_accepted,
        minimum_transaction_amount::NUMERIC(10,2) AS minimum_transaction_amount,
        availability_channel,
        order_id,
        'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM (
        SELECT order_id, INITCAP(payment_method) AS payment_method_src_id,
               payment_channel_type, processing_fee_percent, settlement_period_days,
               refundable, currency_accepted, minimum_transaction_amount, availability_channel
        FROM sa_b2c.src_novatech_b2c_orders
    ) norm
    ORDER BY payment_method_src_id, order_id::BIGINT
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_PAYMENT_METHODS t
    WHERE UPPER(t.payment_method_src_id) = UPPER(x.payment_method_src_id)
      AND UPPER(t.source_system)          = UPPER(x.source_system)
      AND UPPER(t.source_table)            = UPPER(x.source_table)
);

-- =============================================================================
-- B.8  CE_SHIPPING_TYPES  <-  distinct shipping types from the B2C source
-- only (B2B always resolves to the default row, shipping_type_id = -1).
-- estimated_delivery_days stays VARCHAR because the source stores range
-- values (e.g. '0-1', '5-7').
-- =============================================================================
INSERT INTO BL_3NF.CE_SHIPPING_TYPES
    (shipping_type_id, shipping_type_src_id, source_system, source_table, shipping_type_name,
     shipping_carrier, estimated_delivery_days, shipping_cost_tier, free_shipping_eligible,
     tracking_available, max_package_weight_kg, international_shipping_available, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_SHIPPING_TYPE_ID'),
    COALESCE(x.shipping_type_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.shipping_type_name, 'n.a.'),
    COALESCE(x.shipping_carrier, 'n.a.'),
    COALESCE(x.estimated_delivery_days, 'n.a.'),
    COALESCE(x.shipping_cost_tier, 'n.a.'),
    COALESCE(x.free_shipping_eligible, 'n.a.'),
    COALESCE(x.tracking_available, 'n.a.'),
    COALESCE(x.max_package_weight_kg, -1),
    COALESCE(x.intl_shipping_available, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT ON (shipping_type)
        shipping_type AS shipping_type_src_id,
        shipping_type AS shipping_type_name,
        shipping_carrier, estimated_delivery_days, shipping_cost_tier,
        free_shipping_eligible, tracking_available,
        max_package_weight_kg::INT AS max_package_weight_kg,
        intl_shipping_available,
        'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    ORDER BY shipping_type, order_id::BIGINT
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_SHIPPING_TYPES t
    WHERE UPPER(t.shipping_type_src_id) = UPPER(x.shipping_type_src_id)
      AND UPPER(t.source_system)         = UPPER(x.source_system)
      AND UPPER(t.source_table)           = UPPER(x.source_table)
);

-- =============================================================================
-- B.9  CE_PAYMENT_TERMS  <-  distinct payment terms from the B2B source only
-- (B2C always resolves to the default row, payment_terms_id = -1).
-- =============================================================================
INSERT INTO BL_3NF.CE_PAYMENT_TERMS
    (payment_terms_id, payment_terms_src_id, source_system, source_table, payment_terms_name,
     payment_due_days, early_payment_discount_pct, late_payment_penalty_pct, currency,
     preferred_payment_method, terms_effective_date, insert_dt, update_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PAYMENT_TERMS_ID'),
    COALESCE(x.payment_terms_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.payment_terms_name, 'n.a.'),
    COALESCE(x.payment_due_days, -1),
    COALESCE(x.early_payment_discount_pct, -1),
    COALESCE(x.late_payment_penalty_pct, -1),
    COALESCE(x.currency, 'n.a.'),
    COALESCE(x.preferred_payment_method, 'n.a.'),
    COALESCE(x.terms_effective_date, DATE '1900-01-01'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT DISTINCT ON (payment_terms)
        payment_terms AS payment_terms_src_id,
        payment_terms AS payment_terms_name,
        payment_due_days::INT                    AS payment_due_days,
        early_payment_discount_pct::NUMERIC(5,2) AS early_payment_discount_pct,
        late_payment_penalty_pct::NUMERIC(5,2)   AS late_payment_penalty_pct,
        currency, preferred_payment_method,
        terms_effective_date::DATE               AS terms_effective_date,
        'SA_NOVATECH_BUSINESS' AS source_system, 'src_novatech_b2b_orders' AS source_table
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY payment_terms, order_id::BIGINT
) x
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_PAYMENT_TERMS t
    WHERE UPPER(t.payment_terms_src_id) = UPPER(x.payment_terms_src_id)
      AND UPPER(t.source_system)         = UPPER(x.source_system)
      AND UPPER(t.source_table)           = UPPER(x.source_table)
);

COMMIT;
-- =============================================================================
-- B.10  CE_CUSTOMERS_SCD  <-  full SCD Type-2 history.
-- One row per version of each customer (B2C) or company (B2B). A new
-- version is opened whenever the tracked attribute changes between orders:
--   B2C: loyalty_member
--   B2B: account_tier
-- The two source streams are combined with UNION ALL and processed together.
-- LAG() detects a change in the tracked attribute (ordered by order date);
-- LEAD() computes the end date of the version being closed. Every order
-- event is used directly — no separate deduplication step collapses same-
-- day repeat orders before computing versions.
-- On every run:
--   B.10.a — closes (UPDATE) any open version superseded by a newer one.
--   B.10.b — inserts any version not yet present in the table.
-- customer_id is durable across versions: a returning customer (matched on
-- the full source triplet) reuses its existing id; a new customer gets a
-- freshly-sequenced id.
-- date_of_birth is populated with the sentinel DATE '1900-01-01' for B2C
-- rows because the source provides customer_age, not date_of_birth.
-- end_dt uses TIMESTAMP '9999-12-31 00:00:00' for the currently active
-- version instead of NULL.
-- =============================================================================

BEGIN;

WITH all_events AS (
    SELECT
        'Individual'                AS customer_type,
        customer_id                 AS customer_src_id,
        'SA_NOVATECH_DIRECT'        AS source_system,
        'src_novatech_b2c_orders'   AS source_table,
        order_date::DATE            AS event_dt,
        customer_name               AS customer_name,
        DATE '1900-01-01'           AS date_of_birth,
        customer_gender             AS gender,
        loyalty_member               AS loyalty_member,
        customer_segment            AS customer_segment,
        'n.a.'                      AS industry,
        'n.a.'                      AS account_tier,
        'n.a.'                      AS company_size,
        DATE '1900-01-01'           AS onboarding_date,
        CAST(-1 AS NUMERIC(12,2))   AS credit_limit,
        'n.a.'                      AS approver_name,
        'n.a.'                      AS budget_code,
        country                     AS country_src_id,
        city || '|' || country      AS city_src_id,
        loyalty_member               AS tracked_attr
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT
        'Business',
        company_id,
        'SA_NOVATECH_BUSINESS',
        'src_novatech_b2b_orders',
        order_date::DATE,
        company_name,
        DATE '1900-01-01',
        'n.a.',
        'n.a.',
        'n.a.',
        industry,
        account_tier,
        company_size,
        onboarding_date::DATE,
        credit_limit::NUMERIC(12,2),
        approver_name,
        budget_code,
        country,
        city || '|' || country,
        account_tier
    FROM sa_b2b.src_novatech_b2b_orders
),
flagged AS (
    SELECT *,
        CASE
            WHEN LAG(tracked_attr) OVER (PARTITION BY customer_type, customer_src_id ORDER BY event_dt)
                 IS DISTINCT FROM tracked_attr
            THEN 1 ELSE 0
        END AS is_new_version
    FROM all_events
),
versions_raw AS (
    SELECT * FROM flagged WHERE is_new_version = 1
),
versions AS (
    SELECT *,
        LEAD(event_dt) OVER (PARTITION BY customer_type, customer_src_id ORDER BY event_dt) AS next_start_dt
    FROM versions_raw
),
resolved AS (
    SELECT
        v.*,
        COALESCE(ci.city_id, -1) AS city_id
    FROM versions v
    LEFT JOIN BL_3NF.CE_COUNTRIES co
        ON UPPER(co.country_src_id) = UPPER(v.country_src_id)
       AND UPPER(co.source_system)   = UPPER(v.source_system)
       AND UPPER(co.source_table)     = UPPER(v.source_table)
    LEFT JOIN BL_3NF.CE_CITIES ci
        ON UPPER(ci.city_src_id) = UPPER(v.city_src_id)
       AND UPPER(ci.source_system) = UPPER(v.source_system)
       AND UPPER(ci.source_table)   = UPPER(v.source_table)
)

-- B.10.a — close any previously open version that is now superseded
UPDATE BL_3NF.CE_CUSTOMERS_SCD t
SET end_dt    = COALESCE(r.next_start_dt::TIMESTAMP, TIMESTAMP '9999-12-31 00:00:00'),
    is_active = (r.next_start_dt IS NULL)
FROM resolved r
WHERE UPPER(t.customer_src_id) = UPPER(r.customer_src_id)
  AND UPPER(t.source_system)    = UPPER(r.source_system)
  AND UPPER(t.source_table)      = UPPER(r.source_table)
  AND t.start_dt = r.event_dt::TIMESTAMP
  AND t.end_dt IS DISTINCT FROM COALESCE(r.next_start_dt::TIMESTAMP, TIMESTAMP '9999-12-31 00:00:00');


-- B.10.b — insert any version not yet present
WITH all_events AS (
    SELECT
        'Individual'                AS customer_type,
        customer_id                 AS customer_src_id,
        'SA_NOVATECH_DIRECT'        AS source_system,
        'src_novatech_b2c_orders'   AS source_table,
        order_date::DATE            AS event_dt,
        customer_name               AS customer_name,
        DATE '1900-01-01'           AS date_of_birth,
        customer_gender             AS gender,
        loyalty_member               AS loyalty_member,
        customer_segment            AS customer_segment,
        'n.a.'                      AS industry,
        'n.a.'                      AS account_tier,
        'n.a.'                      AS company_size,
        DATE '1900-01-01'           AS onboarding_date,
        CAST(-1 AS NUMERIC(12,2))   AS credit_limit,
        'n.a.'                      AS approver_name,
        'n.a.'                      AS budget_code,
        country                     AS country_src_id,
        city || '|' || country      AS city_src_id,
        loyalty_member               AS tracked_attr
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT
        'Business',
        company_id,
        'SA_NOVATECH_BUSINESS',
        'src_novatech_b2b_orders',
        order_date::DATE,
        company_name,
        DATE '1900-01-01',
        'n.a.',
        'n.a.',
        'n.a.',
        industry,
        account_tier,
        company_size,
        onboarding_date::DATE,
        credit_limit::NUMERIC(12,2),
        approver_name,
        budget_code,
        country,
        city || '|' || country,
        account_tier
    FROM sa_b2b.src_novatech_b2b_orders
),
flagged AS (
    SELECT *,
        CASE
            WHEN LAG(tracked_attr) OVER (PARTITION BY customer_type, customer_src_id ORDER BY event_dt)
                 IS DISTINCT FROM tracked_attr
            THEN 1 ELSE 0
        END AS is_new_version
    FROM all_events
),
versions_raw AS (
    SELECT * FROM flagged WHERE is_new_version = 1
),
versions AS (
    SELECT *,
        LEAD(event_dt) OVER (PARTITION BY customer_type, customer_src_id ORDER BY event_dt) AS next_start_dt
    FROM versions_raw
),
resolved AS (
    SELECT
        v.*,
        COALESCE(ci.city_id, -1) AS city_id
    FROM versions v
    LEFT JOIN BL_3NF.CE_COUNTRIES co
        ON UPPER(co.country_src_id) = UPPER(v.country_src_id)
       AND UPPER(co.source_system)   = UPPER(v.source_system)
       AND UPPER(co.source_table)     = UPPER(v.source_table)
    LEFT JOIN BL_3NF.CE_CITIES ci
        ON UPPER(ci.city_src_id) = UPPER(v.city_src_id)
       AND UPPER(ci.source_system) = UPPER(v.source_system)
       AND UPPER(ci.source_table)   = UPPER(v.source_table)
),
existing_customer_ids AS (
    SELECT DISTINCT customer_src_id, source_system, source_table, customer_id
    FROM BL_3NF.CE_CUSTOMERS_SCD
)
INSERT INTO BL_3NF.CE_CUSTOMERS_SCD
    (customer_id, start_dt, customer_src_id, source_system, source_table, customer_type, customer_name,
     date_of_birth, gender, loyalty_member, customer_segment, industry, account_tier, company_size,
     onboarding_date, credit_limit, approver_name, budget_code, city_id, end_dt, is_active, insert_dt)
SELECT
    COALESCE(ex.customer_id, NEXTVAL('BL_3NF.SEQ_CUSTOMER_ID')),
    r.event_dt::TIMESTAMP,
    COALESCE(r.customer_src_id, 'n.a.'),
    COALESCE(r.source_system, 'Manual'),
    COALESCE(r.source_table, 'Manual'),
    COALESCE(r.customer_type, 'n.a.'),
    COALESCE(r.customer_name, 'n.a.'),
    COALESCE(r.date_of_birth, DATE '1900-01-01'),
    COALESCE(r.gender, 'n.a.'),
    COALESCE(r.loyalty_member, 'n.a.'),
    COALESCE(r.customer_segment, 'n.a.'),
    COALESCE(r.industry, 'n.a.'),
    COALESCE(r.account_tier, 'n.a.'),
    COALESCE(r.company_size, 'n.a.'),
    COALESCE(r.onboarding_date, DATE '1900-01-01'),
    COALESCE(r.credit_limit, -1),
    COALESCE(r.approver_name, 'n.a.'),
    COALESCE(r.budget_code, 'n.a.'),
    COALESCE(r.city_id, -1),
    COALESCE(r.next_start_dt::TIMESTAMP, TIMESTAMP '9999-12-31 00:00:00'),
    (r.next_start_dt IS NULL),
    CURRENT_TIMESTAMP
FROM resolved r
LEFT JOIN existing_customer_ids ex
    ON UPPER(ex.customer_src_id) = UPPER(r.customer_src_id)
   AND UPPER(ex.source_system)    = UPPER(r.source_system)
   AND UPPER(ex.source_table)      = UPPER(r.source_table)
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_CUSTOMERS_SCD ex2
    WHERE UPPER(ex2.customer_src_id) = UPPER(r.customer_src_id)
      AND UPPER(ex2.source_system)    = UPPER(r.source_system)
      AND UPPER(ex2.source_table)      = UPPER(r.source_table)
      AND ex2.start_dt = r.event_dt::TIMESTAMP
);

COMMIT;
-- =============================================================================
-- B.11  CE_SALES  <-  one row per order line, both channels loaded in a
-- single INSERT via UNION ALL. Every dimension lookup uses LEFT JOIN with
-- UPPER() on both sides of the comparison and COALESCE(<id>, -1), so a
-- channel-specific dimension that does not apply to a given order (e.g.
-- payment_terms on a B2C row) resolves to that table's "Not Applicable"
-- default row instead of a NULL foreign key.
-- customer_id is resolved to the SCD version active on the order date via
-- a date-range join on start_dt / end_dt, matched on the full customer
-- source triplet.
-- channel_id is resolved dynamically from CE_CHANNELS by channel_name
-- ('B2C' / 'B2B') rather than hardcoded, consistent with every other FK
-- lookup in this load.
-- All values read from the (fully untyped) staging tables are explicitly
-- cast to the BL_3NF column's declared type, then wrapped in COALESCE with
-- a sentinel (-1 / 'n.a.' / DATE '1900-01-01').
-- resolution_time_days is stored as a decimal string in the source (e.g.
-- '9.0'), so it is cast via ::NUMERIC(5,1)::INT rather than directly to INT.
-- =============================================================================

BEGIN;

INSERT INTO BL_3NF.CE_SALES
    (product_id, customer_id, employee_id, channel_id, payment_method_id, shipping_type_id, payment_terms_id,
     sales_id, sales_src_id, source_system, source_table, order_id, order_date, order_status, quantity,
     unit_price, unit_cost, total_sales, total_cost, rating, add_on_total, return_or_complaint,
     feedback_comment, resolution_time_days, refund_amount, support_channel_used, escalation_required,
     po_number, po_issue_date, requested_delivery_date, approval_status, po_type, po_value_threshold_flag,
     insert_dt, update_dt)
SELECT
    COALESCE(p.product_id, -1),
    COALESCE(cu.customer_id, -1),
    COALESCE(emp.employee_id, -1),
    COALESCE(ch.channel_id, -1),
    COALESCE(pm.payment_method_id, -1),
    COALESCE(st.shipping_type_id, -1),
    COALESCE(pt.payment_terms_id, -1),
    NEXTVAL('BL_3NF.SEQ_SALES_ID'),
    COALESCE(x.sales_src_id, 'n.a.'),
    COALESCE(x.source_system, 'Manual'),
    COALESCE(x.source_table, 'Manual'),
    COALESCE(x.sales_src_id::BIGINT, -1),
    COALESCE(x.order_date::DATE, DATE '1900-01-01'),
    COALESCE(x.order_status, 'n.a.'),
    COALESCE(x.quantity::INT, -1),
    COALESCE(x.unit_price::NUMERIC(10,2), -1),
    COALESCE(x.unit_cost::NUMERIC(10,2), -1),
    COALESCE(x.total_sales::NUMERIC(12,2), -1),
    COALESCE(x.total_cost::NUMERIC(12,2), -1),
    COALESCE(x.rating::INT, -1),
    COALESCE(x.addon_total::NUMERIC(10,2), -1),
    COALESCE(x.return_or_complaint, 'n.a.'),
    COALESCE(x.feedback_comment, 'n.a.'),
    COALESCE(x.resolution_time_days::NUMERIC(5,1)::INT, -1),
    COALESCE(x.refund_amount::NUMERIC(10,2), -1),
    COALESCE(x.support_channel_used, 'n.a.'),
    COALESCE(x.escalation_required, 'n.a.'),
    COALESCE(x.po_number, 'n.a.'),
    COALESCE(x.po_issue_date::DATE, DATE '1900-01-01'),
    COALESCE(x.requested_delivery_date::DATE, DATE '1900-01-01'),
    COALESCE(x.approval_status, 'n.a.'),
    COALESCE(x.po_type, 'n.a.'),
    COALESCE(x.po_value_threshold_flag, 'n.a.'),
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM (
    SELECT
        order_id AS sales_src_id, order_date,
        customer_id            AS customer_src_id,
        sku                    AS product_src_id,
        INITCAP(payment_method) AS payment_method_src_id,
        shipping_type          AS shipping_type_src_id,
        NULL::VARCHAR AS employee_src_id, NULL::VARCHAR AS payment_terms_src_id,
        order_status, quantity, unit_price, unit_cost, total_sales, total_cost,
        rating, addon_total, return_or_complaint, feedback_comment, resolution_time_days, refund_amount,
        support_channel_used, escalation_required,
        NULL::VARCHAR AS po_number, NULL::VARCHAR AS po_issue_date, NULL::VARCHAR AS requested_delivery_date,
        NULL::VARCHAR AS approval_status, NULL::VARCHAR AS po_type, NULL::VARCHAR AS po_value_threshold_flag,
        'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table, 'B2C' AS channel_flag
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT
        order_id AS sales_src_id, order_date,
        company_id             AS customer_src_id,
        sku                    AS product_src_id,
        NULL::VARCHAR AS payment_method_src_id,
        NULL::VARCHAR AS shipping_type_src_id,
        account_manager_id AS employee_src_id, payment_terms AS payment_terms_src_id,
        order_status, quantity, unit_price, unit_cost, total_sales, total_cost,
        NULL::VARCHAR AS rating, NULL::VARCHAR AS addon_total, NULL::VARCHAR AS return_or_complaint,
        NULL::VARCHAR AS feedback_comment, NULL::VARCHAR AS resolution_time_days, NULL::VARCHAR AS refund_amount,
        NULL::VARCHAR AS support_channel_used, NULL::VARCHAR AS escalation_required,
        po_number, po_issue_date, requested_delivery_date, approval_status, po_type, po_value_threshold_flag,
        'SA_NOVATECH_BUSINESS' AS source_system, 'src_novatech_b2b_orders' AS source_table, 'B2B' AS channel_flag
    FROM sa_b2b.src_novatech_b2b_orders
) x
LEFT JOIN BL_3NF.CE_PRODUCTS p
    ON UPPER(p.product_src_id) = UPPER(x.product_src_id)
   AND UPPER(p.source_system)   = UPPER(x.source_system)
   AND UPPER(p.source_table)     = UPPER(x.source_table)
LEFT JOIN BL_3NF.CE_CUSTOMERS_SCD cu
    ON UPPER(cu.customer_src_id) = UPPER(x.customer_src_id)
   AND UPPER(cu.source_system)    = UPPER(x.source_system)
   AND UPPER(cu.source_table)      = UPPER(x.source_table)
   AND x.order_date::DATE >= cu.start_dt
   AND x.order_date::DATE <  cu.end_dt
LEFT JOIN BL_3NF.CE_EMPLOYEES emp
    ON UPPER(emp.employee_src_id) = UPPER(x.employee_src_id)
   AND UPPER(emp.source_system)    = UPPER(x.source_system)
   AND UPPER(emp.source_table)      = UPPER(x.source_table)
LEFT JOIN BL_3NF.CE_CHANNELS ch
    ON UPPER(ch.channel_name) = UPPER(x.channel_flag)
LEFT JOIN BL_3NF.CE_PAYMENT_METHODS pm
    ON UPPER(pm.payment_method_src_id) = UPPER(x.payment_method_src_id)
   AND UPPER(pm.source_system)          = UPPER(x.source_system)
   AND UPPER(pm.source_table)            = UPPER(x.source_table)
LEFT JOIN BL_3NF.CE_SHIPPING_TYPES st
    ON UPPER(st.shipping_type_src_id) = UPPER(x.shipping_type_src_id)
   AND UPPER(st.source_system)         = UPPER(x.source_system)
   AND UPPER(st.source_table)           = UPPER(x.source_table)
LEFT JOIN BL_3NF.CE_PAYMENT_TERMS pt
    ON UPPER(pt.payment_terms_src_id) = UPPER(x.payment_terms_src_id)
   AND UPPER(pt.source_system)         = UPPER(x.source_system)
   AND UPPER(pt.source_table)           = UPPER(x.source_table)
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_SALES t
    WHERE UPPER(t.sales_src_id) = UPPER(x.sales_src_id)
      AND UPPER(t.source_system) = UPPER(x.source_system)
      AND UPPER(t.source_table)   = UPPER(x.source_table)
);
COMMIT;
