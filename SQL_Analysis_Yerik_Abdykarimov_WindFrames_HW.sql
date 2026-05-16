-- ============================================================
-- SQL Analysis: Writing Queries Using Window Frames
-- Yerik Abdykarimov


-- ============================================================
-- TASK 1
-- Annual sales analysis for 1999-2001
-- Regions: Americas, Asia, Europe
-- Columns: AMOUNT_SOLD, % BY CHANNELS, % PREVIOUS PERIOD, % DIFF
-- ============================================================

WITH sales_agg AS (
    -- Step 1: aggregate raw sales per region / year / channel
    SELECT
        co.country_region,
        t.calendar_year,
        ch.channel_desc,
        SUM(s.amount_sold)  AS amount_sold
    FROM
        sh.sales       s
        JOIN sh.times     t  ON s.time_id     = t.time_id
        JOIN sh.channels  ch ON s.channel_id  = ch.channel_id
        JOIN sh.customers cu ON s.cust_id     = cu.cust_id
        JOIN sh.countries co ON cu.country_id = co.country_id
    WHERE
        t.calendar_year      BETWEEN 1999 AND 2001
        AND co.country_region IN ('Americas', 'Asia', 'Europe')
    GROUP BY
        co.country_region,
        t.calendar_year,
        ch.channel_desc
),
pct_calc AS (
    -- Step 2: compute each channel's share of its region-year total
    SELECT
        country_region,
        calendar_year,
        channel_desc,
        amount_sold,
        ROUND(
            amount_sold
            / SUM(amount_sold) OVER (PARTITION BY country_region, calendar_year)
            * 100,
            2
        )  AS pct_by_channels
    FROM sales_agg
)
-- Step 3: bring in the previous year's percentage with LAG and derive % DIFF
SELECT
    country_region,
    calendar_year,
    channel_desc,
    amount_sold,
    pct_by_channels                                                          AS "% BY CHANNELS",
    LAG(pct_by_channels) OVER (
        PARTITION BY country_region, channel_desc
        ORDER BY calendar_year
    )                                                                        AS "% PREVIOUS PERIOD",
    pct_by_channels
        - LAG(pct_by_channels) OVER (
            PARTITION BY country_region, channel_desc
            ORDER BY calendar_year
          )                                                                  AS "% DIFF"
FROM pct_calc
ORDER BY
    country_region,
    calendar_year,
    channel_desc;


-- ============================================================
-- TASK 2
-- Weekly sales report for weeks 49, 50, 51 of 1999
-- Columns: CUM_SUM (resets each week)
--          CENTERED_3_DAY_AVG
--            • Monday  → avg(Sat, Sun, Mon, Tue)  [2 PRECEDING, 1 FOLLOWING]
--            • Friday  → avg(Thu, Fri, Sat, Sun)  [1 PRECEDING, 2 FOLLOWING]
--            • Others  → avg(prev, curr, next)    [1 PRECEDING, 1 FOLLOWING]
-- Week 48 Saturday & Sunday are pulled in so that Monday of
-- week 49 can look back two rows; they are filtered out in the
-- final SELECT.
-- ============================================================

WITH daily_sales AS (
    SELECT
        t.calendar_week_number,
        t.time_id,
        t.day_name,
        SUM(s.amount_sold)  AS sales
    FROM
        sh.sales  s
        JOIN sh.times t ON s.time_id = t.time_id
    WHERE
        t.calendar_year          = 1999
        AND t.calendar_week_number IN (48, 49, 50, 51)
    GROUP BY
        t.calendar_week_number,
        t.time_id,
        t.day_name
),
windowed AS (
    SELECT
        calendar_week_number,
        time_id,
        day_name,
        sales,
        -- Cumulative sum resets at the start of each calendar week
        SUM(sales) OVER (
            PARTITION BY calendar_week_number
            ORDER BY     time_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )  AS cum_sum,
        -- Three separate averages; the CASE below picks the right one
        AVG(sales) OVER (
            ORDER BY time_id
            ROWS BETWEEN 2 PRECEDING AND 1 FOLLOWING   -- Monday window
        )  AS avg_monday,
        AVG(sales) OVER (
            ORDER BY time_id
            ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING   -- Normal window
        )  AS avg_normal,
        AVG(sales) OVER (
            ORDER BY time_id
            ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING   -- Friday window
        )  AS avg_friday
    FROM daily_sales
)
SELECT
    calendar_week_number,
    time_id,
    day_name,
    ROUND(sales,   2)  AS sales,
    ROUND(cum_sum, 2)  AS cum_sum,
    ROUND(
        CASE
            WHEN day_name = 'Monday' THEN avg_monday
            WHEN day_name = 'Friday' THEN avg_friday
            ELSE                          avg_normal
        END,
        2
    )                  AS centered_3_day_avg
FROM windowed
WHERE calendar_week_number IN (49, 50, 51)
ORDER BY time_id;


-- ============================================================
-- TASK 3
-- Three window-function examples illustrating ROWS, RANGE,
-- and GROUPS frame modes, each with an explanation of why
-- that specific mode was chosen.
-- ============================================================

-- ------------------------------------------------------------
-- Example 1 — ROWS
-- Business question: What is the running (cumulative) total
-- of annual sales for each sales channel?
--
-- Why ROWS?
--   ROWS operates on physical row positions in the result set.
--   Because our GROUP BY guarantees exactly one row per
--   (channel, year) pair, ROWS BETWEEN UNBOUNDED PRECEDING
--   AND CURRENT ROW adds one year's revenue at a time and
--   produces a strict, predictable accumulation.
--   If we used RANGE here, any two years that happened to
--   share the same ORDER BY value would be lumped together,
--   which could silently distort the running total.
--   ROWS avoids that risk by never looking at values — only
--   positions.
-- ------------------------------------------------------------
SELECT
    t.calendar_year,
    ch.channel_desc,
    SUM(s.amount_sold)                                              AS yearly_sales,
    SUM(SUM(s.amount_sold)) OVER (
        PARTITION BY ch.channel_desc
        ORDER BY     t.calendar_year
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                               AS cumulative_sales_rows
FROM
    sh.sales      s
    JOIN sh.times    t  ON s.time_id    = t.time_id
    JOIN sh.channels ch ON s.channel_id = ch.channel_id
GROUP BY
    t.calendar_year,
    ch.channel_desc
ORDER BY
    ch.channel_desc,
    t.calendar_year;


-- ------------------------------------------------------------
-- Example 2 — RANGE
-- Business question: What is the 3-month centered moving
-- average of monthly sales in 2001 (previous month, current
-- month, next month)?
--
-- Why RANGE?
--   RANGE interprets frame boundaries as VALUE offsets on the
--   ORDER BY column, not as row-count offsets.
--   With ORDER BY calendar_month_number and
--   RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING, the engine
--   automatically includes every row whose month number falls
--   within [current_month - 1, current_month + 1].
--   This is semantically correct: we want "the adjacent
--   months by calendar proximity", not "the adjacent rows by
--   position." If months were ever missing from the data (e.g.
--   no sales in February), ROWS would silently skip over the
--   gap while RANGE would correctly limit the average to the
--   months that are truly within ±1 of the current one.
-- ------------------------------------------------------------
SELECT
    t.calendar_year,
    t.calendar_month_number,
    SUM(s.amount_sold)                                              AS monthly_sales,
    ROUND(
        AVG(SUM(s.amount_sold)) OVER (
            PARTITION BY t.calendar_year
            ORDER BY     t.calendar_month_number
            RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING
        ),
        2
    )                                                               AS centered_3month_avg_range
FROM
    sh.sales  s
    JOIN sh.times t ON s.time_id = t.time_id
WHERE
    t.calendar_year = 2001
GROUP BY
    t.calendar_year,
    t.calendar_month_number
ORDER BY
    t.calendar_month_number;


-- ------------------------------------------------------------
-- Example 3 — GROUPS
-- Business question: For each sales channel, what is the
-- smoothed average of yearly sales using a sliding window of
-- the previous year, the current year, and the next year?
--
-- Why GROUPS?
--   GROUPS counts peer groups — sets of rows that share the
--   same ORDER BY value — as single logical units.
--   Here every channel row for a given year forms one peer
--   group. GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING means
--   "include the whole previous-year group, this year's
--   group, and the whole next-year group," regardless of how
--   many channel rows each year contains.
--   • ROWS would be wrong: the number of rows per year can
--     vary as channels are added or discontinued, making
--     ROWS N PRECEDING an unreliable proxy for "N years ago."
--   • RANGE would be wrong: it would require a numeric offset
--     of 1 on calendar_year, which only works cleanly when
--     years are perfectly consecutive; RANGE also cannot
--     naturally express "one group back."
--   GROUPS is the clearest, most robust choice when the
--   logical unit of analysis is a year-group rather than a
--   row or a value distance.
-- ------------------------------------------------------------
SELECT
    t.calendar_year,
    ch.channel_desc,
    SUM(s.amount_sold)                                              AS yearly_channel_sales,
    ROUND(
        AVG(SUM(s.amount_sold)) OVER (
            PARTITION BY ch.channel_desc
            ORDER BY     t.calendar_year
            GROUPS BETWEEN 1 PRECEDING AND 1 FOLLOWING
        ),
        2
    )                                                               AS smoothed_avg_groups
FROM
    sh.sales      s
    JOIN sh.times    t  ON s.time_id    = t.time_id
    JOIN sh.channels ch ON s.channel_id = ch.channel_id
GROUP BY
    t.calendar_year,
    ch.channel_desc
ORDER BY
    ch.channel_desc,
    t.calendar_year;
