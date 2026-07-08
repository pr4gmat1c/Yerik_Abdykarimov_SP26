-- ============================================================
-- TASK 1: Create the employee table
-- ============================================================

DROP TABLE IF EXISTS public.employee;

CREATE TABLE public.employee (
    id     SERIAL,
    name   VARCHAR,
    status VARCHAR
);


-- ============================================================
-- TASK 2: Replicate the MVCC lecture example
--
-- Open TWO psql sessions (Session A = left, Session B = right).
-- Run the numbered steps in order across both sessions.
-- This demonstrates how xmin / xmax track row versions.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- FIRST TRANSACTION
-- ─────────────────────────────────────────────────────────────

-- [Step A-1] SESSION A ──────────────────────────────────────
BEGIN;

SELECT txid_current();  -- note this XID; it becomes xmin for Alice

INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');

-- xmin = current XID, xmax = 0 (row not yet deleted)
SELECT *, xmin, xmax
FROM public.employee e;

-- [Step B-1] SESSION B (run while Session A is still open) ──
BEGIN;

-- Session B sees an EMPTY table: Alice's row has xmin = A's uncommitted XID,
-- so it is invisible to B (MVCC snapshot taken at B's BEGIN).
SELECT *, xmin, xmax
FROM public.employee e;

COMMIT; -- Session B ends its first transaction

-- [Step A-2] SESSION A ──────────────────────────────────────
COMMIT; -- Alice's row is now committed; xmin is finalised, xmax = 0


-- ─────────────────────────────────────────────────────────────
-- SECOND TRANSACTION
-- (Re-insert Alice first as described in the task sheet)
-- ─────────────────────────────────────────────────────────────

-- Insert Alice again so there is a live row to observe
INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');

-- [Step A-3] SESSION A ──────────────────────────────────────
BEGIN;

-- Alice is visible; xmax = 0 (row is alive)
SELECT *, xmin, xmax
FROM public.employee e;

-- [Step B-2] SESSION B ──────────────────────────────────────
BEGIN;

SELECT txid_current();  -- note this XID

DELETE FROM public.employee
WHERE id = 1;           -- marks the row: xmax = B's XID (still uncommitted)

-- B sees the row disappear from its own perspective (it issued the DELETE)
SELECT *, xmin, xmax
FROM public.employee e;

COMMIT; -- B commits the DELETE

-- [Step A-4] SESSION A (run AFTER B has committed) ──────────
-- First read: row is gone (B committed the delete before this read)
SELECT *, xmin, xmax
FROM public.employee e;

-- Second read: same result — row stays absent
SELECT *, xmin, xmax
FROM public.employee e;

COMMIT; -- Session A ends


-- ─────────────────────────────────────────────────────────────
-- THIRD TRANSACTION
-- ─────────────────────────────────────────────────────────────

-- Insert Alice again so we have a row with id = 2 for the UPDATE demo
INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');

-- [Step A-5] SESSION A ──────────────────────────────────────
BEGIN;

-- First read: Alice (id=2) is alive; xmax = 0
SELECT *, xmin, xmax
FROM public.employee e;

-- [Step B-3] SESSION B ──────────────────────────────────────
BEGIN;

SELECT txid_current();  -- note this XID

-- UPDATE is internally a DELETE of the old version + INSERT of a new version.
-- Old row: xmax = B's XID. New row: xmin = B's XID, xmax = 0.
UPDATE public.employee
SET    status = 'Fired'
WHERE  id = 2;

-- B sees its own new version (status = 'Fired')
SELECT *, xmin, xmax
FROM public.employee e;

COMMIT; -- B commits the UPDATE

-- [Step A-6] SESSION A (run AFTER B committed) ──────────────
-- Now A sees the updated row (status = 'Fired') with the new xmin
SELECT *, xmin, xmax
FROM public.employee e;

-- Second read: same updated state
SELECT *, xmin, xmax
FROM public.employee e;

COMMIT;


-- ============================================================
-- TASK 3: Set transaction isolation level to REPEATABLE READ
-- (Run this in EACH new session before beginning a transaction)
-- ============================================================

SET default_transaction_isolation TO 'repeatable read';

-- Or set it only for the current transaction:
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- ... your statements ...
COMMIT;


-- ============================================================
-- TASK 4: Check current isolation level
-- (Run in each session)
-- ============================================================

SHOW transaction_isolation;
-- Expected: "repeatable read"


-- ============================================================
-- TASK 5: Recreate employee table and redo Task 2
--         adding cmin and cmax system columns
-- ============================================================

-- cmin = command ID of the INSERT within the inserting transaction
-- cmax = command ID of the DELETE within the deleting transaction
-- Multiple DML statements in one transaction increment cmin/cmax.

DROP TABLE IF EXISTS public.employee;

CREATE TABLE public.employee (
    id     SERIAL,
    name   VARCHAR,
    status VARCHAR
);

-- ─── FIRST TRANSACTION (with cmin / cmax) ────────────────────

-- SESSION A
BEGIN;

SELECT txid_current();

INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');
-- cmin = 0 (first command in this txn), cmax = 0 (not deleted yet)

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

-- SESSION B
BEGIN;

SELECT *, xmin, xmax, cmin, cmax     -- empty; Alice not yet committed
FROM public.employee e;

COMMIT;

-- SESSION A
COMMIT;

-- ─── SECOND TRANSACTION (DELETE — observe cmax) ──────────────

INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');

-- SESSION A
BEGIN;

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

-- SESSION B
BEGIN;

SELECT txid_current();

DELETE FROM public.employee
WHERE id = 1;
-- The deleted row now has: xmax = B's XID, cmax = 0

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;  -- row gone for B

COMMIT;

-- SESSION A (after B commits)
SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;  -- row gone for A too

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

COMMIT;

-- ─── THIRD TRANSACTION (UPDATE — observe new xmin / cmin) ────

INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Not fired');

-- SESSION A
BEGIN;

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

-- SESSION B
BEGIN;

SELECT txid_current();

UPDATE public.employee
SET    status = 'Fired'
WHERE  id = 2;
-- New row version: xmin = B's XID, cmin = 0, xmax = 0, cmax = 0

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

COMMIT;

-- SESSION A (after B commits)
SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

SELECT *, xmin, xmax, cmin, cmax
FROM public.employee e;

COMMIT;

/*
WHAT CHANGED with cmin / cmax?

  • cmin shows *which command within a transaction* created a row version.
    If a single transaction inserts two rows, the first gets cmin = 0
    and the second gets cmin = 1.

  • cmax shows which command within the deleting transaction removed the row.

  • These columns matter for intra-transaction visibility: within the same
    transaction, a later command (higher cmin) should NOT see rows created
    by an earlier command if they have already been deleted by an even
    earlier command.

In practice cmin and cmax occupy the same 4-byte field in the tuple header
(PostgreSQL uses a "combo CID" if a row is both inserted and deleted inside
the same transaction). For normal cross-transaction DML they are typically 0.
*/


-- ============================================================
-- TASK 6 (*): Serialization Anomaly
-- ============================================================

-- ─── Setup ───────────────────────────────────────────────────

DROP TABLE IF EXISTS public.employee;

CREATE TABLE public.employee (
    id     SERIAL,
    name   VARCHAR,
    status VARCHAR
);

INSERT INTO public.employee ("name", status)
VALUES ('Alice', 'Active'),
       ('Bob',   'Active'),
       ('Carol', 'Active');

-- ─────────────────────────────────────────────────────────────
-- Part A: at REPEATABLE READ — anomaly CAN occur
-- ─────────────────────────────────────────────────────────────
-- Scenario: two transactions each count a different status and
-- then insert a row in the *opposite* status.  If run serially
-- the counts would differ; when run concurrently they both read
-- the same snapshot and produce a logically impossible outcome.

-- SESSION A
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- A counts 'Active' rows = 3
SELECT COUNT(*) FROM public.employee WHERE status = 'Active';

-- SESSION B (run concurrently)
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- B also counts 'Active' rows = 3
SELECT COUNT(*) FROM public.employee WHERE status = 'Active';

-- B counts 'Inactive' rows = 0 and decides to insert an 'Active' row
SELECT COUNT(*) FROM public.employee WHERE status = 'Inactive';
INSERT INTO public.employee ("name", status)
VALUES ('Dave', 'Active');

COMMIT; -- B commits successfully

-- A counts 'Inactive' = 0 (snapshot from before B's commit) and inserts 'Inactive'
SELECT COUNT(*) FROM public.employee WHERE status = 'Inactive';
INSERT INTO public.employee ("name", status)
VALUES ('Eve', 'Inactive');

COMMIT; -- A commits successfully — ANOMALY: both inserted based on stale counts

/*
Result at REPEATABLE READ: both commits succeed.
The final table is inconsistent with any serial ordering:
  • If A ran first: A inserts 'Inactive' (count=0), then B inserts 'Active'
  • If B ran first: B inserts 'Active', then A inserts 'Inactive' (count=1, not 0)
Neither matches what actually happened (both saw count=0).
*/

-- ─────────────────────────────────────────────────────────────
-- Part B: at SERIALIZABLE — anomaly is PREVENTED
-- ─────────────────────────────────────────────────────────────

-- Reset data
DELETE FROM public.employee WHERE name IN ('Dave', 'Eve');

-- SESSION A
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SELECT COUNT(*) FROM public.employee WHERE status = 'Active';    -- 3

-- SESSION B (run concurrently)
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

SELECT COUNT(*) FROM public.employee WHERE status = 'Active';    -- 3
SELECT COUNT(*) FROM public.employee WHERE status = 'Inactive';  -- 0
INSERT INTO public.employee ("name", status) VALUES ('Dave', 'Active');

COMMIT; -- B commits first

-- SESSION A
SELECT COUNT(*) FROM public.employee WHERE status = 'Inactive';  -- 0
INSERT INTO public.employee ("name", status) VALUES ('Eve', 'Inactive');

COMMIT;
-- ERROR: could not serialize access due to read/write dependencies among
--        transactions.  DETAIL: Reason code: Canceled on identification as a
--        pivot, during commit attempt.  HINT: The transaction might succeed if
--        retried.

/*
WHAT HAPPENED at SERIALIZABLE?

PostgreSQL's SSI (Serializable Snapshot Isolation) tracks read/write
dependencies between transactions.  It detected that:
  • A read rows that B later wrote  (A's count scan covered B's insert range)
  • B read rows that A later wrote  (B's count scan covered A's insert range)
This forms a cycle of dependencies that cannot exist in any serial execution.
PostgreSQL aborts one of the transactions (whichever tries to commit last)
with a serialization failure, forcing the application to retry.
*/


-- ============================================================
-- TASK 7 (*): Lost Update at READ COMMITTED
-- ============================================================

-- ─── Setup ───────────────────────────────────────────────────

DROP TABLE IF EXISTS public.employee;

CREATE TABLE public.employee (
    id     SERIAL,
    name   VARCHAR,
    status VARCHAR,
    salary NUMERIC DEFAULT 100
);

INSERT INTO public.employee ("name", status, salary)
VALUES ('Alice', 'Active', 100),
       ('Bob',   'Active', 200);

-- ─────────────────────────────────────────────────────────────
-- Scenario: two transactions read Alice's salary and write back
-- an application-computed value (simulating read-modify-write
-- done in application code, i.e. hardcoded final values).
-- ─────────────────────────────────────────────────────────────

-- SESSION A
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- A reads salary = 100, intends to set it to 150 (raise of +50)
SELECT salary FROM public.employee WHERE id = 1;   -- 100

-- SESSION B (run BEFORE A commits)
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- B also reads salary = 100, intends to set it to 80 (deduction of -20)
SELECT salary FROM public.employee WHERE id = 1;   -- 100

-- A writes its computed value
UPDATE public.employee SET salary = 150 WHERE id = 1;
COMMIT; -- A commits; salary = 150

-- B now writes ITS computed value (based on the stale read of 100)
-- This UPDATE blocks until A commits, then re-checks the WHERE clause.
-- The WHERE id = 1 still matches, so Postgres applies B's write → salary = 80.
UPDATE public.employee SET salary = 80 WHERE id = 1;
COMMIT; -- B commits; salary = 80  ← A's change is LOST

SELECT salary FROM public.employee WHERE id = 1;   -- 80 (expected 130 = 150-20)

/*
WHAT HAPPENED?

PostgreSQL prevents dirty reads even at READ COMMITTED, but it does NOT
prevent the lost-update pattern when application code reads a value and
writes back a hard-coded result:

  1. A and B both read salary = 100.
  2. A writes 150 and commits.
  3. B was blocked by A's row lock.  After A commits, Postgres re-evaluates
     B's WHERE clause against the *newly committed* row — id=1 still matches —
     so B's UPDATE proceeds, overwriting 150 with 80.
  4. A's raise of +50 is completely lost.

DOWNSIDES OF POSTGRES'S APPROACH AT READ COMMITTED:

  1. Silent data loss: The update succeeds with no error; the application
     has no indication that it overwrote another committed change.

  2. WHERE re-evaluation surprise: After unblocking, Postgres re-evaluates
     the WHERE predicate on the latest committed data, but the SET expression
     is still based on B's original (now stale) read.  This split between
     "which rows to touch" and "what value to write" is a logic trap.

  3. Correctness burden shifts to the application: To avoid lost updates at
     READ COMMITTED the developer must use explicit locking
     (SELECT ... FOR UPDATE) or write atomic SQL expressions
     (SET salary = salary - 20) rather than reading in the app and
     writing back a computed constant.

  4. No automatic detection or retry: Unlike SERIALIZABLE, READ COMMITTED
     will not raise an error; it silently corrupts the data.

SAFER ALTERNATIVES:
  • Use SET salary = salary - 20  (atomic expression — Postgres serialises
    the arithmetic on the live row, so no lost update occurs).
  • Use SELECT ... FOR UPDATE to lock the row before reading, preventing
    another transaction from modifying it until the lock is released.
  • Raise the isolation level to REPEATABLE READ or SERIALIZABLE (though
    REPEATABLE READ alone does not prevent all lost-update patterns either;
    SERIALIZABLE with SSI is the strongest guarantee).
*/
