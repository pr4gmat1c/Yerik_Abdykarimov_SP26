-- =============================================================================
-- HOTEL BOOKING SYSTEM — Physical Database Implementation
-- Erik Abdykarimov
-- =============================================================================

-- -----------------------------------------------------------------------------
-- STEP 0: DATABASE & SCHEMA
-- -----------------------------------------------------------------------------

-- CREATE DATABASE hotel_booking_db;   -- <-- run separately in pgAdmin

CREATE SCHEMA IF NOT EXISTS hotel_booking;

-- Make every subsequent statement use this schema automatically
SET search_path TO hotel_booking;

-- =============================================================================
-- DDL ORDER EXPLANATION
-- If a child table is created before its parent, PostgreSQL raises:
--   ERROR: relation "<parent>" does not exist
-- Correct creation order (parent → child):
--   1. hotels
--   2. addresses, guests, room_types   (depend only on hotels / standalone)
--   3. staff                           (depends on hotels; self-ref manager)
--   4. rooms                           (depends on hotels + room_types)
--   5. bookings                        (depends on guests)
--   6. booking_rooms                   (depends on bookings + rooms)
--   7. payments                        (depends on bookings)
--   8. booking_status_history          (depends on bookings + staff)
--   9. reviews                         (depends on bookings + guests)
-- =============================================================================


-- =============================================================================
-- TABLE 1: HOTELS
-- Root / parent table — no foreign keys to other domain tables.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.hotels (
    hotel_id    SERIAL          PRIMARY KEY,

    -- VARCHAR(150): a bounded string prevents unbounded storage consumption.
    -- TEXT would allow unlimited-length hotel names, causing display/truncation
    -- issues in UIs and reports. CHAR wastes space by padding shorter names.
    -- Risk of wrong type: INT would be meaningless; TEXT without a length limit
    -- could store multi-megabyte strings.
    name        VARCHAR(150)    NOT NULL,

    -- SMALLINT (2 bytes) is sufficient for 1–5 star ratings.
    -- Using INT wastes 2 extra bytes per row; FLOAT would allow fractional
    -- ratings like 3.7, which is not the domain intent.
    -- Risk: TEXT allows '★★★' or letters, breaking any numeric aggregation.
    star_rating SMALLINT        DEFAULT 3,

    phone       VARCHAR(20)     NOT NULL,

    -- UNIQUE (constraint #4): enforces that no two hotels share an e-mail.
    -- Without UNIQUE: duplicate emails would cause ambiguous communications
    -- and failed JOIN lookups that assume email uniqueness.
    -- Risk of wrong type: TEXT without UNIQUE allows unlimited duplicates.
    email       VARCHAR(100)    NOT NULL    UNIQUE,

    -- TIMESTAMPTZ (timestamp with time zone) is preferred over TIMESTAMP
    -- because it stores the UTC offset, making the value unambiguous across
    -- time zones. Using DATE would lose the time component.
    -- Risk: VARCHAR would allow '2020-not-a-date' without error.
    created_at  TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    -- CONSTRAINT #3 (specific value — analogous to a gender enum):
    -- star_rating must be one of the five internationally recognised values.
    -- Without this: star_rating = 0 or 99 could be inserted, corrupting hotel
    -- ranking reports and customer-facing displays.
    CONSTRAINT chk_hotels_star_rating CHECK (star_rating BETWEEN 1 AND 5)
);


-- =============================================================================
-- TABLE 2: ADDRESSES
-- Depends on: HOTELS (one-to-one relationship).
-- FK behaviour: If hotel_id FK is missing, an address row could reference a
-- non-existent hotel, producing orphan records that corrupt any
-- address → hotel JOIN and make mailing/mapping impossible.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.addresses (
    address_id  SERIAL          PRIMARY KEY,

    -- FK to hotels. ON DELETE CASCADE: if a hotel is deleted, its address is
    -- automatically removed, preserving referential integrity automatically.
    hotel_id    INT             NOT NULL
                REFERENCES hotel_booking.hotels(hotel_id)
                ON DELETE CASCADE,

    street      VARCHAR(200)    NOT NULL,
    city        VARCHAR(100)    NOT NULL,
    country     VARCHAR(100)    NOT NULL,
    postal_code VARCHAR(20),

    -- UNIQUE on hotel_id enforces the one-to-one cardinality from the logical
    -- model. Without it, a hotel could have multiple address rows. (constraint #4)
    CONSTRAINT uq_addresses_hotel UNIQUE (hotel_id)
);


-- =============================================================================
-- TABLE 3: GUESTS
-- Standalone parent — no FK dependencies on other domain tables.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.guests (
    guest_id        SERIAL          PRIMARY KEY,
    first_name      VARCHAR(80)     NOT NULL,
    last_name       VARCHAR(80)     NOT NULL,

    -- UNIQUE + NOT NULL on email (constraints #4 & #5):
    -- email is the primary contact identifier used for booking confirmations.
    -- Without UNIQUE: two guests could share one email, making targeted
    -- communication and password-reset flows impossible.
    email           VARCHAR(150)    NOT NULL    UNIQUE,

    phone           VARCHAR(25),

    -- VARCHAR: passport numbers contain letters in many countries (e.g. 'AB1234567').
    -- Risk: using INT would silently reject or truncate alphabetic passports.
    passport_number VARCHAR(30)     UNIQUE,

    nationality     VARCHAR(60),

    -- GENERATED ALWAYS AS: full_name is always derived from first + last name.
    -- This guarantees consistency — no manual update required when name parts change.
    -- STORED: computed and saved on disk so it can be indexed.
    full_name       VARCHAR(201)    GENERATED ALWAYS AS
                        (first_name || ' ' || last_name) STORED,

    created_at      TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================================
-- TABLE 4: ROOM_TYPES
-- Depends on: HOTELS.
-- FK behaviour: If hotel_id FK is missing, room types could belong to a
-- non-existent hotel, making it impossible to determine pricing per hotel
-- or enforce that a hotel only offers its own room types.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.room_types (
    room_type_id    SERIAL          PRIMARY KEY,

    hotel_id        INT             NOT NULL
                    REFERENCES hotel_booking.hotels(hotel_id)
                    ON DELETE CASCADE,

    type_name       VARCHAR(80)     NOT NULL,

    -- NUMERIC(10,2): monetary value with exactly 2 decimal places.
    -- FLOAT/REAL uses IEEE 754 binary fractions, producing rounding errors like
    -- 199.9999999 instead of 200.00 — catastrophic in financial reporting.
    -- Risk: VARCHAR allows '200 KZT', breaking arithmetic aggregations.
    base_price      NUMERIC(10,2)   NOT NULL,

    max_occupancy   SMALLINT        NOT NULL,
    description     TEXT,

    -- CONSTRAINT #2 (non-negative numeric value):
    -- base_price must be strictly greater than zero. Without this, a data-entry
    -- error could store 0 or -5000, which would produce invalid invoice totals.
    CONSTRAINT chk_room_types_base_price    CHECK (base_price > 0),
    CONSTRAINT chk_room_types_occupancy     CHECK (max_occupancy >= 1)
);


-- =============================================================================
-- TABLE 5: STAFF
-- Depends on: HOTELS; self-referencing FK for manager hierarchy.
-- NOTE: 'namager_id' in the logical diagram is a typo — corrected to
-- 'manager_id' here. The data type and behaviour remain unchanged.
-- FK hotel_id: Without it, staff could belong to no hotel, making scheduling
-- and payroll impossible to link to a property.
-- FK manager_id: Self-referential. Without it, manager_id values could point
-- to non-existent staff IDs, silently corrupting the org-chart hierarchy.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.staff (
    staff_id    SERIAL          PRIMARY KEY,

    hotel_id    INT             NOT NULL
                REFERENCES hotel_booking.hotels(hotel_id)
                ON DELETE RESTRICT,

    first_name  VARCHAR(80)     NOT NULL,
    last_name   VARCHAR(80)     NOT NULL,

    -- VARCHAR(60) with CHECK: role names are short, bounded strings.
    role        VARCHAR(60)     NOT NULL,

    email       VARCHAR(150)    NOT NULL    UNIQUE,
    phone       VARCHAR(25),

    -- Self-referencing FK: a manager is also a staff member.
    -- NULL means top-level (no manager). ON DELETE SET NULL: if a manager
    -- leaves, subordinates become top-level rather than being deleted.
    manager_id  INT
                REFERENCES hotel_booking.staff(staff_id)
                ON DELETE SET NULL,

    -- CONSTRAINT #3 (specific value — analogous to gender enum):
    -- role must be one of the five defined values.
    -- Without this: 'ninja' or 'boss' could be inserted, breaking
    -- role-based access control and shift scheduling logic.
    CONSTRAINT chk_staff_role CHECK (
        role IN ('manager', 'receptionist', 'housekeeper', 'maintenance', 'chef')
    )
);


-- =============================================================================
-- TABLE 6: ROOMS
-- Depends on: HOTELS, ROOM_TYPES.
-- FK hotel_id: Without it, a room could reference a non-existent hotel,
-- making check-in assignment and housekeeping routing impossible.
-- FK room_type_id: Without it, pricing, occupancy limits, and amenity info
-- attached to the room type would be permanently lost.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.rooms (
    room_id         SERIAL          PRIMARY KEY,

    hotel_id        INT             NOT NULL
                    REFERENCES hotel_booking.hotels(hotel_id)
                    ON DELETE CASCADE,

    room_type_id    INT             NOT NULL
                    REFERENCES hotel_booking.room_types(room_type_id)
                    ON DELETE RESTRICT,

    -- VARCHAR(10): room numbers are alphanumeric in many hotels (e.g. 'PH1', '2A').
    -- Risk: INT would silently reject or misinterpret alphanumeric room numbers.
    room_number     VARCHAR(10)     NOT NULL,

    floor           SMALLINT,

    -- DEFAULT 'available': new rooms start as available by convention.
    status          VARCHAR(20)     NOT NULL    DEFAULT 'available',

    -- CONSTRAINT #3 (specific value):
    -- status must be one of the three operational states.
    -- Without this: 'broken' or 'unknown' could enter the system and prevent
    -- the booking engine from correctly filtering available rooms.
    CONSTRAINT chk_rooms_status CHECK (
        status IN ('available', 'occupied', 'maintenance')
    ),

    -- Composite UNIQUE: a room number must be unique within a hotel. (constraint #4)
    CONSTRAINT uq_rooms_hotel_number UNIQUE (hotel_id, room_number)
);


-- =============================================================================
-- TABLE 7: BOOKINGS
-- Depends on: GUESTS.
-- FK guest_id: Without it, a booking has no identifiable guest, making
-- check-in procedures and revenue attribution completely impossible.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.bookings (
    booking_id      SERIAL          PRIMARY KEY,

    guest_id        INT             NOT NULL
                    REFERENCES hotel_booking.guests(guest_id)
                    ON DELETE RESTRICT,

    check_in_date   DATE            NOT NULL,
    check_out_date  DATE            NOT NULL,

    total_price     NUMERIC(10,2)   NOT NULL    DEFAULT 0.00,

    created_at      TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    -- CONSTRAINT #1 (date > January 1, 2000):
    -- Prevents erroneous historical dates (e.g. '1900-01-01' from defaults or
    -- bad imports) from entering the system and corrupting date-range analytics.
    CONSTRAINT chk_bookings_checkin_date    CHECK (check_in_date  > '2000-01-01'),
    CONSTRAINT chk_bookings_checkout_date   CHECK (check_out_date > '2000-01-01'),

    -- Business rule: checkout must be strictly after check-in.
    CONSTRAINT chk_bookings_date_order      CHECK (check_out_date > check_in_date),

    -- CONSTRAINT #2 (non-negative numeric value):
    -- total_price cannot be negative. Without this, refund bugs or manual
    -- overrides could store negative balances, breaking revenue reports.
    CONSTRAINT chk_bookings_total_price     CHECK (total_price >= 0)
);


-- =============================================================================
-- TABLE 8: BOOKING_ROOMS  (many-to-many resolver: BOOKINGS ↔ ROOMS)
-- Depends on: BOOKINGS, ROOMS.
-- FK booking_id: Without it, room assignments become orphaned — we lose which
-- stay the room was reserved for, making housekeeping planning impossible.
-- FK room_id: Without it, we lose the physical room identity — overbooking
-- detection and room-level revenue tracking both fail.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.booking_rooms (
    booking_room_id SERIAL          PRIMARY KEY,

    booking_id      INT             NOT NULL
                    REFERENCES hotel_booking.bookings(booking_id)
                    ON DELETE CASCADE,

    room_id         INT             NOT NULL
                    REFERENCES hotel_booking.rooms(room_id)
                    ON DELETE RESTRICT,

    price_per_night NUMERIC(10,2)   NOT NULL,

    CONSTRAINT chk_booking_rooms_price CHECK (price_per_night >= 0),

    -- Prevent the same room from appearing twice in one booking. (constraint #4)
    CONSTRAINT uq_booking_room UNIQUE (booking_id, room_id)
);


-- =============================================================================
-- TABLE 9: PAYMENTS
-- Depends on: BOOKINGS.
-- FK booking_id: Without it, payments are unlinked from their booking,
-- making revenue reconciliation, refunds, and invoicing impossible.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.payments (
    payment_id      SERIAL          PRIMARY KEY,

    booking_id      INT             NOT NULL
                    REFERENCES hotel_booking.bookings(booking_id)
                    ON DELETE RESTRICT,

    amount          NUMERIC(10,2)   NOT NULL,
    payment_method  VARCHAR(30)     NOT NULL,
    payment_date    TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    -- UNIQUE: each transaction must have its own reference number. (constraint #4)
    -- Without UNIQUE: duplicate transaction_refs could hide double-charges.
    transaction_ref VARCHAR(100)    UNIQUE,

    -- CONSTRAINT #2 (non-negative numeric value):
    -- Payment amount must be strictly greater than zero — zero payments are
    -- meaningless records; refunds are handled as separate entries.
    CONSTRAINT chk_payments_amount CHECK (amount > 0),

    -- CONSTRAINT #3 (specific value):
    -- Only these five payment methods are accepted by the business.
    -- Without this: 'barter' or 'crypto' could appear, breaking accounting.
    CONSTRAINT chk_payments_method CHECK (
        payment_method IN ('cash', 'credit_card', 'debit_card', 'bank_transfer', 'online')
    )
);


-- =============================================================================
-- TABLE 10: BOOKING_STATUS_HISTORY
-- Depends on: BOOKINGS, STAFF.
-- FK booking_id: Without it, status-change records are orphaned — the audit
-- trail becomes useless and dispute resolution fails.
-- FK changed_by: Without it, we cannot identify which staff member made the
-- status change, violating audit and compliance requirements.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.booking_status_history (
    status_history_id   SERIAL          PRIMARY KEY,

    booking_id          INT             NOT NULL
                        REFERENCES hotel_booking.bookings(booking_id)
                        ON DELETE CASCADE,

    status              VARCHAR(30)     NOT NULL,

    changed_at          TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    -- NULLABLE: top-level status changes (e.g. system-generated 'pending' on
    -- booking creation) may not have an identifiable staff member responsible.
    -- Without allowing NULL: automatic or guest-triggered status events could
    -- not be recorded, breaking the complete audit trail.
    changed_by          INT
                        REFERENCES hotel_booking.staff(staff_id)
                        ON DELETE RESTRICT,

    -- CONSTRAINT #3 (specific value):
    -- Booking lifecycle must follow a controlled set of states.
    -- Without this: 'unknown' or 'deleted' could be stored, breaking the
    -- booking workflow engine and customer notification triggers.
    CONSTRAINT chk_status_history_status CHECK (
        status IN ('pending', 'confirmed', 'checked_in', 'checked_out', 'cancelled')
    )
);


-- =============================================================================
-- TABLE 11: REVIEWS
-- Depends on: BOOKINGS, GUESTS.
-- FK booking_id: Without it, we cannot verify the reviewer actually completed
-- a stay — fake or manipulated reviews become impossible to detect.
-- FK guest_id: Without it, reviews are anonymous, preventing platform
-- credibility enforcement and GDPR deletion requests.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hotel_booking.reviews (
    review_id   SERIAL          PRIMARY KEY,

    booking_id  INT             NOT NULL
                REFERENCES hotel_booking.bookings(booking_id)
                ON DELETE CASCADE,

    guest_id    INT             NOT NULL
                REFERENCES hotel_booking.guests(guest_id)
                ON DELETE RESTRICT,

    -- SMALLINT: ratings are whole numbers 1–5. FLOAT allows 3.7 (not the domain
    -- intent); TEXT prevents mathematical aggregation (AVG, etc.).
    -- Risk: INT without a CHECK allows 0 or 999, skewing hotel averages.
    rating      SMALLINT        NOT NULL,

    comment     TEXT,

    created_at  TIMESTAMPTZ     NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    -- CONSTRAINT #2 + specific range: rating must be 1–5.
    -- Without this: a rating of 0 or 100 would corrupt hotel scoring averages.
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),

    -- One review per booking (not per booking+guest): a booking has exactly one
    -- reviewer. Composite UNIQUE(booking_id, guest_id) would allow the same
    -- guest to review different bookings freely, but booking_id alone ensures
    -- only one review exists per stay event, preventing review farming. (constraint #4)
    CONSTRAINT uq_reviews_booking UNIQUE (booking_id)
);


-- =============================================================================
-- SAMPLE DATA
-- Strategy for consistency and rerunability:
--   • All values match the example data from the logical model document exactly.
--   • Parent rows inserted before child rows (matches DDL order above).
--   • ON CONFLICT DO NOTHING on UNIQUE columns prevents duplicate errors.
--   • INSERT … SELECT … WHERE NOT EXISTS used where no UNIQUE column is
--     available to target with ON CONFLICT.
--   • FK values resolved via JOIN on natural keys (emails, room numbers) so
--     auto-generated serial IDs need not be hard-coded (avoids hardcoding).
--   • All relationships are preserved: every child row references a parent
--     that was inserted in the same script run.
-- Total rows: 2+2+2+2+2+2+2+2+2+3+2 = 25
-- =============================================================================

-- --------------------------------------------------
-- HOTELS  (2 rows)
-- Source: logical model document, Table HOTELS example data.
-- --------------------------------------------------
INSERT INTO hotel_booking.hotels
    (name,               star_rating, phone,              email,                  created_at)
VALUES
    ('Grand Palace Hotel', 5,         '+7 727 333 4455',  'info@grandpalace.kz',  '2024-01-10 09:00:00+06'),
    ('City Inn Almaty',    3,         '+7 727 222 9988',  'booking@cityinn.kz',   '2024-03-01 12:00:00+06')
ON CONFLICT (email) DO NOTHING;

-- --------------------------------------------------
-- ADDRESSES  (2 rows)
-- Resolved via hotel email to avoid hardcoding IDs.
-- Source: logical model document, Table ADDRESSES example data.
-- --------------------------------------------------
INSERT INTO hotel_booking.addresses
    (hotel_id, street,        city,   country,    postal_code)
SELECT
    h.hotel_id,
    a.street,
    a.city,
    a.country,
    a.postal_code
FROM (VALUES
    ('info@grandpalace.kz', '77 Dostyk Ave', 'Almaty', 'Kazakhstan', '050010'),
    ('booking@cityinn.kz',  '12 Alatau St',  'Almaty', 'Kazakhstan', '050020')
) AS a(hotel_email, street, city, country, postal_code)
JOIN hotel_booking.hotels h ON h.email = a.hotel_email
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.addresses ad
    WHERE ad.hotel_id = h.hotel_id
);

-- --------------------------------------------------
-- GUESTS  (2 rows)
-- Source: logical model document, Table GUESTS example data.
-- --------------------------------------------------
INSERT INTO hotel_booking.guests
    (first_name, last_name,      email,             phone,            passport_number, nationality,   created_at)
VALUES
    ('Aibek',    'Nurmagambetov','aibek@mail.kz',   '+7 701 123 4567','N12345678',     'Kazakhstani', '2024-06-01 00:00:00+06'),
    ('Maria',    'Schmidt',      'maria@email.de',  '+49 151 9999',   'C98765432',     'German',      '2024-08-14 00:00:00+06')
ON CONFLICT (email) DO NOTHING;

-- --------------------------------------------------
-- ROOM_TYPES  (2 rows — both for Grand Palace Hotel)
-- Source: logical model document, Table ROOM_TYPES example data.
-- --------------------------------------------------
INSERT INTO hotel_booking.room_types
    (hotel_id, type_name,         base_price, max_occupancy, description)
SELECT
    h.hotel_id,
    rt.type_name,
    rt.base_price,
    rt.max_occupancy,
    rt.description
FROM (VALUES
    ('info@grandpalace.kz', 'Standard Single', 85.00,  1, 'Cozy room with city view'),
    ('info@grandpalace.kz', 'Deluxe Double',   150.00, 2, 'Spacious room, king-size bed')
) AS rt(hotel_email, type_name, base_price, max_occupancy, description)
JOIN hotel_booking.hotels h ON h.email = rt.hotel_email
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.room_types r
    WHERE r.hotel_id = h.hotel_id AND r.type_name = rt.type_name
);

-- --------------------------------------------------
-- STAFF  (2 rows — both for Grand Palace Hotel)
-- Manager is inserted first (manager_id = NULL) so the ID exists when
-- the subordinate row is inserted. Avoids FK violation in the same batch.
-- Source: logical model document, Table STAFF example data.
-- Role 'General Manager' mapped to 'manager' to satisfy the CHECK constraint.
-- --------------------------------------------------
-- Manager first
INSERT INTO hotel_booking.staff
    (hotel_id, first_name, last_name, role,      email,                    phone,          manager_id)
SELECT
    h.hotel_id,
    'Daniyar', 'Seitkali', 'manager', 'daniyar@grandpalace.kz', '+7 701 111 12 34', NULL
FROM hotel_booking.hotels h
WHERE h.email = 'info@grandpalace.kz'
  AND NOT EXISTS (
    SELECT 1 FROM hotel_booking.staff st WHERE st.email = 'daniyar@grandpalace.kz'
);

-- Subordinate — references Daniyar as manager by email lookup
INSERT INTO hotel_booking.staff
    (hotel_id, first_name, last_name, role,            email,                  phone,          manager_id)
SELECT
    h.hotel_id,
    'Assel', 'Bekova', 'receptionist', 'assel@grandpalace.kz', '+7 701 222 43 21', mgr.staff_id
FROM hotel_booking.hotels h
JOIN hotel_booking.staff  mgr ON mgr.email = 'daniyar@grandpalace.kz'
WHERE h.email = 'info@grandpalace.kz'
  AND NOT EXISTS (
    SELECT 1 FROM hotel_booking.staff st WHERE st.email = 'assel@grandpalace.kz'
);

-- --------------------------------------------------
-- ROOMS  (2 rows — both for Grand Palace Hotel)
-- Source: logical model document, Table ROOMS example data.
-- Room 101 = Standard Single (floor 1, available)
-- Room 201 = Deluxe Double   (floor 2, occupied)
-- --------------------------------------------------
INSERT INTO hotel_booking.rooms
    (hotel_id, room_type_id, room_number, floor, status)
SELECT
    h.hotel_id,
    rt.room_type_id,
    r.room_number,
    r.floor,
    r.status
FROM (VALUES
    ('info@grandpalace.kz', 'Standard Single', '101', 1, 'available'),
    ('info@grandpalace.kz', 'Deluxe Double',   '201', 2, 'occupied')
) AS r(hotel_email, type_name, room_number, floor, status)
JOIN hotel_booking.hotels     h  ON h.email     = r.hotel_email
JOIN hotel_booking.room_types rt ON rt.hotel_id = h.hotel_id AND rt.type_name = r.type_name
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.rooms rm
    WHERE rm.hotel_id = h.hotel_id AND rm.room_number = r.room_number
);

-- --------------------------------------------------
-- BOOKINGS  (2 rows)
-- Source: logical model document, Table BOOKINGS example data.
-- total_price for booking 1 = 600.00 (two card payments: 200 + 400).
-- total_price for booking 2 = 300.00 (single payment).
-- --------------------------------------------------
INSERT INTO hotel_booking.bookings
    (guest_id, check_in_date,  check_out_date, total_price, created_at)
SELECT
    g.guest_id,
    b.check_in_date::DATE,
    b.check_out_date::DATE,
    b.total_price,
    b.created_at::TIMESTAMPTZ
FROM (VALUES
    ('aibek@mail.kz',  '2025-03-10', '2025-03-14', 600.00, '2025-02-20 14:00:00+06'),
    ('maria@email.de', '2025-04-01', '2025-04-03', 300.00, '2025-03-05 10:30:00+06')
) AS b(guest_email, check_in_date, check_out_date, total_price, created_at)
JOIN hotel_booking.guests g ON g.email = b.guest_email
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.bookings bk
    WHERE bk.guest_id = g.guest_id
      AND bk.check_in_date = b.check_in_date::DATE
);

-- --------------------------------------------------
-- BOOKING_ROOMS  (2 rows)
-- Source: logical model document, Table BOOKING_ROOMS example data.
-- Booking 1 (Aibek)  → room 201 (Deluxe Double)   at 150.00 / night
-- Booking 2 (Maria)  → room 101 (Standard Single)  at  85.00 / night
-- --------------------------------------------------
INSERT INTO hotel_booking.booking_rooms
    (booking_id, room_id, price_per_night)
SELECT
    bk.booking_id,
    rm.room_id,
    br.price_per_night
FROM (VALUES
    ('aibek@mail.kz',  '2025-03-10'::DATE, 'info@grandpalace.kz', '201', 150.00),
    ('maria@email.de', '2025-04-01'::DATE, 'info@grandpalace.kz', '101',  85.00)
) AS br(guest_email, check_in_date, hotel_email, room_number, price_per_night)
JOIN hotel_booking.guests   g  ON g.email         = br.guest_email
JOIN hotel_booking.bookings bk ON bk.guest_id     = g.guest_id
                               AND bk.check_in_date = br.check_in_date
JOIN hotel_booking.hotels   h  ON h.email         = br.hotel_email
JOIN hotel_booking.rooms    rm ON rm.hotel_id     = h.hotel_id
                               AND rm.room_number  = br.room_number
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.booking_rooms b
    WHERE b.booking_id = bk.booking_id AND b.room_id = rm.room_id
);

-- --------------------------------------------------
-- PAYMENTS  (2 rows — both for Booking 1 / Aibek)
-- Source: logical model document, Table PAYMENTS example data.
-- Deposit of 200.00 paid on confirmation; balance of 400.00 paid at check-in.
-- ON CONFLICT on transaction_ref (UNIQUE) prevents duplicate payment records.
-- --------------------------------------------------
INSERT INTO hotel_booking.payments
    (booking_id, amount, payment_method, payment_date,               transaction_ref)
SELECT
    bk.booking_id,
    p.amount,
    p.payment_method,
    p.payment_date::TIMESTAMPTZ,
    p.transaction_ref
FROM (VALUES
    ('aibek@mail.kz', '2025-03-10'::DATE, 200.00, 'credit_card', '2025-02-21 09:15:00+06', 'TXN-20250221-001'),
    ('aibek@mail.kz', '2025-03-10'::DATE, 400.00, 'credit_card', '2025-03-10 14:45:00+06', 'TXN-20250310-002')
) AS p(guest_email, check_in_date, amount, payment_method, payment_date, transaction_ref)
JOIN hotel_booking.guests   g  ON g.email       = p.guest_email
JOIN hotel_booking.bookings bk ON bk.guest_id   = g.guest_id
                               AND bk.check_in_date = p.check_in_date
ON CONFLICT (transaction_ref) DO NOTHING;

-- --------------------------------------------------
-- BOOKING_STATUS_HISTORY  (3 rows — all for Booking 1 / Aibek)
-- Source: logical model document, Table BOOKING_STATUS_HISTORY example data.
-- Row 1: 'pending'    — system-generated at booking creation; changed_by = NULL.
-- Row 2: 'confirmed'  — actioned by Daniyar (General Manager).
-- Row 3: 'checked_in' — actioned by Assel (Receptionist) at arrival.
-- changed_by is NULLABLE: automatic status transitions have no staff owner.
-- --------------------------------------------------
-- Pending row — no staff reference
INSERT INTO hotel_booking.booking_status_history
    (booking_id, status,    changed_at,               changed_by)
SELECT
    bk.booking_id,
    'pending',
    '2025-02-20 14:00:00+06'::TIMESTAMPTZ,
    NULL
FROM hotel_booking.guests   g
JOIN hotel_booking.bookings bk ON bk.guest_id     = g.guest_id
                               AND bk.check_in_date = '2025-03-10'::DATE
WHERE g.email = 'aibek@mail.kz'
  AND NOT EXISTS (
    SELECT 1 FROM hotel_booking.booking_status_history bsh
    WHERE bsh.booking_id = bk.booking_id AND bsh.status = 'pending'
);

-- Staff-actioned status changes
INSERT INTO hotel_booking.booking_status_history
    (booking_id, status,      changed_at,               changed_by)
SELECT
    bk.booking_id,
    h.status,
    h.changed_at::TIMESTAMPTZ,
    st.staff_id
FROM (VALUES
    ('aibek@mail.kz', '2025-03-10'::DATE, 'confirmed',  '2025-02-21 09:00:00+06', 'daniyar@grandpalace.kz'),
    ('aibek@mail.kz', '2025-03-10'::DATE, 'checked_in', '2025-03-10 14:30:00+06', 'assel@grandpalace.kz')
) AS h(guest_email, check_in_date, status, changed_at, staff_email)
JOIN hotel_booking.guests   g  ON g.email       = h.guest_email
JOIN hotel_booking.bookings bk ON bk.guest_id   = g.guest_id
                               AND bk.check_in_date = h.check_in_date
JOIN hotel_booking.staff    st ON st.email      = h.staff_email
WHERE NOT EXISTS (
    SELECT 1 FROM hotel_booking.booking_status_history bsh
    WHERE bsh.booking_id = bk.booking_id AND bsh.status = h.status
);

-- --------------------------------------------------
-- REVIEWS  (2 rows)
-- Source: logical model document, Table REVIEWS example data.
-- ON CONFLICT on UNIQUE (booking_id): one review per booking.
-- --------------------------------------------------
INSERT INTO hotel_booking.reviews
    (booking_id, guest_id, rating, comment,                                        created_at)
SELECT
    bk.booking_id,
    g.guest_id,
    r.rating,
    r.comment,
    r.created_at::TIMESTAMPTZ
FROM (VALUES
    ('aibek@mail.kz',  '2025-03-10'::DATE, 5, 'Excellent service and beautiful room!',       '2025-03-15 10:00:00+06'),
    ('maria@email.de', '2025-04-01'::DATE, 4, 'Very comfortable, clean, good breakfast.',    '2025-04-04 08:30:00+06')
) AS r(guest_email, check_in_date, rating, comment, created_at)
JOIN hotel_booking.guests   g  ON g.email       = r.guest_email
JOIN hotel_booking.bookings bk ON bk.guest_id   = g.guest_id
                               AND bk.check_in_date = r.check_in_date
ON CONFLICT (booking_id) DO NOTHING;


-- =============================================================================
-- STEP: Add record_ts to every table via ALTER TABLE
-- NOT NULL + DEFAULT CURRENT_DATE:
--   • New rows always receive today's date automatically.
--   • The DEFAULT also backfills all existing rows created above when the
--     column is first added, so NOT NULL is satisfied without manual UPDATEs.
-- IF NOT EXISTS: makes the statement safe to rerun without errors.
-- =============================================================================

ALTER TABLE hotel_booking.hotels
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.addresses
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.guests
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.room_types
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.staff
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.rooms
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.bookings
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.booking_rooms
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.payments
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.booking_status_history
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

ALTER TABLE hotel_booking.reviews
    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;


-- =============================================================================
-- VERIFICATION: confirm record_ts is set for every row in every table
-- Expected output: 2+2+2+2+2+2+2+2+2+3+2 = 25 total rows across 11 tables.
-- =============================================================================
SELECT 'hotels'                   AS table_name, COUNT(*) AS rows_with_record_ts
  FROM hotel_booking.hotels                  WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'addresses',                           COUNT(*)
  FROM hotel_booking.addresses               WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'guests',                              COUNT(*)
  FROM hotel_booking.guests                  WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'room_types',                          COUNT(*)
  FROM hotel_booking.room_types              WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'staff',                               COUNT(*)
  FROM hotel_booking.staff                   WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'rooms',                               COUNT(*)
  FROM hotel_booking.rooms                   WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'bookings',                            COUNT(*)
  FROM hotel_booking.bookings                WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'booking_rooms',                       COUNT(*)
  FROM hotel_booking.booking_rooms           WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'payments',                            COUNT(*)
  FROM hotel_booking.payments                WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'booking_status_history',              COUNT(*)
  FROM hotel_booking.booking_status_history  WHERE record_ts IS NOT NULL
UNION ALL
SELECT 'reviews',                             COUNT(*)
  FROM hotel_booking.reviews                 WHERE record_ts IS NOT NULL
ORDER BY table_name;