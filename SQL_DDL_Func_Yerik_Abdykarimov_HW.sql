-- =============================================================================
-- DVD Rental Database Assignment


CREATE SCHEMA IF NOT EXISTS core;


-- =============================================================================
-- TASK 1 – CREATE A VIEW: sales_revenue_by_category_qtr
-- =============================================================================

/*
 * View: public.sales_revenue_by_category_qtr
 *
 * PURPOSE
 * -------
 * Displays each film category together with its total payment revenue
 * for the CURRENT calendar quarter and year.  The view is fully dynamic:
 * as soon as a new quarter begins (e.g., 1 April → Q2), the quarter
 * boundary is recalculated automatically on every access because
 * CURRENT_DATE is evaluated at query time, not at view-creation time.
 *
 * HOW CURRENT QUARTER IS DETERMINED
 * -----------------------------------
 *   EXTRACT(QUARTER FROM CURRENT_DATE) returns 1, 2, 3, or 4 based on today:
 *     Q1 = Jan–Mar | Q2 = Apr–Jun | Q3 = Jul–Sep | Q4 = Oct–Dec
 *   EXTRACT(YEAR FROM CURRENT_DATE) returns the 4-digit calendar year.
 *   Both values are compared against the same extractions from payment_date,
 *   so the view automatically "rolls over" when the quarter or year changes.
 *
 * HOW ONLY CATEGORIES WITH SALES APPEAR
 * ----------------------------------------
 *   The join chain  payment → rental → inventory → film → film_category → category
 *   uses INNER JOINs throughout.  A category row only survives this chain when a
 *   payment record exists that links back to it in the current quarter.
 *   There is NO need for a HAVING clause; zero-revenue categories simply have no
 *   matching payment rows and therefore produce no output rows.
 *
 * WHY ZERO-SALES CATEGORIES ARE EXCLUDED
 *   Because every join is an INNER JOIN, categories that had no rentals paid for
 *   in the current quarter are filtered out at the join step – they never reach
 *   the GROUP BY aggregation.
 *
 * VERIFICATION NOTE
 * ------------------
 *   The unmodified dvdrental dataset contains payments dated in 2017 only.
 *   Running this view in 2025/2026 will return 0 rows because no payment falls
 *   in the current quarter/year.
 *
 *   To verify the view logic is correct, use the test queries below, which
 *   simulate a date within the dataset.
 *
 * TEST QUERIES
 * ------------
 * -- Test 1 (valid – Q1 2017, data exists):
 *   SELECT c.name AS category, SUM(p.amount) AS total_sales_revenue
 *   FROM payment p
 *   JOIN rental r        ON p.rental_id    = r.rental_id
 *   JOIN inventory i     ON r.inventory_id = i.inventory_id
 *   JOIN film f          ON i.film_id      = f.film_id
 *   JOIN film_category fc ON f.film_id     = fc.film_id
 *   JOIN category c      ON fc.category_id = c.category_id
 *   WHERE EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM DATE '2017-02-15')
 *     AND EXTRACT(YEAR   FROM p.payment_date) = EXTRACT(YEAR   FROM DATE '2017-02-15')
 *   GROUP BY c.name
 *   ORDER BY total_sales_revenue DESC;
 *   -- Expected: ~16 categories each with a non-zero revenue figure.
 *
 * -- Test 2 (data that should NOT appear – different quarter):
 *   A category whose last payment was in Q3 2017 will NOT appear when
 *   the view is queried in Q1 2017.  Example: execute the view-simulation
 *   query above for DATE '2017-09-15' and compare – Sports, for instance,
 *   generates revenue in Q2 but a zero-contribution category in Q1 will
 *   be absent from the Q1 result set entirely.
 *
 * -- Test 3 (current date – expected 0 rows):
 *   SELECT * FROM public.sales_revenue_by_category_qtr;
 *   -- Returns 0 rows: no 2026 payment data exists in this dataset.
 */
CREATE OR REPLACE VIEW public.sales_revenue_by_category_qtr AS
SELECT
    c.name        AS category,
    SUM(p.amount) AS total_sales_revenue
FROM       payment        p
JOIN       rental         r   ON p.rental_id      = r.rental_id
JOIN       inventory      i   ON r.inventory_id   = i.inventory_id
JOIN       film           f   ON i.film_id        = f.film_id
JOIN       film_category  fc  ON f.film_id        = fc.film_id
JOIN       category       c   ON fc.category_id   = c.category_id
WHERE  EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
  AND  EXTRACT(YEAR   FROM p.payment_date) = EXTRACT(YEAR   FROM CURRENT_DATE)
GROUP BY c.name
ORDER BY total_sales_revenue DESC;


-- =============================================================================
-- TASK 2 – QUERY LANGUAGE FUNCTION: get_sales_revenue_by_category_qtr
-- =============================================================================

/*
 * Function: public.get_sales_revenue_by_category_qtr(p_date DATE)
 *
 * PURPOSE
 * -------
 * Returns the same per-category revenue breakdown as the view
 * sales_revenue_by_category_qtr but for any quarter/year specified by
 * the caller via a single DATE parameter.
 *
 * WHY A PARAMETER IS NEEDED
 * --------------------------
 *   The view is pinned to CURRENT_DATE, making ad-hoc historical analysis
 *   impossible without altering the view.  This function accepts a DATE from
 *   which it derives both the quarter number and the year, letting the caller
 *   query any past or future quarter without touching the view definition.
 *   Using one DATE (rather than two separate INT parameters for quarter + year)
 *   prevents logically impossible combinations such as quarter = 5 or year = 0.
 *
 * PARAMETER
 *   p_date DATE  – Any date falling within the desired quarter/year.
 *                  Defaults to CURRENT_DATE so calling with no argument
 *                  mirrors the view exactly.
 *
 * WHAT HAPPENS IF INVALID QUARTER IS PASSED
 *   Because the parameter is typed as DATE, PostgreSQL validates it before the
 *   function body runs.  An impossible date such as '2017-13-01' raises
 *   "date/time field value out of range" automatically.
 *   A valid date whose quarter/year has no payment data simply returns 0 rows –
 *   this is expected, not an error.
 *
 * WHAT HAPPENS IF NO DATA EXISTS
 *   0 rows are returned.  The function does not raise an exception in this case
 *   because an empty result set is a valid answer (no sales occurred).
 *
 * WHAT HAPPENS IF NULL IS PASSED
 *   EXTRACT on a NULL date returns NULL; the WHERE predicates collapse to
 *   NULL = NULL (false), so 0 rows are returned.
 *
 * TEST QUERIES
 * ------------
 * -- Test 1 (valid – Q1 2017, data exists):
 *   SELECT * FROM public.get_sales_revenue_by_category_qtr('2017-02-15');
 *   -- Expected: ~16 category rows with non-zero revenue.
 *
 * -- Test 2 (edge – current date, no 2026 data):
 *   SELECT * FROM public.get_sales_revenue_by_category_qtr();
 *   -- Expected: 0 rows (no payment data for today's quarter).
 *
 * -- Test 3 (edge – NULL input):
 *   SELECT * FROM public.get_sales_revenue_by_category_qtr(NULL);
 *   -- Expected: 0 rows (NULL comparisons are false, no rows pass the filter).
 */
CREATE OR REPLACE FUNCTION public.get_sales_revenue_by_category_qtr(
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (category TEXT, total_sales_revenue NUMERIC)
LANGUAGE sql
AS $$
    SELECT
        c.name        AS category,
        SUM(p.amount) AS total_sales_revenue
    FROM       payment        p
    JOIN       rental         r   ON p.rental_id      = r.rental_id
    JOIN       inventory      i   ON r.inventory_id   = i.inventory_id
    JOIN       film           f   ON i.film_id        = f.film_id
    JOIN       film_category  fc  ON f.film_id        = fc.film_id
    JOIN       category       c   ON fc.category_id   = c.category_id
    WHERE  EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM p_date)
      AND  EXTRACT(YEAR   FROM p.payment_date) = EXTRACT(YEAR   FROM p_date)
    GROUP BY c.name
    ORDER BY total_sales_revenue DESC;
$$;


-- =============================================================================
-- TASK 3 – PROCEDURE LANGUAGE FUNCTION: core.most_popular_films_by_countries
-- =============================================================================

/*
 * Function: core.most_popular_films_by_countries(p_countries TEXT[])
 *
 * PURPOSE
 * -------
 * For each country supplied in the input array, returns the single most popular
 * film rented by customers who live in that country.
 *
 * HOW 'MOST POPULAR' IS DEFINED
 * --------------------------------
 *   Popularity = total number of rental transactions linked to customers whose
 *   address resolves to that country (via customer → address → city → country).
 *   Revenue and recency are NOT considered; rental count is the fairest and most
 *   intuitive measure of consumer demand.
 *
 * HOW TIES ARE HANDLED
 *   If two films share the identical rental count for a country, the one with
 *   the lower film_id (inserted earlier into the database) is returned.
 *   This is deterministic and avoids arbitrary ordering.
 *   DISTINCT ON (co.country) picks the first row in the ORDER BY sequence:
 *     country ASC, rental_count DESC, film_id ASC.
 *
 * WHAT HAPPENS IF A COUNTRY HAS NO DATA
 *   That country is simply absent from the result set.  Returning NULL-filled
 *   rows for non-existent countries would be misleading; an empty row is cleaner.
 *   If the country name doesn't exist in the country table at all (e.g., a typo),
 *   no row is returned for it either.
 *
 * WHAT HAPPENS IF THE ARRAY IS NULL OR EMPTY
 *   The function returns immediately (0 rows).
 *
 * TEST QUERIES
 * ------------
 * -- Test 1 (valid – known countries with data):
 *   SELECT * FROM core.most_popular_films_by_countries(
 *       ARRAY['Afghanistan', 'Brazil', 'United States']
 *   );
 *   -- Expected: up to 3 rows, one per country, showing the top-rented film.
 *
 * -- Test 2 (edge – country not in database):
 *   SELECT * FROM core.most_popular_films_by_countries(ARRAY['Antarctica']);
 *   -- Expected: 0 rows (no customer data for Antarctica).
 *
 * -- Test 3 (edge – NULL array):
 *   SELECT * FROM core.most_popular_films_by_countries(NULL);
 *   -- Expected: 0 rows (early return guard).
 *
 * -- Test 4 (edge – empty array):
 *   SELECT * FROM core.most_popular_films_by_countries(ARRAY[]::TEXT[]);
 *   -- Expected: 0 rows (array_length returns NULL for an empty array).
 */
CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(
    p_countries TEXT[]
)
RETURNS TABLE (
    country      TEXT,
    film         TEXT,
    rating       TEXT,
    language     TEXT,
    length       SMALLINT,
    release_year INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Guard: return nothing for NULL or empty arrays
    IF p_countries IS NULL OR array_length(p_countries, 1) IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    WITH rental_counts AS (
        -- Aggregate rental count per (country, film) combination.
        -- We also carry through film_id for deterministic tie-breaking.
        SELECT
            co.country                      AS country,
            f.film_id                       AS film_id,
            f.title                         AS title,
            f.rating::TEXT                  AS rating,
            TRIM(l.name)                    AS language,
            f.length                        AS length,
            f.release_year::INT             AS release_year,
            COUNT(r.rental_id)              AS rental_count
        FROM       rental         r
        JOIN       inventory      i   ON r.inventory_id   = i.inventory_id
        JOIN       film           f   ON i.film_id        = f.film_id
        JOIN       language       l   ON f.language_id    = l.language_id
        JOIN       customer       cu  ON r.customer_id    = cu.customer_id
        JOIN       address        a   ON cu.address_id    = a.address_id
        JOIN       city           ci  ON a.city_id        = ci.city_id
        JOIN       country        co  ON ci.country_id    = co.country_id
        WHERE  co.country ILIKE ANY (SELECT unnest(p_countries))
        GROUP BY co.country, f.film_id, f.title, f.rating, l.name, f.length, f.release_year
    )
    -- DISTINCT ON picks one row per country – the first after ordering by
    -- rental_count DESC (highest wins) then film_id ASC (tie-break).
    SELECT DISTINCT ON (rc.country)
        rc.country,
        rc.title        AS film,
        rc.rating,
        rc.language,
        rc.length,
        rc.release_year
    FROM rental_counts rc
    ORDER BY rc.country, rc.rental_count DESC, rc.film_id ASC;

END;
$$;


-- =============================================================================
-- TASK 4 – PROCEDURE LANGUAGE FUNCTION: core.films_in_stock_by_title
-- =============================================================================

/*
 * Function: core.films_in_stock_by_title(p_title TEXT)
 *
 * PURPOSE
 * -------
 * Returns a numbered list of rental records for every film whose title matches
 * the supplied LIKE pattern, together with the customer who rented each copy
 * and when.  This gives front-desk staff a quick view of which customers
 * currently hold (or have recently held) copies of a film.
 *
 * HOW PATTERN MATCHING WORKS (LIKE / %)
 *   The parameter is passed directly to an ILIKE predicate:
 *     f.title ILIKE p_title
 *   The caller controls the wildcards:
 *     '%love%'  → any title containing "love" (case-insensitive)
 *     'love%'   → titles that START with "love"
 *     '%love'   → titles that END with "love"
 *   ILIKE is used (rather than LIKE) so the search is case-insensitive.
 *
 * CASE SENSITIVITY
 *   ILIKE makes the match case-insensitive: '%Love%', '%LOVE%', and '%love%'
 *   all produce identical results.
 *
 * PERFORMANCE CONSIDERATIONS
 *   A leading wildcard ('%love%') prevents index use on the title column and
 *   forces a full sequential scan of the film table.  For large datasets this
 *   can be slow.  Mitigation options:
 *     1. Use a pg_trgm GIN index on film.title (supports ILIKE with any wildcard).
 *     2. Restrict to trailing-wildcard patterns ('love%') which CAN use a B-tree index.
 *   In the dvdrental dataset (~1 000 films) the sequential scan is negligible.
 *   The join to rental (≈16 000 rows) and inventory is also small, so no
 *   additional optimisation is needed here.
 *
 * ROW_NUM FIELD
 *   Generated with ROW_NUMBER() OVER (ORDER BY f.title, r.rental_date).
 *   Starts at 1 for each function call and increments by 1 per row.
 *   The window ordering means rows are sorted first by film title
 *   alphabetically, then chronologically by rental date within each title.
 *
 * WHAT HAPPENS IF MULTIPLE MATCHES EXIST
 *   All matching rentals are returned, one row per rental event.
 *   row_num continues to increment across all titles.
 *
 * WHAT HAPPENS IF NO MATCHES EXIST
 *   If no film title in the database matches the pattern, a RAISE EXCEPTION
 *   is raised with a descriptive message, because returning 0 rows silently
 *   could be confused with "the film exists but has no rentals".
 *
 * TEST QUERIES
 * ------------
 * -- Test 1 (valid – '%love%', expected multiple rows):
 *   SELECT * FROM core.films_in_stock_by_title('%love%');
 *
 * -- Test 2 (valid – exact title with wildcards):
 *   SELECT * FROM core.films_in_stock_by_title('%academy%');
 *
 * -- Test 3 (edge – no match, raises exception):
 *   SELECT * FROM core.films_in_stock_by_title('%zzznomatch999%');
 *   -- Expected: ERROR: Film matching "%zzznomatch999%" was not found.
 *
 * -- Test 4 (edge – no rentals for an existing film):
 *   (hypothetical) A film that exists in the film table but has no rental rows
 *   will pass the existence check and return 0 rows from the RETURN QUERY.
 *   This correctly reflects "film is in catalog but has never been rented".
 */
CREATE OR REPLACE FUNCTION core.films_in_stock_by_title(
    p_title TEXT
)
RETURNS TABLE (
    row_num       BIGINT,
    film_title    TEXT,
    language      TEXT,
    customer_name TEXT,
    rental_date   TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_film_count INT;
BEGIN
    -- Validate that at least one film matches the pattern
    SELECT COUNT(*)
    INTO   v_film_count
    FROM   film f
    WHERE  f.title ILIKE p_title;

    IF v_film_count = 0 THEN
        RAISE EXCEPTION
            'Film matching "%" was not found in the database. '
            'Check spelling or wildcard placement (e.g., ''%%love%%'').',
            p_title;
    END IF;

    -- Return all rental records for matching films.
    -- row_num is a sequential counter ordered by title then rental date.
    RETURN QUERY
    SELECT
        ROW_NUMBER() OVER (ORDER BY f.title, r.rental_date)::BIGINT
                                              AS row_num,
        f.title                               AS film_title,
        TRIM(l.name)                          AS language,
        cu.first_name || ' ' || cu.last_name  AS customer_name,
        r.rental_date                         AS rental_date
    FROM       rental     r
    JOIN       inventory  i   ON r.inventory_id = i.inventory_id
    JOIN       film       f   ON i.film_id      = f.film_id
    JOIN       language   l   ON f.language_id  = l.language_id
    JOIN       customer   cu  ON r.customer_id  = cu.customer_id
    WHERE  f.title ILIKE p_title
    ORDER BY f.title, r.rental_date;

END;
$$;


-- =============================================================================
-- TASK 5 – PROCEDURE LANGUAGE FUNCTION: public.new_movie
-- =============================================================================

/*
 * Function: public.new_movie(p_title, p_release_year, p_language)
 *
 * PURPOSE
 * -------
 * Inserts a new film into the film table with standardised default values
 * and returns the auto-generated film_id.
 *
 * HOW UNIQUE FILM_ID IS GENERATED
 *   The INSERT statement omits film_id and relies on the column's DEFAULT
 *   (nextval('public.film_film_id_seq')).  PostgreSQL advances the sequence
 *   atomically, guaranteeing uniqueness even under concurrent inserts.
 *   The generated ID is captured via RETURNING film_id INTO v_film_id.
 *   We do NOT use MAX(film_id)+1 because that is non-atomic and fails under
 *   concurrent load.
 *
 * HOW DUPLICATES ARE PREVENTED
 *   Before inserting, an EXISTS check tests whether a row with the same title
 *   (case-sensitive exact match) already exists in the film table.
 *   If it does, RAISE EXCEPTION aborts the function immediately.
 *   This is a business-rule guard; the film table also has no UNIQUE constraint
 *   on title in the original schema, so the function provides that protection.
 *
 * WHAT HAPPENS IF MOVIE ALREADY EXISTS
 *   RAISE EXCEPTION 'A film with the title "..." already exists.' is raised.
 *   The transaction is rolled back (no partial insert occurs).
 *
 * HOW LANGUAGE EXISTENCE IS VALIDATED
 *   The function performs a SELECT on the language table using ILIKE so that
 *   'klingon', 'Klingon', and 'KLINGON' all resolve correctly.
 *   If no matching language is found, RAISE EXCEPTION fires before the INSERT.
 *
 * WHAT HAPPENS IF INSERTION FAILS
 *   Any unhandled error (e.g., NOT NULL violation, check constraint) propagates
 *   as a PostgreSQL exception and rolls back the transaction automatically,
 *   preserving data consistency.
 *
 * HOW CONSISTENCY IS PRESERVED
 *   - Language ID is looked up from the language table (no hard-coding).
 *   - fulltext (tsvector) is populated via to_tsvector(p_title) so the
 *     full-text search index remains usable after the insert.
 *   - rental_rate, rental_duration, and replacement_cost use the defaults
 *     specified in the assignment (4.99, 3 days, 19.99).
 *
 * PARAMETERS
 *   p_title        TEXT  – Required. Movie title. Must be unique.
 *   p_release_year INT   – Optional. Defaults to the current calendar year.
 *   p_language     TEXT  – Optional. Defaults to 'Klingon'.
 *
 * RETURNS
 *   INT – the newly generated film_id.
 *
 * TEST QUERIES
 * ------------
 * -- Test 1 (valid – new film with defaults):
 *   SELECT public.new_movie('Quantum Horizon');
 *   -- Expected: returns a new film_id (e.g., 1001).
 *   SELECT film_id, title, release_year, language_id, rental_rate
 *   FROM film WHERE title = 'Quantum Horizon';
 *
 * -- Test 2 (valid – all parameters specified):
 *   SELECT public.new_movie('Desert Storm Chronicles', 2019, 'English');
 *   -- Expected: returns a new film_id; language_id points to English.
 *
 * -- Test 3 (edge – duplicate title):
 *   SELECT public.new_movie('Quantum Horizon');  -- run twice
 *   -- Expected: ERROR: A film with the title "Quantum Horizon" already exists.
 *
 * -- Test 4 (edge – invalid language):
 *   SELECT public.new_movie('Ghost Frequency', 2024, 'Elvish');
 *   -- Expected: ERROR: Language "Elvish" does not exist in the language table.
 */
CREATE OR REPLACE FUNCTION public.new_movie(
    p_title        TEXT,
    p_release_year INT  DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    p_language     TEXT DEFAULT 'Klingon'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_language_id INT;
    v_film_id     INT;
BEGIN
    -- 1. Guard against duplicate titles (exact case-sensitive match)
    IF EXISTS (SELECT 1 FROM film WHERE title = p_title) THEN
        RAISE EXCEPTION
            'A film with the title "%" already exists. Duplicate titles are not permitted.',
            p_title;
    END IF;

    -- 2. Validate that the requested language exists in the language table
    SELECT language_id
    INTO   v_language_id
    FROM   language
    WHERE  TRIM(name) ILIKE p_language
    LIMIT  1;

    IF v_language_id IS NULL THEN
        RAISE EXCEPTION
            'Language "%" does not exist in the language table. '
            'Add the language first or choose an existing one.',
            p_language;
    END IF;

    -- 3. Insert the new film and capture the auto-generated film_id
    INSERT INTO film (
        title,
        release_year,
        language_id,
        rental_rate,
        rental_duration,
        replacement_cost,
        fulltext
    )
    VALUES (
        p_title,
        p_release_year,
        v_language_id,
        4.99,               -- default rental rate per assignment spec
        3,                  -- default rental duration (days) per assignment spec
        19.99,              -- default replacement cost per assignment spec
        to_tsvector(p_title) -- populate tsvector for full-text search
    )
    RETURNING film_id INTO v_film_id;

    RETURN v_film_id;
END;
$$;


-- =============================================================================
-- END OF SCRIPT
-- =============================================================================