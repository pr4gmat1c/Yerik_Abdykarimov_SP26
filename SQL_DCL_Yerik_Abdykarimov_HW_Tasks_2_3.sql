-- =============================================================================
-- DVD Rental Database Assignment: Creating and Managing Roles
-- Yerik Abdykarimov
-- =============================================================================


-- =============================================================================
-- TASK 2 – ROLE-BASED AUTHENTICATION MODEL
-- =============================================================================

-- ── Step 1: Create rentaluser with connect-only permission ───────────────────
/*
 * The user receives CONNECT on the database but no table-level privileges.
 * Attempting to query any table at this point returns:
 *   ERROR: permission denied for table <name>
 */
CREATE USER rentaluser WITH PASSWORD 'rentalpassword';
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;

-- Verify: rolcanlogin should be true
SELECT rolname, rolcanlogin
FROM pg_roles
WHERE rolname = 'rentaluser';


-- ── Step 2: Grant SELECT on customer to rentaluser ───────────────────────────
/*
 * Grant read access to the customer table. No other tables are accessible yet.
 *
 * Demonstrated below:
 *   SELECT on customer → succeeds (returns rows)
 *   SELECT on rental   → ERROR: permission denied
 */
GRANT USAGE  ON SCHEMA public TO rentaluser;
GRANT SELECT ON TABLE  public.customer TO rentaluser;

-- Verification: run as rentaluser (succeeds)
SET SESSION AUTHORIZATION rentaluser;
SELECT customer_id, first_name, last_name, email
FROM customer
LIMIT 5;
-- Expected output (first 5 rows):
--  customer_id | first_name | last_name |               email
-- -------------+------------+-----------+------------------------------------
--            1 | MARY       | SMITH     | MARY.SMITH@sakilacustomer.org
--            2 | PATRICIA   | JOHNSON   | PATRICIA.JOHNSON@sakilacustomer.org
--            3 | LINDA      | WILLIAMS  | LINDA.WILLIAMS@sakilacustomer.org
--            4 | BARBARA    | JONES     | BARBARA.JONES@sakilacustomer.org
--            5 | ELIZABETH  | BROWN     | ELIZABETH.BROWN@sakilacustomer.org

-- Verification: rental table is still denied
SELECT rental_id FROM rental LIMIT 3;
-- Expected: ERROR: permission denied for table rental

RESET SESSION AUTHORIZATION;


-- ── Step 3: Create user group 'rental' and add rentaluser ────────────────────
/*
 * A group role (no login) is created so that permissions can be managed
 * centrally. Any member of the group inherits its privileges.
 */
CREATE ROLE rental;                  -- group role, cannot log in
GRANT rental TO rentaluser;          -- rentaluser becomes a member

-- Verify membership
SELECT
    r.rolname  AS member,
    b.rolname  AS group_role,
    m.inherit_option
FROM pg_auth_members m
JOIN pg_roles r ON m.member  = r.oid
JOIN pg_roles b ON m.roleid  = b.oid
WHERE b.rolname = 'rental';
-- Expected: rentaluser | rental | t


-- ── Step 4: Grant INSERT and UPDATE on rental to rental group ────────────────
/*
 * INSERT and UPDATE are granted to the 'rental' group role.
 * rentaluser also receives the same grants directly because PostgreSQL 16
 * requires explicit grants for SET SESSION AUTHORIZATION scenarios.
 * Both INSERT (new row) and UPDATE (return_date update) are demonstrated.
 */
GRANT USAGE  ON SCHEMA public                        TO rental;
GRANT INSERT, UPDATE ON TABLE  public.rental         TO rental;
GRANT USAGE  ON SEQUENCE public.rental_rental_id_seq TO rental;

-- Direct grants to rentaluser (required in PostgreSQL 16)
GRANT SELECT, INSERT, UPDATE ON TABLE public.rental          TO rentaluser;
GRANT USAGE  ON SEQUENCE public.rental_rental_id_seq         TO rentaluser;

-- Verify the ACL on rental
SELECT relname, pg_catalog.array_to_string(relacl, E'\n') AS acl
FROM pg_class
WHERE relname = 'rental';

-- Demonstrate INSERT as rentaluser
SET SESSION AUTHORIZATION rentaluser;

INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), 1, 1, 1)
RETURNING rental_id, rental_date, inventory_id, customer_id;
-- Expected: one new row returned with a freshly generated rental_id

-- Demonstrate UPDATE as rentaluser
UPDATE rental
SET    return_date = NOW()
WHERE  rental_id   = 2
RETURNING rental_id, return_date;
-- Expected: rental_id=2 with updated return_date

RESET SESSION AUTHORIZATION;


-- ── Step 5: Revoke INSERT from rental group; confirm denial ──────────────────
/*
 * INSERT is removed from both the group role and rentaluser directly.
 * After revocation, any INSERT attempt returns:
 *   ERROR: permission denied for table rental
 * UPDATE remains available (rentaluser still has the 'w' privilege).
 */
REVOKE INSERT ON TABLE public.rental FROM rental;
REVOKE INSERT ON TABLE public.rental FROM rentaluser;

-- Verify ACL: rental group should now show only 'w' (UPDATE)
SELECT relname, pg_catalog.array_to_string(relacl, E'\n') AS acl
FROM pg_class
WHERE relname = 'rental';
-- Expected snippet: rental=w/postgres, rentaluser=rw/postgres
-- Note: 'r' = SELECT, 'w' = UPDATE, 'a' = INSERT

-- Demonstrate that INSERT is now denied
SET SESSION AUTHORIZATION rentaluser;

INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), 3, 3, 1);
-- Expected: ERROR: permission denied for table rental

RESET SESSION AUTHORIZATION;


-- ── Step 6: Personalized client roles ────────────────────────────────────────
/*
 * A PL/pgSQL anonymous block creates one LOGIN role per customer who has
 * BOTH a payment record AND a rental record (599 customers qualify).
 *
 * Role name convention: client_{first_name}_{last_name}
 *   e.g., customer MARY SMITH  → role  client_mary_smith
 *
 * Only 5 roles are created here as a demonstrable sample. Remove the LIMIT
 * clause to generate all 599.
 *
 * Note: Special characters in names are replaced with underscores using
 * regexp_replace to ensure valid PostgreSQL identifier names.
 */
DO $$
DECLARE
    r         RECORD;
    role_name TEXT;
BEGIN
    FOR r IN
        SELECT DISTINCT c.first_name, c.last_name, c.customer_id
        FROM   customer c
        WHERE  EXISTS (SELECT 1 FROM payment p  WHERE p.customer_id  = c.customer_id)
          AND  EXISTS (SELECT 1 FROM rental  r2 WHERE r2.customer_id = c.customer_id)
        ORDER  BY c.customer_id
        LIMIT  5          -- Remove LIMIT to create all 599 roles
    LOOP
        role_name := 'client_'
            || lower(regexp_replace(r.first_name, '[^a-zA-Z0-9]', '_', 'g'))
            || '_'
            || lower(regexp_replace(r.last_name,  '[^a-zA-Z0-9]', '_', 'g'));

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
            EXECUTE format(
                'CREATE ROLE %I LOGIN PASSWORD %L',
                role_name,
                'temppass123'    -- Should be changed to a strong password in production
            );
            RAISE NOTICE 'Created role: %', role_name;
        ELSE
            RAISE NOTICE 'Role already exists: %  (skipped)', role_name;
        END IF;
    END LOOP;
END;
$$;

-- Verify created roles
SELECT rolname, rolcanlogin
FROM   pg_roles
WHERE  rolname LIKE 'client_%'
ORDER  BY rolname;
-- Expected (sample):
--          rolname         | rolcanlogin
-- -------------------------+-------------
--  client_barbara_jones    | t
--  client_elizabeth_brown  | t
--  client_linda_williams   | t
--  client_mary_smith       | t
--  client_patricia_johnson | t


-- =============================================================================
-- TASK 3 – ROW-LEVEL SECURITY (RLS)
-- Reference: https://www.postgresql.org/docs/12/ddl-rowsecurity.html
-- =============================================================================
/*
 * Each client role (client_{first_name}_{last_name}) is configured so that
 * it can only access rows in the 'rental' and 'payment' tables that belong
 * to their own customer account.
 *
 * The demonstration role is: client_mary_smith  (customer_id = 1)
 *
 * Strategy:
 *   The RLS policy resolves current_user back to a customer_id by matching
 *   the role name against the pattern built from the customer table:
 *     'client_' || lower(first_name) || '_' || lower(last_name)
 *   This is deterministic, requires no extra mapping table, and automatically
 *   works for all 599 client roles using the same two policies.
 */

-- ── 3.1 Enable RLS on the target tables ─────────────────────────────────────
ALTER TABLE rental  ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment ENABLE ROW LEVEL SECURITY;


-- ── 3.2 Grant table-level access to the example client role ─────────────────
/*
 * Without a table-level GRANT the role would hit "permission denied" before
 * the RLS policy is even evaluated. The RLS layer is a second filter on top
 * of the existing privilege system.
 */
GRANT USAGE  ON SCHEMA public TO client_mary_smith;
GRANT SELECT ON TABLE public.customer            TO client_mary_smith;
GRANT SELECT ON TABLE public.rental              TO client_mary_smith;
GRANT SELECT ON TABLE public.payment             TO client_mary_smith;
-- Payment is partitioned; child tables also need explicit grants:
GRANT SELECT ON TABLE public.payment_p2017_01   TO client_mary_smith;
GRANT SELECT ON TABLE public.payment_p2017_02   TO client_mary_smith;
GRANT SELECT ON TABLE public.payment_p2017_03   TO client_mary_smith;
GRANT SELECT ON TABLE public.payment_p2017_04   TO client_mary_smith;
GRANT SELECT ON TABLE public.payment_p2017_05   TO client_mary_smith;
GRANT SELECT ON TABLE public.payment_p2017_06   TO client_mary_smith;


-- ── 3.3 Create RLS policies ──────────────────────────────────────────────────
CREATE POLICY rental_customer_isolation ON rental
    FOR SELECT
    USING (
        customer_id = (
            SELECT c.customer_id
            FROM   customer c
            WHERE  'client_' || lower(c.first_name) || '_' || lower(c.last_name)
                   = current_user
            LIMIT  1
        )
    );

CREATE POLICY payment_customer_isolation ON payment
    FOR SELECT
    USING (
        customer_id = (
            SELECT c.customer_id
            FROM   customer c
            WHERE  'client_' || lower(c.first_name) || '_' || lower(c.last_name)
                   = current_user
            LIMIT  1
        )
    );

-- Confirm policies are registered
SELECT schemaname, tablename, policyname, cmd, qual
FROM   pg_policies
WHERE  tablename IN ('rental', 'payment')
ORDER  BY tablename;


-- ── 3.4 Verification: own data is accessible ─────────────────────────────────
SET SESSION AUTHORIZATION client_mary_smith;
SELECT current_user;   -- should be: client_mary_smith

-- Own rentals (customer_id = 1, Mary Smith)
SELECT rental_id, rental_date, inventory_id, customer_id
FROM   rental
ORDER  BY rental_date
LIMIT  5;
-- Expected: 5 rows, all with customer_id = 1

-- Count check: total rows visible vs. database total (32,089)
SELECT COUNT(*) AS visible_rentals, MIN(customer_id), MAX(customer_id)
FROM   rental;
-- Expected: count=65, min=1, max=1

-- Own payments
SELECT payment_id, customer_id, amount, payment_date
FROM   payment
ORDER  BY payment_date
LIMIT  5;
-- Expected: 5 rows, all with customer_id = 1

RESET SESSION AUTHORIZATION;


-- ── 3.5 Verification: other customers' data is blocked ───────────────────────
SET SESSION AUTHORIZATION client_mary_smith;

-- Explicit attempt to read Patricia Johnson's rentals (customer_id = 2)
SELECT rental_id, customer_id
FROM   rental
WHERE  customer_id = 2
LIMIT  5;
-- Expected: (0 rows)  ← RLS filters the rows silently, no error is raised

-- Overall count still shows only Mary's rows
SELECT COUNT(*) AS visible_rentals, MIN(customer_id), MAX(customer_id)
FROM   rental;
-- Expected: count=65, min=1, max=1

-- Payment cross-customer attempt
SELECT COUNT(*) AS visible_payments, MIN(customer_id), MAX(customer_id)
FROM   payment;
-- Expected: count=64, min=1, max=1

RESET SESSION AUTHORIZATION;
