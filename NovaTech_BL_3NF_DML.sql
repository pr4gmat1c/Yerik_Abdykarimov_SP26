-- =============================================================================
-- Business Layer 3NF (schema BL_3NF) — DML: default rows + regular loads
-- =============================================================================
--
-- Load order matters and is followed throughout: hierarchy parents before
-- children (CE_PRODUCT_CATEGORIES -> CE_PRODUCT_TYPES -> CE_PRODUCTS;
-- CE_COUNTRIES -> CE_CITIES -> CE_CUSTOMERS_SCD), then every other
-- dimension/reference table, and CE_SALES loads last, since it is the only
-- table that needs every other table's surrogate key already in place.
--
-- NULL handling: every load into CE_SALES that resolves a channel-specific
-- FK (employee_id, payment_method_id, shipping_type_id, payment_terms_id)
-- uses LEFT JOIN ... COALESCE(<dim>.<id>, 0) against the relevant dimension,
-- so a B2C row that has no real employee (and vice-versa for B2B) resolves
-- to that dimension's pre-loaded "Not Applicable" row (id = 0) instead of a
-- NULL foreign key — exactly the pattern in the Default Value slide deck
-- (slides 6-7).
--
-- Idempotency: every INSERT uses a NOT EXISTS / LEFT JOIN ... IS NULL guard
-- against the target table's natural key (source_id, or order_id for
-- CE_SALES) and/or ON CONFLICT DO NOTHING on the surrogate PK, so a re-run
-- inserts 0 new rows the second time. Every section ends in an explicit
-- COMMIT.
--
-- Updated for the latest mentor-reviewed revision of Task 5: every column
-- on sa_b2c.src_novatech_b2c_orders / sa_b2b.src_novatech_b2b_orders is now
-- VARCHAR(1000) and untyped (no BIGINT/DATE/NUMERIC at staging at all).
-- Section B below is where that typing now happens — every value pulled
-- from staging is explicitly cast (::DATE, ::INT, ::NUMERIC(p,s), ::BIGINT)
-- to the BL_3NF column's real type at the point it is selected.
-- =============================================================================


-- #############################################################################
-- SECTION A — DEFAULT ROWS  (run once, after the DDL script; safe to re-run)
-- #############################################################################
-- Every BL_3NF table except the fact table (CE_SALES) gets a dedicated
-- "Not Applicable" row, per the Default Value slide deck (slide 4): numeric
-- surrogate keys = 0 (matching this project's existing BL_3NF/BL_DM
-- precedent, not the generic -1 example), text columns = 'n.a.', the source
-- triplet = 'MANUAL' / 'MANUAL' / 'n.a.' (the row was never loaded from a
-- real source), and dates = 1900-01-01 where a date is genuinely required
-- NOT NULL. Columns that are already nullable for unrelated reasons (e.g.
-- CE_PRODUCTS.warranty_period_months) are simply left NULL on the default
-- row too, rather than forcing an artificial 0/'n.a.' onto an optional
-- column — only the columns this table declares NOT NULL need a sentinel.

BEGIN;

-- CE_PRODUCT_CATEGORIES
INSERT INTO BL_3NF.CE_PRODUCT_CATEGORIES
    (product_category_id, source_id, source_system, source_table, product_category_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (product_category_id) DO NOTHING;

-- CE_PRODUCT_TYPES
INSERT INTO BL_3NF.CE_PRODUCT_TYPES
    (product_type_id, source_id, source_system, source_table, product_type_name, product_category_id, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', 0, CURRENT_TIMESTAMP)
ON CONFLICT (product_type_id) DO NOTHING;

-- CE_PRODUCTS
INSERT INTO BL_3NF.CE_PRODUCTS
    (product_id, source_id, source_system, source_table, sku, product_type_id, brand, product_status, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', 0, 'n.a.', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (product_id) DO NOTHING;

-- CE_COUNTRIES
INSERT INTO BL_3NF.CE_COUNTRIES
    (country_id, source_id, source_system, source_table, country_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (country_id) DO NOTHING;

-- CE_CITIES
INSERT INTO BL_3NF.CE_CITIES
    (city_id, source_id, source_system, source_table, city_name, country_id, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', 0, CURRENT_TIMESTAMP)
ON CONFLICT (city_id) DO NOTHING;

-- CE_EMPLOYEES — the row every B2C sale points to (no account manager involved)
INSERT INTO BL_3NF.CE_EMPLOYEES
    (employee_id, source_id, source_system, source_table, employee_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'Not Applicable', CURRENT_TIMESTAMP)
ON CONFLICT (employee_id) DO NOTHING;

-- CE_CHANNELS — built entirely by the ETL, no real outside source at all;
-- both real members (B2C / B2B) are seeded here too, since the channel set
-- is small, fixed, and known in advance rather than discovered from a load.
INSERT INTO BL_3NF.CE_CHANNELS
    (channel_id, source_id, source_system, source_table, channel_name, originating_system_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', 'n.a.', CURRENT_TIMESTAMP),
    (1, 'B2C',  'MANUAL', 'MANUAL', 'B2C',  'NovaTech Direct',             CURRENT_TIMESTAMP),
    (2, 'B2B',  'MANUAL', 'MANUAL', 'B2B',  'NovaTech Business Solutions', CURRENT_TIMESTAMP)
ON CONFLICT (channel_id) DO NOTHING;

-- CE_PAYMENT_METHODS — the row every B2B sale points to (B2B uses Payment
-- Terms / invoicing, not a per-transaction payment method)
INSERT INTO BL_3NF.CE_PAYMENT_METHODS
    (payment_method_id, source_id, source_system, source_table, payment_method_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (payment_method_id) DO NOTHING;

-- CE_SHIPPING_TYPES — the row every B2B sale points to (B2B doesn't carry a
-- per-line shipping type in this extract)
INSERT INTO BL_3NF.CE_SHIPPING_TYPES
    (shipping_type_id, source_id, source_system, source_table, shipping_type_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (shipping_type_id) DO NOTHING;

-- CE_PAYMENT_TERMS — the row every B2C sale points to (B2C pays per
-- transaction, not on invoicing terms)
INSERT INTO BL_3NF.CE_PAYMENT_TERMS
    (payment_terms_id, source_id, source_system, source_table, payment_terms_name, insert_dt)
VALUES
    (0, 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', CURRENT_TIMESTAMP)
ON CONFLICT (payment_terms_id) DO NOTHING;

-- CE_CUSTOMERS_SCD — every sale (B2C or B2B) always has a real customer or
-- company on it, so this dimension's default row exists only for
-- completeness with the task brief ("default row in each table"), not
-- because CE_SALES.customer_id ever needs to fall back to it.
INSERT INTO BL_3NF.CE_CUSTOMERS_SCD
    (customer_id, start_dt, source_id, source_system, source_table, customer_type, customer_name,
     city_id, end_dt, is_active, insert_dt)
VALUES
    (0, TIMESTAMP '1900-01-01', 'n.a.', 'MANUAL', 'MANUAL', 'n.a.', 'Not Applicable',
     0, NULL, TRUE, CURRENT_TIMESTAMP)
ON CONFLICT (customer_id, start_dt) DO NOTHING;

COMMIT;


-- #############################################################################
-- SECTION B — REGULAR LOADS  (rerunnable; can be scheduled, e.g. daily)
-- #############################################################################
-- Reads from the staging layer (sa_b2c.src_novatech_b2c_orders,
-- sa_b2b.src_novatech_b2b_orders — Task 5, latest mentor-reviewed revision)
-- only. Every INSERT/UPDATE is guarded so a re-run against unchanged
-- staging data changes 0 rows. Load order: hierarchy parents before
-- children, every other reference table next, CE_SALES always last (it
-- needs every other table's surrogate key already in place).
--
-- IMPORTANT — typing now happens HERE, not in staging: per the mentor's
-- latest review of Task 5, every column on both sa_b2c.src_novatech_b2c_orders
-- and sa_b2b.src_novatech_b2b_orders is VARCHAR(1000), completely untyped and
-- nullable (except order_id/stg_load_dt/source_file_name). BL_3NF is exactly
-- where "what type is this column" gets decided, so every value pulled from
-- staging below is explicitly cast to the BL_3NF column's real type
-- (::DATE, ::INT, ::NUMERIC(p,s), ::BIGINT) at the point it is selected.
-- A handful of columns (estimated_delivery_days, shipping_cost_tier, and
-- similar enumerated/range-like attributes) are intentionally cast to
-- nothing — they stay text on the BL_3NF side too, per the original ERD.
--
-- Where the same business entity is conformed from BOTH sources (Product
-- via SKU; here also Country/City, which both files happen to share), and a
-- value legitimately differs only in which source-triplet gets recorded
-- (not in the business value itself), B2C is treated as the tie-break
-- "primary" source throughout, since it is Source System 1 in the Business
-- Template — an arbitrary but consistent and documented choice.

BEGIN;

-- =============================================================================
-- B.1  CE_PRODUCT_CATEGORIES  <-  distinct product_category values from both
-- staging tables (hierarchy top level, shared by both channels). Purely
-- textual — no cast needed.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT product_category AS category_name,
           1 AS src_priority, 'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT product_category,
           2, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
),
winners AS (
    SELECT DISTINCT ON (category_name) category_name, source_system, source_table
    FROM candidates
    ORDER BY category_name, src_priority
)
INSERT INTO BL_3NF.CE_PRODUCT_CATEGORIES
    (product_category_id, source_id, source_system, source_table, product_category_name, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_CATEGORY_ID'), w.category_name, w.source_system, w.source_table, w.category_name, CURRENT_TIMESTAMP
FROM winners w
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_PRODUCT_CATEGORIES t WHERE t.source_id = w.category_name);

-- =============================================================================
-- B.2  CE_PRODUCT_TYPES  <-  distinct (product_type, product_category) pairs,
-- resolved against the just-loaded CE_PRODUCT_CATEGORIES via LEFT JOIN +
-- COALESCE (falls back to the "Not Applicable" category, id 0, if a type's
-- category was somehow never loaded). Purely textual — no cast needed.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT product_type AS type_name, product_category AS category_name,
           1 AS src_priority, 'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT product_type, product_category,
           2, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
),
winners AS (
    SELECT DISTINCT ON (type_name) type_name, category_name, source_system, source_table
    FROM candidates
    ORDER BY type_name, src_priority
)
INSERT INTO BL_3NF.CE_PRODUCT_TYPES
    (product_type_id, source_id, source_system, source_table, product_type_name, product_category_id, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_TYPE_ID'), w.type_name, w.source_system, w.source_table, w.type_name,
    COALESCE(cat.product_category_id, 0), CURRENT_TIMESTAMP
FROM winners w
LEFT JOIN BL_3NF.CE_PRODUCT_CATEGORIES cat ON cat.source_id = w.category_name
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_PRODUCT_TYPES t WHERE t.source_id = w.type_name);

-- =============================================================================
-- B.3  CE_PRODUCTS  <-  one row per SKU, conformed across B2C and B2B.
-- source_id holds the SKU itself (the actual conforming natural key), not
-- either source's local Product ID. B2C supplies warranty/launch-year
-- (cast ::INT); B2B supplies bulk-packaging (text)/min-order-qty (::INT);
-- brand/status/type/category are coalesced (prefer B2C, fall back to B2B).
-- =============================================================================
WITH b2c_products AS (
    SELECT DISTINCT ON (sku)
        sku, product_type, brand,
        warranty_period_months::INT AS warranty_period_months,
        launch_year::INT            AS launch_year,
        product_status
    FROM sa_b2c.src_novatech_b2c_orders
    ORDER BY sku, order_id::BIGINT
),
b2b_products AS (
    SELECT DISTINCT ON (sku)
        sku, product_type, brand,
        bulk_packaging_unit,
        minimum_order_quantity::INT AS minimum_order_quantity,
        product_status
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY sku, order_id::BIGINT
),
all_skus AS (
    SELECT sku FROM b2c_products
    UNION
    SELECT sku FROM b2b_products
),
conformed AS (
    SELECT
        s.sku,
        COALESCE(c.product_type, b.product_type)     AS product_type,
        COALESCE(c.brand, b.brand)                    AS brand,
        c.warranty_period_months,
        c.launch_year,
        b.bulk_packaging_unit,
        b.minimum_order_quantity,
        COALESCE(c.product_status, b.product_status)  AS product_status,
        CASE WHEN c.sku IS NOT NULL THEN 'SA_NOVATECH_DIRECT'   ELSE 'SA_NOVATECH_BUSINESS' END AS source_system,
        CASE WHEN c.sku IS NOT NULL THEN 'src_novatech_b2c_orders' ELSE 'src_novatech_b2b_orders' END AS source_table
    FROM all_skus s
    LEFT JOIN b2c_products c ON c.sku = s.sku
    LEFT JOIN b2b_products b ON b.sku = s.sku
)
INSERT INTO BL_3NF.CE_PRODUCTS
    (product_id, source_id, source_system, source_table, sku, product_type_id, brand,
     warranty_period_months, launch_year, bulk_packaging_unit, minimum_order_quantity,
     product_status, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PRODUCT_ID'), cf.sku, cf.source_system, cf.source_table, cf.sku,
    COALESCE(pt.product_type_id, 0), cf.brand,
    cf.warranty_period_months, cf.launch_year, cf.bulk_packaging_unit, cf.minimum_order_quantity,
    cf.product_status, CURRENT_TIMESTAMP
FROM conformed cf
LEFT JOIN BL_3NF.CE_PRODUCT_TYPES pt ON pt.source_id = cf.product_type
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_PRODUCTS t WHERE t.source_id = cf.sku);

-- =============================================================================
-- B.4  CE_COUNTRIES  <-  distinct country values from both staging tables.
-- Purely textual — no cast needed.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT country AS country_name,
           1 AS src_priority, 'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT country,
           2, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
),
winners AS (
    SELECT DISTINCT ON (country_name) country_name, source_system, source_table
    FROM candidates
    ORDER BY country_name, src_priority
)
INSERT INTO BL_3NF.CE_COUNTRIES
    (country_id, source_id, source_system, source_table, country_name, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_COUNTRY_ID'), w.country_name, w.source_system, w.source_table, w.country_name, CURRENT_TIMESTAMP
FROM winners w
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_COUNTRIES t WHERE t.source_id = w.country_name);

-- =============================================================================
-- B.5  CE_CITIES  <-  distinct (city, country) pairs from both staging
-- tables, resolved against the just-loaded CE_COUNTRIES. Purely textual —
-- no cast needed. Natural key: a city name is only unique within its
-- country, so source_id carries both (e.g. 'Lyon|France').
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT city AS city_name, country AS country_name,
           1 AS src_priority, 'SA_NOVATECH_DIRECT' AS source_system, 'src_novatech_b2c_orders' AS source_table
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT DISTINCT city, country,
           2, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders'
    FROM sa_b2b.src_novatech_b2b_orders
),
winners AS (
    SELECT DISTINCT ON (city_name, country_name) city_name, country_name, source_system, source_table
    FROM candidates
    ORDER BY city_name, country_name, src_priority
)
INSERT INTO BL_3NF.CE_CITIES
    (city_id, source_id, source_system, source_table, city_name, country_id, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_CITY_ID'), w.city_name || '|' || w.country_name, w.source_system, w.source_table,
    w.city_name, COALESCE(co.country_id, 0), CURRENT_TIMESTAMP
FROM winners w
LEFT JOIN BL_3NF.CE_COUNTRIES co ON co.source_id = w.country_name
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_CITIES t WHERE t.source_id = w.city_name || '|' || w.country_name
);

-- =============================================================================
-- B.6  CE_EMPLOYEES  <-  distinct account_manager_id from B2B (B2C has no
-- employee involved; that channel always resolves to the default row, id 0,
-- loaded in Section A). hire_date and sales_quota are cast to their real
-- types; everything else stays text.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT ON (account_manager_id)
        account_manager_id AS source_id, account_manager_name AS employee_name,
        department, region_assigned,
        hire_date::DATE AS hire_date,
        email,
        sales_quota::NUMERIC(12,2) AS sales_quota,
        performance_tier
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY account_manager_id, order_id::BIGINT
)
INSERT INTO BL_3NF.CE_EMPLOYEES
    (employee_id, source_id, source_system, source_table, employee_name, department,
     region_assigned, hire_date, email, sales_quota, performance_tier, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_EMPLOYEE_ID'), c.source_id, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders',
    c.employee_name, c.department, c.region_assigned, c.hire_date, c.email, c.sales_quota, c.performance_tier,
    CURRENT_TIMESTAMP
FROM candidates c
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_EMPLOYEES t WHERE t.source_id = c.source_id);

-- =============================================================================
-- B.7  CE_PAYMENT_METHODS  <-  distinct payment_method from B2C (B2B always
-- resolves to the default row, id 0). Conforms the data-quality casing
-- issue flagged in the Business Template (both 'PayPal' and 'Paypal' map to
-- the same business value) by comparing on INITCAP(). processing_fee_percent,
-- settlement_period_days and minimum_transaction_amount are cast to their
-- real numeric types.
-- =============================================================================
WITH normalized AS (
    SELECT order_id, INITCAP(payment_method) AS payment_method_norm,
           payment_channel_type,
           processing_fee_percent::NUMERIC(5,2) AS processing_fee_percent,
           settlement_period_days::INT AS settlement_period_days,
           refundable, currency_accepted,
           minimum_transaction_amount::NUMERIC(10,2) AS minimum_transaction_amount,
           availability_channel
    FROM sa_b2c.src_novatech_b2c_orders
),
candidates AS (
    SELECT DISTINCT ON (payment_method_norm)
        payment_method_norm AS source_id, payment_method_norm AS payment_method_name,
        payment_channel_type, processing_fee_percent,
        settlement_period_days, refundable,
        currency_accepted, minimum_transaction_amount, availability_channel
    FROM normalized
    ORDER BY payment_method_norm, order_id::BIGINT
)
INSERT INTO BL_3NF.CE_PAYMENT_METHODS
    (payment_method_id, source_id, source_system, source_table, payment_method_name, payment_channel_type,
     processing_fee_percent, settlement_period_days, refundable, currency_accepted,
     minimum_transaction_amount, availability_channel, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PAYMENT_METHOD_ID'), c.source_id, 'SA_NOVATECH_DIRECT', 'src_novatech_b2c_orders',
    c.payment_method_name, c.payment_channel_type, c.processing_fee_percent, c.settlement_period_days,
    c.refundable, c.currency_accepted, c.minimum_transaction_amount, c.availability_channel, CURRENT_TIMESTAMP
FROM candidates c
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_PAYMENT_METHODS t WHERE t.source_id = c.source_id);

-- =============================================================================
-- B.8  CE_SHIPPING_TYPES  <-  distinct shipping_type from B2C (B2B always
-- resolves to the default row, id 0). estimated_delivery_days stays text on
-- purpose (it holds ranges like '0-1', '5-7'); max_package_weight_kg is
-- cast to INT.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT ON (shipping_type)
        shipping_type AS source_id, shipping_type AS shipping_type_name,
        shipping_carrier, estimated_delivery_days, shipping_cost_tier,
        free_shipping_eligible, tracking_available,
        max_package_weight_kg::INT AS max_package_weight_kg,
        intl_shipping_available
    FROM sa_b2c.src_novatech_b2c_orders
    ORDER BY shipping_type, order_id::BIGINT
)
INSERT INTO BL_3NF.CE_SHIPPING_TYPES
    (shipping_type_id, source_id, source_system, source_table, shipping_type_name, shipping_carrier,
     estimated_delivery_days, shipping_cost_tier, free_shipping_eligible, tracking_available,
     max_package_weight_kg, international_shipping_available, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_SHIPPING_TYPE_ID'), c.source_id, 'SA_NOVATECH_DIRECT', 'src_novatech_b2c_orders',
    c.shipping_type_name, c.shipping_carrier, c.estimated_delivery_days, c.shipping_cost_tier,
    c.free_shipping_eligible, c.tracking_available, c.max_package_weight_kg, c.intl_shipping_available,
    CURRENT_TIMESTAMP
FROM candidates c
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_SHIPPING_TYPES t WHERE t.source_id = c.source_id);

-- =============================================================================
-- B.9  CE_PAYMENT_TERMS  <-  distinct payment_terms from B2B (B2C always
-- resolves to the default row, id 0). payment_due_days, the two pct
-- columns, and terms_effective_date are cast to their real types.
-- =============================================================================
WITH candidates AS (
    SELECT DISTINCT ON (payment_terms)
        payment_terms AS source_id, payment_terms AS payment_terms_name,
        payment_due_days::INT AS payment_due_days,
        early_payment_discount_pct::NUMERIC(5,2) AS early_payment_discount_pct,
        late_payment_penalty_pct::NUMERIC(5,2)   AS late_payment_penalty_pct,
        currency, preferred_payment_method,
        terms_effective_date::DATE AS terms_effective_date
    FROM sa_b2b.src_novatech_b2b_orders
    ORDER BY payment_terms, order_id::BIGINT
)
INSERT INTO BL_3NF.CE_PAYMENT_TERMS
    (payment_terms_id, source_id, source_system, source_table, payment_terms_name, payment_due_days,
     early_payment_discount_pct, late_payment_penalty_pct, currency, preferred_payment_method,
     terms_effective_date, insert_dt)
SELECT
    NEXTVAL('BL_3NF.SEQ_PAYMENT_TERMS_ID'), c.source_id, 'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders',
    c.payment_terms_name, c.payment_due_days, c.early_payment_discount_pct, c.late_payment_penalty_pct,
    c.currency, c.preferred_payment_method, c.terms_effective_date, CURRENT_TIMESTAMP
FROM candidates c
WHERE NOT EXISTS (SELECT 1 FROM BL_3NF.CE_PAYMENT_TERMS t WHERE t.source_id = c.source_id);

COMMIT;


-- =============================================================================
-- B.10  CE_CUSTOMERS_SCD  <-  full Type-2 history derived from every order
-- each customer/company placed. account_tier (B2B) / loyalty_member (B2C)
-- is the tracked attribute: a new version is recognized whenever it differs
-- from that customer's previous order, using LAG()/LEAD() over the
-- customer's own order history ordered by order_date (cast ::DATE — staging
-- delivers it as text). Re-running this block against unchanged staging
-- data recomputes the identical version list every time and changes 0 rows
-- (idempotent); against staging data that has grown since the last run, it
-- both inserts brand-new versions and closes (UPDATE) any previously
-- "currently open" row that a newer version now supersedes.
--
-- Known data-quality caveat (flagging rather than silently working around):
-- per NovaTech_Business_Template_Task_4.docx, this entity's design assumed
-- the B2C extract would carry date_of_birth (per the Task 1 review comment
-- replacing age with date of birth). The staging layer actually delivers
-- customer_age, not a birth date. date_of_birth is a nullable column on
-- CE_CUSTOMERS_SCD, so rather than fabricate an estimated birth date from
-- age (which would misrepresent the data), it is intentionally left NULL
-- for every B2C row below. customer_age itself is not loaded anywhere in
-- BL_3NF, since the column the model defines is date_of_birth, not age —
-- recommend reconciling this gap with the source file (or the model)
-- before the next layer.
-- =============================================================================

BEGIN;

WITH all_events AS (
    SELECT
        'Individual'                AS customer_type,
        customer_id                 AS source_id,
        'SA_NOVATECH_DIRECT'        AS source_system,
        'src_novatech_b2c_orders'   AS source_table,
        order_date::DATE            AS event_dt,
        customer_name                AS customer_name,
        NULL::DATE                  AS date_of_birth,   -- see caveat above: source has no DOB, only age
        customer_gender              AS gender,
        loyalty_member                AS loyalty_member,
        customer_segment             AS customer_segment,
        NULL::VARCHAR(50)            AS industry,
        NULL::VARCHAR(10)            AS account_tier,
        NULL::VARCHAR(20)            AS company_size,
        NULL::DATE                  AS onboarding_date,
        NULL::NUMERIC(12,2)         AS credit_limit,
        NULL::VARCHAR(255)          AS approver_name,
        NULL::VARCHAR(20)           AS budget_code,
        country                      AS country_name,
        city                          AS city_name,
        loyalty_member                AS tracked_attr
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT
        'Business',
        company_id,
        'SA_NOVATECH_BUSINESS',
        'src_novatech_b2b_orders',
        order_date::DATE,
        company_name,
        NULL::DATE,
        NULL::VARCHAR(10),
        NULL::VARCHAR(5),
        NULL::VARCHAR(20),
        industry,
        account_tier,
        company_size,
        onboarding_date::DATE,
        credit_limit::NUMERIC(12,2),
        approver_name,
        budget_code,
        country,
        city,
        account_tier
    FROM sa_b2b.src_novatech_b2b_orders
),
dedup_events AS (
    -- one row per (customer, calendar day): collapses same-day repeat orders
    SELECT DISTINCT ON (customer_type, source_id, event_dt) *
    FROM all_events
    ORDER BY customer_type, source_id, event_dt
),
flagged AS (
    SELECT *,
        CASE
            WHEN LAG(tracked_attr) OVER (PARTITION BY customer_type, source_id ORDER BY event_dt)
                 IS DISTINCT FROM tracked_attr
            THEN 1 ELSE 0
        END AS is_new_version
    FROM dedup_events
),
versions_raw AS (
    SELECT * FROM flagged WHERE is_new_version = 1
),
versions AS (
    SELECT *,
        LEAD(event_dt) OVER (PARTITION BY customer_type, source_id ORDER BY event_dt) AS next_start_dt
    FROM versions_raw
),
resolved AS (
    SELECT
        v.*,
        COALESCE(ci.city_id, 0) AS city_id
    FROM versions v
    LEFT JOIN BL_3NF.CE_COUNTRIES co ON co.source_id = v.country_name
    LEFT JOIN BL_3NF.CE_CITIES   ci ON ci.source_id = v.city_name || '|' || v.country_name
)

-- B.10.a — close any previously-loaded "open" version that this run's fresh
-- version list shows is no longer current (a later version now exists for
-- that customer/company). No-op on a re-run against unchanged staging data.
UPDATE BL_3NF.CE_CUSTOMERS_SCD t
SET end_dt    = r.next_start_dt,
    is_active = (r.next_start_dt IS NULL)
FROM resolved r
WHERE t.source_id = r.source_id
  AND t.start_dt = r.event_dt::timestamp
  AND t.end_dt IS DISTINCT FROM r.next_start_dt;


-- B.10.b — insert every version not yet present. customer_id is reused from
-- any existing version of the same customer (durable across versions, per
-- Naming_Conventions.docx); a brand-new customer gets a freshly-sequenced id.
WITH all_events AS (
    SELECT
        'Individual'                AS customer_type,
        customer_id                 AS source_id,
        'SA_NOVATECH_DIRECT'        AS source_system,
        'src_novatech_b2c_orders'   AS source_table,
        order_date::DATE            AS event_dt,
        customer_name                AS customer_name,
        NULL::DATE                  AS date_of_birth,
        customer_gender              AS gender,
        loyalty_member                AS loyalty_member,
        customer_segment             AS customer_segment,
        NULL::VARCHAR(50)            AS industry,
        NULL::VARCHAR(10)            AS account_tier,
        NULL::VARCHAR(20)            AS company_size,
        NULL::DATE                  AS onboarding_date,
        NULL::NUMERIC(12,2)         AS credit_limit,
        NULL::VARCHAR(255)          AS approver_name,
        NULL::VARCHAR(20)           AS budget_code,
        country                      AS country_name,
        city                          AS city_name,
        loyalty_member                AS tracked_attr
    FROM sa_b2c.src_novatech_b2c_orders
    UNION ALL
    SELECT
        'Business',
        company_id,
        'SA_NOVATECH_BUSINESS',
        'src_novatech_b2b_orders',
        order_date::DATE,
        company_name,
        NULL::DATE,
        NULL::VARCHAR(10),
        NULL::VARCHAR(5),
        NULL::VARCHAR(20),
        industry,
        account_tier,
        company_size,
        onboarding_date::DATE,
        credit_limit::NUMERIC(12,2),
        approver_name,
        budget_code,
        country,
        city,
        account_tier
    FROM sa_b2b.src_novatech_b2b_orders
),
dedup_events AS (
    SELECT DISTINCT ON (customer_type, source_id, event_dt) *
    FROM all_events
    ORDER BY customer_type, source_id, event_dt
),
flagged AS (
    SELECT *,
        CASE
            WHEN LAG(tracked_attr) OVER (PARTITION BY customer_type, source_id ORDER BY event_dt)
                 IS DISTINCT FROM tracked_attr
            THEN 1 ELSE 0
        END AS is_new_version
    FROM dedup_events
),
versions_raw AS (
    SELECT * FROM flagged WHERE is_new_version = 1
),
versions AS (
    SELECT *,
        LEAD(event_dt) OVER (PARTITION BY customer_type, source_id ORDER BY event_dt) AS next_start_dt
    FROM versions_raw
),
resolved AS (
    SELECT
        v.*,
        COALESCE(ci.city_id, 0) AS city_id
    FROM versions v
    LEFT JOIN BL_3NF.CE_COUNTRIES co ON co.source_id = v.country_name
    LEFT JOIN BL_3NF.CE_CITIES   ci ON ci.source_id = v.city_name || '|' || v.country_name
),
existing_customer_ids AS (
    SELECT DISTINCT source_id, customer_id FROM BL_3NF.CE_CUSTOMERS_SCD
)
INSERT INTO BL_3NF.CE_CUSTOMERS_SCD
    (customer_id, start_dt, source_id, source_system, source_table, customer_type, customer_name,
     date_of_birth, gender, loyalty_member, customer_segment, industry, account_tier, company_size,
     onboarding_date, credit_limit, approver_name, budget_code, city_id, end_dt, is_active, insert_dt)
SELECT
    COALESCE(ex.customer_id, NEXTVAL('BL_3NF.SEQ_CUSTOMER_ID')),
    r.event_dt::timestamp,
    r.source_id, r.source_system, r.source_table, r.customer_type, r.customer_name,
    r.date_of_birth, r.gender, r.loyalty_member, r.customer_segment, r.industry, r.account_tier,
    r.company_size, r.onboarding_date, r.credit_limit, r.approver_name, r.budget_code, r.city_id,
    CASE WHEN r.next_start_dt IS NULL THEN NULL ELSE r.next_start_dt::timestamp END,
    (r.next_start_dt IS NULL),
    CURRENT_TIMESTAMP
FROM resolved r
LEFT JOIN existing_customer_ids ex ON ex.source_id = r.source_id
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_CUSTOMERS_SCD ex2
    WHERE ex2.source_id = r.source_id AND ex2.start_dt = r.event_dt::timestamp
);

COMMIT;


-- =============================================================================
-- B.11  CE_SALES  <-  one row per order line, loaded last since it needs
-- every other table's surrogate key already in place. Every dimension
-- lookup uses LEFT JOIN + COALESCE(<dim>.<id>, 0), so a row whose
-- channel-specific dimension genuinely does not apply (e.g. payment_terms
-- on a B2C row) resolves to that table's "Not Applicable" row (id 0)
-- instead of leaving a NULL foreign key — the pattern from the Default
-- Value slide deck (slides 6-7). customer_id resolves to whichever
-- CE_CUSTOMERS_SCD version was the active one on the sale's own order_date
-- (the version the order itself may have just opened, in the case of the
-- very order that changed a tracked attribute). Every numeric/date column
-- read from staging is explicitly cast; resolution_time_days arrives as
-- text like '13.0', so it is cast via ::NUMERIC(5,1)::INT (the BL_3NF
-- column is INT) rather than straight to INT, which a decimal-formatted
-- string would reject.
-- =============================================================================

BEGIN;

-- B.11.a — B2C order lines
INSERT INTO BL_3NF.CE_SALES
    (product_id, customer_id, employee_id, channel_id, payment_method_id, shipping_type_id, payment_terms_id,
     sales_id, source_id, source_system, source_table, order_id, order_date, order_status, quantity,
     unit_price, unit_cost, total_sales, total_cost, rating, add_on_total, return_or_complaint,
     feedback_comment, resolution_time_days, refund_amount, support_channel_used, escalation_required,
     po_number, po_issue_date, requested_delivery_date, approval_status, po_type, po_value_threshold_flag,
     insert_dt)
SELECT
    COALESCE(p.product_id, 0),
    COALESCE(cu.customer_id, 0),
    0,                                                          -- B2C: no account manager
    1,                                                          -- CE_CHANNELS: B2C
    COALESCE(pm.payment_method_id, 0),
    COALESCE(st.shipping_type_id, 0),
    0,                                                          -- B2C: pays per transaction, not on terms
    NEXTVAL('BL_3NF.SEQ_SALES_ID'),
    src.order_id,
    'SA_NOVATECH_DIRECT', 'src_novatech_b2c_orders',
    src.order_id::BIGINT, src.order_date::DATE, src.order_status, src.quantity::INT,
    src.unit_price::NUMERIC(10,2), src.unit_cost::NUMERIC(10,2),
    src.total_sales::NUMERIC(12,2), src.total_cost::NUMERIC(12,2),
    src.rating::INT, src.addon_total::NUMERIC(10,2), src.return_or_complaint,
    src.feedback_comment, src.resolution_time_days::NUMERIC(5,1)::INT, src.refund_amount::NUMERIC(10,2),
    src.support_channel_used, src.escalation_required,
    NULL, NULL, NULL, NULL, NULL, NULL,                          -- B2B-only Purchase Order block: n/a on a B2C row
    CURRENT_TIMESTAMP
FROM sa_b2c.src_novatech_b2c_orders src
LEFT JOIN BL_3NF.CE_PRODUCTS         p  ON p.source_id  = src.sku
LEFT JOIN BL_3NF.CE_CUSTOMERS_SCD    cu ON cu.source_id = src.customer_id
                                        AND src.order_date::DATE >= cu.start_dt
                                        AND (cu.end_dt IS NULL OR src.order_date::DATE < cu.end_dt)
LEFT JOIN BL_3NF.CE_PAYMENT_METHODS  pm ON pm.source_id = INITCAP(src.payment_method)
LEFT JOIN BL_3NF.CE_SHIPPING_TYPES   st ON st.source_id = src.shipping_type
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_SALES t WHERE t.source_id = src.order_id
);

-- B.11.b — B2B order lines
INSERT INTO BL_3NF.CE_SALES
    (product_id, customer_id, employee_id, channel_id, payment_method_id, shipping_type_id, payment_terms_id,
     sales_id, source_id, source_system, source_table, order_id, order_date, order_status, quantity,
     unit_price, unit_cost, total_sales, total_cost, rating, add_on_total, return_or_complaint,
     feedback_comment, resolution_time_days, refund_amount, support_channel_used, escalation_required,
     po_number, po_issue_date, requested_delivery_date, approval_status, po_type, po_value_threshold_flag,
     insert_dt)
SELECT
    COALESCE(p.product_id, 0),
    COALESCE(cu.customer_id, 0),
    COALESCE(emp.employee_id, 0),
    2,                                                          -- CE_CHANNELS: B2B
    0,                                                          -- B2B: uses Payment Terms, not a payment method
    0,                                                          -- B2B: no per-line shipping type in this extract
    COALESCE(pt.payment_terms_id, 0),
    NEXTVAL('BL_3NF.SEQ_SALES_ID'),
    src.order_id,
    'SA_NOVATECH_BUSINESS', 'src_novatech_b2b_orders',
    src.order_id::BIGINT, src.order_date::DATE, src.order_status, src.quantity::INT,
    src.unit_price::NUMERIC(10,2), src.unit_cost::NUMERIC(10,2),
    src.total_sales::NUMERIC(12,2), src.total_cost::NUMERIC(12,2),
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,              -- B2C-only Order Experience block: n/a on a B2B row
    src.po_number, src.po_issue_date::DATE, src.requested_delivery_date::DATE,
    src.approval_status, src.po_type, src.po_value_threshold_flag,
    CURRENT_TIMESTAMP
FROM sa_b2b.src_novatech_b2b_orders src
LEFT JOIN BL_3NF.CE_PRODUCTS         p   ON p.source_id   = src.sku
LEFT JOIN BL_3NF.CE_CUSTOMERS_SCD    cu  ON cu.source_id  = src.company_id
                                         AND src.order_date::DATE >= cu.start_dt
                                         AND (cu.end_dt IS NULL OR src.order_date::DATE < cu.end_dt)
LEFT JOIN BL_3NF.CE_EMPLOYEES        emp ON emp.source_id = src.account_manager_id
LEFT JOIN BL_3NF.CE_PAYMENT_TERMS    pt  ON pt.source_id  = src.payment_terms
WHERE NOT EXISTS (
    SELECT 1 FROM BL_3NF.CE_SALES t WHERE t.source_id = src.order_id
);

COMMIT;
