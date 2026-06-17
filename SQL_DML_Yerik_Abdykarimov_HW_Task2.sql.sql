
--                                TASK   2



-- =
-- STEP 1 — Create table_to_delete and populate it with 10 million rows
-- =

CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM   generate_series(1, (10^7)::int) x;
-- generate_series creates 10^7 rows (1 → 10,000,000) of sequential integers.


-- =
-- STEP 2 — Check space consumption BEFORE any deletion
-- =
SELECT *,
       pg_size_pretty(total_bytes)               AS total,
       pg_size_pretty(index_bytes)               AS index,
       pg_size_pretty(toast_bytes)               AS toast,
       pg_size_pretty(table_bytes)               AS table
FROM (
    SELECT *,
           total_bytes - index_bytes - COALESCE(toast_bytes, 0) AS table_bytes
    FROM (
        SELECT c.oid,
               nspname              AS table_schema,
               relname              AS table_name,
               c.reltuples          AS row_estimate,
               pg_total_relation_size(c.oid)            AS total_bytes,
               pg_indexes_size(c.oid)                   AS index_bytes,
               pg_total_relation_size(reltoastrelid)    AS toast_bytes
        FROM   pg_class c
        LEFT   JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE  relkind = 'r'
    ) a
) a
WHERE  table_name LIKE '%table_to_delete%';


-- =
-- STEP 3 — DELETE 1/3 of all rows
-- =

DELETE FROM table_to_delete
WHERE  REPLACE(col, 'veeeeeeery_long_string', '')::int % 3 = 0;
-- Removes all rows whose numeric suffix is divisible by 3 (≈ 3.33 million rows).

VACUUM FULL VERBOSE table_to_delete;

DROP TABLE IF EXISTS table_to_delete;

CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM   generate_series(1, (10^7)::int) x;


-- =
-- STEP 4 — TRUNCATE and observe
-- =

TRUNCATE table_to_delete;

-- =
-- STEP 5 — Investigation Results & Conclusions
-- =
/*

   Metric                  DELETE                       TRUNCATE

  Execution time       │ Slow (seconds–minutes for  │ Instantaneous — O(1)
                       │ millions of rows). Fires   │ regardless of row count.
                       │ row-level triggers and     │ Does NOT fire row-level
                       │ updates indexes per row.   │ triggers.

  Disk space freed     │ NOT freed immediately.      │ Freed IMMEDIATELY.
  immediately?         │ Dead tuples remain on disk  │ Table storage is reset
                       │ until VACUUM / VACUUM FULL. │ to 0 pages on commit.

  Transaction behavior │ Fully transactional:        │ Fully transactional in
                       │ can be rolled back before   │ PostgreSQL: can be rolled
                       │ COMMIT. Uses WAL logging.   │ back before COMMIT.

  Rollback possible?   │ YES — within a transaction  │ YES — in PostgreSQL only.
                       │ (standard SQL behaviour).   │ (Other DBs: NO rollback.) 


 WHY DELETE DOES NOT FREE SPACE IMMEDIATELY:
   PostgreSQL uses MVCC (Multi-Version Concurrency Control). When a row is
   deleted, it is NOT physically erased; instead, its xmax (transaction ID of
   the deleting transaction) is set to indicate it is "dead". The page is kept
   so concurrent transactions that started before the DELETE can still see the
   old version of the row. Space is only reclaimed by VACUUM (marks pages for
   reuse) or VACUUM FULL (rewrites the whole table, physically compacting it).

 WHY VACUUM FULL CHANGES TABLE SIZE:
   VACUUM FULL acquires an exclusive lock and rewrites the entire table into a
   new heap file, skipping all dead tuples. The old file is then deleted.
   Unlike regular VACUUM (which marks dead pages as reusable but does not shrink
   the file), VACUUM FULL actually reduces the on-disk file size.

 WHY TRUNCATE BEHAVES DIFFERENTLY:
   TRUNCATE does not scan or mark individual rows. It simply drops the underlying
   data pages and replaces them with an empty relation, updating the relation's
   file pointer in the system catalog. This is why it is O(1) in time and
   immediately reclaims all space.

 HOW THESE OPERATIONS AFFECT PERFORMANCE AND STORAGE:
   • DELETE is suitable when you need fine-grained control (WHERE clause),
     want row-level trigger execution, or need the operation to be interleaved
     with other DML in the same transaction.
   • After a large DELETE, running VACUUM (or AUTOVACUUM) is essential to avoid
     table bloat — wasted space that slows sequential scans.
   • TRUNCATE is the right tool when you need to empty an entire table quickly
     without retaining any rows. Use it in ETL pipelines, test teardowns, and
     staging table resets.
   • From a WAL (Write-Ahead Log) perspective: DELETE generates a WAL record
     per row; TRUNCATE generates a single WAL record, dramatically reducing I/O
     and replication lag on busy systems.
*/