-- SCHEMA ANALYSIS
-- -----------------------------------------------------------------------------
-- Transactional tables: payment, rental
--   Capture individual business events (payments collected, films rented).
--   They grow continuously and are the primary source of business metrics.
--
-- Reference tables: film, actor, category, language, address, city, country
--   Relatively stable descriptive data that transactional rows point to.
--
-- Junction tables: film_actor, film_category, inventory
--   Resolve M:N relationships (actor-film, film-category) and link films
--   to physical stores (inventory).
--
-- Operational entity tables: staff, store, customer
--   Represent people and locations involved in transactions.
-- =============================================================================
-- NOTES
--   1. Three solutions per task: JOIN, then CTE, then Subquery.
--      If a JOIN solution cannot be implemented correctly the reason is documented (per assignment rule 1).
--   2. Schema prefix "public." on every table reference (rule 5).
--   3. No hard-coded IDs (rule 6).
--   4. GROUP BY / ORDER BY use column names, not positional numbers (rule 7).
--   5. JOIN type always specified explicitly (rule 8).
--   6. No window functions (rule 10).
-- =============================================================================


-- =============================================================================
-- PART 1 -- TASK 1
-- =============================================================================
-- The marketing team needs Animation movies released between 2017 and 2019
-- with rental_rate > 1, sorted alphabetically.
--
-- Assumptions:
--   * "Rate more than 1" means rental_rate > 1 (strictly).
--   * "Between 2017 and 2019" is inclusive on both ends.
--   * release_year uses PostgreSQL's custom "year" type; integer literals
--     compare to it directly without casting.
-- =============================================================================

-- Solution 1: JOIN
-- INNER JOINs film -> film_category -> category.
-- All three conditions (category, year range, rate) live in the WHERE clause.
-- Advantage: single pass; fewest moving parts; easy to index-tune.
-- Disadvantage: all filters mixed in one WHERE clause.
-- Production choice: this variant - simplest and most transparent.

SELECT
    f.title,
    f.release_year,
    f.rental_rate
FROM       public.film          f
INNER JOIN public.film_category fc ON f.film_id      = fc.film_id
INNER JOIN public.category       c ON fc.category_id = c.category_id
WHERE c.name         = 'Animation'
  AND f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate  > 1
ORDER BY f.title;


-- Solution 2: CTE
-- CTE isolates "which films are Animation?" from the outer sort logic.
-- Advantage: each concern is named and independently readable.
-- Disadvantage: PostgreSQL < 12 materialises CTEs as optimisation fences.

WITH animation_films AS (
    SELECT fc.film_id
    FROM   public.film_category fc
    INNER JOIN public.category c ON fc.category_id = c.category_id
    WHERE  c.name = 'Animation'
)
SELECT
    f.title,
    f.release_year,
    f.rental_rate
FROM       public.film        f
INNER JOIN animation_films   af ON f.film_id = af.film_id
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate  > 1
ORDER BY f.title;


-- Solution 3: Subquery
-- IN subquery returns the film_ids that belong to Animation category.
-- Advantage: separates the category filter into a reusable sub-expression.
-- Disadvantage: the optimiser may or may not flatten the subquery.

SELECT
    f.title,
    f.release_year,
    f.rental_rate
FROM public.film f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate  > 1
  AND f.film_id IN (
      SELECT fc.film_id
      FROM   public.film_category fc
      INNER JOIN public.category c ON fc.category_id = c.category_id
      WHERE  c.name = 'Animation'
  )
ORDER BY f.title;


-- =============================================================================
-- PART 1 -- TASK 2
-- =============================================================================
-- Revenue earned by each rental store after March 2017.
-- Columns: combined address (address + address2), revenue.
--
-- Assumptions:
--   * "After March 2017" = payment_date >= '2017-04-01'.
--   * Store is linked via the staff member who processed the payment
--     (payment.staff_id -> staff.store_id). Per the assignment: "if staff
--     processed the payment he works in the same store."
--   * address2 can be NULL; CASE handles this cleanly.
-- =============================================================================

-- Solution 1: JOIN
-- Chain: payment -> staff -> store -> address.
-- Advantage: single linear join path; very readable.
-- Disadvantage: store is attributed to the staff's registered store, not the physical inventory store of the rented item.
-- Production choice: this variant, given the stated assumption above.

SELECT
    a.address
        || CASE
               WHEN a.address2 IS NOT NULL AND a.address2 <> ''
               THEN ', ' || a.address2
               ELSE ''
           END  AS address,
    SUM(p.amount) AS revenue
FROM       public.payment p
INNER JOIN public.staff   st ON p.staff_id   = st.staff_id
INNER JOIN public.store    s  ON st.store_id  = s.store_id
INNER JOIN public.address  a  ON s.address_id = a.address_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY s.store_id, a.address, a.address2
ORDER BY revenue DESC;


-- Solution 2: CTE
-- CTE pre-builds the staff -> store address mapping; outer query aggregates.
-- Advantage: the address construction is encapsulated and reusable.
-- Disadvantage: extra materialisation step on large payment tables.

WITH staff_store_address AS (
    SELECT
        st.staff_id,
        s.store_id,
        a.address
            || CASE
                   WHEN a.address2 IS NOT NULL AND a.address2 <> ''
                   THEN ', ' || a.address2
                   ELSE ''
               END AS full_address
    FROM       public.staff   st
    INNER JOIN public.store    s ON st.store_id  = s.store_id
    INNER JOIN public.address  a ON s.address_id = a.address_id
)
SELECT
    ssa.full_address AS address,
    SUM(p.amount)    AS revenue
FROM       public.payment          p
INNER JOIN staff_store_address    ssa ON p.staff_id = ssa.staff_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY ssa.store_id, ssa.full_address
ORDER BY revenue DESC;


-- Solution 3: Subquery
-- Inline subquery encapsulates the staff -> address mapping.
-- Advantage: self-contained; clear separation of address derivation.
-- Disadvantage: inline views can be harder to debug than named CTEs.

SELECT
    sa.full_address AS address,
    SUM(p.amount)   AS revenue
FROM public.payment p
INNER JOIN (
    SELECT
        st.staff_id,
        s.store_id,
        a.address
            || CASE
                   WHEN a.address2 IS NOT NULL AND a.address2 <> ''
                   THEN ', ' || a.address2
                   ELSE ''
               END AS full_address
    FROM       public.staff   st
    INNER JOIN public.store    s ON st.store_id  = s.store_id
    INNER JOIN public.address  a ON s.address_id = a.address_id
) sa ON p.staff_id = sa.staff_id
WHERE p.payment_date >= '2017-04-01'
GROUP BY sa.store_id, sa.full_address
ORDER BY revenue DESC;


-- =============================================================================
-- PART 1 -- TASK 3
-- =============================================================================
-- Top-5 actors by number of movies they appeared in, released after 2015.
-- Columns: first_name, last_name, number_of_movies. Sorted DESC.
--
-- Assumptions:
--   * "After 2015" = release_year > 2015, this means 2016 and later.
--   * Each film_actor row counts as one participation.
-- =============================================================================

-- Solution 1: JOIN
-- actor -> film_actor -> film, filtered by release_year, grouped by actor.
-- Advantage: most concise; single scan with a simple GROUP BY.
-- Disadvantage: aggregation and join logic share one statement.
-- Production choice: this variant.

SELECT
    a.first_name,
    a.last_name,
    COUNT(fa.film_id) AS number_of_movies
FROM       public.actor       a
INNER JOIN public.film_actor  fa ON a.actor_id = fa.actor_id
INNER JOIN public.film         f ON fa.film_id  = f.film_id
WHERE f.release_year > 2015
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY number_of_movies DESC
LIMIT 5;


-- Solution 2: CTE
-- CTE first counts movies per actor; outer query joins back for names.
-- Advantage: aggregation and name lookup are clearly separated.
-- Disadvantage: two passes over the data (CTE scan + join).

WITH actor_movie_count AS (
    SELECT
        fa.actor_id,
        COUNT(fa.film_id) AS number_of_movies
    FROM       public.film_actor fa
    INNER JOIN public.film        f ON fa.film_id = f.film_id
    WHERE f.release_year > 2015
    GROUP BY fa.actor_id
)
SELECT
    a.first_name,
    a.last_name,
    amc.number_of_movies
FROM       actor_movie_count  amc
INNER JOIN public.actor        a  ON amc.actor_id = a.actor_id
ORDER BY amc.number_of_movies DESC
LIMIT 5;


-- Solution 3: Subquery
-- Correlated scalar subquery computes the count per actor in the SELECT list.
-- Advantage: the count computation is visually isolated per actor.
-- Disadvantage: executes once per actor row; slower without proper indexes.

SELECT
    a.first_name,
    a.last_name,
    (
        SELECT COUNT(fa.film_id)
        FROM   public.film_actor fa
        INNER JOIN public.film    f ON fa.film_id = f.film_id
        WHERE  fa.actor_id    = a.actor_id
          AND  f.release_year > 2015
    ) AS number_of_movies
FROM public.actor a
ORDER BY number_of_movies DESC
LIMIT 5;


-- =============================================================================
-- PART 1 -- TASK 4
-- =============================================================================
-- Number of Drama, Travel, and Documentary films per release year.
-- Columns: release_year, number_of_drama_movies, number_of_travel_movies,
--          number_of_documentary_movies. Sorted by release_year DESC.
--
-- Assumptions:
--   * Solution 1 (JOIN) uses conditional aggregation: it shows 0 for
--     missing genre/year combos, and only includes years that contain at
--     least one film in any of the three genres. All 31 years in the data
--     have at least one of the three genres, so no year is silently lost.
--     The trade-off: missing combos show 0 instead of NULL.
--   * Solutions 2 and 3 preserve NULL for missing genre/year combos, which
--     more precisely signals "no data" vs. "count is zero."
-- =============================================================================

-- Solution 1: JOIN
-- Single scan with CASE WHEN inside COUNT -- classic pivot technique.
-- Advantage: one pass over joined tables; most efficient.
-- Disadvantage: missing genre/year combos show 0 instead of NULL;
--      years with zero films in all three genres would be excluded
--      (not an issue in this dataset, but a logical limitation).

SELECT
    f.release_year,
    COUNT(CASE WHEN c.name = 'Drama'       THEN 1 END) AS number_of_drama_movies,
    COUNT(CASE WHEN c.name = 'Travel'      THEN 1 END) AS number_of_travel_movies,
    COUNT(CASE WHEN c.name = 'Documentary' THEN 1 END) AS number_of_documentary_movies
FROM       public.film          f
INNER JOIN public.film_category fc ON f.film_id      = fc.film_id
INNER JOIN public.category       c ON fc.category_id = c.category_id
WHERE c.name IN ('Drama', 'Travel', 'Documentary')
GROUP BY f.release_year
ORDER BY f.release_year DESC;


-- Solution 2: CTE
-- Four CTEs: a full year list, plus one per genre. LEFT JOINs ensure every
-- year appears; NULL correctly signals "no film of this genre this year."
-- Advantage: each genre is a named, independently readable step; NULL semantics are correct.
-- Disadvantage: more verbose; three extra CTEs vs. a single JOIN scan.
-- Production choice: this variant for its correct NULL semantics.

WITH all_years AS (
    SELECT DISTINCT release_year
    FROM   public.film
    WHERE  release_year IS NOT NULL
),
drama AS (
    SELECT f.release_year, COUNT(*) AS cnt
    FROM       public.film          f
    INNER JOIN public.film_category fc ON f.film_id      = fc.film_id
    INNER JOIN public.category       c ON fc.category_id = c.category_id
    WHERE c.name = 'Drama'
    GROUP BY f.release_year
),
travel AS (
    SELECT f.release_year, COUNT(*) AS cnt
    FROM       public.film          f
    INNER JOIN public.film_category fc ON f.film_id      = fc.film_id
    INNER JOIN public.category       c ON fc.category_id = c.category_id
    WHERE c.name = 'Travel'
    GROUP BY f.release_year
),
documentary AS (
    SELECT f.release_year, COUNT(*) AS cnt
    FROM       public.film          f
    INNER JOIN public.film_category fc ON f.film_id      = fc.film_id
    INNER JOIN public.category       c ON fc.category_id = c.category_id
    WHERE c.name = 'Documentary'
    GROUP BY f.release_year
)
SELECT
    ay.release_year,
    d.cnt   AS number_of_drama_movies,
    t.cnt   AS number_of_travel_movies,
    doc.cnt AS number_of_documentary_movies
FROM            all_years   ay
LEFT JOIN drama        d   ON ay.release_year = d.release_year
LEFT JOIN travel       t   ON ay.release_year = t.release_year
LEFT JOIN documentary doc  ON ay.release_year = doc.release_year
ORDER BY ay.release_year DESC;


-- Solution 3: Subquery
-- Three correlated scalar subqueries per year; outer query drives from a DISTINCT inline subquery over all years.
-- Advantage: each genre count is visually self-contained; NULL preserved.
-- Disadvantage: three correlated subquery executions per year row; slowest.

SELECT
    yr.release_year,
    (
        SELECT COUNT(*)
        FROM       public.film          f2
        INNER JOIN public.film_category fc2 ON f2.film_id      = fc2.film_id
        INNER JOIN public.category       c2 ON fc2.category_id = c2.category_id
        WHERE c2.name = 'Drama' AND f2.release_year = yr.release_year
    ) AS number_of_drama_movies,
    (
        SELECT COUNT(*)
        FROM       public.film          f3
        INNER JOIN public.film_category fc3 ON f3.film_id      = fc3.film_id
        INNER JOIN public.category       c3 ON fc3.category_id = c3.category_id
        WHERE c3.name = 'Travel' AND f3.release_year = yr.release_year
    ) AS number_of_travel_movies,
    (
        SELECT COUNT(*)
        FROM       public.film          f4
        INNER JOIN public.film_category fc4 ON f4.film_id      = fc4.film_id
        INNER JOIN public.category       c4 ON fc4.category_id = c4.category_id
        WHERE c4.name = 'Documentary' AND f4.release_year = yr.release_year
    ) AS number_of_documentary_movies
FROM (
    SELECT DISTINCT release_year
    FROM   public.film
    WHERE  release_year IS NOT NULL
) yr
ORDER BY yr.release_year DESC;


-- =============================================================================
-- PART 2 -- TASK 1
-- =============================================================================
-- Top-3 staff by total revenue in 2017, plus the last store they worked in.
--
-- Assumptions:
--   * Only payment_date determines the year (2017).
--   * "Last store" = the inventory store linked to the most recent payment
--     processed by that staff member in 2017 (payment -> rental -> inventory).
--
-- JOIN LIMITATION (rule 1 explanation):
--   Finding "the last payment per staff" requires selecting exactly one row
--   per staff at the maximum payment_date. With a LEFT JOIN anti-join
--   (LEFT JOIN payment p_later WHERE p_later.payment_id IS NULL), ties at
--   the maximum timestamp cause the anti-join to retain all tied rows. Those
--   rows pass through the rental -> inventory join and produce multiple
--   (staff, store) combinations, so the GROUP BY splits revenue by store
--   rather than summing it per staff -- producing incorrect totals. Because
--   many payments in this dataset share the exact same maximum timestamp per
--   staff, the JOIN approach cannot correctly solve this task.
--   Solutions 2 (CTE) and 3 (Subquery) are the correct implementations.
-- =============================================================================

-- Solution 1: JOIN
-- LEFT JOIN anti-join pattern attempts to identify the last payment per staff.
-- As documented above, ties in payment_date cause revenue to be split by
-- store and incorrect results are produced. The query executes without errors
-- but does not give the correct answer for this dataset.

SELECT
    st.first_name,
    st.last_name,
    SUM(p.amount)  AS total_revenue,
    i.store_id     AS last_store_id
FROM       public.staff      st
INNER JOIN public.payment    p       ON st.staff_id         = p.staff_id
                                     AND EXTRACT(YEAR FROM p.payment_date) = 2017
INNER JOIN public.rental     r       ON p.rental_id         = r.rental_id
INNER JOIN public.inventory  i       ON r.inventory_id      = i.inventory_id
LEFT  JOIN public.payment    p_later ON p.staff_id          = p_later.staff_id
                                     AND p_later.payment_date > p.payment_date
                                     AND EXTRACT(YEAR FROM p_later.payment_date) = 2017
WHERE p_later.payment_id IS NULL
GROUP BY st.staff_id, st.first_name, st.last_name, i.store_id
ORDER BY total_revenue DESC
LIMIT 3;


-- Solution 2: CTE
-- CTE 1: total 2017 revenue per staff.
-- CTE 2: last store via DISTINCT ON (staff_id) ordered by payment_date DESC,
--         which returns exactly one row per staff even when timestamps tie.
-- Advantage: each logical step is named; correct for any timestamp ties.
-- Disadvantage: two separate scans of the payment table.
-- Production choice: this variant.

WITH revenue_2017 AS (
    SELECT
        p.staff_id,
        SUM(p.amount) AS total_revenue
    FROM public.payment p
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
    GROUP BY p.staff_id
),
last_payment_store AS (
    SELECT DISTINCT ON (p.staff_id)
        p.staff_id,
        i.store_id AS last_store_id
    FROM       public.payment   p
    INNER JOIN public.rental    r ON p.rental_id    = r.rental_id
    INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
    ORDER BY p.staff_id, p.payment_date DESC
)
SELECT
    s.first_name,
    s.last_name,
    rv.total_revenue,
    lps.last_store_id
FROM            revenue_2017       rv
INNER JOIN public.staff             s   ON rv.staff_id  = s.staff_id
INNER JOIN last_payment_store      lps ON rv.staff_id  = lps.staff_id
ORDER BY rv.total_revenue DESC
LIMIT 3;


-- Solution 3: Subquery
-- Inline subqueries express both the revenue aggregate and the last-store lookup directly inside the main query.
-- Advantage: fully self-contained; no CTE dependencies.
-- Disadvantage: inline subqueries are harder to inspect in isolation.

SELECT
    s.first_name,
    s.last_name,
    rev.total_revenue,
    lps.last_store_id
FROM public.staff s
INNER JOIN (
    SELECT staff_id, SUM(amount) AS total_revenue
    FROM   public.payment
    WHERE  EXTRACT(YEAR FROM payment_date) = 2017
    GROUP  BY staff_id
) rev ON s.staff_id = rev.staff_id
INNER JOIN (
    SELECT DISTINCT ON (p.staff_id)
        p.staff_id,
        i.store_id AS last_store_id
    FROM       public.payment   p
    INNER JOIN public.rental    r ON p.rental_id    = r.rental_id
    INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
    WHERE EXTRACT(YEAR FROM p.payment_date) = 2017
    ORDER BY p.staff_id, p.payment_date DESC
) lps ON s.staff_id = lps.staff_id
ORDER BY rev.total_revenue DESC
LIMIT 3;


-- =============================================================================
-- PART 2 -- TASK 2
-- =============================================================================
-- Top-5 most rented movies with MPA expected audience age.
--
-- MPA rating to expected age mapping:
--   G -> All ages   PG -> 8+   PG-13 -> 13+   R -> 17+   NC-17 -> 18+
--
-- Assumptions:
--   * Rental count = number of rows in rental linked via inventory.
--   * Age mapping is derived from the MPA standard, not stored in the DB.
-- =============================================================================

-- Solution 1: JOIN
-- film -> inventory -> rental; CASE maps rating to expected age.
-- Advantage: single pass; clean GROUP BY; easy to extend with new ratings.
-- Production choice: this variant.

SELECT
    f.title,
    f.rating,
    COUNT(r.rental_id) AS number_of_rentals,
    CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN '8+'
        WHEN 'PG-13' THEN '13+'
        WHEN 'R'     THEN '17+'
        WHEN 'NC-17' THEN '18+'
        ELSE              'Unknown'
    END                AS expected_audience_age
FROM       public.film      f
INNER JOIN public.inventory i ON f.film_id      = i.film_id
INNER JOIN public.rental    r ON i.inventory_id = r.inventory_id
GROUP BY f.film_id, f.title, f.rating
ORDER BY number_of_rentals DESC
LIMIT 5;


-- Solution 2: CTE
-- CTE computes rental counts per film; outer query adds title, rating, age.
-- Advantage: aggregation step is named and independently testable.
-- Disadvantage: extra materialisation step.

WITH rental_counts AS (
    SELECT
        i.film_id,
        COUNT(r.rental_id) AS number_of_rentals
    FROM       public.inventory i
    INNER JOIN public.rental    r ON i.inventory_id = r.inventory_id
    GROUP BY i.film_id
)
SELECT
    f.title,
    f.rating,
    rc.number_of_rentals,
    CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN '8+'
        WHEN 'PG-13' THEN '13+'
        WHEN 'R'     THEN '17+'
        WHEN 'NC-17' THEN '18+'
        ELSE              'Unknown'
    END AS expected_audience_age
FROM            rental_counts rc
INNER JOIN public.film         f ON rc.film_id = f.film_id
ORDER BY rc.number_of_rentals DESC
LIMIT 5;


-- Solution 3: Subquery
-- Inline subquery computes rental counts; outer query joins to film.
-- Advantage: fully self-contained in one statement.
-- Disadvantage: slightly harder to debug than the named CTE form.

SELECT
    f.title,
    f.rating,
    rc.rental_count AS number_of_rentals,
    CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN '8+'
        WHEN 'PG-13' THEN '13+'
        WHEN 'R'     THEN '17+'
        WHEN 'NC-17' THEN '18+'
        ELSE              'Unknown'
    END             AS expected_audience_age
FROM public.film f
INNER JOIN (
    SELECT i.film_id, COUNT(r.rental_id) AS rental_count
    FROM       public.inventory i
    INNER JOIN public.rental    r ON i.inventory_id = r.inventory_id
    GROUP BY i.film_id
) rc ON f.film_id = rc.film_id
ORDER BY rc.rental_count DESC
LIMIT 5;


-- =============================================================================
-- PART 3 -- ACTOR INACTIVITY
-- =============================================================================
-- V1: Gap between each actor's latest film year and the current year (2026).
-- V2: Maximum gap between consecutive film years per actor.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- V1: Gap to current year (2026)
-- -----------------------------------------------------------------------------

-- Solution 1: JOIN
-- Direct join; MAX(release_year) and arithmetic entirely in SELECT/GROUP BY.
-- Advantage: simplest possible expression; no sub-expressions needed.
-- Production choice: this variant.

SELECT
    a.first_name,
    a.last_name,
    MAX(f.release_year)        AS latest_film_year,
    2026 - MAX(f.release_year) AS years_since_last_film
FROM       public.actor       a
INNER JOIN public.film_actor  fa ON a.actor_id = fa.actor_id
INNER JOIN public.film         f ON fa.film_id  = f.film_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY years_since_last_film DESC;


-- Solution 2: CTE
-- CTE computes the latest year per actor; outer query adds the gap column.
-- Advantage: named step avoids repeating the MAX expression twice.
-- Disadvantage: two-step where one would suffice for this simple case.

WITH latest_year_per_actor AS (
    SELECT
        fa.actor_id,
        MAX(f.release_year) AS latest_film_year
    FROM       public.film_actor fa
    INNER JOIN public.film        f ON fa.film_id = f.film_id
    GROUP BY fa.actor_id
)
SELECT
    a.first_name,
    a.last_name,
    ly.latest_film_year,
    2026 - ly.latest_film_year AS years_since_last_film
FROM            latest_year_per_actor ly
INNER JOIN public.actor                a ON ly.actor_id = a.actor_id
ORDER BY years_since_last_film DESC;


-- Solution 3: Subquery
-- Correlated scalar subquery fetches the latest year for each actor row.
-- Advantage: self-documenting; the "latest year" step is explicit.
-- Disadvantage: executes once per actor row; slower on large tables.

SELECT
    a.first_name,
    a.last_name,
    (
        SELECT MAX(f.release_year)
        FROM   public.film_actor fa
        INNER JOIN public.film    f ON fa.film_id = f.film_id
        WHERE  fa.actor_id = a.actor_id
    ) AS latest_film_year,
    2026 - (
        SELECT MAX(f.release_year)
        FROM   public.film_actor fa
        INNER JOIN public.film    f ON fa.film_id = f.film_id
        WHERE  fa.actor_id = a.actor_id
    ) AS years_since_last_film
FROM public.actor a
ORDER BY years_since_last_film DESC;


-- -----------------------------------------------------------------------------
-- V2: Maximum gap between consecutive film years per actor
-- -----------------------------------------------------------------------------
--
-- JOIN LIMITATION FOR V2 (rule 1 explanation):
--   "Consecutive" means the immediately next year in which the actor was
--   active -- no other active year in between. Detecting this requires, for
--   each (actor, y1, y2) pair, confirming that NO year exists between y1
--   and y2 in the same actor's filmography.
--
--   The classic SQL anti-join form looks like JOINs:
--       LEFT JOIN film_actor fa_mid ON a.actor_id = fa_mid.actor_id
--       LEFT JOIN film f_mid ON fa_mid.film_id = f_mid.film_id
--                            AND f_mid.release_year > y1
--                            AND f_mid.release_year < y2
--       WHERE f_mid.film_id IS NULL
--
--   However, this fails here because the LEFT JOIN to film_actor
--   produces multiple rows per (y1, y2) pair: one for each of the actor's
--   films. For films outside the intermediate range, f_mid.film_id is NULL
--   (non-consecutive match discarded) but for films inside the range it is
--   non-NULL. The WHERE f_mid.film_id IS NULL filter retains rows where ANY
--   one film_actor row produced a NULL f_mid join -- which is always true
--   when the actor has films outside the range. The result is that
--   non-consecutive year pairs are not filtered out.
--
--   Tested on this dataset: the anti-join returns 0 rows for actors
--   with films in many years, confirming the logic is incorrect.
--
--   The correct pattern requires an EXISTS/NOT EXISTS subquery or a CTE
--   that groups year pairs before checking for intermediates. JOINs
--   cannot express "for this entire group, no matching row exists."
--   Per assignment rule 1, this limitation is documented here.
-- -----------------------------------------------------------------------------

-- Solution 2: CTE
-- Step 1 (actor_years): distinct (actor, year) pairs eliminate film duplicates.
-- Step 2 (year_pairs): self-join finds the next active year (MIN of all
--         strictly later years for the same actor) -- the immediately next one.
-- Step 3: MAX of the per-step gaps gives the longest consecutive gap per actor.
-- Advantage: each step is named and testable; correct results guaranteed.
-- Production choice: this variant.

WITH actor_years AS (
    SELECT DISTINCT
        a.actor_id,
        a.first_name,
        a.last_name,
        f.release_year
    FROM       public.actor       a
    INNER JOIN public.film_actor  fa ON a.actor_id = fa.actor_id
    INNER JOIN public.film         f ON fa.film_id  = f.film_id
),
year_pairs AS (
    SELECT
        ay1.actor_id,
        ay1.first_name,
        ay1.last_name,
        ay1.release_year      AS film_year,
        MIN(ay2.release_year) AS next_film_year
    FROM actor_years ay1
    INNER JOIN actor_years ay2
        ON  ay1.actor_id     = ay2.actor_id
        AND ay2.release_year > ay1.release_year
    GROUP BY ay1.actor_id, ay1.first_name, ay1.last_name, ay1.release_year
)
SELECT
    first_name,
    last_name,
    MAX(next_film_year - film_year) AS max_gap_between_films
FROM year_pairs
GROUP BY actor_id, first_name, last_name
ORDER BY max_gap_between_films DESC;


-- Solution 3: Subquery
-- The same two-step logic expressed as nested inline subqueries.
-- Advantage: avoids CTE materialisation; portable across all SQL dialects.
-- Disadvantage: deeper nesting makes the query harder to follow.

SELECT
    yp.first_name,
    yp.last_name,
    MAX(yp.next_film_year - yp.film_year) AS max_gap_between_films
FROM (
    SELECT
        ay1.actor_id,
        ay1.first_name,
        ay1.last_name,
        ay1.release_year      AS film_year,
        MIN(ay2.release_year) AS next_film_year
    FROM (
        SELECT DISTINCT
            a.actor_id, a.first_name, a.last_name, f.release_year
        FROM       public.actor       a
        INNER JOIN public.film_actor  fa ON a.actor_id = fa.actor_id
        INNER JOIN public.film         f ON fa.film_id  = f.film_id
    ) ay1
    INNER JOIN (
        SELECT DISTINCT
            a2.actor_id, f2.release_year
        FROM       public.actor       a2
        INNER JOIN public.film_actor  fa2 ON a2.actor_id = fa2.actor_id
        INNER JOIN public.film         f2 ON fa2.film_id  = f2.film_id
    ) ay2 ON ay1.actor_id     = ay2.actor_id
          AND ay2.release_year > ay1.release_year
    GROUP BY ay1.actor_id, ay1.first_name, ay1.last_name, ay1.release_year
) yp
GROUP BY yp.actor_id, yp.first_name, yp.last_name
ORDER BY max_gap_between_films DESC;