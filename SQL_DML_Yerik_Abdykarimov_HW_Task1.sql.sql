-- =
-- DVD Rental Database — DML & TCL Assignment
-- Author  : Erik Abdykarimov
-- Movies  : 1) Hacksaw Ridge (2016, Drama,  rate=4.99,  duration=7  days)
--           2) Inception     (2010, Action,  rate=9.99,  duration=14 days)
--           3) Interstellar  (2014, Sci-Fi,  rate=19.99, duration=21 days)
-- =


-- =
--                                TASK   1
-- =


-- =
-- SUBTASK 1 — INSERT 3 FAVORITE FILMS INTO public.film
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   All three film inserts form one logical unit. If any single INSERT fails
 *   (e.g., a FK violation on language_id), PostgreSQL rolls back the entire
 *   transaction, preventing a partial, inconsistent state.
 *
 * WHAT HAPPENS IF THE TRANSACTION FAILS:
 *   An automatic rollback removes every change made since BEGIN, leaving
 *   the film table exactly as it was before.
 *
 * ROLLBACK POSSIBILITY & AFFECTED DATA:
 *   Full rollback is possible at any point before COMMIT.
 *   Only the three film rows attempted in this transaction are affected.
 *
 * REFERENTIAL INTEGRITY:
 *   language_id is looked up via a subquery on public.language instead of
 *   being hardcoded. This guarantees a valid FK value on every DB instance.
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   WHERE NOT EXISTS checks for an existing row with the same title AND
 *   release_year before inserting. Re-running the script is therefore safe.
 *
 * ADVANTAGE OF INSERT INTO … SELECT OVER INSERT INTO … VALUES:
 *   INSERT INTO … SELECT resolves FK values (language_id, etc.) dynamically
 *   at runtime. Hardcoding IDs would break portability — the same language_id
 *   may differ across DB installations. SELECT-based inserts always resolve
 *   the correct, live ID regardless of environment.
 */

BEGIN;

--      1a. Hacksaw Ridge (2016) — Drama | rate 4.99 | duration 7 days (1 week)
INSERT INTO public.film
    (title, description, release_year, language_id,
     rental_duration, rental_rate, length, replacement_cost,
     rating, last_update, special_features)
SELECT
    'Hacksaw Ridge',
    'The true story of Desmond T. Doss, the first conscientious objector to receive '
    'the Medal of Honor. During WWII he saved 75 men at the Battle of Okinawa '
    'without ever firing a single shot.',
    2016,
    (SELECT language_id FROM public.language WHERE name = 'English'),
    7,
    4.99,
    139,
    24.99,
    'R',
    CURRENT_DATE,
    ARRAY['Trailers', 'Deleted Scenes']
WHERE NOT EXISTS (
    SELECT 1 FROM public.film
    WHERE  UPPER(title) = UPPER('Hacksaw Ridge')
    AND    release_year = 2016
)
RETURNING film_id, title, release_year, rental_rate, rental_duration;

--       1b. Inception (2010) — Action | rate 9.99 | duration 14 days (2 weeks)
INSERT INTO public.film
    (title, description, release_year, language_id,
     rental_duration, rental_rate, length, replacement_cost,
     rating, last_update, special_features)
SELECT
    'Inception',
    'A thief who steals corporate secrets through dream-sharing technology is given '
    'the inverse task of planting an idea into the mind of a CEO in exchange for '
    'having his criminal record erased.',
    2010,
    (SELECT language_id FROM public.language WHERE name = 'English'),
    14,
    9.99,
    148,
    29.99,
    'PG-13',
    CURRENT_DATE,
    ARRAY['Trailers', 'Behind the Scenes']
WHERE NOT EXISTS (
    SELECT 1 FROM public.film
    WHERE  UPPER(title) = UPPER('Inception')
    AND    release_year = 2010
)
RETURNING film_id, title, release_year, rental_rate, rental_duration;

--      1c. Interstellar (2014) — Sci-Fi | rate 19.99 | duration 21 days (3 wks)
INSERT INTO public.film
    (title, description, release_year, language_id,
     rental_duration, rental_rate, length, replacement_cost,
     rating, last_update, special_features)
SELECT
    'Interstellar',
    'A team of explorers travel through a wormhole near Saturn in search of a new '
    'habitable planet that can secure the survival of a dying humanity.',
    2014,
    (SELECT language_id FROM public.language WHERE name = 'English'),
    21,
    19.99,
    169,
    34.99,
    'PG-13',
    CURRENT_DATE,
    ARRAY['Trailers', 'Behind the Scenes', 'Deleted Scenes']
WHERE NOT EXISTS (
    SELECT 1 FROM public.film
    WHERE  UPPER(title) = UPPER('Interstellar')
    AND    release_year = 2014
)
RETURNING film_id, title, release_year, rental_rate, rental_duration;

-- Verify all 3 films were inserted correctly
SELECT film_id, title, release_year, rental_rate, rental_duration, rating
FROM   public.film
WHERE  UPPER(title) IN ('HACKSAW RIDGE', 'INCEPTION', 'INTERSTELLAR');

COMMIT;


-- =
-- SUBTASK 1b — LINK FILMS TO CATEGORIES (public.film_category)
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   Film-category links depend on the film rows committed in the previous
 *   transaction. Keeping this separate ensures clean isolation.
 *
 * REFERENTIAL INTEGRITY:
 *   Both film_id and category_id are resolved via subqueries on their
 *   respective parent tables — no hardcoded IDs.
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   NOT EXISTS on (film_id, category_id) prevents duplicate category links.
 */

BEGIN;

-- Hacksaw Ridge → Drama
INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT f.film_id, c.category_id, CURRENT_DATE
FROM   public.film f
CROSS  JOIN public.category c
WHERE  UPPER(f.title) = UPPER('Hacksaw Ridge') AND f.release_year = 2016
AND    c.name = 'Drama'
AND    NOT EXISTS (
           SELECT 1 FROM public.film_category fc
           WHERE  fc.film_id = f.film_id AND fc.category_id = c.category_id
       )
RETURNING film_id, category_id, last_update;

-- Inception → Action
INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT f.film_id, c.category_id, CURRENT_DATE
FROM   public.film f
CROSS  JOIN public.category c
WHERE  UPPER(f.title) = UPPER('Inception') AND f.release_year = 2010
AND    c.name = 'Action'
AND    NOT EXISTS (
           SELECT 1 FROM public.film_category fc
           WHERE  fc.film_id = f.film_id AND fc.category_id = c.category_id
       )
RETURNING film_id, category_id, last_update;

-- Interstellar → Sci-Fi
INSERT INTO public.film_category (film_id, category_id, last_update)
SELECT f.film_id, c.category_id, CURRENT_DATE
FROM   public.film f
CROSS  JOIN public.category c
WHERE  UPPER(f.title) = UPPER('Interstellar') AND f.release_year = 2014
AND    c.name = 'Sci-Fi'
AND    NOT EXISTS (
           SELECT 1 FROM public.film_category fc
           WHERE  fc.film_id = f.film_id AND fc.category_id = c.category_id
       )
RETURNING film_id, category_id, last_update;

-- Verify
SELECT f.title, c.name AS category
FROM   public.film_category fc
JOIN   public.film     f ON f.film_id     = fc.film_id
JOIN   public.category c ON c.category_id = fc.category_id
WHERE  UPPER(f.title) IN ('HACKSAW RIDGE', 'INCEPTION', 'INTERSTELLAR');

COMMIT;


-- =
-- SUBTASK 2 — INSERT ACTORS INTO public.actor (15 real leading actors)
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   Actor rows must exist before film_actor links are created. Isolating
 *   them in their own transaction ensures clean rollback if any actor fails.
 *
 * WHAT HAPPENS IF THE TRANSACTION FAILS:
 *   All actor inserts within this transaction are rolled back automatically.
 *
 * ROLLBACK POSSIBILITY & AFFECTED DATA:
 *   Full rollback before COMMIT — only actor rows in this transaction.
 *
 * REFERENTIAL INTEGRITY:
 *   actor_id values are auto-generated by the sequence. They are referenced
 *   in film_actor via subqueries, never hardcoded.
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   WHERE NOT EXISTS checks first_name + last_name (case-insensitive) before
 *   inserting. This safely handles actors that may already exist in the DB.
 *   Actor names are stored in UPPERCASE to match the dvdrental convention.
 *
 * FILMS AND THEIR LEADING ACTORS (15 total, well above the required 6):
 *   Hacksaw Ridge : Andrew Garfield, Sam Worthington, Teresa Palmer,
 *                   Hugo Weaving, Vince Vaughn
 *   Inception     : Leonardo DiCaprio, Joseph Gordon-Levitt, Tom Hardy,
 *                   Ken Watanabe, Cillian Murphy
 *   Interstellar  : Matthew McConaughey, Anne Hathaway, Jessica Chastain,
 *                   Michael Caine, Matt Damon
 */

BEGIN;

--   = Hacksaw Ridge actors =

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'ANDREW', 'GARFIELD', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'ANDREW' AND UPPER(last_name) = 'GARFIELD'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'SAM', 'WORTHINGTON', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'SAM' AND UPPER(last_name) = 'WORTHINGTON'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'TERESA', 'PALMER', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'TERESA' AND UPPER(last_name) = 'PALMER'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'HUGO', 'WEAVING', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'HUGO' AND UPPER(last_name) = 'WEAVING'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'VINCE', 'VAUGHN', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'VINCE' AND UPPER(last_name) = 'VAUGHN'
)
RETURNING actor_id, first_name, last_name;

--  = Inception actors =

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'LEONARDO', 'DICAPRIO', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'LEONARDO' AND UPPER(last_name) = 'DICAPRIO'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'JOSEPH', 'GORDON-LEVITT', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'JOSEPH' AND UPPER(last_name) = 'GORDON-LEVITT'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'TOM', 'HARDY', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'TOM' AND UPPER(last_name) = 'HARDY'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'KEN', 'WATANABE', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'KEN' AND UPPER(last_name) = 'WATANABE'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'CILLIAN', 'MURPHY', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'CILLIAN' AND UPPER(last_name) = 'MURPHY'
)
RETURNING actor_id, first_name, last_name;

--       = Interstellar actors =

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'MATTHEW', 'MCCONAUGHEY', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'MATTHEW' AND UPPER(last_name) = 'MCCONAUGHEY'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'ANNE', 'HATHAWAY', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'ANNE' AND UPPER(last_name) = 'HATHAWAY'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'JESSICA', 'CHASTAIN', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'JESSICA' AND UPPER(last_name) = 'CHASTAIN'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'MICHAEL', 'CAINE', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'MICHAEL' AND UPPER(last_name) = 'CAINE'
)
RETURNING actor_id, first_name, last_name;

INSERT INTO public.actor (first_name, last_name, last_update)
SELECT 'MATT', 'DAMON', CURRENT_DATE
WHERE  NOT EXISTS (
    SELECT 1 FROM public.actor
    WHERE  UPPER(first_name) = 'MATT' AND UPPER(last_name) = 'DAMON'
)
RETURNING actor_id, first_name, last_name;

-- Verify all 15 actors exist
SELECT actor_id, first_name, last_name
FROM   public.actor
WHERE  (UPPER(first_name), UPPER(last_name)) IN (
    ('ANDREW','GARFIELD'),   ('SAM','WORTHINGTON'),    ('TERESA','PALMER'),
    ('HUGO','WEAVING'),      ('VINCE','VAUGHN'),
    ('LEONARDO','DICAPRIO'), ('JOSEPH','GORDON-LEVITT'),('TOM','HARDY'),
    ('KEN','WATANABE'),      ('CILLIAN','MURPHY'),
    ('MATTHEW','MCCONAUGHEY'),('ANNE','HATHAWAY'),      ('JESSICA','CHASTAIN'),
    ('MICHAEL','CAINE'),     ('MATT','DAMON')
)
ORDER  BY last_name;

COMMIT;


-- =
-- SUBTASK 2b — LINK ACTORS TO FILMS (public.film_actor)
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   film_actor depends on both actor and film rows already being committed.
 *   Using a separate transaction ensures those parent rows exist before we
 *   attempt to create the links.
 *
 * ROLLBACK POSSIBILITY:
 *   Full rollback before COMMIT — only film_actor rows in this transaction.
 *
 * REFERENTIAL INTEGRITY:
 *   Both actor_id and film_id are resolved via subqueries, not hardcoded.
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   NOT EXISTS on the composite PK (actor_id, film_id) prevents duplicate links.
 */

BEGIN;

--          = Hacksaw Ridge actors =

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='ANDREW'  AND UPPER(a.last_name)='GARFIELD'
AND    UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='SAM' AND UPPER(a.last_name)='WORTHINGTON'
AND    UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='TERESA' AND UPPER(a.last_name)='PALMER'
AND    UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='HUGO' AND UPPER(a.last_name)='WEAVING'
AND    UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='VINCE' AND UPPER(a.last_name)='VAUGHN'
AND    UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

--          = Inception actors =

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='LEONARDO' AND UPPER(a.last_name)='DICAPRIO'
AND    UPPER(f.title)='INCEPTION' AND f.release_year=2010
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='JOSEPH' AND UPPER(a.last_name)='GORDON-LEVITT'
AND    UPPER(f.title)='INCEPTION' AND f.release_year=2010
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='TOM' AND UPPER(a.last_name)='HARDY'
AND    UPPER(f.title)='INCEPTION' AND f.release_year=2010
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='KEN' AND UPPER(a.last_name)='WATANABE'
AND    UPPER(f.title)='INCEPTION' AND f.release_year=2010
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='CILLIAN' AND UPPER(a.last_name)='MURPHY'
AND    UPPER(f.title)='INCEPTION' AND f.release_year=2010
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

--       = Interstellar actors =

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='MATTHEW' AND UPPER(a.last_name)='MCCONAUGHEY'
AND    UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='ANNE' AND UPPER(a.last_name)='HATHAWAY'
AND    UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='JESSICA' AND UPPER(a.last_name)='CHASTAIN'
AND    UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='MICHAEL' AND UPPER(a.last_name)='CAINE'
AND    UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM   public.actor a, public.film f
WHERE  UPPER(a.first_name)='MATT' AND UPPER(a.last_name)='DAMON'
AND    UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
AND    NOT EXISTS (SELECT 1 FROM public.film_actor fa WHERE fa.actor_id=a.actor_id AND fa.film_id=f.film_id)
RETURNING actor_id, film_id;

-- Verify all 15 actor–film links
SELECT f.title, a.first_name || ' ' || a.last_name AS actor
FROM   public.film_actor fa
JOIN   public.film  f ON f.film_id  = fa.film_id
JOIN   public.actor a ON a.actor_id = fa.actor_id
WHERE  UPPER(f.title) IN ('HACKSAW RIDGE', 'INCEPTION', 'INTERSTELLAR')
ORDER  BY f.title, a.last_name;

COMMIT;


-- =
-- SUBTASK 3 — ADD FILMS TO STORE INVENTORY (public.inventory)
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   Inventory inserts are logically independent of actor/film inserts and
 *   required before rentals can reference them. Isolation keeps rollback
 *   boundaries clear.
 *
 * ROLLBACK POSSIBILITY:
 *   Full rollback before COMMIT — only the three inventory rows.
 *
 * REFERENTIAL INTEGRITY:
 *   film_id is resolved via subquery; store_id = 1 is a valid existing store.
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   NOT EXISTS checks (film_id, store_id) so re-running the script does not
 *   create duplicate inventory rows.
 */

BEGIN;

-- Add Hacksaw Ridge to Store 1
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id, 1, CURRENT_DATE
FROM   public.film f
WHERE  UPPER(f.title) = UPPER('Hacksaw Ridge') AND f.release_year = 2016
AND    NOT EXISTS (
    SELECT 1 FROM public.inventory i
    WHERE  i.film_id = f.film_id AND i.store_id = 1
)
RETURNING inventory_id, film_id, store_id;

-- Add Inception to Store 1
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id, 1, CURRENT_DATE
FROM   public.film f
WHERE  UPPER(f.title) = UPPER('Inception') AND f.release_year = 2010
AND    NOT EXISTS (
    SELECT 1 FROM public.inventory i
    WHERE  i.film_id = f.film_id AND i.store_id = 1
)
RETURNING inventory_id, film_id, store_id;

-- Add Interstellar to Store 1
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id, 1, CURRENT_DATE
FROM   public.film f
WHERE  UPPER(f.title) = UPPER('Interstellar') AND f.release_year = 2014
AND    NOT EXISTS (
    SELECT 1 FROM public.inventory i
    WHERE  i.film_id = f.film_id AND i.store_id = 1
)
RETURNING inventory_id, film_id, store_id;

-- Verify
SELECT i.inventory_id, f.title, i.store_id
FROM   public.inventory i
JOIN   public.film f ON f.film_id = i.film_id
WHERE  UPPER(f.title) IN ('HACKSAW RIDGE', 'INCEPTION', 'INTERSTELLAR');

COMMIT;


-- =
-- SUBTASK 4 — UPDATE CUSTOMER RECORD TO MY PERSONAL DATA
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   The UPDATE touches a single, identified customer row. A separate
 *   transaction lets us verify the target with a SELECT first, and roll
 *   back the change cleanly if anything is wrong.
 *
 * WHAT HAPPENS IF THE TRANSACTION FAILS:
 *   The original customer row is fully restored on rollback.
 *
 * REFERENTIAL INTEGRITY:
 *   store_id = 1 references an existing store. address_id is kept unchanged
 *   (we cannot modify the address table per the task rules).
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   UPDATE targets exactly one customer_id resolved by a LIMIT 1 subquery
 *   on a customer meeting the ≥43 rental / ≥43 payment threshold.
 */

-- Double-check: preview the target customer BEFORE committing
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       c.email,
       COUNT(DISTINCT r.rental_id)  AS total_rentals,
       COUNT(DISTINCT p.payment_id) AS total_payments
FROM   public.customer c
JOIN   public.rental  r ON r.customer_id = c.customer_id
JOIN   public.payment p ON p.customer_id = c.customer_id
GROUP  BY c.customer_id, c.first_name, c.last_name, c.email
HAVING COUNT(DISTINCT r.rental_id)  >= 43
AND    COUNT(DISTINCT p.payment_id) >= 43
ORDER  BY total_rentals DESC
LIMIT  5;

BEGIN;

UPDATE public.customer
SET    first_name  = 'Erik',
       last_name   = 'Abdykarimov',
       email       = 'erik.abdykarimov@sakilacustomer.org',
       store_id    = 1,
       activebool  = TRUE,
       active      = 1,
       last_update = CURRENT_DATE
WHERE  customer_id = (
    SELECT c.customer_id
    FROM   public.customer c
    JOIN   public.rental  r ON r.customer_id = c.customer_id
    JOIN   public.payment p ON p.customer_id = c.customer_id
    GROUP  BY c.customer_id
    HAVING COUNT(DISTINCT r.rental_id)  >= 43
    AND    COUNT(DISTINCT p.payment_id) >= 43
    ORDER  BY COUNT(DISTINCT r.rental_id) DESC
    LIMIT  1
)
RETURNING customer_id, first_name, last_name, email, store_id;

-- Verify the update applied correctly
SELECT customer_id, first_name, last_name, email, store_id, active
FROM   public.customer
WHERE  email = 'erik.abdykarimov@sakilacustomer.org';

COMMIT;


-- =
-- SUBTASK 5 — DELETE ALL EXISTING RENTAL & PAYMENT RECORDS FOR MY CUSTOMER
--             (all tables EXCEPT public.customer and public.inventory)
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   Deletes must be atomic. If payment rows are removed but the rental
 *   delete then fails (or vice versa), the DB would be in an inconsistent
 *   state. BEGIN/COMMIT keeps both deletes as one unit.
 *
 * WHY DELETING FROM THESE TABLES IS SAFE:
 *   • We target ONLY rows where customer_id matches our single customer,
 *     resolved via email — the most unique, non-ambiguous key.
 *   • public.customer and public.inventory are explicitly preserved (task rule).
 *   • No other tables (film, actor, staff, address, etc.) hold customer_id FKs.
 *
 * ORDER OF DELETION (FK dependency):
 *   public.payment references public.rental via rental_id.
 *   ∴ payment MUST be deleted BEFORE rental to satisfy the FK constraint.
 *
 * HOW UNINTENDED DATA LOSS IS PREVENTED:
 *   SELECT previews are run before BEGIN to confirm exactly which rows
 *   will be deleted. customer_id is never hardcoded.
 *
 * ROLLBACK POSSIBILITY & AFFECTED DATA:
 *   Full rollback before COMMIT restores both payment and rental rows.
 */

--          Preview: payment rows that will be deleted
SELECT p.payment_id, p.amount, p.payment_date
FROM   public.payment p
WHERE  p.customer_id = (
    SELECT customer_id FROM public.customer
    WHERE  email = 'erik.abdykarimov@sakilacustomer.org'
);

--          Preview: rental rows that will be deleted
SELECT r.rental_id, r.rental_date, r.return_date, r.inventory_id
FROM   public.rental r
WHERE  r.customer_id = (
    SELECT customer_id FROM public.customer
    WHERE  email = 'erik.abdykarimov@sakilacustomer.org'
);

BEGIN;

-- Step 1 — Delete payment rows first (child of rental via FK rental_id)
DELETE FROM public.payment
WHERE  customer_id = (
    SELECT customer_id FROM public.customer
    WHERE  email = 'erik.abdykarimov@sakilacustomer.org'
)
RETURNING payment_id, rental_id, amount, payment_date;

-- Step 2 — Delete rental rows (parent of payment, child of inventory)
DELETE FROM public.rental
WHERE  customer_id = (
    SELECT customer_id FROM public.customer
    WHERE  email = 'erik.abdykarimov@sakilacustomer.org'
)
RETURNING rental_id, inventory_id, rental_date;

-- Post-delete verification: both counts must be 0
SELECT 'payments remaining' AS check_label,
       COUNT(*) AS row_count
FROM   public.payment
WHERE  customer_id = (
    SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
UNION ALL
SELECT 'rentals remaining',
       COUNT(*)
FROM   public.rental
WHERE  customer_id = (
    SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org');

COMMIT;


-- =
-- SUBTASK 6 — RENT THE 3 FAVORITE MOVIES & RECORD PAYMENTS
-- =
/*
 * WHY A SEPARATE TRANSACTION:
 *   Rental and payment inserts are coupled — a payment without a rental
 *   violates FK integrity, and a rental without payment is business-logic
 *   incomplete. Keeping them in one transaction ensures all-or-nothing.
 *
 * WHAT HAPPENS IF THE TRANSACTION FAILS:
 *   All rental and payment rows inserted here are rolled back.
 *
 * REFERENTIAL INTEGRITY:
 *   rental.inventory_id → public.inventory (resolved via subquery by film title)
 *   rental.customer_id  → public.customer  (resolved via email subquery)
 *   rental.staff_id     → public.staff     (resolved via store_id = 1 subquery)
 *   payment.rental_id   → public.rental    (resolved via film-title subquery)
 *
 * HOW DUPLICATES ARE AVOIDED:
 *   NOT EXISTS on (inventory_id, customer_id, rental_date) prevents inserting
 *   the same rental twice. Payments are guarded by NOT EXISTS on rental_id.
 *
 * PAYMENT DATE / PARTITION:
 *   Payments are dated 2017-01-15, which routes them into the existing
 *   partition payment_p2017_01 (covers 2017-01-01 → 2017-02-01).
 *   All monthly 2017 partitions already exist in this database instance,
 *   so no new partition needs to be created.
 *   Payment amounts match the rental_rate values assigned to each film.
 *     • Hacksaw Ridge :  4.99
 *     • Inception     :  9.99
 *     • Interstellar  : 19.99
 */

-- NOTE: All 2017 monthly partitions already exist in this database.

--                   RENTAL INSERTS

BEGIN;

-- Rental 1: Hacksaw Ridge (return after 7 days = 1 week)
INSERT INTO public.rental
    (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:00:00'::TIMESTAMP,
    (SELECT i.inventory_id
     FROM   public.inventory i
     JOIN   public.film f ON f.film_id = i.film_id
     WHERE  UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
     AND    i.store_id = 1
     LIMIT  1),
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    '2017-01-22 10:00:00'::TIMESTAMP,
    (SELECT staff_id FROM public.staff WHERE store_id = 1 LIMIT 1),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental r2
    WHERE  r2.inventory_id = (
               SELECT i.inventory_id FROM public.inventory i
               JOIN   public.film f ON f.film_id = i.film_id
               WHERE  UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
               AND    i.store_id = 1 LIMIT 1)
    AND    r2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    r2.rental_date = '2017-01-15 10:00:00'::TIMESTAMP
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

-- Rental 2: Inception (return after 14 days = 2 weeks)
INSERT INTO public.rental
    (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:05:00'::TIMESTAMP,
    (SELECT i.inventory_id
     FROM   public.inventory i
     JOIN   public.film f ON f.film_id = i.film_id
     WHERE  UPPER(f.title)='INCEPTION' AND f.release_year=2010
     AND    i.store_id = 1
     LIMIT  1),
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    '2017-01-29 10:05:00'::TIMESTAMP,
    (SELECT staff_id FROM public.staff WHERE store_id = 1 LIMIT 1),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental r2
    WHERE  r2.inventory_id = (
               SELECT i.inventory_id FROM public.inventory i
               JOIN   public.film f ON f.film_id = i.film_id
               WHERE  UPPER(f.title)='INCEPTION' AND f.release_year=2010
               AND    i.store_id = 1 LIMIT 1)
    AND    r2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    r2.rental_date = '2017-01-15 10:05:00'::TIMESTAMP
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

-- Rental 3: Interstellar (return after 21 days = 3 weeks)
INSERT INTO public.rental
    (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:10:00'::TIMESTAMP,
    (SELECT i.inventory_id
     FROM   public.inventory i
     JOIN   public.film f ON f.film_id = i.film_id
     WHERE  UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
     AND    i.store_id = 1
     LIMIT  1),
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    '2017-02-05 10:10:00'::TIMESTAMP,
    (SELECT staff_id FROM public.staff WHERE store_id = 1 LIMIT 1),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental r2
    WHERE  r2.inventory_id = (
               SELECT i.inventory_id FROM public.inventory i
               JOIN   public.film f ON f.film_id = i.film_id
               WHERE  UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
               AND    i.store_id = 1 LIMIT 1)
    AND    r2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    r2.rental_date = '2017-01-15 10:10:00'::TIMESTAMP
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

--                          PAYMENT INSERTS

-- Payment 1: Hacksaw Ridge — 4.99
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    (SELECT staff_id FROM public.staff WHERE store_id=1 LIMIT 1),
    (SELECT r.rental_id
     FROM   public.rental r
     JOIN   public.inventory i ON i.inventory_id = r.inventory_id
     JOIN   public.film f      ON f.film_id      = i.film_id
     WHERE  UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
     AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
     LIMIT  1),
    4.99,
    '2017-01-15 10:00:00'::TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment p2
    WHERE  p2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    p2.rental_id   = (
               SELECT r.rental_id FROM public.rental r
               JOIN   public.inventory i ON i.inventory_id=r.inventory_id
               JOIN   public.film f ON f.film_id=i.film_id
               WHERE  UPPER(f.title)='HACKSAW RIDGE' AND f.release_year=2016
               AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
               LIMIT  1)
)
RETURNING payment_id, rental_id, amount, payment_date;

-- Payment 2: Inception — 9.99
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    (SELECT staff_id FROM public.staff WHERE store_id=1 LIMIT 1),
    (SELECT r.rental_id
     FROM   public.rental r
     JOIN   public.inventory i ON i.inventory_id = r.inventory_id
     JOIN   public.film f      ON f.film_id      = i.film_id
     WHERE  UPPER(f.title)='INCEPTION' AND f.release_year=2010
     AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
     LIMIT  1),
    9.99,
    '2017-01-15 10:05:00'::TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment p2
    WHERE  p2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    p2.rental_id   = (
               SELECT r.rental_id FROM public.rental r
               JOIN   public.inventory i ON i.inventory_id=r.inventory_id
               JOIN   public.film f ON f.film_id=i.film_id
               WHERE  UPPER(f.title)='INCEPTION' AND f.release_year=2010
               AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
               LIMIT  1)
)
RETURNING payment_id, rental_id, amount, payment_date;

-- Payment 3: Interstellar — 19.99
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org'),
    (SELECT staff_id FROM public.staff WHERE store_id=1 LIMIT 1),
    (SELECT r.rental_id
     FROM   public.rental r
     JOIN   public.inventory i ON i.inventory_id = r.inventory_id
     JOIN   public.film f      ON f.film_id      = i.film_id
     WHERE  UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
     AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
     LIMIT  1),
    19.99,
    '2017-01-15 10:10:00'::TIMESTAMP
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment p2
    WHERE  p2.customer_id = (SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
    AND    p2.rental_id   = (
               SELECT r.rental_id FROM public.rental r
               JOIN   public.inventory i ON i.inventory_id=r.inventory_id
               JOIN   public.film f ON f.film_id=i.film_id
               WHERE  UPPER(f.title)='INTERSTELLAR' AND f.release_year=2014
               AND    r.customer_id=(SELECT customer_id FROM public.customer WHERE email='erik.abdykarimov@sakilacustomer.org')
               LIMIT  1)
)
RETURNING payment_id, rental_id, amount, payment_date;

--          Final verification: all 3 rentals + payments for my customer
SELECT f.title,
       r.rental_date,
       r.return_date,
       p.amount,
       p.payment_date
FROM   public.rental r
JOIN   public.inventory i ON i.inventory_id = r.inventory_id
JOIN   public.film      f ON f.film_id      = i.film_id
JOIN   public.payment   p ON p.rental_id    = r.rental_id
WHERE  r.customer_id = (
    SELECT customer_id FROM public.customer
    WHERE  email = 'erik.abdykarimov@sakilacustomer.org'
)
ORDER  BY r.rental_date;

COMMIT;
