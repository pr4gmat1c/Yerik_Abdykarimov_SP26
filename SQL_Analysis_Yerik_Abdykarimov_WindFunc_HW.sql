-- =============================================================
-- SQL for Analysis: Window Functions — Homework
-- Yerik Abdykarimov


/* =============================================================
   TASK 1
   Goal : Top-5 customers per sales channel ranked by total sales.
          Include 'sales_percentage' – each customer's share of
          their channel's total sales.

   Design choices
   ──────────────
   1. CTE «customer_channel_sales»
      Collapses raw sales rows into one row per (channel, customer)
      using a plain GROUP BY aggregate BEFORE any window function.
      This is more efficient: window functions then see far fewer rows.

   2. SUM() OVER (PARTITION BY channel_desc)
      Placed in the second CTE after grouping.
      No ORDER BY inside OVER → default frame covers the whole
      partition automatically, so no explicit ROWS/RANGE needed.

   3. RANK() OVER (PARTITION BY channel_desc ORDER BY … DESC)
      Ranking function – has no frame concept at all.
      RANK() is preferred over ROW_NUMBER() because two customers
      with identical totals should share the same rank position.

   4. Formatting
      TO_CHAR with FM-prefix suppresses padding spaces/leading zeros.
      sales_percentage = (customer / channel_total) × 100 rounded
      to 4 decimal places, with ' %' appended.
   ============================================================= */

WITH customer_channel_sales AS (
    -- Aggregate sales per (channel, customer) to get one row each
    SELECT
        ch.channel_desc,
        c.cust_last_name,
        c.cust_first_name,
        SUM(s.amount_sold) AS cust_total_sales
    FROM   sales     s
    JOIN   customers c  ON c.cust_id     = s.cust_id
    JOIN   channels  ch ON ch.channel_id = s.channel_id
    GROUP BY
        ch.channel_desc,
        c.cust_last_name,
        c.cust_first_name
),
ranked_customers AS (
    -- Apply window functions on the already-aggregated data
    SELECT
        channel_desc,
        cust_last_name,
        cust_first_name,
        cust_total_sales,

        -- Channel total: SUM with only PARTITION BY (no ORDER BY, no frame)
        -- The whole partition is summed, giving us the denominator for %
        SUM(cust_total_sales) OVER (PARTITION BY channel_desc) AS channel_total_sales,

        -- Rank customers inside each channel; ties share the same rank
        RANK() OVER (PARTITION BY channel_desc ORDER BY cust_total_sales DESC) AS sales_rank

    FROM customer_channel_sales
)
SELECT
    channel_desc,
    cust_last_name,
    cust_first_name,
    TO_CHAR(cust_total_sales,                               'FM999999990.00') AS amount_sold,
    TO_CHAR(cust_total_sales / channel_total_sales * 100, 'FM990.0000') || ' %' AS sales_percentage
FROM   ranked_customers
WHERE  sales_rank <= 5
ORDER BY channel_desc,
         cust_total_sales DESC;


/* =============================================================
   TASK 2
   Goal : Total sales of Photo-category products in the Asian
          region for the year 2000.  Pivot results by calendar
          quarter (q1–q4) and add a YEAR_SUM column.

   Design choices
   ──────────────
   1. crosstab() from the 'tablefunc' extension
      It pivots a (row_id, category, value) result set into
      wide-format columns – exactly what the quarterly layout needs.
      The second argument lists all expected category values so
      missing quarters receive NULL (handled with COALESCE → 0).

   2. Inner query
      Joins sales → products → times → customers → countries to
      filter Photo category + Asia region + year 2000.
      Groups by product name and quarter number, then formats
      the quarter label as 'q1', 'q2', 'q3', 'q4'.
      ORDER BY inside the query string is mandatory for crosstab
      to assign values to the correct columns.

   3. YEAR_SUM
      Computed outside crosstab by summing all four quarter columns
      (with COALESCE to treat NULL as 0 for products with no sales
      in a particular quarter).

   4. Final ORDER BY year_sum DESC as required by the assignment.

   Note: CREATE EXTENSION is idempotent (IF NOT EXISTS) and only
         needs to run once per database; left here for portability.
   ============================================================= */

CREATE EXTENSION IF NOT EXISTS tablefunc;

SELECT
    product_name,
    TO_CHAR(COALESCE(q1, 0), 'FM999999990.00') AS q1,
    TO_CHAR(COALESCE(q2, 0), 'FM999999990.00') AS q2,
    TO_CHAR(COALESCE(q3, 0), 'FM999999990.00') AS q3,
    TO_CHAR(COALESCE(q4, 0), 'FM999999990.00') AS q4,
    TO_CHAR(
        COALESCE(q1, 0) + COALESCE(q2, 0) + COALESCE(q3, 0) + COALESCE(q4, 0),
        'FM999999990.00'
    ) AS year_sum
FROM crosstab(
    -- Source query: one row per (product, quarter) with summed sales
    $$
    SELECT
        p.prod_name                            AS product_name,
        'q' || t.calendar_quarter_number       AS quarter,
        ROUND(SUM(s.amount_sold)::NUMERIC, 2)  AS sales_amount
    FROM   sales     s
    JOIN   products  p  ON p.prod_id     = s.prod_id
    JOIN   times     t  ON t.time_id     = s.time_id
    JOIN   customers c  ON c.cust_id     = s.cust_id
    JOIN   countries co ON co.country_id = c.country_id
    WHERE  p.prod_category   = 'Photo'
      AND  co.country_region = 'Asia'
      AND  t.calendar_year   = 2000
    GROUP BY p.prod_name, t.calendar_quarter_number
    ORDER BY p.prod_name, t.calendar_quarter_number
    $$,
    -- Explicit category list so missing quarters map to NULL, not shift
    $$VALUES ('q1'), ('q2'), ('q3'), ('q4')$$
) AS pivot_table (
    product_name TEXT,
    q1           NUMERIC,
    q2           NUMERIC,
    q3           NUMERIC,
    q4           NUMERIC
)
ORDER BY
    (COALESCE(q1, 0) + COALESCE(q2, 0) + COALESCE(q3, 0) + COALESCE(q4, 0)) DESC;


/* =============================================================
   TASK 3
   Goal : Sales report for customers who ranked in the top 300
          by total sales across the years 1998, 1999, and 2001.
          Results are broken out by sales channel; only purchases
          made through each listed channel are included.

   Design choices
   ──────────────
   1. CTE «yearly_totals»
      Sums each customer's amount_sold for the three target years
      in a single pass using an IN filter on calendar_year.

   2. CTE «top_300»
      Applies RANK() OVER (ORDER BY total_sales DESC) — a pure
      ranking function with no frame — then keeps only rank ≤ 300.
      RANK() is used so that ties at position 300 are all included,
      avoiding arbitrary cut-offs.

   3. CTE «channel_sales»
      Re-joins the original sales table (filtered to the same years
      and to top-300 customers) and groups by channel + customer.
      This gives each customer's channel-specific amount, which is
      what "include only purchases made on the channel specified" means.

   4. CTE «channel_ranked»
      RANK() OVER (PARTITION BY channel_desc ORDER BY amount_sold DESC)
      performs a *separate* ranking calculation for every channel,
      fulfilling the "separate calculations per channel" requirement.
      No frame is involved because RANK() never uses one.

   5. Final SELECT
      Outputs channel_desc, cust_id, names, and formatted amount_sold
      ordered by channel then descending sales, matching the sample layout.
   ============================================================= */

WITH yearly_totals AS (
    -- Total sales per customer restricted to the three specified years
    SELECT
        s.cust_id,
        SUM(s.amount_sold) AS total_sales
    FROM   sales  s
    JOIN   times  t ON t.time_id = s.time_id
    WHERE  t.calendar_year IN (1998, 1999, 2001)
    GROUP BY s.cust_id
),
top_300 AS (
    -- Rank all customers; retain those in the top 300
    -- RANK() needs no frame – it is a ranking (non-aggregate) window function
    SELECT cust_id
    FROM (
        SELECT
            cust_id,
            RANK() OVER (ORDER BY total_sales DESC) AS overall_rank
        FROM yearly_totals
    ) ranked
    WHERE overall_rank <= 300
),
channel_sales AS (
    -- For top-300 customers, aggregate sales *per channel* in the same years
    -- Only channel-specific amounts are summed (no cross-channel totals),
    -- satisfying "include only purchases made on the channel specified"
    SELECT
        ch.channel_desc,
        c.cust_id,
        c.cust_last_name,
        c.cust_first_name,
        SUM(s.amount_sold) AS amount_sold
    FROM   sales     s
    JOIN   customers c  ON c.cust_id     = s.cust_id
    JOIN   channels  ch ON ch.channel_id = s.channel_id
    JOIN   times     t  ON t.time_id     = s.time_id
    WHERE  s.cust_id IN (SELECT cust_id FROM top_300)
      AND  t.calendar_year IN (1998, 1999, 2001)
    GROUP BY
        ch.channel_desc,
        c.cust_id,
        c.cust_last_name,
        c.cust_first_name
),
channel_ranked AS (
    -- Separate RANK() per channel – "separate calculations for each channel"
    -- PARTITION BY channel_desc ensures rankings restart for every channel
    SELECT
        channel_desc,
        cust_id,
        cust_last_name,
        cust_first_name,
        amount_sold,
        RANK() OVER (PARTITION BY channel_desc ORDER BY amount_sold DESC) AS channel_rank
    FROM channel_sales
)
SELECT
    channel_desc,
    cust_id,
    cust_last_name,
    cust_first_name,
    TO_CHAR(amount_sold, 'FM999999990.00') AS amount_sold
FROM   channel_ranked
ORDER BY channel_desc,
         amount_sold DESC;


/* =============================================================
   TASK 4
   Goal : Sales report for January, February, and March 2000
          for the Europe and Americas regions.
          Display results by month and product category
          (both in alphabetical order), with one column per region.

   Design choices
   ──────────────
   1. Conditional aggregation instead of crosstab
      Because we are pivoting only two known regions (Americas,
      Europe), using SUM(CASE WHEN region = '...' THEN amount END)
      is simpler and more readable than crosstab().
      It avoids an extra extension call and keeps the query self-
      contained. No window functions with frames are needed here.

   2. Filter on calendar_month_desc
      The three months are identified by their canonical string
      values ('2000-01', '2000-02', '2000-03') rather than by
      month number + year, so the output column already contains
      the formatted month descriptor matching the sample report.

   3. country_region filter
      Applied as IN ('Americas', 'Europe') directly in the WHERE
      clause; this excludes Asia and other regions efficiently
      before aggregation rather than after.

   4. ROUND(..., 0) → TO_CHAR with comma formatting
      The sample output shows integer values with thousands
      separators (e.g. 143,563). FM prefix removes leading spaces;
      999G999G990 inserts locale group separators.

   5. ORDER BY month alphabetically, then category alphabetically
      '2000-01' < '2000-02' < '2000-03' sorts correctly as plain
      text, so no date casting is needed for the ORDER BY.
   ============================================================= */

SELECT
    t.calendar_month_desc,
    p.prod_category,

    -- Americas: sum only rows where region = 'Americas', else treat as 0
    TO_CHAR(
        ROUND(SUM(CASE WHEN co.country_region = 'Americas' THEN s.amount_sold ELSE 0 END)),
        'FM999G999G990'
    ) AS "Americas SALES",

    -- Europe: sum only rows where region = 'Europe', else treat as 0
    TO_CHAR(
        ROUND(SUM(CASE WHEN co.country_region = 'Europe'   THEN s.amount_sold ELSE 0 END)),
        'FM999G999G990'
    ) AS "Europe SALES"

FROM   sales     s
JOIN   products  p  ON p.prod_id     = s.prod_id
JOIN   times     t  ON t.time_id     = s.time_id
JOIN   customers c  ON c.cust_id     = s.cust_id
JOIN   countries co ON co.country_id = c.country_id

WHERE  t.calendar_month_desc IN ('2000-01', '2000-02', '2000-03')
  AND  co.country_region      IN ('Americas', 'Europe')

GROUP BY
    t.calendar_month_desc,
    p.prod_category

ORDER BY
    t.calendar_month_desc ASC,
    p.prod_category       ASC;
