"""
Library Management System — Python CLI Application
====================================================
Connects to a MySQL database (library_db) and provides two core operations:

  1. Search for a book by title (partial, case-insensitive match).
  2. Issue a book to a member (calls the sp_issue_book stored procedure).

Dependencies:  mysql-connector-python  (see requirements.txt)
Usage:
  python app.py
"""

import sys
import mysql.connector
from mysql.connector import Error

# ------------------------------------------------------------------
# Database connection configuration
# Adjust HOST, PORT, USER, PASSWORD to match your local MySQL setup.
# ------------------------------------------------------------------
DB_CONFIG = {
    "host":     "127.0.0.1",
    "port":     3306,
    "user":     "root",       # replace with your MySQL username
    "password": "",           # replace with your MySQL password
    "database": "library_db",
}


def get_connection():
    """Create and return a MySQL connection.  Raises SystemExit on failure."""
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        if conn.is_connected():
            return conn
    except Error as exc:
        print(f"[ERROR] Could not connect to MySQL: {exc}")
        sys.exit(1)


# ------------------------------------------------------------------
# Feature 1: Search for a book by title
# ------------------------------------------------------------------
def search_books(conn, keyword: str) -> None:
    """
    Print all books whose title contains *keyword* (case-insensitive).
    Also shows available copies so the user knows if a book can be issued.
    """
    query = """
        SELECT
            b.book_id,
            b.title,
            CONCAT(a.first_name, ' ', a.last_name) AS author,
            b.genre,
            b.published_year,
            b.available_copies,
            b.total_copies
        FROM   Books  b
        JOIN   Authors a ON a.author_id = b.author_id
        WHERE  b.title LIKE %s
        ORDER  BY b.title
    """
    # Use SQL wildcard for a "contains" search
    pattern = f"%{keyword}%"

    cursor = conn.cursor(dictionary=True)
    cursor.execute(query, (pattern,))
    rows = cursor.fetchall()
    cursor.close()

    if not rows:
        print(f'\n  No books found matching "{keyword}".\n')
        return

    print(f'\n  Search results for "{keyword}":\n')
    print(f"  {'ID':<5} {'Title':<45} {'Author':<25} {'Genre':<20} {'Year':<6} {'Avail/Total'}")
    print("  " + "-" * 115)
    for row in rows:
        avail = f"{row['available_copies']}/{row['total_copies']}"
        print(
            f"  {row['book_id']:<5} "
            f"{row['title'][:43]:<45} "
            f"{row['author'][:23]:<25} "
            f"{(row['genre'] or '')[:18]:<20} "
            f"{row['published_year'] or '':<6} "
            f"{avail}"
        )
    print()


# ------------------------------------------------------------------
# Feature 2: Issue a book to a member
# ------------------------------------------------------------------
def issue_book(conn, book_id: int, member_id: int, loan_days: int = 14) -> None:
    """
    Call the sp_issue_book stored procedure to issue a book copy to a member.
    The procedure handles availability checks and creates the Transaction row.
    The database trigger (trg_after_issue) will update BookCopies and Books
    automatically — the application does not need to do this manually.
    """
    # OUT parameter placeholder (@p_result) is read back via a SELECT
    call_sql   = "CALL sp_issue_book(%s, %s, %s, @p_result)"
    fetch_sql  = "SELECT @p_result AS result"

    cursor = conn.cursor()
    try:
        cursor.execute(call_sql, (book_id, member_id, loan_days))
        # Consume any result sets the stored procedure might return
        cursor.fetchall()
        # Read the OUT parameter
        cursor.execute(fetch_sql)
        row = cursor.fetchone()
        result_msg = row[0] if row else "No response from procedure."
        print(f"\n  {result_msg}\n")
        conn.commit()   # commit the INSERT made by the procedure
    except Error as exc:
        conn.rollback()
        print(f"\n  [ERROR] {exc}\n")
    finally:
        cursor.close()


# ------------------------------------------------------------------
# Helper: List all members (so the user can pick a member_id)
# ------------------------------------------------------------------
def list_members(conn) -> None:
    """Print a brief list of all library members."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        "SELECT member_id, full_name, email FROM Members ORDER BY member_id"
    )
    rows = cursor.fetchall()
    cursor.close()

    print("\n  Registered Members:\n")
    print(f"  {'ID':<5} {'Name':<25} {'Email'}")
    print("  " + "-" * 60)
    for row in rows:
        print(f"  {row['member_id']:<5} {row['full_name'][:23]:<25} {row['email']}")
    print()


# ------------------------------------------------------------------
# CLI menu
# ------------------------------------------------------------------
def main():
    print("=" * 55)
    print("   Library Management System — Python CLI")
    print("=" * 55)

    # Establish database connection once; reuse for the session
    conn = get_connection()
    print("  Connected to library_db successfully.\n")

    while True:
        print("  Options:")
        print("    1. Search for a book by title")
        print("    2. Issue a book to a member")
        print("    3. List all members")
        print("    0. Exit")
        choice = input("\n  Enter your choice: ").strip()

        if choice == "1":
            keyword = input("  Enter title keyword to search: ").strip()
            if keyword:
                search_books(conn, keyword)
            else:
                print("  [!] Please enter a search keyword.\n")

        elif choice == "2":
            list_members(conn)
            try:
                book_id   = int(input("  Enter Book ID to issue: ").strip())
                member_id = int(input("  Enter Member ID       : ").strip())
                days_inp  = input("  Loan period in days [default 14]: ").strip()
                loan_days = int(days_inp) if days_inp.isdigit() else 14
                issue_book(conn, book_id, member_id, loan_days)
            except ValueError:
                print("  [!] Book ID and Member ID must be integers.\n")

        elif choice == "3":
            list_members(conn)

        elif choice == "0":
            print("\n  Goodbye!\n")
            break

        else:
            print("  [!] Invalid option. Please try again.\n")

    conn.close()


if __name__ == "__main__":
    main()
