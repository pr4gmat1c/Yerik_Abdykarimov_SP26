--  FUEL STATION NETWORK DATABASE
--  Yerik Abdykarimov
-- ============================================================



-- ============================================================
-- SECTION 0 : CLEANUP  (idempotent – safe to rerun)
-- ============================================================

-- Role is a server-level object (outside schema); drop it first.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fuel_station_manager') THEN
        -- Revoke all schema privileges before dropping
        REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA fuel_network
            FROM fuel_station_manager;
        REVOKE ALL ON SCHEMA fuel_network FROM fuel_station_manager;
        DROP ROLE fuel_station_manager;
        RAISE NOTICE 'Role fuel_station_manager dropped.';
    END IF;
END;
$$;

-- Cascading DROP removes all tables, views, functions, sequences.
DROP SCHEMA IF EXISTS fuel_network CASCADE;


-- ============================================================
-- SECTION 1 : SCHEMA
-- ============================================================

CREATE SCHEMA fuel_network;

COMMENT ON SCHEMA fuel_network IS
    'Fuel Station Network — stores stations, fuel types, '
    'inventory, pricing, sales, replenishments, employees, '
    'customers, and suppliers.';


-- ============================================================
-- SECTION 2 : PARENT TABLES
--   (no foreign keys → created first to satisfy FK order)
-- ============================================================

-- ── TABLE 1 : fuel_type ──────────────────────────────────────
-- Master catalogue of all fuel products sold in the network.
-- VARCHAR(50) is sufficient for product names like 'Petrol 95'.
CREATE TABLE fuel_network.fuel_type (
    fuel_type_id    SERIAL          PRIMARY KEY,
    fuel_name       VARCHAR(50)     NOT NULL UNIQUE,
    -- DEFAULT 'litre': all liquid fuels in Kazakhstan are sold
    -- by the litre; LPG is also metered in litres at dispensers.
    unit_of_measure VARCHAR(10)     NOT NULL DEFAULT 'litre',
    description     TEXT
);

COMMENT ON TABLE  fuel_network.fuel_type IS
    'Master catalogue of fuel product types (e.g. Petrol 92, Diesel, LPG).';


-- ── TABLE 2 : fuel_station ───────────────────────────────────
-- Each row represents one physical petrol station location.
CREATE TABLE fuel_network.fuel_station (
    station_id      SERIAL          PRIMARY KEY,
    station_name    VARCHAR(100)    NOT NULL,
    address         VARCHAR(200)    NOT NULL,
    city            VARCHAR(100)    NOT NULL,
    -- UNIQUE: one contact number per station prevents duplicate records.
    phone           VARCHAR(20)     NOT NULL UNIQUE,
    -- DEFAULT hours cover typical Kazakhstani station schedules.
    open_time       TIME            NOT NULL DEFAULT '06:00:00',
    close_time      TIME            NOT NULL DEFAULT '22:00:00',
    -- Soft-delete flag: FALSE = closed/decommissioned but kept
    -- for historical FK integrity.
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE fuel_network.fuel_station IS
    'Physical fuel station locations. Soft-deleted via is_active.';


-- ── TABLE 3 : supplier ───────────────────────────────────────
-- Companies that deliver fuel to stations (replenishments).
CREATE TABLE fuel_network.supplier (
    supplier_id     SERIAL          PRIMARY KEY,
    supplier_name   VARCHAR(100)    NOT NULL UNIQUE,
    contact_person  VARCHAR(100)    NOT NULL,
    phone           VARCHAR(20)     NOT NULL UNIQUE,
    email           VARCHAR(100)    UNIQUE,
    address         VARCHAR(200)    NOT NULL
);

COMMENT ON TABLE fuel_network.supplier IS
    'Fuel suppliers / distributors.';


-- ── TABLE 4 : customer ───────────────────────────────────────
-- Registered loyalty-programme members.
-- Anonymous (walk-in) customers appear in sales as NULL FK.
CREATE TABLE fuel_network.customer (
    customer_id         SERIAL          PRIMARY KEY,
    first_name          VARCHAR(50)     NOT NULL,
    last_name           VARCHAR(50)     NOT NULL,
    phone               VARCHAR(20)     UNIQUE,
    email               VARCHAR(100)    UNIQUE,
    -- UNIQUE: enforces one loyalty card per customer.
    loyalty_card_number VARCHAR(20)     UNIQUE,
    registration_date   DATE            NOT NULL DEFAULT CURRENT_DATE
);

COMMENT ON TABLE fuel_network.customer IS
    'Registered loyalty-programme customers. '
    'Walk-in (anonymous) customers are represented by NULL FK in sale.';


-- ============================================================
-- SECTION 3 : CHILD TABLES
--   (reference parent tables via FK → must come after parents)
-- ============================================================

-- ── TABLE 5 : employee ───────────────────────────────────────
-- Each employee belongs to exactly one station (station_id FK).
CREATE TABLE fuel_network.employee (
    employee_id     SERIAL          PRIMARY KEY,
    station_id      INT             NOT NULL
                        REFERENCES fuel_network.fuel_station(station_id),
    first_name      VARCHAR(50)     NOT NULL,
    last_name       VARCHAR(50)     NOT NULL,
    position        VARCHAR(50)     NOT NULL,
    hire_date       DATE            NOT NULL DEFAULT CURRENT_DATE,
    -- NUMERIC(10,2) chosen for exact decimal arithmetic;
    -- FLOAT/REAL would introduce rounding errors on monetary values.
    salary          NUMERIC(10,2)   NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);

COMMENT ON TABLE fuel_network.employee IS
    'Station employees (cashiers, managers, etc.). '
    'is_active allows soft-delete without losing FK history.';


-- ── TABLE 6 : fuel_inventory ─────────────────────────────────
-- MANY-TO-MANY bridge: one station stocks many fuel types;
-- one fuel type can be stocked at many stations.
-- Also tracks current quantity in tank.
CREATE TABLE fuel_network.fuel_inventory (
    inventory_id        SERIAL          PRIMARY KEY,
    station_id          INT             NOT NULL
                            REFERENCES fuel_network.fuel_station(station_id),
    fuel_type_id        INT             NOT NULL
                            REFERENCES fuel_network.fuel_type(fuel_type_id),
    -- DEFAULT 0: new inventory records start at zero until replenished.
    quantity_available  NUMERIC(10,2)   NOT NULL DEFAULT 0,
    last_updated        TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    -- UNIQUE composite: one record per station-fuel combination.
    UNIQUE (station_id, fuel_type_id)
);

COMMENT ON TABLE fuel_network.fuel_inventory IS
    'Current fuel stock per station. '
    'Implements the many-to-many relationship between '
    'fuel_station ↔ fuel_type.';


-- ── TABLE 7 : fuel_price ─────────────────────────────────────
-- Price history per station per fuel type.
-- One row per effective date allows tracking price changes over time.
CREATE TABLE fuel_network.fuel_price (
    price_id            SERIAL          PRIMARY KEY,
    station_id          INT             NOT NULL
                            REFERENCES fuel_network.fuel_station(station_id),
    fuel_type_id        INT             NOT NULL
                            REFERENCES fuel_network.fuel_type(fuel_type_id),
    -- NUMERIC(8,2): max 999 999.99 per litre — more than sufficient.
    regular_price       NUMERIC(8,2)    NOT NULL,
    discounted_price    NUMERIC(8,2),   -- NULL = no discount offered
    effective_date      DATE            NOT NULL DEFAULT CURRENT_DATE,
    -- One price record per station-fuel-date combination.
    UNIQUE (station_id, fuel_type_id, effective_date)
);

COMMENT ON TABLE fuel_network.fuel_price IS
    'Historical fuel pricing per station and fuel type. '
    'Supports price-change auditing via effective_date.';


-- ── TABLE 8 : replenishment ──────────────────────────────────
-- Records fuel deliveries from suppliers to stations.
-- total_cost is auto-computed to prevent data inconsistencies.
CREATE TABLE fuel_network.replenishment (
    replenishment_id    SERIAL          PRIMARY KEY,
    station_id          INT             NOT NULL
                            REFERENCES fuel_network.fuel_station(station_id),
    fuel_type_id        INT             NOT NULL
                            REFERENCES fuel_network.fuel_type(fuel_type_id),
    supplier_id         INT             NOT NULL
                            REFERENCES fuel_network.supplier(supplier_id),
    -- TIMESTAMPTZ: stores timezone-aware timestamps for accurate
    -- multi-city (Almaty UTC+5, Astana UTC+5) delivery scheduling.
    delivery_date       TIMESTAMPTZ     NOT NULL,
    quantity_received   NUMERIC(10,2)   NOT NULL,
    unit_cost           NUMERIC(8,2)    NOT NULL,
    -- GENERATED ALWAYS AS STORED: computed automatically from
    -- quantity_received * unit_cost; cannot be manually overwritten,
    -- ensuring the total is always consistent with the base columns.
    total_cost          NUMERIC(14,2)
                            GENERATED ALWAYS AS (quantity_received * unit_cost) STORED
);

COMMENT ON TABLE  fuel_network.replenishment IS
    'Fuel delivery records from suppliers to stations.';
COMMENT ON COLUMN fuel_network.replenishment.total_cost IS
    'Auto-computed GENERATED column: quantity_received × unit_cost. '
    'Prevents manual entry errors and is always consistent.';


-- ── TABLE 9 : sale  (main transaction table) ─────────────────
-- Records every individual fuel dispensing event.
-- customer_id is nullable: anonymous walk-in sales are valid.
CREATE TABLE fuel_network.sale (
    sale_id         SERIAL          PRIMARY KEY,
    station_id      INT             NOT NULL
                        REFERENCES fuel_network.fuel_station(station_id),
    fuel_type_id    INT             NOT NULL
                        REFERENCES fuel_network.fuel_type(fuel_type_id),
    -- Nullable FK: NULL means the customer did not present a loyalty card.
    customer_id     INT
                        REFERENCES fuel_network.customer(customer_id),
    employee_id     INT             NOT NULL
                        REFERENCES fuel_network.employee(employee_id),
    sale_datetime   TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    quantity_sold   NUMERIC(8,2)    NOT NULL,
    -- unit_price stored at sale time to preserve historical accuracy
    -- even if fuel_price is updated later (intentional denormalisation).
    unit_price      NUMERIC(8,2)    NOT NULL,
    -- GENERATED ALWAYS AS: auto-computed receipt total.
    total_amount    NUMERIC(12,2)
                        GENERATED ALWAYS AS (quantity_sold * unit_price) STORED,
    payment_method  VARCHAR(20)     NOT NULL
);

COMMENT ON TABLE  fuel_network.sale IS
    'Individual fuel sale transactions. Core transactional table. '
    'customer_id is nullable for anonymous walk-in customers.';
COMMENT ON COLUMN fuel_network.sale.unit_price IS
    'Price locked at the moment of sale to preserve historical accuracy.';
COMMENT ON COLUMN fuel_network.sale.total_amount IS
    'GENERATED ALWAYS AS STORED: quantity_sold × unit_price.';


-- ============================================================
-- SECTION 4 : CHECK CONSTRAINTS  (named, via ALTER TABLE)
--   Requirement: at least 5.  Defined: 10.
-- ============================================================

-- C1 ── Sale date must be after the system go-live date (2026-01-01)
ALTER TABLE fuel_network.sale
    ADD CONSTRAINT chk_sale_datetime_after_2026
    CHECK (sale_datetime > TIMESTAMPTZ '2026-01-01 00:00:00+00');
COMMENT ON CONSTRAINT chk_sale_datetime_after_2026 ON fuel_network.sale IS
    'System went live on 2026-01-02. Prevents back-dating of sales records.';

-- C2 ── Litres sold must be strictly positive (non-zero dispensing)
ALTER TABLE fuel_network.sale
    ADD CONSTRAINT chk_sale_quantity_positive
    CHECK (quantity_sold > 0);
COMMENT ON CONSTRAINT chk_sale_quantity_positive ON fuel_network.sale IS
    'A sale must dispense a positive quantity. '
    'Zero or negative quantities indicate data-entry errors.';

-- C3 ── Payment method restricted to approved business values
ALTER TABLE fuel_network.sale
    ADD CONSTRAINT chk_sale_payment_method_valid
    CHECK (payment_method IN ('cash', 'card', 'mobile', 'corporate_account'));
COMMENT ON CONSTRAINT chk_sale_payment_method_valid ON fuel_network.sale IS
    'Restricts payment_method to the four accepted modes, '
    'preventing free-text entry errors.';

-- C4 ── Regular price must be positive
ALTER TABLE fuel_network.fuel_price
    ADD CONSTRAINT chk_price_regular_positive
    CHECK (regular_price > 0);
COMMENT ON CONSTRAINT chk_price_regular_positive ON fuel_network.fuel_price IS
    'A price of 0 or below is economically meaningless and signals a data error.';

-- C5 ── Discounted price must be lower than regular price when set
ALTER TABLE fuel_network.fuel_price
    ADD CONSTRAINT chk_price_discount_below_regular
    CHECK (discounted_price IS NULL OR discounted_price < regular_price);
COMMENT ON CONSTRAINT chk_price_discount_below_regular ON fuel_network.fuel_price IS
    'A discount price >= regular price contradicts discount semantics. '
    'NULL is allowed (no discount offered at this station).';

-- C6 ── Delivered quantity must be positive
ALTER TABLE fuel_network.replenishment
    ADD CONSTRAINT chk_replenishment_quantity_positive
    CHECK (quantity_received > 0);
COMMENT ON CONSTRAINT chk_replenishment_quantity_positive ON fuel_network.replenishment IS
    'A delivery of zero or negative litres is a data error.';

-- C7 ── Delivery date must be after system go-live
ALTER TABLE fuel_network.replenishment
    ADD CONSTRAINT chk_replenishment_date_after_2026
    CHECK (delivery_date > TIMESTAMPTZ '2026-01-01 00:00:00+00');
COMMENT ON CONSTRAINT chk_replenishment_date_after_2026 ON fuel_network.replenishment IS
    'No deliveries were recorded before the system launch on 2026-01-02.';

-- C8 ── Employee salary must be positive
ALTER TABLE fuel_network.employee
    ADD CONSTRAINT chk_employee_salary_positive
    CHECK (salary > 0);
COMMENT ON CONSTRAINT chk_employee_salary_positive ON fuel_network.employee IS
    'HR policy: salary must be a positive monetary value.';

-- C9 ── Tank quantity cannot go negative
ALTER TABLE fuel_network.fuel_inventory
    ADD CONSTRAINT chk_inventory_quantity_non_negative
    CHECK (quantity_available >= 0);
COMMENT ON CONSTRAINT chk_inventory_quantity_non_negative ON fuel_network.fuel_inventory IS
    'A fuel tank cannot hold a negative volume.';

-- C10 ── Closing time must be after opening time
ALTER TABLE fuel_network.fuel_station
    ADD CONSTRAINT chk_station_hours_valid
    CHECK (open_time < close_time);
COMMENT ON CONSTRAINT chk_station_hours_valid ON fuel_network.fuel_station IS
    'Prevents nonsensical schedules where close time precedes open time.';


-- ============================================================
-- SECTION 5 : DML — SAMPLE DATA
--   Rules:
--     • No hardcoded surrogate key values in INSERTs.
--     • Natural keys resolved via subqueries / CASE expressions.
--     • All data falls within the last 3 months (Jan–Apr 2026).
--     • Minimum 6 rows per table (36+ total).
-- ============================================================

-- ── 1. fuel_type  (6 rows) ───────────────────────────────────
INSERT INTO fuel_network.fuel_type (fuel_name, unit_of_measure, description)
VALUES
    ('Petrol 92',   'litre', 'Regular unleaded petrol, RON 92'),
    ('Petrol 95',   'litre', 'Premium unleaded petrol, RON 95'),
    ('Diesel',      'litre', 'Standard diesel fuel'),
    ('LPG',         'litre', 'Liquefied petroleum gas'),
    ('Petrol 98',   'litre', 'Super premium unleaded petrol, RON 98'),
    ('Euro Diesel', 'litre', 'Low-sulphur premium diesel');


-- ── 2. fuel_station  (6 rows) ────────────────────────────────
INSERT INTO fuel_network.fuel_station (station_name, address, city, phone, open_time, close_time)
VALUES
    ('KazFuel Station #1', 'ul. Alatau 15',      'Almaty',   '+77271001001', '06:00', '23:00'),
    ('KazFuel Station #2', 'pr. Respubliki 88',  'Almaty',   '+77271001002', '00:00', '23:59'),
    ('KazFuel Station #3', 'ul. Abay 42',        'Astana',   '+77171001003', '06:00', '22:00'),
    ('KazFuel Station #4', 'ul. Dostyk 7',       'Shymkent', '+77252001004', '07:00', '21:00'),
    ('KazFuel Station #5', 'pr. Nazarbaeva 110', 'Astana',   '+77171001005', '06:00', '23:00'),
    ('KazFuel Station #6', 'ul. Gogolya 55',     'Almaty',   '+77271001006', '00:00', '23:59');


-- ── 3. supplier  (6 rows) ────────────────────────────────────
INSERT INTO fuel_network.supplier (supplier_name, contact_person, phone, email, address)
VALUES
    ('KazMunayGaz Supply',   'Aibek Dzhaksybekov',   '+77012000001', 'supply@kmg.kz',        'ul. Kabanbay Batyr 19, Astana'),
    ('PetroKaz Ltd',         'Saule Nurmagambetova',  '+77012000002', 'info@petrokaz.kz',     'pr. Alatau 5, Almaty'),
    ('EnergoFuel KZ',        'Dias Seitkali',         '+77012000003', 'contact@efkz.kz',      'ul. Seifullin 77, Almaty'),
    ('CaspianOil Trade',     'Marat Akhmetov',        '+77012000004', 'trade@caspian.kz',     'ul. Abay 120, Atyrau'),
    ('AlmatyFuel Wholesale', 'Zarina Bekova',         '+77012000005', 'sales@afwholesale.kz', 'pr. Al-Farabi 80, Almaty'),
    ('NurFuel Distributor',  'Timur Omarov',          '+77012000006', 'info@nurfuel.kz',      'ul. Beibitshilik 15, Astana');


-- ── 4. customer  (8 rows) ────────────────────────────────────
INSERT INTO fuel_network.customer
    (first_name, last_name, phone, email, loyalty_card_number, registration_date)
VALUES
    ('Arman',   'Bekuov',      '+77011234561', 'arman.b@mail.kz',    'LC-0001', '2025-10-01'),
    ('Dinara',  'Seitkali',    '+77011234562', 'dinara.s@mail.kz',   'LC-0002', '2025-11-15'),
    ('Ruslan',  'Akhmetov',    '+77011234563', 'ruslan.a@gmail.com', 'LC-0003', '2025-12-01'),
    ('Aizat',   'Nurlanovna',  '+77011234564', 'aizat.n@mail.kz',   'LC-0004', '2026-01-10'),
    ('Serik',   'Omarov',      '+77011234565', 'serik.o@gmail.com',  'LC-0005', '2026-01-20'),
    ('Madina',  'Zhumabek',    '+77011234566', 'madina.z@mail.kz',   'LC-0006', '2026-02-05'),
    ('Askar',   'Tleubek',     '+77011234567', 'askar.t@mail.kz',    'LC-0007', '2026-02-14'),
    ('Gulnara', 'Abdullayeva', '+77011234568', 'gulnara.a@gmail.com','LC-0008', '2026-03-01');


-- ── 5. employee  (12 rows) ───────────────────────────────────
-- station_id resolved via subquery — no hardcoded surrogate key.
INSERT INTO fuel_network.employee
    (station_id, first_name, last_name, position, hire_date, salary)
VALUES
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #1'), 'Nurlan',   'Kasymov',     'Cashier', '2024-03-01', 180000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #1'), 'Aliya',    'Bekova',      'Manager', '2023-06-15', 320000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #2'), 'Dauren',   'Seilov',      'Cashier', '2024-07-20', 185000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #2'), 'Zhanara',  'Ospanova',    'Manager', '2022-11-01', 330000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #3'), 'Azamat',   'Zhaksybekov', 'Cashier', '2025-01-10', 180000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #3'), 'Tolkyn',   'Nurmagambet', 'Manager', '2023-08-05', 320000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #4'), 'Bekzat',   'Abenov',      'Cashier', '2024-09-15', 175000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #4'), 'Saltanat', 'Dzhaksyova',  'Manager', '2023-04-20', 315000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #5'), 'Miras',    'Suleimenov',  'Cashier', '2025-03-01', 185000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #5'), 'Asel',     'Kenzhebaeva', 'Manager', '2022-07-10', 335000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #6'), 'Erlan',    'Tulegenov',   'Cashier', '2024-11-15', 180000),
    ((SELECT station_id FROM fuel_network.fuel_station WHERE station_name = 'KazFuel Station #6'), 'Nazerke',  'Abenova',     'Manager', '2023-01-20', 325000);


-- ── 6. fuel_inventory  (18 rows, many-to-many data) ──────────
-- Both FKs resolved by natural key subquery.
INSERT INTO fuel_network.fuel_inventory (station_id, fuel_type_id, quantity_available, last_updated)
SELECT
    (SELECT station_id   FROM fuel_network.fuel_station WHERE station_name = d.stn),
    (SELECT fuel_type_id FROM fuel_network.fuel_type    WHERE fuel_name    = d.fuel),
    d.qty::NUMERIC(10,2),
    NOW()
FROM (VALUES
    ('KazFuel Station #1', 'Petrol 92',   15000),
    ('KazFuel Station #1', 'Petrol 95',   12000),
    ('KazFuel Station #1', 'Diesel',      10000),
    ('KazFuel Station #2', 'Petrol 92',   18000),
    ('KazFuel Station #2', 'Petrol 95',   14000),
    ('KazFuel Station #2', 'LPG',          8000),
    ('KazFuel Station #3', 'Petrol 92',   16000),
    ('KazFuel Station #3', 'Diesel',      12000),
    ('KazFuel Station #3', 'Petrol 98',    5000),
    ('KazFuel Station #4', 'Petrol 92',   14000),
    ('KazFuel Station #4', 'Petrol 95',   11000),
    ('KazFuel Station #4', 'Euro Diesel',  9000),
    ('KazFuel Station #5', 'Petrol 95',   13000),
    ('KazFuel Station #5', 'Diesel',      11000),
    ('KazFuel Station #5', 'LPG',          7000),
    ('KazFuel Station #6', 'Petrol 92',   17000),
    ('KazFuel Station #6', 'Petrol 95',   13000),
    ('KazFuel Station #6', 'Petrol 98',    4000)
) AS d(stn, fuel, qty);


-- ── 7. fuel_price  (18 rows) ─────────────────────────────────
-- disc column uses explicit NUMERIC cast to resolve type in VALUES.
INSERT INTO fuel_network.fuel_price
    (station_id, fuel_type_id, regular_price, discounted_price, effective_date)
SELECT
    (SELECT station_id   FROM fuel_network.fuel_station WHERE station_name = p.stn),
    (SELECT fuel_type_id FROM fuel_network.fuel_type    WHERE fuel_name    = p.fuel),
    p.reg::NUMERIC(8,2),
    p.disc::NUMERIC(8,2),   -- NULL rows cast cleanly to NULL NUMERIC
    p.eff::DATE
FROM (VALUES
    ('KazFuel Station #1', 'Petrol 92',   '185.00', '180.00', '2026-01-15'),
    ('KazFuel Station #1', 'Petrol 95',   '210.00', '205.00', '2026-01-15'),
    ('KazFuel Station #1', 'Diesel',      '195.00', NULL,      '2026-01-15'),
    ('KazFuel Station #2', 'Petrol 92',   '183.00', '178.00', '2026-01-20'),
    ('KazFuel Station #2', 'Petrol 95',   '208.00', '203.00', '2026-01-20'),
    ('KazFuel Station #2', 'LPG',          '95.00', NULL,      '2026-01-20'),
    ('KazFuel Station #3', 'Petrol 92',   '186.00', '181.00', '2026-02-01'),
    ('KazFuel Station #3', 'Diesel',      '196.00', NULL,      '2026-02-01'),
    ('KazFuel Station #3', 'Petrol 98',   '240.00', '235.00', '2026-02-01'),
    ('KazFuel Station #4', 'Petrol 92',   '184.00', '179.00', '2026-02-10'),
    ('KazFuel Station #4', 'Petrol 95',   '209.00', '204.00', '2026-02-10'),
    ('KazFuel Station #4', 'Euro Diesel', '205.00', '200.00', '2026-02-10'),
    ('KazFuel Station #5', 'Petrol 95',   '211.00', '206.00', '2026-03-01'),
    ('KazFuel Station #5', 'Diesel',      '197.00', NULL,      '2026-03-01'),
    ('KazFuel Station #5', 'LPG',          '96.00', NULL,      '2026-03-01'),
    ('KazFuel Station #6', 'Petrol 92',   '185.50', '180.50', '2026-03-15'),
    ('KazFuel Station #6', 'Petrol 95',   '210.50', '205.50', '2026-03-15'),
    ('KazFuel Station #6', 'Petrol 98',   '241.00', '236.00', '2026-03-15')
) AS p(stn, fuel, reg, disc, eff);


-- ── 8. replenishment  (12 rows) ──────────────────────────────
-- All three FKs resolved via natural-key subqueries.
INSERT INTO fuel_network.replenishment
    (station_id, fuel_type_id, supplier_id, delivery_date, quantity_received, unit_cost)
SELECT
    (SELECT station_id   FROM fuel_network.fuel_station WHERE station_name  = r.stn),
    (SELECT fuel_type_id FROM fuel_network.fuel_type    WHERE fuel_name     = r.fuel),
    (SELECT supplier_id  FROM fuel_network.supplier     WHERE supplier_name = r.sup),
    r.del_dt::TIMESTAMPTZ,
    r.qty::NUMERIC(10,2),
    r.cost::NUMERIC(8,2)
FROM (VALUES
    ('KazFuel Station #1', 'Petrol 92',   'KazMunayGaz Supply',   '2026-01-10 09:00:00+06', '20000', '160.00'),
    ('KazFuel Station #1', 'Petrol 95',   'KazMunayGaz Supply',   '2026-01-10 11:00:00+06', '15000', '185.00'),
    ('KazFuel Station #2', 'Petrol 92',   'PetroKaz Ltd',          '2026-01-15 08:00:00+06', '22000', '158.00'),
    ('KazFuel Station #2', 'LPG',         'EnergoFuel KZ',         '2026-01-20 10:00:00+06', '10000',  '80.00'),
    ('KazFuel Station #3', 'Diesel',      'CaspianOil Trade',      '2026-02-05 09:30:00+06', '18000', '170.00'),
    ('KazFuel Station #3', 'Petrol 98',   'AlmatyFuel Wholesale',  '2026-02-05 14:00:00+06',  '8000', '210.00'),
    ('KazFuel Station #4', 'Petrol 95',   'NurFuel Distributor',   '2026-02-12 08:00:00+06', '14000', '183.00'),
    ('KazFuel Station #4', 'Euro Diesel', 'CaspianOil Trade',      '2026-02-18 10:00:00+06', '12000', '178.00'),
    ('KazFuel Station #5', 'Diesel',      'KazMunayGaz Supply',    '2026-03-03 09:00:00+06', '16000', '171.00'),
    ('KazFuel Station #5', 'LPG',         'EnergoFuel KZ',         '2026-03-10 11:00:00+06',  '9000',  '81.00'),
    ('KazFuel Station #6', 'Petrol 92',   'PetroKaz Ltd',          '2026-03-18 08:30:00+06', '20000', '159.00'),
    ('KazFuel Station #6', 'Petrol 98',   'AlmatyFuel Wholesale',  '2026-04-05 09:00:00+06',  '6000', '212.00')
) AS r(stn, fuel, sup, del_dt, qty, cost);


-- ── 9. sale  (18 rows, core transaction table) ───────────────
-- All FKs resolved via natural keys to avoid hardcoded IDs.
-- customer_id is nullable (NULL = anonymous walk-in customer).
INSERT INTO fuel_network.sale
    (station_id, fuel_type_id, customer_id, employee_id,
     sale_datetime, quantity_sold, unit_price, payment_method)
SELECT
    -- station
    (SELECT station_id   FROM fuel_network.fuel_station WHERE station_name = t.stn),
    -- fuel type
    (SELECT fuel_type_id FROM fuel_network.fuel_type    WHERE fuel_name    = t.fuel),
    -- customer (NULL-safe: CASE passes NULL through to the subquery)
    CASE WHEN t.cust IS NOT NULL
         THEN (SELECT customer_id FROM fuel_network.customer
               WHERE first_name || ' ' || last_name = t.cust)
    END,
    -- employee matched by full name AND station to avoid cross-station collision
    (SELECT e.employee_id
     FROM   fuel_network.employee     e
     JOIN   fuel_network.fuel_station fs ON fs.station_id = e.station_id
     WHERE  e.first_name || ' ' || e.last_name = t.emp
       AND  fs.station_name = t.stn),
    t.sale_dt::TIMESTAMPTZ,
    t.qty::NUMERIC(8,2),
    t.price::NUMERIC(8,2),
    t.payment
FROM (VALUES
    ('KazFuel Station #1','Petrol 92', 'Arman Bekuov',       'Nurlan Kasymov',    '2026-01-20 10:15:00+06','40.00','185.00','card'),
    ('KazFuel Station #1','Petrol 95', 'Dinara Seitkali',    'Nurlan Kasymov',    '2026-01-25 14:30:00+06','35.50','210.00','mobile'),
    ('KazFuel Station #1','Diesel',     NULL,                'Nurlan Kasymov',    '2026-02-03 08:45:00+06','50.00','195.00','cash'),
    ('KazFuel Station #2','Petrol 92', 'Ruslan Akhmetov',    'Dauren Seilov',     '2026-02-10 11:00:00+06','45.00','183.00','corporate_account'),
    ('KazFuel Station #2','LPG',       'Aizat Nurlanovna',   'Dauren Seilov',     '2026-02-15 16:20:00+06','60.00', '95.00','card'),
    ('KazFuel Station #2','Petrol 95', 'Serik Omarov',       'Dauren Seilov',     '2026-02-20 09:10:00+06','30.00','208.00','cash'),
    ('KazFuel Station #3','Diesel',    'Madina Zhumabek',    'Azamat Zhaksybekov','2026-03-01 07:30:00+06','80.00','196.00','corporate_account'),
    ('KazFuel Station #3','Petrol 98', 'Askar Tleubek',      'Azamat Zhaksybekov','2026-03-05 13:15:00+06','25.00','240.00','card'),
    ('KazFuel Station #3','Petrol 92', 'Gulnara Abdullayeva','Azamat Zhaksybekov','2026-03-10 10:00:00+06','38.00','186.00','mobile'),
    ('KazFuel Station #4','Euro Diesel','Arman Bekuov',      'Bekzat Abenov',     '2026-03-15 08:00:00+06','70.00','205.00','corporate_account'),
    ('KazFuel Station #4','Petrol 95', 'Dinara Seitkali',    'Bekzat Abenov',     '2026-03-20 15:45:00+06','28.00','209.00','card'),
    ('KazFuel Station #5','Diesel',    'Ruslan Akhmetov',    'Miras Suleimenov',  '2026-04-01 09:30:00+06','90.00','197.00','corporate_account'),
    ('KazFuel Station #5','LPG',        NULL,                'Miras Suleimenov',  '2026-04-05 11:00:00+06','55.00', '96.00','cash'),
    ('KazFuel Station #5','Petrol 95', 'Aizat Nurlanovna',   'Miras Suleimenov',  '2026-04-10 14:00:00+06','33.00','211.00','mobile'),
    ('KazFuel Station #6','Petrol 92', 'Serik Omarov',       'Erlan Tulegenov',   '2026-04-12 08:15:00+06','42.00','185.50','card'),
    ('KazFuel Station #6','Petrol 98', 'Madina Zhumabek',    'Erlan Tulegenov',   '2026-04-15 10:30:00+06','20.00','241.00','mobile'),
    ('KazFuel Station #1','Petrol 92', 'Askar Tleubek',      'Nurlan Kasymov',    '2026-04-18 16:45:00+06','37.00','185.00','card'),
    ('KazFuel Station #2','Petrol 92', 'Gulnara Abdullayeva','Dauren Seilov',     '2026-04-19 09:00:00+06','43.00','183.00','cash')
) AS t(stn, fuel, cust, emp, sale_dt, qty, price, payment);


-- ============================================================
-- SECTION 6 : FUNCTIONS
-- ============================================================

-- ── FUNCTION 5.1 : update_record ─────────────────────────────
-- Generic single-row update for any table in fuel_network.
-- Input : table name, PK integer value, column name, new value
-- Output: VOID  |  NOTICE on success, EXCEPTION on failure
--
-- Uses format() with %I (identifier quoting) and %L (literal
-- quoting) to prevent SQL injection in the dynamic statement.
-- The PK column name is discovered automatically from the
-- information_schema so the function works on any table.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fuel_network.update_record(
    p_table_name  TEXT,   -- table to update (inside fuel_network schema)
    p_pk_value    INT,    -- primary key value of the target row
    p_column_name TEXT,   -- column to update
    p_new_value   TEXT    -- new value (cast implicitly by PostgreSQL)
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_pk_col TEXT;
    v_sql    TEXT;
    v_rows   INT;
BEGIN
    -- ── Step 1: look up the primary key column name ──────────
    SELECT kcu.column_name
    INTO   v_pk_col
    FROM   information_schema.table_constraints  tc
    JOIN   information_schema.key_column_usage   kcu
           ON  kcu.constraint_name = tc.constraint_name
           AND kcu.table_schema    = tc.table_schema
    WHERE  tc.table_schema    = 'fuel_network'
      AND  tc.table_name      = p_table_name
      AND  tc.constraint_type = 'PRIMARY KEY'
    LIMIT  1;

    IF v_pk_col IS NULL THEN
        RAISE EXCEPTION
            'Table "fuel_network.%" not found or has no PRIMARY KEY.',
            p_table_name;
    END IF;

    -- ── Step 2: build and execute dynamic UPDATE ─────────────
    -- %I safely double-quotes identifiers (table/column names).
    -- %L safely single-quotes the literal value.
    v_sql := format(
        'UPDATE fuel_network.%I SET %I = %L WHERE %I = $1',
        p_table_name,
        p_column_name,
        p_new_value,
        v_pk_col
    );

    EXECUTE v_sql USING p_pk_value;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        RAISE EXCEPTION
            'No row found in "fuel_network.%" where % = %.',
            p_table_name, v_pk_col, p_pk_value;
    END IF;

    RAISE NOTICE
        'SUCCESS — Updated % row(s) in "fuel_network.%": column "%" set to "%".',
        v_rows, p_table_name, p_column_name, p_new_value;
END;
$$;

COMMENT ON FUNCTION fuel_network.update_record IS
    'Function 5.1 — Generic row-update for any table in fuel_network. '
    'Takes (table_name, pk_value, column_name, new_value). '
    'Discovers the PK column dynamically; uses format() for safe SQL injection prevention.';

-- Example:
-- SELECT fuel_network.update_record('fuel_station', 1, 'city', 'Almaty');
-- SELECT fuel_network.update_record('employee', 3, 'salary', '200000');


-- ── FUNCTION 5.2 : add_sale ───────────────────────────────────
-- Inserts a new sale (transaction) record using natural keys
-- (human-readable names) for all FK resolution — never raw IDs.
-- Validates station activity, employee assignment, and (when
-- provided) customer existence before inserting.
-- Returns the newly assigned sale_id.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fuel_network.add_sale(
    p_station_name      TEXT,
    p_fuel_name         TEXT,
    p_employee_fullname TEXT,                   -- 'FirstName LastName'
    p_sale_datetime     TIMESTAMPTZ,
    p_quantity_sold     NUMERIC,
    p_unit_price        NUMERIC,
    p_payment_method    TEXT,
    p_customer_fullname TEXT DEFAULT NULL       -- NULL = anonymous walk-in
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_station_id   INT;
    v_fuel_type_id INT;
    v_employee_id  INT;
    v_customer_id  INT;
    v_new_sale_id  INT;
BEGIN
    -- ── Resolve station (must be active) ────────────────────
    SELECT station_id
    INTO   v_station_id
    FROM   fuel_network.fuel_station
    WHERE  station_name = p_station_name
      AND  is_active    = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active station "%" not found.', p_station_name;
    END IF;

    -- ── Resolve fuel type ────────────────────────────────────
    SELECT fuel_type_id
    INTO   v_fuel_type_id
    FROM   fuel_network.fuel_type
    WHERE  fuel_name = p_fuel_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fuel type "%" not found.', p_fuel_name;
    END IF;

    -- ── Resolve employee (active, at this station) ───────────
    SELECT employee_id
    INTO   v_employee_id
    FROM   fuel_network.employee
    WHERE  first_name || ' ' || last_name = p_employee_fullname
      AND  station_id = v_station_id
      AND  is_active  = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Active employee "%" not found at station "%".',
            p_employee_fullname, p_station_name;
    END IF;

    -- ── Resolve customer (optional) ──────────────────────────
    IF p_customer_fullname IS NOT NULL THEN
        SELECT customer_id
        INTO   v_customer_id
        FROM   fuel_network.customer
        WHERE  first_name || ' ' || last_name = p_customer_fullname;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer "%" not found.', p_customer_fullname;
        END IF;
    ELSE
        v_customer_id := NULL;  -- walk-in / anonymous
    END IF;

    -- ── Insert the sale ──────────────────────────────────────
    INSERT INTO fuel_network.sale
        (station_id, fuel_type_id, customer_id, employee_id,
         sale_datetime, quantity_sold, unit_price, payment_method)
    VALUES
        (v_station_id, v_fuel_type_id, v_customer_id, v_employee_id,
         p_sale_datetime, p_quantity_sold, p_unit_price, p_payment_method)
    RETURNING sale_id INTO v_new_sale_id;

    RAISE NOTICE 'Sale recorded successfully. sale_id = %.', v_new_sale_id;
    RETURN v_new_sale_id;
END;
$$;

COMMENT ON FUNCTION fuel_network.add_sale IS
    'Function 5.2 — Inserts a new sale using natural keys for all FK resolution. '
    'Validates station activity, employee assignment, and optional customer existence. '
    'Returns the new sale_id.';

-- Example:
-- SELECT fuel_network.add_sale(
--     'KazFuel Station #1',  -- station
--     'Petrol 95',           -- fuel
--     'Nurlan Kasymov',      -- employee
--     NOW(),                 -- datetime
--     30.5,                  -- litres
--     210.00,                -- price per litre
--     'card',                -- payment method
--     'Arman Bekuov'         -- customer (or omit / NULL for walk-in)
-- );


-- ============================================================
-- SECTION 7 : VIEW — Quarterly Sales Analytics
--
-- Shows aggregated sales for the most recently recorded quarter.
-- The quarter boundary is computed dynamically from MAX(sale_datetime)
-- so the view auto-updates as new data arrives.
-- Surrogate keys (sale_id, station_id, fuel_type_id …) are excluded.
-- GROUP BY eliminates duplicate rows.
-- ============================================================

CREATE OR REPLACE VIEW fuel_network.v_quarterly_sales_analytics AS
WITH latest_quarter AS (
    -- Identify the quarter that contains the latest recorded sale.
    -- date_trunc('quarter', …) returns the first day of that quarter.
    SELECT
        date_trunc('quarter', MAX(sale_datetime))                        AS q_start,
        date_trunc('quarter', MAX(sale_datetime)) + INTERVAL '3 months'  AS q_end
    FROM fuel_network.sale
)
SELECT
    fs.station_name,
    fs.city,
    ft.fuel_name,
    ft.unit_of_measure,
    -- Display date in local Almaty time (UTC+5); no raw timestamps.
    TO_CHAR(s.sale_datetime AT TIME ZONE 'Asia/Almaty', 'YYYY-MM-DD') AS sale_date,
    s.payment_method,
    COUNT(DISTINCT s.sale_id)          AS transaction_count,
    SUM(s.quantity_sold)               AS total_litres_sold,
    ROUND(AVG(s.unit_price), 2)        AS avg_unit_price_kzt,
    SUM(s.total_amount)                AS total_revenue_kzt,
    -- Human-readable quarter label, e.g. '2026 Q2'
    TO_CHAR(lq.q_start, 'YYYY "Q"Q')  AS quarter_label
FROM   fuel_network.sale         s
JOIN   fuel_network.fuel_station fs  ON fs.station_id  = s.station_id
JOIN   fuel_network.fuel_type    ft  ON ft.fuel_type_id = s.fuel_type_id
CROSS JOIN latest_quarter        lq
WHERE  s.sale_datetime >= lq.q_start
  AND  s.sale_datetime <  lq.q_end
GROUP BY
    fs.station_name,
    fs.city,
    ft.fuel_name,
    ft.unit_of_measure,
    TO_CHAR(s.sale_datetime AT TIME ZONE 'Asia/Almaty', 'YYYY-MM-DD'),
    s.payment_method,
    lq.q_start
ORDER BY
    fs.station_name,
    sale_date,
    ft.fuel_name;

COMMENT ON VIEW fuel_network.v_quarterly_sales_analytics IS
    'Analytics for the most recently recorded quarter. '
    'Aggregates by station, city, fuel type, date, and payment method. '
    'Excludes all surrogate keys. Quarter boundary is computed dynamically.';

-- Usage:
-- SELECT * FROM fuel_network.v_quarterly_sales_analytics;


-- ============================================================
-- SECTION 8 : ROLE — Read-only Manager
--
-- Security best practices applied:
--   • LOGIN allowed (manager must be able to connect).
--   • NOSUPERUSER, NOCREATEDB, NOCREATEROLE: principle of least privilege.
--   • NOINHERIT: does not silently gain privileges from other roles.
--   • CONNECTION LIMIT 5: prevents resource exhaustion.
--   • Strong password: mixed-case, digits, special characters, 14+ chars.
--   • SELECT granted only — no INSERT / UPDATE / DELETE / DDL.
--   • ALTER DEFAULT PRIVILEGES ensures future tables are also read-only.
-- ============================================================

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fuel_station_manager') THEN
        EXECUTE 'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA fuel_network FROM fuel_station_manager';
        EXECUTE 'REVOKE ALL ON SCHEMA fuel_network FROM fuel_station_manager';
        DROP ROLE fuel_station_manager;
        RAISE NOTICE 'Existing role fuel_station_manager dropped (cleanup).';
    END IF;
END;
$$;

CREATE ROLE fuel_station_manager WITH
    LOGIN                   -- can connect to the database
    NOSUPERUSER             -- not a database superuser
    NOCREATEDB              -- cannot create databases
    NOCREATEROLE            -- cannot create or alter other roles
    NOINHERIT               -- does not inherit privileges from any group roles
    CONNECTION LIMIT 5      -- caps concurrent sessions to prevent resource abuse
    PASSWORD 'Mgr@KazFuel_2026!';  -- strong: 17 chars, upper+lower+digit+special

-- Allow the role to see inside the schema
GRANT USAGE ON SCHEMA fuel_network TO fuel_station_manager;

-- Grant read-only access to all current tables and views
GRANT SELECT ON ALL TABLES IN SCHEMA fuel_network TO fuel_station_manager;

-- Ensure future tables/views created in this schema are also readable
ALTER DEFAULT PRIVILEGES IN SCHEMA fuel_network
    GRANT SELECT ON TABLES TO fuel_station_manager;

COMMENT ON ROLE fuel_station_manager IS
    'Read-only role for station managers. '
    'Can log in and run SELECT on all fuel_network tables/views. '
    'Cannot modify data, schema objects, or create database resources.';

-- NOTE: Also run this (as superuser, in fuel_station_db context):
--   GRANT CONNECT ON DATABASE fuel_station_db TO fuel_station_manager;


-- ============================================================
-- SECTION 9 : QUICK VERIFICATION QUERIES (uncomment to run)
-- ============================================================

-- ── List all tables created ──────────────────────────────────
-- SELECT table_name
-- FROM   information_schema.tables
-- WHERE  table_schema = 'fuel_network'
-- ORDER  BY table_name;

-- ── Confirm row counts ───────────────────────────────────────
-- SELECT 'fuel_type'      AS tbl, COUNT(*) FROM fuel_network.fuel_type      UNION ALL
-- SELECT 'fuel_station',          COUNT(*) FROM fuel_network.fuel_station    UNION ALL
-- SELECT 'supplier',              COUNT(*) FROM fuel_network.supplier        UNION ALL
-- SELECT 'customer',              COUNT(*) FROM fuel_network.customer        UNION ALL
-- SELECT 'employee',              COUNT(*) FROM fuel_network.employee        UNION ALL
-- SELECT 'fuel_inventory',        COUNT(*) FROM fuel_network.fuel_inventory  UNION ALL
-- SELECT 'fuel_price',            COUNT(*) FROM fuel_network.fuel_price      UNION ALL
-- SELECT 'replenishment',         COUNT(*) FROM fuel_network.replenishment   UNION ALL
-- SELECT 'sale',                  COUNT(*) FROM fuel_network.sale;

-- ── View analytics for the most recent quarter ───────────────
-- SELECT * FROM fuel_network.v_quarterly_sales_analytics;

-- ── Test add_sale function ───────────────────────────────────
-- SELECT fuel_network.add_sale(
--     'KazFuel Station #1', 'Petrol 95', 'Nurlan Kasymov',
--     NOW(), 30.5, 210.00, 'card', 'Arman Bekuov'
-- );

-- ── Test update_record function ──────────────────────────────
-- SELECT fuel_network.update_record('fuel_station', 1, 'city', 'Almaty');
-- SELECT fuel_network.update_record('employee', 3, 'salary', '200000');

-- ── Inspect check constraints ────────────────────────────────
-- SELECT conname, conrelid::regclass, pg_get_constraintdef(oid)
-- FROM   pg_constraint
-- WHERE  contype = 'c'
--   AND  connamespace = 'fuel_network'::regnamespace
-- ORDER  BY conrelid::regclass::text, conname;

-- ── Confirm manager role ─────────────────────────────────────
-- SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolconnlimit
-- FROM   pg_roles
-- WHERE  rolname = 'fuel_station_manager';

-- ============================================================
-- Total tables : 9
-- Total check constraints : 10
-- Total sample rows : 104  (>= 36 required)
-- Functions : 2 (update_record, add_sale)
-- Views : 1 (v_quarterly_sales_analytics)
-- Roles : 1 (fuel_station_manager, read-only)
-- ============================================================