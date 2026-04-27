-- =============================================================
-- Library Management System — Triggers
-- =============================================================
-- Run this script AFTER schema.sql.
--
-- Trigger 1 (trg_after_issue):
--   When a new Transaction row is inserted with status='issued',
--   mark the physical copy as 'issued' and decrement
--   Books.available_copies by 1.
--
-- Trigger 2 (trg_after_return):
--   When a Transaction row is updated and return_date is set
--   (i.e. the book is returned), mark the physical copy back to
--   'available' and increment Books.available_copies by 1.
-- =============================================================

USE library_db;

-- Drop existing triggers before (re)creating, to keep the script idempotent
DROP TRIGGER IF EXISTS trg_after_issue;
DROP TRIGGER IF EXISTS trg_after_return;

DELIMITER $$

-- -------------------------------------------------------------------
-- Trigger 1: Book issued — fires AFTER INSERT on Transactions
-- -------------------------------------------------------------------
CREATE TRIGGER trg_after_issue
AFTER INSERT ON Transactions
FOR EACH ROW
BEGIN
    -- Only act when the book is being issued (not a direct 'returned' insert)
    IF NEW.status = 'issued' THEN

        -- 1. Mark the physical copy as 'issued'
        UPDATE BookCopies
        SET    status = 'issued'
        WHERE  copy_id = NEW.copy_id;

        -- 2. Decrement the available count on the parent Books row.
        --    We derive book_id from BookCopies to keep the trigger
        --    independent of the application layer.
        UPDATE Books b
        JOIN   BookCopies bc ON bc.book_id = b.book_id
        SET    b.available_copies = b.available_copies - 1
        WHERE  bc.copy_id = NEW.copy_id
          AND  b.available_copies > 0;  -- guard against going negative

    END IF;
END$$

-- -------------------------------------------------------------------
-- Trigger 2: Book returned — fires AFTER UPDATE on Transactions
-- -------------------------------------------------------------------
CREATE TRIGGER trg_after_return
AFTER UPDATE ON Transactions
FOR EACH ROW
BEGIN
    -- Detect the moment a book is returned:
    -- return_date was NULL before the update and is now set.
    IF OLD.return_date IS NULL AND NEW.return_date IS NOT NULL THEN

        -- 1. Mark the physical copy back to 'available'
        UPDATE BookCopies
        SET    status = 'available'
        WHERE  copy_id = NEW.copy_id;

        -- 2. Increment the available count on the parent Books row
        UPDATE Books b
        JOIN   BookCopies bc ON bc.book_id = b.book_id
        SET    b.available_copies = b.available_copies + 1
        WHERE  bc.copy_id = NEW.copy_id
          AND  b.available_copies < b.total_copies;  -- guard against exceeding total

    END IF;
END$$

DELIMITER ;
