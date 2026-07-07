-- BL_DM schema — data loads from BL_3NF
-- Task 7

-- Run sections in order. Section A must go first because the FCT load
-- (Section J) falls back to surr_id = -1 for any unmatched dimension rows,
-- and those default rows need to exist before the FK constraints are tested.
--
-- Load order:
--   A  — default rows for all DIM tables
--   B  — DIM_PRODUCTS        (CE_PRODUCTS + CE_PRODUCT_TYPES + CE_PRODUCT_CATEGORIES)
--   C  — DIM_EMPLOYEES       (CE_EMPLOYEES)
--   D  — DIM_CHANNELS        (CE_CHANNELS)
--   E  — DIM_PAYMENT_METHODS (CE_PAYMENT_METHODS)
--   F  — DIM_SHIPPING_TYPES  (CE_SHIPPING_TYPES)
--   G  — DIM_PAYMENT_TERMS   (CE_PAYMENT_TERMS)
--   H  — DIM_CUSTOMERS_SCD   (CE_CUSTOMERS_SCD + CE_CITIES + CE_COUNTRIES)
--   I  — DIM_TIME_DAY        (generated via generate_series)
--   J  — FCT_SALES_DD        (CE_SALES with all DIM surrogate lookups)
--
-- All non-KPI values are wrapped in COALESCE (numeric fallback = -1,
-- text = 'Manual', date = '1900-01-01'). Every INSERT uses NOT EXISTS on the
-- source triplet, so re-running against unchanged BL_3NF data inserts nothing.
-- UPPER() is applied on both sides of source-triplet comparisons to avoid
-- case mismatches between run cycles. BL_3NF source_table maps to
-- BL_DM source_entity. Each section ends with COMMIT.


-- -------------------------------------------------------------------------
-- SECTION A — DEFAULT ROWS
-- surr_id = -1, text = 'Manual', numbers = -1, dates = '1900-01-01'.
-- source_system / source_entity = 'Manual' (record was manually introduced).
-- All attribute columns (_src_id, names, codes, flags) = 'n.a.' since no
-- real value exists for a default row.
-- FCT_SALES_DD gets no default row — it is a fact table.
-- ON CONFLICT DO NOTHING makes this safe to re-run.
-- -------------------------------------------------------------------------

BEGIN;

-- DIM_PRODUCTS default row
INSERT INTO BL_DM.DIM_PRODUCTS
    (product_surr_id, product_src_id, source_system, source_entity,
     sku, brand, warranty_period_months, launch_year,
     bulk_packaging_unit, minimum_order_quantity, product_status,
     product_type_id, product_type_name,
     product_category_id, product_category_name,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.', -1, -1,
     'n.a.', -1, 'n.a.',
     -1, 'n.a.',
     -1, 'n.a.',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (product_surr_id) DO NOTHING;

-- DIM_EMPLOYEES default row
INSERT INTO BL_DM.DIM_EMPLOYEES
    (employee_surr_id, employee_src_id, source_system, source_entity,
     employee_name, department, region_assigned, hire_date_dt,
     email, sales_quota, performance_tier,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.', 'n.a.', DATE '1900-01-01',
     'n.a.', -1, 'n.a.',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (employee_surr_id) DO NOTHING;

-- DIM_CHANNELS default row
INSERT INTO BL_DM.DIM_CHANNELS
    (channel_surr_id, channel_src_id, source_system, source_entity,
     channel_name, originating_system_name,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (channel_surr_id) DO NOTHING;

-- DIM_PAYMENT_METHODS default row
INSERT INTO BL_DM.DIM_PAYMENT_METHODS
    (payment_method_surr_id, payment_method_src_id, source_system, source_entity,
     payment_method_name, payment_channel_type, processing_fee_percent,
     settlement_period_days, refundable, currency_accepted,
     minimum_transaction_amount, availability_channel,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.', -1,
     -1, 'n.a.', 'n.a.',
     -1, 'n.a.',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (payment_method_surr_id) DO NOTHING;

-- DIM_SHIPPING_TYPES default row
INSERT INTO BL_DM.DIM_SHIPPING_TYPES
    (shipping_type_surr_id, shipping_type_src_id, source_system, source_entity,
     shipping_type_name, shipping_carrier, estimated_delivery_days,
     shipping_cost_tier, free_shipping_eligible, tracking_available,
     max_package_weight_kg, international_shipping_available,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.', 'n.a.',
     'n.a.', 'n.a.', 'n.a.',
     -1, 'n.a.',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (shipping_type_surr_id) DO NOTHING;

-- DIM_PAYMENT_TERMS default row
INSERT INTO BL_DM.DIM_PAYMENT_TERMS
    (payment_terms_surr_id, payment_terms_src_id, source_system, source_entity,
     payment_terms_name, payment_due_days, early_payment_discount_pct,
     late_payment_penalty_pct, currency, preferred_payment_method,
     terms_effective_date_dt,
     insert_dt, update_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', -1, -1,
     -1, 'n.a.', 'n.a.',
     DATE '1900-01-01',
     CURRENT_DATE, CURRENT_DATE)
ON CONFLICT (payment_terms_surr_id) DO NOTHING;

-- DIM_CUSTOMERS_SCD default row
INSERT INTO BL_DM.DIM_CUSTOMERS_SCD
    (customer_surr_id, customer_src_id, source_system, source_entity,
     customer_type, customer_name, date_of_birth_dt, gender,
     loyalty_member, customer_segment, industry, account_tier,
     company_size, onboarding_date_dt, credit_limit, approver_name,
     budget_code, city_id, city_name, country_id, country_name,
     start_dt, end_dt, is_active, insert_dt)
VALUES
    (-1, 'n.a.', 'Manual', 'Manual',
     'n.a.', 'n.a.', DATE '1900-01-01', 'n.a.',
     'n.a.', 'n.a.', 'n.a.', 'n.a.',
     'n.a.', DATE '1900-01-01', -1, 'n.a.',
     'n.a.', -1, 'n.a.', -1, 'n.a.',
     DATE '1900-01-01', DATE '9999-12-31', 'N', CURRENT_DATE)
ON CONFLICT (customer_surr_id) DO NOTHING;


COMMIT;


-- -------------------------------------------------------------------------
-- SECTION B — DIM_PRODUCTS
-- Products from CE_PRODUCTS with type and category joined in from BL_3NF.
-- BL_3NF default rows (product_id = -1) are skipped.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_PRODUCTS
    (product_surr_id, product_src_id, source_system, source_entity,
     sku, brand, warranty_period_months, launch_year,
     bulk_packaging_unit, minimum_order_quantity, product_status,
     product_type_id, product_type_name,
     product_category_id, product_category_name,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_PRODUCTS_ID'),
    COALESCE(p.product_src_id,             'Manual'),
    COALESCE(p.source_system,               'Manual'),
    COALESCE(p.source_table,                'Manual'),
    COALESCE(p.sku,                         'Manual'),
    COALESCE(p.brand,                       'Manual'),
    COALESCE(p.warranty_period_months,      -1),
    COALESCE(p.launch_year,                 -1),
    COALESCE(p.bulk_packaging_unit,         'Manual'),
    COALESCE(p.minimum_order_quantity,      -1),
    COALESCE(p.product_status,              'Manual'),
    COALESCE(pt.product_type_id,            -1),
    COALESCE(pt.product_type_name,          'Manual'),
    COALESCE(pc.product_category_id,        -1),
    COALESCE(pc.product_category_name,      'Manual'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_PRODUCTS p
LEFT JOIN BL_3NF.CE_PRODUCT_TYPES      pt
    ON  p.product_type_id       = pt.product_type_id
LEFT JOIN BL_3NF.CE_PRODUCT_CATEGORIES pc
    ON  pt.product_category_id  = pc.product_category_id
WHERE p.product_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_PRODUCTS d
      WHERE  UPPER(d.product_src_id) = UPPER(p.product_src_id)
        AND  UPPER(d.source_system)  = UPPER(p.source_system)
        AND  UPPER(d.source_entity)  = UPPER(p.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION C — DIM_EMPLOYEES
-- Straight load from CE_EMPLOYEES. B2C sales will fall back to surr_id = -1.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_EMPLOYEES
    (employee_surr_id, employee_src_id, source_system, source_entity,
     employee_name, department, region_assigned, hire_date_dt,
     email, sales_quota, performance_tier,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_EMPLOYEES_ID'),
    COALESCE(e.employee_src_id,     'Manual'),
    COALESCE(e.source_system,        'Manual'),
    COALESCE(e.source_table,         'Manual'),
    COALESCE(e.employee_name,        'Manual'),
    COALESCE(e.department,           'Manual'),
    COALESCE(e.region_assigned,      'Manual'),
    COALESCE(e.hire_date,            DATE '1900-01-01'),
    COALESCE(e.email,                'Manual'),
    COALESCE(e.sales_quota,          -1),
    COALESCE(e.performance_tier,     'Manual'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_EMPLOYEES e
WHERE e.employee_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_EMPLOYEES d
      WHERE  UPPER(d.employee_src_id) = UPPER(e.employee_src_id)
        AND  UPPER(d.source_system)   = UPPER(e.source_system)
        AND  UPPER(d.source_entity)   = UPPER(e.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION D — DIM_CHANNELS
-- CE_CHANNELS has channel_id 1 (B2C) and 2 (B2B); -1 is excluded here
-- since the DM default row was already inserted in Section A.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_CHANNELS
    (channel_surr_id, channel_src_id, source_system, source_entity,
     channel_name, originating_system_name,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_CHANNELS_ID'),
    COALESCE(c.channel_src_id,          'Manual'),
    COALESCE(c.source_system,            'Manual'),
    COALESCE(c.source_table,             'Manual'),
    COALESCE(c.channel_name,             'Manual'),
    COALESCE(c.originating_system_name,  'Manual'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_CHANNELS c
WHERE c.channel_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_CHANNELS d
      WHERE  UPPER(d.channel_src_id) = UPPER(c.channel_src_id)
        AND  UPPER(d.source_system)  = UPPER(c.source_system)
        AND  UPPER(d.source_entity)  = UPPER(c.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION E — DIM_PAYMENT_METHODS (B2C-only)
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_PAYMENT_METHODS
    (payment_method_surr_id, payment_method_src_id, source_system, source_entity,
     payment_method_name, payment_channel_type, processing_fee_percent,
     settlement_period_days, refundable, currency_accepted,
     minimum_transaction_amount, availability_channel,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_PAYMENT_METHODS_ID'),
    COALESCE(pm.payment_method_src_id,       'Manual'),
    COALESCE(pm.source_system,                'Manual'),
    COALESCE(pm.source_table,                 'Manual'),
    COALESCE(pm.payment_method_name,          'Manual'),
    COALESCE(pm.payment_channel_type,         'Manual'),
    COALESCE(pm.processing_fee_percent,       -1),
    COALESCE(pm.settlement_period_days,       -1),
    COALESCE(pm.refundable,                   'Manual'),
    COALESCE(pm.currency_accepted,            'Manual'),
    COALESCE(pm.minimum_transaction_amount,   -1),
    COALESCE(pm.availability_channel,         'Manual'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_PAYMENT_METHODS pm
WHERE pm.payment_method_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_PAYMENT_METHODS d
      WHERE  UPPER(d.payment_method_src_id) = UPPER(pm.payment_method_src_id)
        AND  UPPER(d.source_system)         = UPPER(pm.source_system)
        AND  UPPER(d.source_entity)         = UPPER(pm.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION F — DIM_SHIPPING_TYPES (B2C-only)
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_SHIPPING_TYPES
    (shipping_type_surr_id, shipping_type_src_id, source_system, source_entity,
     shipping_type_name, shipping_carrier, estimated_delivery_days,
     shipping_cost_tier, free_shipping_eligible, tracking_available,
     max_package_weight_kg, international_shipping_available,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_SHIPPING_TYPES_ID'),
    COALESCE(st.shipping_type_src_id,                'Manual'),
    COALESCE(st.source_system,                        'Manual'),
    COALESCE(st.source_table,                         'Manual'),
    COALESCE(st.shipping_type_name,                   'Manual'),
    COALESCE(st.shipping_carrier,                     'Manual'),
    COALESCE(st.estimated_delivery_days,              'Manual'),
    COALESCE(st.shipping_cost_tier,                   'Manual'),
    COALESCE(st.free_shipping_eligible,               'Manual'),
    COALESCE(st.tracking_available,                   'Manual'),
    COALESCE(st.max_package_weight_kg,                -1),
    COALESCE(st.international_shipping_available,     'Manual'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_SHIPPING_TYPES st
WHERE st.shipping_type_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_SHIPPING_TYPES d
      WHERE  UPPER(d.shipping_type_src_id) = UPPER(st.shipping_type_src_id)
        AND  UPPER(d.source_system)        = UPPER(st.source_system)
        AND  UPPER(d.source_entity)        = UPPER(st.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION G — DIM_PAYMENT_TERMS (B2B-only)
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_PAYMENT_TERMS
    (payment_terms_surr_id, payment_terms_src_id, source_system, source_entity,
     payment_terms_name, payment_due_days, early_payment_discount_pct,
     late_payment_penalty_pct, currency, preferred_payment_method,
     terms_effective_date_dt,
     insert_dt, update_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_PAYMENT_TERMS_ID'),
    COALESCE(pt.payment_terms_src_id,       'Manual'),
    COALESCE(pt.source_system,               'Manual'),
    COALESCE(pt.source_table,                'Manual'),
    COALESCE(pt.payment_terms_name,          'Manual'),
    COALESCE(pt.payment_due_days,            -1),
    COALESCE(pt.early_payment_discount_pct,  -1),
    COALESCE(pt.late_payment_penalty_pct,    -1),
    COALESCE(pt.currency,                    'Manual'),
    COALESCE(pt.preferred_payment_method,    'Manual'),
    COALESCE(pt.terms_effective_date,        DATE '1900-01-01'),
    CURRENT_DATE,
    CURRENT_DATE
FROM BL_3NF.CE_PAYMENT_TERMS pt
WHERE pt.payment_terms_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_PAYMENT_TERMS d
      WHERE  UPPER(d.payment_terms_src_id) = UPPER(pt.payment_terms_src_id)
        AND  UPPER(d.source_system)        = UPPER(pt.source_system)
        AND  UPPER(d.source_entity)        = UPPER(pt.source_table)
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION H — DIM_CUSTOMERS_SCD
-- Each historical version in CE_CUSTOMERS_SCD gets its own customer_surr_id
-- here. City and country are joined in and stored directly on the row.
-- is_active is cast from BOOLEAN to 'Y'/'N'; start_dt and end_dt are cast
-- from TIMESTAMP to DATE. The idempotency check includes start_dt to tell
-- versions apart.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_CUSTOMERS_SCD
    (customer_surr_id, customer_src_id, source_system, source_entity,
     customer_type, customer_name, date_of_birth_dt, gender,
     loyalty_member, customer_segment, industry, account_tier,
     company_size, onboarding_date_dt, credit_limit, approver_name,
     budget_code, city_id, city_name, country_id, country_name,
     start_dt, end_dt, is_active, insert_dt)
SELECT
    NEXTVAL('BL_DM.SEQ_DIM_CUSTOMERS_SCD_ID'),
    COALESCE(cs.customer_src_id,     'Manual'),
    COALESCE(cs.source_system,        'Manual'),
    COALESCE(cs.source_table,         'Manual'),
    COALESCE(cs.customer_type,        'Manual'),
    COALESCE(cs.customer_name,        'Manual'),
    COALESCE(cs.date_of_birth,        DATE '1900-01-01'),
    COALESCE(cs.gender,               'Manual'),
    COALESCE(cs.loyalty_member,       'Manual'),
    COALESCE(cs.customer_segment,     'Manual'),
    COALESCE(cs.industry,             'Manual'),
    COALESCE(cs.account_tier,         'Manual'),
    COALESCE(cs.company_size,         'Manual'),
    COALESCE(cs.onboarding_date,      DATE '1900-01-01'),
    COALESCE(cs.credit_limit,         -1),
    COALESCE(cs.approver_name,        'Manual'),
    COALESCE(cs.budget_code,          'Manual'),
    COALESCE(ci.city_id,              -1),
    COALESCE(ci.city_name,            'Manual'),
    COALESCE(co.country_id,           -1),
    COALESCE(co.country_name,         'Manual'),
    COALESCE(cs.start_dt::DATE,       DATE '1900-01-01'),
    COALESCE(cs.end_dt::DATE,         DATE '9999-12-31'),
    CASE WHEN cs.is_active THEN 'Y' ELSE 'N' END,
    CURRENT_DATE
FROM BL_3NF.CE_CUSTOMERS_SCD cs
LEFT JOIN BL_3NF.CE_CITIES    ci ON cs.city_id    = ci.city_id
LEFT JOIN BL_3NF.CE_COUNTRIES co ON ci.country_id = co.country_id
WHERE cs.customer_id <> -1
  AND NOT EXISTS (
      SELECT 1
      FROM   BL_DM.DIM_CUSTOMERS_SCD d
      WHERE  UPPER(d.customer_src_id) = UPPER(cs.customer_src_id)
        AND  UPPER(d.source_system)   = UPPER(cs.source_system)
        AND  UPPER(d.source_entity)   = UPPER(cs.source_table)
        AND  d.start_dt               = cs.start_dt::DATE
  );

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION I — DIM_TIME_DAY
-- Generates one row per calendar day from 2015-01-01 to 2030-12-31.
-- The default row ('1900-01-01') inserted in Section A is outside this range
-- so there is no conflict with UQ_DIM_TIME_DAY_DATE. TRIM() is needed because
-- TO_CHAR pads day and month names with trailing spaces.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.DIM_TIME_DAY
    (time_day_surr_id, date_dt,
     day_no, month_no, quarter_no, year_no, week_no,
     day_name, month_name, is_weekend,
     insert_dt, update_dt)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::BIGINT,
    d::DATE,
    EXTRACT(DAY     FROM d)::INT,
    EXTRACT(MONTH   FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(YEAR    FROM d)::INT,
    EXTRACT(WEEK    FROM d)::INT,
    TRIM(TO_CHAR(d, 'Day')),
    TRIM(TO_CHAR(d, 'Month')),
    CASE WHEN EXTRACT(DOW FROM d) IN (0, 6) THEN 'Y' ELSE 'N' END,
    CURRENT_DATE,
    CURRENT_DATE
FROM generate_series(
         DATE '2015-01-01',
         DATE '2030-12-31',
         INTERVAL '1 day'
     ) AS d
WHERE NOT EXISTS (
    SELECT 1
    FROM   BL_DM.DIM_TIME_DAY t
    WHERE  t.date_dt = d::DATE
);

COMMIT;


-- -------------------------------------------------------------------------
-- SECTION J — FCT_SALES_DD
-- Loads from CE_SALES. For each dimension, the surrogate key is resolved in
-- two steps: first join to the BL_3NF table to get the source triplet, then
-- join to the BL_DM DIM table on that triplet to get the surr_id. If no match
-- is found, COALESCE falls back to -1 so the FK constraint is never broken.
--
-- Customer SCD2: the order_date is matched against the validity window
-- (start_dt..end_dt) in CE_CUSTOMERS_SCD to find the right version, then
-- that version's surr_id is looked up in DIM_CUSTOMERS_SCD using the source
-- triplet + start_dt.
--
-- KPI columns (fct_*) are left as-is without COALESCE — they can be NULL,
-- which is intentional since metrics are exempt from the NOT NULL rule.
-- -------------------------------------------------------------------------

BEGIN;

INSERT INTO BL_DM.FCT_SALES_DD
    (event_dt,
     product_surr_id, customer_surr_id, employee_surr_id,
     channel_surr_id, payment_method_surr_id,
     shipping_type_surr_id, payment_terms_surr_id,
     sales_src_id, source_system, source_entity,
     order_id, order_status,
     fct_quantity, fct_unit_price, fct_unit_cost,
     fct_total_sales, fct_total_cost,
     fct_rating, fct_add_on_total, fct_refund_amount,
     insert_dt, update_dt)
SELECT
    -- Event date (daily grain)
    COALESCE(s.order_date,              DATE '1900-01-01')    AS event_dt,

    -- Dimension surrogate keys (fall back to -1 on lookup miss)
    COALESCE(dp.product_surr_id,        -1)                   AS product_surr_id,
    COALESCE(dc.customer_surr_id,       -1)                   AS customer_surr_id,
    COALESCE(de.employee_surr_id,       -1)                   AS employee_surr_id,
    COALESCE(dch.channel_surr_id,       -1)                   AS channel_surr_id,
    COALESCE(dpm.payment_method_surr_id,-1)                   AS payment_method_surr_id,
    COALESCE(dst.shipping_type_surr_id, -1)                   AS shipping_type_surr_id,
    COALESCE(dpt.payment_terms_surr_id, -1)                   AS payment_terms_surr_id,

    -- Source lineage
    COALESCE(s.sales_src_id,    'Manual')                     AS sales_src_id,
    COALESCE(s.source_system,    'Manual')                     AS source_system,
    COALESCE(s.source_table,     'Manual')                     AS source_entity,

    -- Degenerate dimension
    s.order_id                                                 AS order_id,
    COALESCE(s.order_status,     'Manual')                     AS order_status,

    -- KPI metrics (nullable)
    s.quantity                                                 AS fct_quantity,
    s.unit_price                                               AS fct_unit_price,
    s.unit_cost                                                AS fct_unit_cost,
    s.total_sales                                              AS fct_total_sales,
    s.total_cost                                               AS fct_total_cost,
    s.rating                                                   AS fct_rating,
    s.add_on_total                                             AS fct_add_on_total,
    s.refund_amount                                            AS fct_refund_amount,

    CURRENT_DATE                                               AS insert_dt,
    CURRENT_DATE                                               AS update_dt

FROM BL_3NF.CE_SALES s

-- Product: step 1 get BL_3NF row, step 2 resolve DM surrogate
LEFT JOIN BL_3NF.CE_PRODUCTS cp
    ON  s.product_id = cp.product_id
LEFT JOIN BL_DM.DIM_PRODUCTS dp
    ON  UPPER(dp.product_src_id) = UPPER(cp.product_src_id)
    AND UPPER(dp.source_system)  = UPPER(cp.source_system)
    AND UPPER(dp.source_entity)  = UPPER(cp.source_table)

-- Customer SCD2: match order_date against the validity window, then look up surr_id
LEFT JOIN BL_3NF.CE_CUSTOMERS_SCD ccs
    ON  ccs.customer_id = s.customer_id
    AND s.order_date BETWEEN ccs.start_dt::DATE AND ccs.end_dt::DATE
LEFT JOIN BL_DM.DIM_CUSTOMERS_SCD dc
    ON  UPPER(dc.customer_src_id) = UPPER(ccs.customer_src_id)
    AND UPPER(dc.source_system)   = UPPER(ccs.source_system)
    AND UPPER(dc.source_entity)   = UPPER(ccs.source_table)
    AND dc.start_dt               = ccs.start_dt::DATE

-- Employee
LEFT JOIN BL_3NF.CE_EMPLOYEES ce
    ON  s.employee_id = ce.employee_id
LEFT JOIN BL_DM.DIM_EMPLOYEES de
    ON  UPPER(de.employee_src_id) = UPPER(ce.employee_src_id)
    AND UPPER(de.source_system)   = UPPER(ce.source_system)
    AND UPPER(de.source_entity)   = UPPER(ce.source_table)

-- Channel
LEFT JOIN BL_3NF.CE_CHANNELS cch
    ON  s.channel_id = cch.channel_id
LEFT JOIN BL_DM.DIM_CHANNELS dch
    ON  UPPER(dch.channel_src_id) = UPPER(cch.channel_src_id)
    AND UPPER(dch.source_system)  = UPPER(cch.source_system)
    AND UPPER(dch.source_entity)  = UPPER(cch.source_table)

-- Payment method
LEFT JOIN BL_3NF.CE_PAYMENT_METHODS cpm
    ON  s.payment_method_id = cpm.payment_method_id
LEFT JOIN BL_DM.DIM_PAYMENT_METHODS dpm
    ON  UPPER(dpm.payment_method_src_id) = UPPER(cpm.payment_method_src_id)
    AND UPPER(dpm.source_system)         = UPPER(cpm.source_system)
    AND UPPER(dpm.source_entity)         = UPPER(cpm.source_table)

-- Shipping type
LEFT JOIN BL_3NF.CE_SHIPPING_TYPES cst
    ON  s.shipping_type_id = cst.shipping_type_id
LEFT JOIN BL_DM.DIM_SHIPPING_TYPES dst
    ON  UPPER(dst.shipping_type_src_id) = UPPER(cst.shipping_type_src_id)
    AND UPPER(dst.source_system)        = UPPER(cst.source_system)
    AND UPPER(dst.source_entity)        = UPPER(cst.source_table)

-- Payment terms
LEFT JOIN BL_3NF.CE_PAYMENT_TERMS cpt
    ON  s.payment_terms_id = cpt.payment_terms_id
LEFT JOIN BL_DM.DIM_PAYMENT_TERMS dpt
    ON  UPPER(dpt.payment_terms_src_id) = UPPER(cpt.payment_terms_src_id)
    AND UPPER(dpt.source_system)        = UPPER(cpt.source_system)
    AND UPPER(dpt.source_entity)        = UPPER(cpt.source_table)

-- Idempotency guard
WHERE NOT EXISTS (
    SELECT 1
    FROM   BL_DM.FCT_SALES_DD f
    WHERE  UPPER(f.sales_src_id)  = UPPER(s.sales_src_id)
      AND  UPPER(f.source_system) = UPPER(s.source_system)
      AND  UPPER(f.source_entity) = UPPER(s.source_table)
);

COMMIT;
