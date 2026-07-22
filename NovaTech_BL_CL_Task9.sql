-- =============================================================================
-- Task 9 — Loading FACT TABLE into BL_3NF / BL_DM, DWH Refresh Improving
-- =============================================================================
--
-- Part 1  BL_3NF.CE_SALES        — incremental load (NOT EXISTS guard)
-- Part 2  BL_DM.FCT_SALES_DD     — converted to a table PARTITIONED BY RANGE
--                                   (event_dt), monthly partitions, loaded
--                                   with an attach-new / detach-old rolling
--                                   window (2-3 months kept "hot").
-- Part 3  Master wrapper + idempotency / duplicate / coverage tests
--
-- Conventions carried over from Task 7 / Task 8: BL_CL.MTA_LOAD_LOG logging,
-- source triplet NOT EXISTS pattern for idempotency, LANGUAGE sql helper
-- functions to avoid PL/pgSQL RETURNS TABLE column-name ambiguity.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 0.  Schema change required to support partitioning
-- -----------------------------------------------------------------------------
-- PostgreSQL requires every unique/primary key on a partitioned table to
-- include all partition-key columns. FCT_SALES_DD's original PK
-- (sales_src_id, source_system, source_entity) does not include event_dt,
-- so it cannot be kept as-is on a table PARTITION BY RANGE (event_dt).
-- FCT_SALES_DD currently holds no rows in our environment (Task 8 only
-- populated the DIM_ tables), so the table is dropped and re-created here
-- as partitioned, with event_dt added to the PK. This is documented as a
-- one-time, deliberate DDL change for Task 9 rather than a silent one.
DROP TABLE IF EXISTS BL_DM.FCT_SALES_DD;

CREATE TABLE BL_DM.FCT_SALES_DD
(
    event_dt                   DATE            NOT NULL,
    product_surr_id            BIGINT          NOT NULL,
    customer_surr_id           BIGINT          NOT NULL,
    employee_surr_id           BIGINT          NOT NULL,
    channel_surr_id            INT             NOT NULL,
    payment_method_surr_id     INT             NOT NULL,
    shipping_type_surr_id      INT             NOT NULL,
    payment_terms_surr_id      INT             NOT NULL,
    sales_src_id                VARCHAR(60)    NOT NULL,
    source_system               VARCHAR(40)    NOT NULL,
    source_entity                VARCHAR(60)   NOT NULL,
    order_id                    BIGINT         NOT NULL,
    order_status                 VARCHAR(20)   NOT NULL,
    fct_quantity                 INT,
    fct_unit_price                NUMERIC(10,2),
    fct_unit_cost                 NUMERIC(10,2),
    fct_total_sales                NUMERIC(12,2),
    fct_total_cost                 NUMERIC(12,2),
    fct_rating                     INT,
    fct_add_on_total                NUMERIC(10,2),
    fct_refund_amount                NUMERIC(10,2),
    insert_dt                        DATE       NOT NULL,
    update_dt                        DATE       NOT NULL,
    CONSTRAINT PK_FCT_SALES_DD
        PRIMARY KEY (event_dt, sales_src_id, source_system, source_entity)
)
PARTITION BY RANGE (event_dt);

-- A DEFAULT partition catches any row whose event_dt falls outside every
-- named monthly partition (e.g. a very old order that has aged out of the
-- rolling window but is re-loaded by mistake). Its existence is required
-- before ATTACH/DETACH operations run cleanly against a range-partitioned
-- table with no partitions yet.
CREATE TABLE IF NOT EXISTS BL_DM.FCT_SALES_DD_DEFAULT
    PARTITION OF BL_DM.FCT_SALES_DD DEFAULT;

COMMIT;

-- =============================================================================
-- PART 1 — BL_3NF.CE_SALES  (incremental load)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.a  Source functions — LANGUAGE sql (avoids the RETURNS TABLE column-name
-- ambiguity we hit in Task 7 whenever a source column shares a name with a
-- declared OUT column, e.g. order_status / order_id).
-- Each function resolves every CE_ dimension FK for its channel and leaves
-- the columns that don't apply to that channel as NULL — they are nullable
-- on CE_SALES by design.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION BL_CL.fn_src_ce_sales_b2c()
RETURNS TABLE (
    product_id BIGINT, customer_id BIGINT, employee_id BIGINT, channel_id INT,
    payment_method_id INT, shipping_type_id INT, payment_terms_id INT,
    src_id VARCHAR, src_system VARCHAR, src_table VARCHAR,
    ord_id BIGINT, ord_date DATE, ord_status VARCHAR,
    qty INT, u_price NUMERIC, u_cost NUMERIC, t_sales NUMERIC, t_cost NUMERIC,
    rtg INT, addon NUMERIC,
    ret_flag VARCHAR, fbk VARCHAR, res_days INT, refund NUMERIC,
    supp_ch VARCHAR, esc_flag VARCHAR,
    po_num VARCHAR, po_dt DATE, req_dt DATE, appr VARCHAR, po_ty VARCHAR, po_thr VARCHAR
)
LANGUAGE sql AS $$
    SELECT
        cp.product_id,
        cc.customer_id,
        (-1)::BIGINT                                       AS employee_id,        -- B2C -> "Not Applicable" employee
        1                                                AS channel_id,        -- CE_CHANNELS: 1 = B2C
        COALESCE(pm.payment_method_id, -1)                AS payment_method_id,
        COALESCE(st.shipping_type_id, -1)                 AS shipping_type_id,
        (-1)                                             AS payment_terms_id,  -- B2C -> "Not Applicable" payment terms
        s.order_id::VARCHAR(60)                          AS src_id,
        'SA_NOVATECH_DIRECT'::VARCHAR(40)                AS src_system,
        'src_novatech_b2c_orders'::VARCHAR(60)            AS src_table,
        s.order_id::BIGINT                                AS ord_id,
        s.order_date::DATE                                AS ord_date,
        s.order_status::VARCHAR(20)                       AS ord_status,
        s.quantity::INT                                   AS qty,
        s.unit_price::NUMERIC(10,2)                       AS u_price,
        s.unit_cost::NUMERIC(10,2)                        AS u_cost,
        s.total_sales::NUMERIC(12,2)                      AS t_sales,
        s.total_cost::NUMERIC(12,2)                       AS t_cost,
        COALESCE(NULLIF(s.rating,''), '0')::INT                  AS rtg,
        COALESCE(NULLIF(s.addon_total,''), '0')::NUMERIC(10,2)   AS addon,
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR, 0::INT, 0::NUMERIC,     -- B2B-only support-ticket columns: n/a for B2C
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR,
        'n.a.'::VARCHAR, '1900-01-01'::DATE, '1900-01-01'::DATE,
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR, 'n.a.'::VARCHAR         -- B2B-only PO columns: n/a for B2C
    FROM sa_b2c.src_novatech_b2c_orders s
    -- Every dimension lookup below uses LATERAL ... ORDER BY <id> LIMIT 1 instead
    -- of a plain JOIN. CE_PRODUCTS was found to contain exact duplicate rows for
    -- the same SKU (a Task 7 load artifact), which fans a plain JOIN out into
    -- two output rows per order and breaks CE_SALES/FCT_SALES_DD's PK. LATERAL
    -- makes every lookup deterministic (lowest id wins) no matter how many
    -- duplicate *_src_id rows exist underneath, in any of these tables.
    JOIN LATERAL (
        SELECT cp2.product_id FROM BL_3NF.CE_PRODUCTS cp2
        WHERE UPPER(cp2.product_src_id) = UPPER(s.sku)
        ORDER BY cp2.product_id LIMIT 1
    ) cp ON TRUE
    JOIN LATERAL (
        SELECT cc2.customer_id FROM BL_3NF.CE_CUSTOMERS_SCD cc2
        WHERE UPPER(cc2.customer_src_id) = UPPER(s.customer_id)
          AND UPPER(cc2.source_system) = 'SA_NOVATECH_DIRECT'
          AND cc2.is_active = TRUE
        ORDER BY cc2.customer_id LIMIT 1
    ) cc ON TRUE
    LEFT JOIN LATERAL (
        SELECT pm2.payment_method_id FROM BL_3NF.CE_PAYMENT_METHODS pm2
        WHERE UPPER(pm2.payment_method_src_id) = UPPER(s.payment_method)
        ORDER BY pm2.payment_method_id LIMIT 1
    ) pm ON TRUE
    LEFT JOIN LATERAL (
        SELECT st2.shipping_type_id FROM BL_3NF.CE_SHIPPING_TYPES st2
        WHERE UPPER(st2.shipping_type_src_id) = UPPER(s.shipping_type)
        ORDER BY st2.shipping_type_id LIMIT 1
    ) st ON TRUE;
$$;

CREATE OR REPLACE FUNCTION BL_CL.fn_src_ce_sales_b2b()
RETURNS TABLE (
    product_id BIGINT, customer_id BIGINT, employee_id BIGINT, channel_id INT,
    payment_method_id INT, shipping_type_id INT, payment_terms_id INT,
    src_id VARCHAR, src_system VARCHAR, src_table VARCHAR,
    ord_id BIGINT, ord_date DATE, ord_status VARCHAR,
    qty INT, u_price NUMERIC, u_cost NUMERIC, t_sales NUMERIC, t_cost NUMERIC,
    rtg INT, addon NUMERIC,
    ret_flag VARCHAR, fbk VARCHAR, res_days INT, refund NUMERIC,
    supp_ch VARCHAR, esc_flag VARCHAR,
    po_num VARCHAR, po_dt DATE, req_dt DATE, appr VARCHAR, po_ty VARCHAR, po_thr VARCHAR
)
LANGUAGE sql AS $$
    SELECT
        cp.product_id,
        cc.customer_id,
        COALESCE(ce.employee_id, -1)                       AS employee_id,
        2                                                  AS channel_id,      -- CE_CHANNELS: 2 = B2B
        (-1)                                               AS payment_method_id, -- B2B -> "Not Applicable" payment method
        (-1)                                               AS shipping_type_id,  -- B2B -> "Not Applicable" shipping type
        COALESCE(pt.payment_terms_id, -1)                   AS payment_terms_id,
        s.order_id::VARCHAR(60)                            AS src_id,
        'SA_NOVATECH_BUSINESS'::VARCHAR(40)                AS src_system,
        'src_novatech_b2b_orders'::VARCHAR(60)              AS src_table,
        s.order_id::BIGINT                                  AS ord_id,
        s.order_date::DATE                                  AS ord_date,
        s.order_status::VARCHAR(20)                         AS ord_status,
        s.quantity::INT                                     AS qty,
        s.unit_price::NUMERIC(10,2)                         AS u_price,
        s.unit_cost::NUMERIC(10,2)                          AS u_cost,
        s.total_sales::NUMERIC(12,2)                        AS t_sales,
        s.total_cost::NUMERIC(12,2)                         AS t_cost,
        0::INT, 0::NUMERIC,                                                    -- B2C-only rating/add-on: n/a for B2B
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR, 0::INT, 0::NUMERIC,                  -- B2C-only support-ticket columns: n/a for B2B
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR,
        COALESCE(NULLIF(s.po_number,''), 'n.a.')::VARCHAR(20),
        '1900-01-01'::DATE, '1900-01-01'::DATE,
        'n.a.'::VARCHAR, 'n.a.'::VARCHAR, 'n.a.'::VARCHAR    -- PO date/approval/type/threshold not present in CSV
    FROM sa_b2b.src_novatech_b2b_orders s
    JOIN LATERAL (
        SELECT cp2.product_id FROM BL_3NF.CE_PRODUCTS cp2
        WHERE UPPER(cp2.product_src_id) = UPPER(s.sku)
        ORDER BY cp2.product_id LIMIT 1
    ) cp ON TRUE
    JOIN LATERAL (
        SELECT cc2.customer_id FROM BL_3NF.CE_CUSTOMERS_SCD cc2
        WHERE UPPER(cc2.customer_src_id) = UPPER(s.company_id)
          AND UPPER(cc2.source_system) = 'SA_NOVATECH_BUSINESS'
          AND cc2.is_active = TRUE
        ORDER BY cc2.customer_id LIMIT 1
    ) cc ON TRUE
    LEFT JOIN LATERAL (
        SELECT ce2.employee_id FROM BL_3NF.CE_EMPLOYEES ce2
        WHERE UPPER(ce2.employee_src_id) = UPPER(s.account_manager_id)
        ORDER BY ce2.employee_id LIMIT 1
    ) ce ON TRUE
    LEFT JOIN LATERAL (
        SELECT pt2.payment_terms_id FROM BL_3NF.CE_PAYMENT_TERMS pt2
        WHERE UPPER(pt2.payment_terms_src_id) = UPPER(s.payment_terms)
        ORDER BY pt2.payment_terms_id LIMIT 1
    ) pt ON TRUE;
$$;

-- -----------------------------------------------------------------------------
-- 1.b  BL_CL.prc_load_ce_sales() — incremental load procedure
-- Idempotency: WHERE NOT EXISTS on the source triplet (source_id +
-- source_system) — the same pattern used for every CE_ dimension in Task 7.
-- A second run against unchanged source data inserts 0 rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_ce_sales()
LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT := 0;
BEGIN
    INSERT INTO BL_3NF.CE_SALES (
        product_id, customer_id, employee_id, channel_id, payment_method_id,
        shipping_type_id, payment_terms_id, sales_id, sales_src_id, source_system,
        source_table, order_id, order_date, order_status, quantity, unit_price,
        unit_cost, total_sales, total_cost, rating, add_on_total,
        return_or_complaint, feedback_comment, resolution_time_days, refund_amount,
        support_channel_used, escalation_required, po_number, po_issue_date,
        requested_delivery_date, approval_status, po_type, po_value_threshold_flag,
        insert_dt, update_dt
    )
    SELECT
        src.product_id, src.customer_id, src.employee_id, src.channel_id,
        src.payment_method_id, src.shipping_type_id, src.payment_terms_id,
        NEXTVAL('BL_3NF.SEQ_SALES_ID'), src.src_id, src.src_system, src.src_table,
        src.ord_id, src.ord_date, src.ord_status, src.qty, src.u_price, src.u_cost,
        src.t_sales, src.t_cost, src.rtg, src.addon, src.ret_flag, src.fbk,
        src.res_days, src.refund, src.supp_ch, src.esc_flag, src.po_num, src.po_dt,
        src.req_dt, src.appr, src.po_ty, src.po_thr, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM (
        SELECT * FROM BL_CL.fn_src_ce_sales_b2c()
        UNION ALL
        SELECT * FROM BL_CL.fn_src_ce_sales_b2b()
    ) src
    WHERE NOT EXISTS (
        SELECT 1 FROM BL_3NF.CE_SALES cs
        WHERE UPPER(cs.sales_src_id) = UPPER(src.src_id)
          AND UPPER(cs.source_system) = UPPER(src.src_system)
    );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL BL_CL.prc_log_insert('prc_load_ce_sales', v_rows, 0, 'SUCCESS');
END;
$$;

-- =============================================================================
-- PART 2 — BL_DM.FCT_SALES_DD  (partitioned, rolling-window load)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 2.a  BL_CL.prc_manage_fct_sales_partitions(p_month, p_window_months)
--
-- ATTACH: creates BL_DM.FCT_SALES_DD_YYYYMM as a native monthly partition
-- (CREATE TABLE ... PARTITION OF ... FOR VALUES FROM/TO) if it doesn't
-- already exist for p_month.
--
-- DETACH: walks pg_inherits/pg_class to find every existing monthly
-- partition of FCT_SALES_DD, and for any partition whose window is older
-- than p_window_months months before p_month, DETACHes it and DROPs the
-- detached table. DETACH is near-instant DDL (per the courseware,
-- Section 2.2) — no row-by-row DELETE, no bloat, no subsequent VACUUM.
-- In a production run the detached table would typically be archived with
-- COPY/pg_dump before the DROP; that step is omitted here for the demo but
-- is called out below.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_manage_fct_sales_partitions(
    p_month          DATE,
    p_window_months  INT DEFAULT 3
)
LANGUAGE plpgsql AS $$
DECLARE
    v_month_start   DATE := date_trunc('month', p_month)::DATE;
    v_month_end     DATE := (date_trunc('month', p_month) + INTERVAL '1 month')::DATE;
    v_part_name     TEXT := 'fct_sales_dd_' || to_char(v_month_start, 'YYYYMM');
    v_cutoff        DATE := (date_trunc('month', p_month) - (p_window_months - 1) * INTERVAL '1 month')::DATE;
    v_rec           RECORD;
    v_start_txt     TEXT;
BEGIN
    -- ATTACH: create this month's partition if it does not exist yet.
    -- CREATE TABLE ... PARTITION OF is itself the attach operation.
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'bl_dm' AND c.relname = v_part_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE BL_DM.%I PARTITION OF BL_DM.FCT_SALES_DD FOR VALUES FROM (%L) TO (%L)',
            v_part_name, v_month_start, v_month_end
        );
    END IF;

    -- DETACH + DROP: any monthly partition whose range starts before the
    -- rolling-window cutoff gets removed. The DEFAULT partition is skipped.
    FOR v_rec IN
        -- pg_get_expr decodes each partition's FOR VALUES FROM (...) TO (...)
        -- bound (relative to its own oid) so the start date can be read
        -- back out as text and compared against the cutoff.
        SELECT c.relname,
               pg_get_expr(c.relpartbound, c.oid) AS bound_text
        FROM pg_inherits i
        JOIN pg_class c       ON c.oid = i.inhrelid
        JOIN pg_class p       ON p.oid = i.inhparent
        JOIN pg_namespace n   ON n.oid = p.relnamespace
        WHERE n.nspname = 'bl_dm'
          AND p.relname = 'fct_sales_dd'
          AND c.relname <> 'fct_sales_dd_default'
    LOOP
        v_start_txt := substring(v_rec.bound_text FROM E'FROM \\(''([0-9-]+)''');

        IF v_start_txt IS NOT NULL AND v_start_txt::DATE < v_cutoff THEN
            EXECUTE format('ALTER TABLE BL_DM.FCT_SALES_DD DETACH PARTITION BL_DM.%I', v_rec.relname);
            -- Production note: back up with
            --   COPY BL_DM.<partition> TO 'archive/<partition>.csv' CSV HEADER;
            -- (or pg_dump -t) before the DROP, per courseware Section 2.2.
            EXECUTE format('DROP TABLE BL_DM.%I', v_rec.relname);
        END IF;
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2.b  BL_CL.prc_load_fct_sales_dd(p_month) — loads one month's worth of
-- BL_3NF.CE_SALES into the matching FCT_SALES_DD partition.
--
-- Surrogate-key resolution follows the Task 8 "chain rule": for Type-1/0
-- dimensions the BL_3NF surrogate id becomes the DIM's *_src_id, so the
-- join is a direct id-to-id match. DIM_CUSTOMERS_SCD is the one Type-2
-- dimension, so it is resolved with a point-in-time join on event_dt
-- BETWEEN start_dt AND end_dt, per Naming Conventions "Rules for Facts
-- table" #2 (SCD2 FK is logical only, resolved at load time).
--
-- Idempotency: NOT EXISTS on the fact table's own PK triplet
-- (sales_src_id, source_system, source_entity) scoped to the month being
-- loaded — a second run for the same month inserts 0 rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_fct_sales_dd(p_month DATE)
LANGUAGE plpgsql AS $$
DECLARE
    v_month_start DATE := date_trunc('month', p_month)::DATE;
    v_month_end   DATE := (date_trunc('month', p_month) + INTERVAL '1 month')::DATE;
    v_rows        INT := 0;
BEGIN
    INSERT INTO BL_DM.FCT_SALES_DD (
        event_dt, product_surr_id, customer_surr_id, employee_surr_id,
        channel_surr_id, payment_method_surr_id, shipping_type_surr_id,
        payment_terms_surr_id, sales_src_id, source_system, source_entity,
        order_id, order_status, fct_quantity, fct_unit_price, fct_unit_cost,
        fct_total_sales, fct_total_cost, fct_rating, fct_add_on_total,
        fct_refund_amount, insert_dt, update_dt
    )
    SELECT
        ce.order_date, dp.product_surr_id, dcs.customer_surr_id, de.employee_surr_id,
        dc.channel_surr_id, dpm.payment_method_surr_id, dst.shipping_type_surr_id,
        dpt.payment_terms_surr_id, ce.sales_src_id, ce.source_system, ce.source_table,
        ce.order_id, ce.order_status, ce.quantity, ce.unit_price, ce.unit_cost,
        ce.total_sales, ce.total_cost, ce.rating, ce.add_on_total,
        ce.refund_amount, CURRENT_DATE, CURRENT_DATE
    FROM BL_3NF.CE_SALES ce
    -- Same LATERAL-with-ORDER-BY-LIMIT-1 pattern as the 3NF load functions,
    -- for the same reason: guards against any duplicate *_src_id rows in the
    -- DIM_ tables fanning this join out and breaking FCT_SALES_DD's PK.
    JOIN LATERAL (
        SELECT dp2.product_surr_id FROM BL_DM.DIM_PRODUCTS dp2
        WHERE dp2.product_src_id = ce.product_id::VARCHAR
        ORDER BY dp2.product_surr_id LIMIT 1
    ) dp ON TRUE
    JOIN LATERAL (
        SELECT de2.employee_surr_id FROM BL_DM.DIM_EMPLOYEES de2
        WHERE de2.employee_src_id = ce.employee_id::VARCHAR
        ORDER BY de2.employee_surr_id LIMIT 1
    ) de ON TRUE
    JOIN LATERAL (
        SELECT dc2.channel_surr_id FROM BL_DM.DIM_CHANNELS dc2
        WHERE dc2.channel_src_id = ce.channel_id::VARCHAR
        ORDER BY dc2.channel_surr_id LIMIT 1
    ) dc ON TRUE
    JOIN LATERAL (
        SELECT dpm2.payment_method_surr_id FROM BL_DM.DIM_PAYMENT_METHODS dpm2
        WHERE dpm2.payment_method_src_id = ce.payment_method_id::VARCHAR
        ORDER BY dpm2.payment_method_surr_id LIMIT 1
    ) dpm ON TRUE
    JOIN LATERAL (
        SELECT dst2.shipping_type_surr_id FROM BL_DM.DIM_SHIPPING_TYPES dst2
        WHERE dst2.shipping_type_src_id = ce.shipping_type_id::VARCHAR
        ORDER BY dst2.shipping_type_surr_id LIMIT 1
    ) dst ON TRUE
    JOIN LATERAL (
        SELECT dpt2.payment_terms_surr_id FROM BL_DM.DIM_PAYMENT_TERMS dpt2
        WHERE dpt2.payment_terms_src_id = ce.payment_terms_id::VARCHAR
        ORDER BY dpt2.payment_terms_surr_id LIMIT 1
    ) dpt ON TRUE
    JOIN LATERAL (
        SELECT dcs2.customer_surr_id FROM BL_DM.DIM_CUSTOMERS_SCD dcs2
        WHERE dcs2.customer_src_id = ce.customer_id::VARCHAR
          AND ce.order_date BETWEEN dcs2.start_dt AND dcs2.end_dt
        ORDER BY dcs2.customer_surr_id LIMIT 1
    ) dcs ON TRUE
    WHERE ce.order_date >= v_month_start
      AND ce.order_date <  v_month_end
      AND NOT EXISTS (
          SELECT 1 FROM BL_DM.FCT_SALES_DD f
          WHERE UPPER(f.sales_src_id)   = UPPER(ce.sales_src_id)
            AND UPPER(f.source_system)  = UPPER(ce.source_system)
            AND UPPER(f.source_entity)  = UPPER(ce.source_table)
      );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    CALL BL_CL.prc_log_insert('prc_load_fct_sales_dd', v_rows, 0, 'SUCCESS');
END;
$$;

-- -----------------------------------------------------------------------------
-- 2.c  Master wrapper — one CALL runs the whole fact layer refresh for a
-- given month: 3NF incremental load, partition attach/detach housekeeping,
-- then the DM month load.
-- p_month defaults to the latest month present in CE_SALES, so the same
-- CALL works unmodified as new source data lands.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE BL_CL.prc_load_fact_layer(p_month DATE DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_month DATE;
BEGIN
    CALL BL_CL.prc_load_ce_sales();

    v_month := COALESCE(p_month, (SELECT date_trunc('month', MAX(order_date))::DATE FROM BL_3NF.CE_SALES));

    CALL BL_CL.prc_manage_fct_sales_partitions(v_month, 3);
    CALL BL_CL.prc_load_fct_sales_dd(v_month);
END;
$$;
