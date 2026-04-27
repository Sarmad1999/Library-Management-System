-- =============================================================
-- Library Management System — Dummy / Seed Data
-- =============================================================
-- Run this script AFTER schema.sql.
-- Provides at least 5 realistic records per table.
-- =============================================================

USE library_db;

-- -------------------------------------------------------------
-- Authors (6 records)
-- -------------------------------------------------------------
INSERT INTO Authors (first_name, last_name, nationality, birth_year) VALUES
  ('George',   'Orwell',       'British',    1903),
  ('J.K.',     'Rowling',      'British',    1965),
  ('Frank',    'Herbert',      'American',   1920),
  ('Toni',     'Morrison',     'American',   1931),
  ('Gabriel',  'Garcia Marquez','Colombian', 1927),
  ('Haruki',   'Murakami',     'Japanese',   1949);

-- -------------------------------------------------------------
-- Books (6 records — one per author above)
-- -------------------------------------------------------------
INSERT INTO Books (author_id, title, isbn, genre, published_year, total_copies, available_copies) VALUES
  (1, 'Nineteen Eighty-Four',        '978-0451524935', 'Dystopian',      1949, 4, 4),
  (2, 'Harry Potter and the Philosopher''s Stone', '978-0439708180', 'Fantasy', 1997, 5, 5),
  (3, 'Dune',                        '978-0441013593', 'Science Fiction', 1965, 3, 3),
  (4, 'Beloved',                     '978-1400033416', 'Historical Fiction', 1987, 3, 3),
  (5, 'One Hundred Years of Solitude','978-0060883287', 'Magical Realism', 1967, 4, 4),
  (6, 'Norwegian Wood',              '978-0375704024', 'Literary Fiction', 1987, 2, 2);

-- -------------------------------------------------------------
-- BookCopies (21 physical copies spread across the 6 books)
-- -------------------------------------------------------------
-- Book 1 — 4 copies
INSERT INTO BookCopies (book_id, status) VALUES (1,'available'),(1,'available'),(1,'available'),(1,'available');
-- Book 2 — 5 copies
INSERT INTO BookCopies (book_id, status) VALUES (2,'available'),(2,'available'),(2,'available'),(2,'available'),(2,'available');
-- Book 3 — 3 copies
INSERT INTO BookCopies (book_id, status) VALUES (3,'available'),(3,'available'),(3,'available');
-- Book 4 — 3 copies
INSERT INTO BookCopies (book_id, status) VALUES (4,'available'),(4,'available'),(4,'available');
-- Book 5 — 4 copies
INSERT INTO BookCopies (book_id, status) VALUES (5,'available'),(5,'available'),(5,'available'),(5,'available');
-- Book 6 — 2 copies
INSERT INTO BookCopies (book_id, status) VALUES (6,'available'),(6,'available');

-- -------------------------------------------------------------
-- Members (6 records)
-- -------------------------------------------------------------
INSERT INTO Members (full_name, email, phone, address, membership_date) VALUES
  ('Alice Johnson',  'alice@example.com',  '555-0101', '12 Elm Street, Springfield',  '2023-01-15'),
  ('Bob Martinez',   'bob@example.com',    '555-0102', '34 Oak Avenue, Shelbyville',  '2023-03-22'),
  ('Carol White',    'carol@example.com',  '555-0103', '56 Pine Road, Capital City',  '2023-06-10'),
  ('David Lee',      'david@example.com',  '555-0104', '78 Maple Lane, Ogdenville',   '2024-01-05'),
  ('Eva Brown',      'eva@example.com',    '555-0105', '90 Cedar Blvd, North Haverbrook', '2024-02-28'),
  ('Frank Green',    'frank@example.com',  '555-0106', '11 Birch Court, Brockway',    '2024-04-01');

-- -------------------------------------------------------------
-- Transactions (6 records — mix of returned and still-issued)
-- -------------------------------------------------------------
-- Alice borrowed copy 1 (Book 1) and returned it on time
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (1, 1, '2025-01-05', '2025-01-19', '2025-01-17', 'returned');

-- Bob borrowed copy 5 (Book 2) — still out, not overdue
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (5, 2, CURDATE() - INTERVAL 7 DAY, CURDATE() + INTERVAL 7 DAY, NULL, 'issued');

-- Carol borrowed copy 9 (Book 3) — overdue, not returned
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (9, 3, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 6 DAY, NULL, 'overdue');

-- David borrowed copy 12 (Book 4) and returned it late
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (12, 4, '2025-02-01', '2025-02-15', '2025-02-20', 'returned');

-- Eva borrowed copy 13 (Book 5) — still out but overdue
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (13, 5, CURDATE() - INTERVAL 25 DAY, CURDATE() - INTERVAL 11 DAY, NULL, 'overdue');

-- Frank borrowed copy 20 (Book 6) and returned on time
INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, return_date, status) VALUES
  (20, 6, '2025-03-01', '2025-03-15', '2025-03-10', 'returned');

-- Mark the copies that are currently issued as 'issued' in BookCopies
UPDATE BookCopies SET status = 'issued' WHERE copy_id IN (5, 9, 13);

-- Decrement available_copies for books with currently issued copies
UPDATE Books SET available_copies = available_copies - 1 WHERE book_id IN (2, 3, 5);

-- -------------------------------------------------------------
-- Fines (5 records — for the overdue/late transactions above)
-- -------------------------------------------------------------
-- Transaction 3: Carol — still overdue (fine calculated today)
INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on) VALUES
  (3, 3.00, 'unpaid', CURDATE());

-- Transaction 4: David — returned 5 days late @ $0.50/day
INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on, paid_on) VALUES
  (4, 2.50, 'paid', '2025-02-21', '2025-02-22');

-- Transaction 5: Eva — still overdue (fine calculated today)
INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on) VALUES
  (5, 5.50, 'unpaid', CURDATE());

-- Two additional historical fines for completeness
INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on, paid_on) VALUES
  (1, 0.00, 'paid', '2025-01-17', '2025-01-17'); -- returned on time, no real fine

INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on, paid_on) VALUES
  (6, 0.00, 'paid', '2025-03-10', '2025-03-10'); -- returned on time, no real fine
