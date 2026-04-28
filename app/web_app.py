"""
Library Management System — Flask Web Application
===================================================
Provides a browser-based interface to the same library_db MySQL database
used by the CLI (app.py).  Runs on http://127.0.0.1:5000 by default.

Features
--------
  • Dashboard  — live stats + recent transactions + overdue summary
  • Books       — searchable catalogue with available-copy badges
  • Members     — list of all registered members
  • Issue Book  — web form that calls sp_issue_book stored procedure
  • Transactions— filterable list with one-click "Return" action
  • Fines       — list of fines with "Calculate Fines" and "Mark Paid" actions

Dependencies: Flask, mysql-connector-python  (see requirements.txt)
Usage:
  python web_app.py
"""

import os
from datetime import date

import mysql.connector
from mysql.connector import Error
from flask import Flask, flash, redirect, render_template, request, url_for

# ------------------------------------------------------------------
# Database connection configuration
# Adjust HOST, PORT, USER, PASSWORD to match your local MySQL setup,
# or set the DB_PASSWORD environment variable instead.
# ------------------------------------------------------------------
DB_CONFIG = {
    "host":     os.environ.get("DB_HOST",     "127.0.0.1"),
    "port":     int(os.environ.get("DB_PORT", "3306")),
    "user":     os.environ.get("DB_USER",     "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME",     "library_db"),
}

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "change-me-in-production")


# ------------------------------------------------------------------
# Database helpers
# ------------------------------------------------------------------

def get_connection():
    """Return a new MySQL connection or raise RuntimeError on failure."""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        if conn.is_connected():
            return conn
    except Error as exc:
        raise RuntimeError(f"Could not connect to MySQL: {exc}") from exc


def query_db(sql: str, params=(), one=False):
    """Execute a SELECT and return a list of dicts (or a single dict)."""
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute(sql, params)
        rows = cursor.fetchall()
        return rows[0] if (one and rows) else rows
    finally:
        cursor.close()
        conn.close()


# ------------------------------------------------------------------
# Routes
# ------------------------------------------------------------------

@app.route("/")
def index():
    """Dashboard: aggregate stats + recent transactions + overdue loans."""
    stats = {
        "total_books":    query_db("SELECT COUNT(*) AS n FROM Books", one=True)["n"],
        "total_members":  query_db("SELECT COUNT(*) AS n FROM Members", one=True)["n"],
        "active_loans":   query_db(
            "SELECT COUNT(*) AS n FROM Transactions WHERE return_date IS NULL", one=True
        )["n"],
        "unpaid_fines":   query_db(
            "SELECT COALESCE(SUM(fine_amount), 0) AS n FROM Fines WHERE status='unpaid'",
            one=True,
        )["n"] or 0,
    }

    recent_transactions = query_db("""
        SELECT t.transaction_id, t.due_date, t.status,
               m.full_name  AS member_name,
               b.title
        FROM   Transactions t
        JOIN   Members    m  ON m.member_id = t.member_id
        JOIN   BookCopies bc ON bc.copy_id  = t.copy_id
        JOIN   Books      b  ON b.book_id   = bc.book_id
        ORDER  BY t.transaction_id DESC
        LIMIT  10
    """)

    overdue_summary = query_db("""
        SELECT m.full_name AS member_name,
               b.title,
               DATEDIFF(CURDATE(), t.due_date) AS days_overdue,
               COALESCE(f.fine_amount, 0)       AS fine_amount
        FROM   Transactions t
        JOIN   Members    m  ON m.member_id = t.member_id
        JOIN   BookCopies bc ON bc.copy_id  = t.copy_id
        JOIN   Books      b  ON b.book_id   = bc.book_id
        LEFT JOIN Fines   f  ON f.transaction_id = t.transaction_id
        WHERE  t.return_date IS NULL
          AND  t.due_date < CURDATE()
        ORDER  BY days_overdue DESC
    """)

    return render_template(
        "index.html",
        stats=stats,
        recent_transactions=recent_transactions,
        overdue_summary=overdue_summary,
    )


@app.route("/books")
def books():
    """Book catalogue with optional title search."""
    query = request.args.get("q", "").strip()
    if query:
        rows = query_db(
            """
            SELECT b.book_id, b.title,
                   CONCAT(a.first_name, ' ', a.last_name) AS author,
                   b.genre, b.published_year,
                   b.available_copies, b.total_copies
            FROM   Books   b
            JOIN   Authors a ON a.author_id = b.author_id
            WHERE  b.title LIKE %s
            ORDER  BY b.title
            """,
            (f"%{query}%",),
        )
    else:
        rows = query_db(
            """
            SELECT b.book_id, b.title,
                   CONCAT(a.first_name, ' ', a.last_name) AS author,
                   b.genre, b.published_year,
                   b.available_copies, b.total_copies
            FROM   Books   b
            JOIN   Authors a ON a.author_id = b.author_id
            ORDER  BY b.title
            """
        )
    return render_template("books.html", books=rows, query=query)


@app.route("/members")
def members():
    """List all library members."""
    rows = query_db(
        "SELECT * FROM Members ORDER BY member_id"
    )
    return render_template("members.html", members=rows)


@app.route("/issue", methods=["GET", "POST"])
def issue():
    """
    GET  — show the issue-book form (pre-selecting book/member from query params).
    POST — call sp_issue_book and redirect with a flash message.
    """
    if request.method == "POST":
        try:
            book_id   = int(request.form["book_id"])
            member_id = int(request.form["member_id"])
            loan_days = int(request.form.get("loan_days") or 14)
        except (ValueError, KeyError):
            flash("Invalid input — please fill in all fields.", "error")
            return redirect(url_for("issue"))

        conn = get_connection()
        cursor = conn.cursor()
        try:
            cursor.execute(
                "CALL sp_issue_book(%s, %s, %s, @p_result)",
                (book_id, member_id, loan_days),
            )
            cursor.fetchall()
            cursor.execute("SELECT @p_result AS result")
            row = cursor.fetchone()
            result_msg = row[0] if row else "No response from procedure."
            conn.commit()
            if result_msg and result_msg.startswith("SUCCESS"):
                flash(result_msg, "success")
            else:
                flash(result_msg, "error")
        except Error as exc:
            conn.rollback()
            flash(f"Database error: {exc}", "error")
        finally:
            cursor.close()
            conn.close()

        return redirect(url_for("transactions"))

    # GET — populate dropdowns
    book_list = query_db(
        """
        SELECT b.book_id, b.title, b.available_copies
        FROM   Books b
        ORDER  BY b.title
        """
    )
    member_list = query_db(
        "SELECT member_id, full_name FROM Members ORDER BY full_name"
    )

    selected_book_id   = request.args.get("book_id",   type=int)
    selected_member_id = request.args.get("member_id", type=int)

    return render_template(
        "issue.html",
        books=book_list,
        members=member_list,
        selected_book_id=selected_book_id,
        selected_member_id=selected_member_id,
    )


@app.route("/transactions")
def transactions():
    """List all transactions, optionally filtered by status."""
    status_filter = request.args.get("status", "").strip()
    if status_filter in ("issued", "returned", "overdue"):
        rows = query_db(
            """
            SELECT t.transaction_id, t.copy_id, t.issue_date, t.due_date,
                   t.return_date, t.status,
                   m.full_name AS member_name,
                   b.title
            FROM   Transactions t
            JOIN   Members    m  ON m.member_id = t.member_id
            JOIN   BookCopies bc ON bc.copy_id  = t.copy_id
            JOIN   Books      b  ON b.book_id   = bc.book_id
            WHERE  t.status = %s
            ORDER  BY t.transaction_id DESC
            """,
            (status_filter,),
        )
    else:
        status_filter = ""
        rows = query_db(
            """
            SELECT t.transaction_id, t.copy_id, t.issue_date, t.due_date,
                   t.return_date, t.status,
                   m.full_name AS member_name,
                   b.title
            FROM   Transactions t
            JOIN   Members    m  ON m.member_id = t.member_id
            JOIN   BookCopies bc ON bc.copy_id  = t.copy_id
            JOIN   Books      b  ON b.book_id   = bc.book_id
            ORDER  BY t.transaction_id DESC
            """
        )
    return render_template(
        "transactions.html", transactions=rows, status_filter=status_filter
    )


@app.route("/return/<int:transaction_id>", methods=["POST"])
def return_book(transaction_id):
    """Mark a transaction as returned (sets return_date to today)."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE Transactions
               SET return_date = %s,
                   status      = 'returned'
             WHERE transaction_id = %s
               AND return_date IS NULL
            """,
            (date.today(), transaction_id),
        )
        affected = cursor.rowcount
        conn.commit()
        if affected:
            flash(f"Transaction #{transaction_id} marked as returned.", "success")
        else:
            flash(
                f"Transaction #{transaction_id} not found or already returned.", "warning"
            )
    except Error as exc:
        conn.rollback()
        flash(f"Database error: {exc}", "error")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("transactions"))


@app.route("/fines")
def fines():
    """List all fines with member and book details."""
    rows = query_db(
        """
        SELECT f.fine_id, f.transaction_id, f.fine_amount,
               f.status, f.calculated_on, f.paid_on,
               m.full_name AS member_name,
               b.title
        FROM   Fines         f
        JOIN   Transactions  t  ON t.transaction_id = f.transaction_id
        JOIN   Members       m  ON m.member_id      = t.member_id
        JOIN   BookCopies    bc ON bc.copy_id        = t.copy_id
        JOIN   Books         b  ON b.book_id         = bc.book_id
        ORDER  BY f.fine_id DESC
        """
    )
    return render_template("fines.html", fines=rows)


@app.route("/fines/calculate", methods=["POST"])
def calculate_fines():
    """Call sp_calculate_fines with the submitted rate."""
    try:
        rate = float(request.form.get("rate") or 0.50)
        if rate <= 0:
            raise ValueError
    except ValueError:
        flash("Please enter a valid positive rate.", "error")
        return redirect(url_for("fines"))

    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("CALL sp_calculate_fines(%s)", (rate,))
        row = cursor.fetchone()
        conn.commit()
        msg = row.get("message", "Fine calculation complete.") if row else "Fine calculation complete."
        flash(msg, "success")
    except Error as exc:
        conn.rollback()
        flash(f"Database error: {exc}", "error")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("fines"))


@app.route("/fines/<int:fine_id>/pay", methods=["POST"])
def pay_fine(fine_id):
    """Mark a fine as paid."""
    conn = get_connection()
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE Fines
               SET status  = 'paid',
                   paid_on = %s
             WHERE fine_id = %s
               AND status  = 'unpaid'
            """,
            (date.today(), fine_id),
        )
        affected = cursor.rowcount
        conn.commit()
        if affected:
            flash(f"Fine #{fine_id} marked as paid.", "success")
        else:
            flash(f"Fine #{fine_id} not found or already paid.", "warning")
    except Error as exc:
        conn.rollback()
        flash(f"Database error: {exc}", "error")
    finally:
        cursor.close()
        conn.close()

    return redirect(url_for("fines"))


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------
if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
