-- =============================================================
-- Library Management System — Stored Procedures
-- =============================================================
-- Run this script AFTER schema.sql.
--
-- Procedure 1 (sp_calculate_fines):
--   Scans all open transactions whose due_date has passed and
--   either inserts a new Fines row or updates an existing one.
--   Fine rate: $0.50 per overdue day (configurable via the
--   p_rate_per_day parameter).
--
-- Procedure 2 (sp_issue_book):
--   Issues an available copy of a book to a member.
--   Validates that the member exists, the book exists, and that
--   at least one copy is available before creating the transaction.
-- =============================================================

USE library_db;

DROP PROCEDURE IF EXISTS sp_calculate_fines;
DROP PROCEDURE IF EXISTS sp_issue_book;

DELIMITER $$

-- -------------------------------------------------------------------
-- Procedure 1: Calculate & upsert fines for all overdue transactions
-- -------------------------------------------------------------------
CREATE PROCEDURE sp_calculate_fines(
    IN  p_rate_per_day DECIMAL(5,2)   -- e.g. 0.50 means $0.50 per day
)
BEGIN
    DECLARE v_txn_id      INT;
    DECLARE v_days_overdue INT;
    DECLARE v_fine_amount  DECIMAL(8,2);
    DECLARE done           INT DEFAULT FALSE;

    -- Cursor: all transactions that are overdue and not yet returned
    DECLARE cur CURSOR FOR
        SELECT t.transaction_id,
               DATEDIFF(CURDATE(), t.due_date) AS days_overdue
        FROM   Transactions t
        WHERE  t.return_date IS NULL           -- not returned yet
          AND  t.due_date < CURDATE();         -- past the due date

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Default to $0.50/day if caller passes NULL or 0
    IF p_rate_per_day IS NULL OR p_rate_per_day <= 0 THEN
        SET p_rate_per_day = 0.50;
    END IF;

    OPEN cur;

    fine_loop: LOOP
        FETCH cur INTO v_txn_id, v_days_overdue;
        IF done THEN LEAVE fine_loop; END IF;

        SET v_fine_amount = v_days_overdue * p_rate_per_day;

        -- Mark the transaction as overdue
        UPDATE Transactions
        SET    status = 'overdue'
        WHERE  transaction_id = v_txn_id;

        -- Insert or update the Fines row (one fine per transaction)
        INSERT INTO Fines (transaction_id, fine_amount, status, calculated_on)
        VALUES (v_txn_id, v_fine_amount, 'unpaid', CURDATE())
        ON DUPLICATE KEY UPDATE
            fine_amount    = v_fine_amount,
            calculated_on  = CURDATE();

    END LOOP fine_loop;

    CLOSE cur;

    SELECT CONCAT('Fine calculation complete. Rate: $', p_rate_per_day, '/day') AS message;
END$$

-- -------------------------------------------------------------------
-- Procedure 2: Issue a book copy to a member
-- -------------------------------------------------------------------
CREATE PROCEDURE sp_issue_book(
    IN  p_book_id   INT,
    IN  p_member_id INT,
    IN  p_loan_days INT,          -- how many days the member may keep the book
    OUT p_result    VARCHAR(200)  -- human-readable outcome message
)
BEGIN
    DECLARE v_copy_id      INT DEFAULT NULL;
    DECLARE v_avail_count  INT DEFAULT 0;
    DECLARE v_member_count INT DEFAULT 0;

    -- 1. Check the member exists
    SELECT COUNT(*) INTO v_member_count
    FROM   Members
    WHERE  member_id = p_member_id;

    IF v_member_count = 0 THEN
        SET p_result = CONCAT('ERROR: Member ID ', p_member_id, ' not found.');
        LEAVE sp_issue_book;  -- exit the procedure
    END IF;

    -- 2. Check the book exists and has available copies
    SELECT available_copies INTO v_avail_count
    FROM   Books
    WHERE  book_id = p_book_id;

    IF v_avail_count IS NULL THEN
        SET p_result = CONCAT('ERROR: Book ID ', p_book_id, ' not found.');
        LEAVE sp_issue_book;
    END IF;

    IF v_avail_count = 0 THEN
        SET p_result = CONCAT('ERROR: No available copies of Book ID ', p_book_id, '.');
        LEAVE sp_issue_book;
    END IF;

    -- 3. Find the first available physical copy
    SELECT copy_id INTO v_copy_id
    FROM   BookCopies
    WHERE  book_id = p_book_id
      AND  status  = 'available'
    LIMIT 1;

    -- 4. Create the transaction (the trg_after_issue trigger handles
    --    updating BookCopies.status and Books.available_copies)
    INSERT INTO Transactions (copy_id, member_id, issue_date, due_date, status)
    VALUES (
        v_copy_id,
        p_member_id,
        CURDATE(),
        DATE_ADD(CURDATE(), INTERVAL p_loan_days DAY),
        'issued'
    );

    SET p_result = CONCAT(
        'SUCCESS: Copy ID ', v_copy_id,
        ' of Book ID ', p_book_id,
        ' issued to Member ID ', p_member_id,
        '. Due: ', DATE_ADD(CURDATE(), INTERVAL p_loan_days DAY)
    );
END$$

DELIMITER ;
