-- =============================================================
-- Library Management System — Database Schema (3NF Normalized)
-- =============================================================
-- Run this script first to create all tables.
-- Foreign key constraints use ON DELETE CASCADE so that deleting
-- a parent record automatically removes its dependent child rows.
-- =============================================================

CREATE DATABASE IF NOT EXISTS library_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE library_db;

-- -------------------------------------------------------------
-- 1. Authors
--    Holds author information separately (1NF → 3NF: removes
--    repeating author data that would otherwise appear in Books).
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Authors (
    author_id   INT          NOT NULL AUTO_INCREMENT,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    nationality VARCHAR(100),
    birth_year  YEAR,
    PRIMARY KEY (author_id)
);

-- -------------------------------------------------------------
-- 2. Books
--    Core catalogue record.  One row per unique title/edition.
--    author_id is a FK to Authors — removing an author cascades
--    and deletes all their book records.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Books (
    book_id       INT           NOT NULL AUTO_INCREMENT,
    author_id     INT           NOT NULL,
    title         VARCHAR(255)  NOT NULL,
    isbn          VARCHAR(20)   NOT NULL UNIQUE,
    genre         VARCHAR(100),
    published_year YEAR,
    total_copies  INT           NOT NULL DEFAULT 1,
    -- available_copies is maintained automatically by triggers
    available_copies INT        NOT NULL DEFAULT 1,
    PRIMARY KEY (book_id),
    CONSTRAINT fk_books_author
        FOREIGN KEY (author_id) REFERENCES Authors (author_id)
        ON DELETE CASCADE
);

-- -------------------------------------------------------------
-- 3. BookCopies
--    Each physical copy of a book gets its own row so that
--    individual copies can be tracked (e.g. damaged, lost).
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS BookCopies (
    copy_id    INT  NOT NULL AUTO_INCREMENT,
    book_id    INT  NOT NULL,
    -- 'available' | 'issued' | 'damaged' | 'lost'
    status     ENUM('available', 'issued', 'damaged', 'lost')
               NOT NULL DEFAULT 'available',
    PRIMARY KEY (copy_id),
    CONSTRAINT fk_copies_book
        FOREIGN KEY (book_id) REFERENCES Books (book_id)
        ON DELETE CASCADE
);

-- -------------------------------------------------------------
-- 4. Members
--    Library card holders.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Members (
    member_id      INT          NOT NULL AUTO_INCREMENT,
    full_name      VARCHAR(200) NOT NULL,
    email          VARCHAR(200) NOT NULL UNIQUE,
    phone          VARCHAR(20),
    address        VARCHAR(300),
    membership_date DATE        NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (member_id)
);

-- -------------------------------------------------------------
-- 5. Transactions
--    Records every issue and return event.
--    Linked to a specific physical copy (copy_id) and a member.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Transactions (
    transaction_id INT  NOT NULL AUTO_INCREMENT,
    copy_id        INT  NOT NULL,
    member_id      INT  NOT NULL,
    issue_date     DATE NOT NULL DEFAULT (CURRENT_DATE),
    due_date       DATE NOT NULL,
    return_date    DATE,          -- NULL means the book is still out
    -- 'issued' | 'returned' | 'overdue'
    status         ENUM('issued', 'returned', 'overdue')
                   NOT NULL DEFAULT 'issued',
    PRIMARY KEY (transaction_id),
    CONSTRAINT fk_txn_copy
        FOREIGN KEY (copy_id) REFERENCES BookCopies (copy_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_txn_member
        FOREIGN KEY (member_id) REFERENCES Members (member_id)
        ON DELETE CASCADE
);

-- -------------------------------------------------------------
-- 6. Fines
--    One fine row per overdue transaction.
--    Linked to the transaction that generated the fine.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS Fines (
    fine_id        INT           NOT NULL AUTO_INCREMENT,
    transaction_id INT           NOT NULL UNIQUE, -- one fine per transaction
    fine_amount    DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    -- 'unpaid' | 'paid'
    status         ENUM('unpaid', 'paid') NOT NULL DEFAULT 'unpaid',
    calculated_on  DATE          NOT NULL DEFAULT (CURRENT_DATE),
    paid_on        DATE,
    PRIMARY KEY (fine_id),
    CONSTRAINT fk_fines_txn
        FOREIGN KEY (transaction_id) REFERENCES Transactions (transaction_id)
        ON DELETE CASCADE
);
