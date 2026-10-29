-- =====================================================================
-- Library Management Database (PostgreSQL 12+)
-- Books, users, and issue/return transactions.
--
-- Run:  psql -d <your_db> -f library_db.sql
--
-- RELATIONSHIPS
--   categories 1 ──< books >──< book_authors >── authors     (book <-> author is many-to-many)
--   books      1 ──< book_copies                             (one title, many physical copies)
--   users      1 ──< transactions >── 1 book_copies          (a transaction = one copy issued to one user)
--   transactions 1 ──0..1 fines                              (a late return produces at most one fine)
-- =====================================================================

DROP TABLE IF EXISTS fines, transactions, book_copies, book_authors,
                     books, authors, categories, users CASCADE;

-- ---------------------------------------------------------------------
-- 1. SCHEMA
-- ---------------------------------------------------------------------

CREATE TABLE categories (
    category_id  SERIAL       PRIMARY KEY,
    name         VARCHAR(60)  NOT NULL UNIQUE
);

CREATE TABLE authors (
    author_id    SERIAL       PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL
);

CREATE TABLE books (               -- the "title" (catalogue entry)
    book_id       SERIAL       PRIMARY KEY,
    isbn          VARCHAR(17)  NOT NULL UNIQUE,
    title         VARCHAR(200) NOT NULL,
    publisher     VARCHAR(100),
    publish_year  INT          CHECK (publish_year BETWEEN 1400 AND 2100),
    category_id   INT          REFERENCES categories(category_id) ON DELETE SET NULL
);

CREATE TABLE book_authors (        -- resolves the many-to-many between books and authors
    book_id    INT NOT NULL REFERENCES books(book_id)    ON DELETE CASCADE,
    author_id  INT NOT NULL REFERENCES authors(author_id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE book_copies (         -- the physical copies that actually get issued
    copy_id   SERIAL      PRIMARY KEY,
    book_id   INT         NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    barcode   VARCHAR(30) NOT NULL UNIQUE,
    status    VARCHAR(10) NOT NULL DEFAULT 'AVAILABLE'
              CHECK (status IN ('AVAILABLE', 'ISSUED', 'LOST', 'DAMAGED'))
);

CREATE TABLE users (
    user_id    SERIAL       PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL,
    email      VARCHAR(120) NOT NULL UNIQUE,
    phone      VARCHAR(20),
    role       VARCHAR(10)  NOT NULL DEFAULT 'STUDENT'
               CHECK (role IN ('STUDENT', 'FACULTY', 'STAFF')),
    max_books  INT          NOT NULL DEFAULT 3 CHECK (max_books > 0),
    status     VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE'
               CHECK (status IN ('ACTIVE', 'SUSPENDED')),
    joined_on  DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE transactions (        -- one row per issue; return_date IS NULL means "still out"
    txn_id       SERIAL  PRIMARY KEY,
    copy_id      INT     NOT NULL REFERENCES book_copies(copy_id),
    user_id      INT     NOT NULL REFERENCES users(user_id),
    issue_date   DATE    NOT NULL DEFAULT CURRENT_DATE,
    due_date     DATE    NOT NULL,
    return_date  DATE,
    CONSTRAINT chk_due_after_issue    CHECK (due_date >= issue_date),
    CONSTRAINT chk_return_after_issue CHECK (return_date IS NULL OR return_date >= issue_date)
);

-- Database-level guarantee: a copy can have at most ONE open (unreturned) transaction.
CREATE UNIQUE INDEX uq_one_open_loan_per_copy
    ON transactions (copy_id) WHERE return_date IS NULL;

CREATE INDEX idx_txn_user ON transactions (user_id);
CREATE INDEX idx_txn_open_due ON transactions (due_date) WHERE return_date IS NULL;
CREATE INDEX idx_copies_book ON book_copies (book_id);

CREATE TABLE fines (
    fine_id  SERIAL        PRIMARY KEY,
    txn_id   INT           NOT NULL UNIQUE REFERENCES transactions(txn_id),
    amount   NUMERIC(8,2)  NOT NULL CHECK (amount > 0),
    paid     BOOLEAN       NOT NULL DEFAULT FALSE,
    paid_on  DATE,
    CONSTRAINT chk_paid_date CHECK ((paid AND paid_on IS NOT NULL) OR (NOT paid AND paid_on IS NULL))
);

-- ---------------------------------------------------------------------
-- 2. ISSUE / RETURN LOGIC (functions run atomically inside one transaction)
-- ---------------------------------------------------------------------

-- Issue a copy to a user. Returns the new txn_id, or raises an error explaining why not.
CREATE OR REPLACE FUNCTION issue_book(
    p_user_id INT,
    p_copy_id INT,
    p_loan_days INT DEFAULT 14
) RETURNS INT AS $$
DECLARE
    v_user     users%ROWTYPE;
    v_status   TEXT;
    v_open     INT;
    v_unpaid   NUMERIC;
    v_txn_id   INT;
BEGIN
    SELECT * INTO v_user FROM users WHERE user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % does not exist', p_user_id;
    END IF;
    IF v_user.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'User % is suspended', p_user_id;
    END IF;

    -- Lock the copy row so two librarians cannot issue the same copy at once.
    SELECT status INTO v_status FROM book_copies WHERE copy_id = p_copy_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy % does not exist', p_copy_id;
    END IF;
    IF v_status <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'Copy % is not available (status: %)', p_copy_id, v_status;
    END IF;

    SELECT COUNT(*) INTO v_open
    FROM transactions WHERE user_id = p_user_id AND return_date IS NULL;
    IF v_open >= v_user.max_books THEN
        RAISE EXCEPTION 'User % has reached the borrowing limit (%)', p_user_id, v_user.max_books;
    END IF;

    SELECT COALESCE(SUM(f.amount), 0) INTO v_unpaid
    FROM fines f JOIN transactions t ON t.txn_id = f.txn_id
    WHERE t.user_id = p_user_id AND NOT f.paid;
    IF v_unpaid > 0 THEN
        RAISE EXCEPTION 'User % has unpaid fines of %', p_user_id, v_unpaid;
    END IF;

    INSERT INTO transactions (copy_id, user_id, issue_date, due_date)
    VALUES (p_copy_id, p_user_id, CURRENT_DATE, CURRENT_DATE + p_loan_days)
    RETURNING txn_id INTO v_txn_id;

    UPDATE book_copies SET status = 'ISSUED' WHERE copy_id = p_copy_id;
    RETURN v_txn_id;
END;
$$ LANGUAGE plpgsql;

-- Return a copy. Closes the open transaction, frees the copy, and records a fine if late.
-- Returns the fine amount (0 if on time).
CREATE OR REPLACE FUNCTION return_book(
    p_copy_id      INT,
    p_return_date  DATE    DEFAULT CURRENT_DATE,
    p_fine_per_day NUMERIC DEFAULT 2.00
) RETURNS NUMERIC AS $$
DECLARE
    v_txn   transactions%ROWTYPE;
    v_fine  NUMERIC := 0;
BEGIN
    SELECT * INTO v_txn FROM transactions
    WHERE copy_id = p_copy_id AND return_date IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Copy % has no open transaction (it is not issued)', p_copy_id;
    END IF;

    UPDATE transactions SET return_date = p_return_date WHERE txn_id = v_txn.txn_id;
    UPDATE book_copies  SET status = 'AVAILABLE'        WHERE copy_id = p_copy_id;

    IF p_return_date > v_txn.due_date THEN
        v_fine := (p_return_date - v_txn.due_date) * p_fine_per_day;
        INSERT INTO fines (txn_id, amount) VALUES (v_txn.txn_id, v_fine);
    END IF;
    RETURN v_fine;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 3. SAMPLE DATA
-- ---------------------------------------------------------------------

INSERT INTO categories (name) VALUES ('Computer Science'), ('Fiction'), ('Science');

INSERT INTO authors (full_name) VALUES
  ('Joshua Bloch'), ('Herbert Schildt'), ('Robert C. Martin'),
  ('George Orwell'), ('Carl Sagan');

INSERT INTO books (isbn, title, publisher, publish_year, category_id) VALUES
  ('978-0134685991', 'Effective Java',        'Addison-Wesley', 2018, 1),
  ('978-1260440232', 'Java: The Complete Reference', 'McGraw-Hill', 2018, 1),
  ('978-0132350884', 'Clean Code',            'Prentice Hall',  2008, 1),
  ('978-0451524935', '1984',                  'Signet Classic', 1950, 2),
  ('978-0345539434', 'Cosmos',                'Ballantine',     2013, 3);

INSERT INTO book_authors (book_id, author_id) VALUES (1,1), (2,2), (3,3), (4,4), (5,5);

INSERT INTO book_copies (book_id, barcode) VALUES
  (1,'EJ-001'), (1,'EJ-002'),
  (2,'JCR-001'),
  (3,'CC-001'), (3,'CC-002'),
  (4,'N84-001'),
  (5,'COS-001');

INSERT INTO users (full_name, email, phone, role, max_books) VALUES
  ('Asha Kumar',  'asha@example.com',  '9000000001', 'STUDENT', 3),
  ('Ravi Menon',  'ravi@example.com',  '9000000002', 'STUDENT', 3),
  ('Dr. Meena Iyer', 'meena@example.com', '9000000003', 'FACULTY', 5),
  ('Suresh Babu', 'suresh@example.com','9000000004', 'STAFF', 2);

-- ---------------------------------------------------------------------
-- 4. USING THE ISSUE / RETURN FUNCTIONS
-- ---------------------------------------------------------------------

-- Issue copy 1 (EJ-001) to user 1 for the default 14 days:
SELECT issue_book(1, 1);

-- Issue copy 4 (CC-001) to user 2 for 7 days:
SELECT issue_book(2, 4, 7);

-- Return copy 1 on time (returns 0 = no fine):
SELECT return_book(1);

-- Return a copy late by passing the actual return date (fine = days late x 2.00):
--   SELECT return_book(4, CURRENT_DATE + 10);

-- ---------------------------------------------------------------------
-- 5. TRACKING QUERIES
-- ---------------------------------------------------------------------

-- Q1. Catalogue with authors and how many copies are available right now
SELECT b.book_id, b.title,
       STRING_AGG(DISTINCT a.full_name, ', ') AS authors,
       c.name AS category,
       COUNT(bc.copy_id)                                    AS total_copies,
       COUNT(bc.copy_id) FILTER (WHERE bc.status = 'AVAILABLE') AS available
FROM books b
LEFT JOIN categories   c  ON c.category_id = b.category_id
LEFT JOIN book_authors ba ON ba.book_id = b.book_id
LEFT JOIN authors      a  ON a.author_id = ba.author_id
LEFT JOIN book_copies  bc ON bc.book_id = b.book_id
GROUP BY b.book_id, b.title, c.name
ORDER BY b.title;

-- Q2. Which copies are available for a given title (to pick one to issue)
SELECT bc.copy_id, bc.barcode
FROM book_copies bc JOIN books b ON b.book_id = bc.book_id
WHERE b.title = 'Clean Code' AND bc.status = 'AVAILABLE';

-- Q3. Currently issued books: who has what, and when it is due
SELECT t.txn_id, u.full_name AS borrower, b.title, bc.barcode,
       t.issue_date, t.due_date,
       (t.due_date - CURRENT_DATE) AS days_left
FROM transactions t
JOIN users u        ON u.user_id  = t.user_id
JOIN book_copies bc ON bc.copy_id = t.copy_id
JOIN books b        ON b.book_id  = bc.book_id
WHERE t.return_date IS NULL
ORDER BY t.due_date;

-- Q4. Overdue books with days overdue and the fine accrued so far (2.00 per day)
SELECT u.full_name AS borrower, u.email, b.title, t.due_date,
       (CURRENT_DATE - t.due_date)        AS days_overdue,
       (CURRENT_DATE - t.due_date) * 2.00 AS fine_so_far
FROM transactions t
JOIN users u        ON u.user_id  = t.user_id
JOIN book_copies bc ON bc.copy_id = t.copy_id
JOIN books b        ON b.book_id  = bc.book_id
WHERE t.return_date IS NULL AND t.due_date < CURRENT_DATE
ORDER BY days_overdue DESC;

-- Q5. Full borrowing history of one user
SELECT b.title, t.issue_date, t.due_date, t.return_date,
       CASE WHEN t.return_date IS NULL THEN 'ISSUED'
            WHEN t.return_date > t.due_date THEN 'RETURNED LATE'
            ELSE 'RETURNED' END AS state
FROM transactions t
JOIN book_copies bc ON bc.copy_id = t.copy_id
JOIN books b        ON b.book_id  = bc.book_id
WHERE t.user_id = 1
ORDER BY t.issue_date DESC;

-- Q6. Each user's current load against their limit
SELECT u.user_id, u.full_name, u.max_books,
       COUNT(t.txn_id) AS currently_borrowed,
       u.max_books - COUNT(t.txn_id) AS can_still_borrow
FROM users u
LEFT JOIN transactions t ON t.user_id = u.user_id AND t.return_date IS NULL
GROUP BY u.user_id, u.full_name, u.max_books
ORDER BY u.full_name;

-- Q7. Most borrowed titles
SELECT b.title, COUNT(*) AS times_borrowed
FROM transactions t
JOIN book_copies bc ON bc.copy_id = t.copy_id
JOIN books b        ON b.book_id  = bc.book_id
GROUP BY b.title
ORDER BY times_borrowed DESC, b.title;

-- Q8. Unpaid fines per user
SELECT u.full_name, SUM(f.amount) AS unpaid_total
FROM fines f
JOIN transactions t ON t.txn_id = f.txn_id
JOIN users u        ON u.user_id = t.user_id
WHERE NOT f.paid
GROUP BY u.full_name
ORDER BY unpaid_total DESC;

-- Q9. Mark a fine as paid
UPDATE fines SET paid = TRUE, paid_on = CURRENT_DATE WHERE fine_id = 1 AND NOT paid;

-- Q10. Books by a given author
SELECT b.title, b.publish_year
FROM books b
JOIN book_authors ba ON ba.book_id = b.book_id
JOIN authors a       ON a.author_id = ba.author_id
WHERE a.full_name = 'Robert C. Martin';
