# Library Management System

A complete **Library Management System** built for a 4th-semester DBMS course.
It demonstrates a 3NF-normalised MySQL schema, triggers, stored procedures, and a
Python CLI application that lets a librarian search for books and issue them to members.

---

## Project Structure

```
Library-Management-System/
├── database/
│   ├── schema.sql        ← CREATE TABLE scripts (3NF, FK + ON DELETE CASCADE)
│   ├── data.sql          ← INSERT seed data (≥ 5 rows per table)
│   ├── triggers.sql      ← Triggers: auto-update availability on issue / return
│   └── procedures.sql    ← Stored procedures: calculate fines, issue a book
├── app/
│   ├── app.py            ← Python CLI (search books, issue books)
│   ├── web_app.py        ← Flask web interface
│   ├── requirements.txt  ← Python dependencies (Flask + mysql-connector-python)
│   └── templates/        ← Jinja2 HTML templates
│       ├── base.html
│       ├── index.html
│       ├── books.html
│       ├── members.html
│       ├── issue.html
│       ├── transactions.html
│       └── fines.html
└── README.md
```

---

## Database Schema (3NF)

| Table          | Purpose                                                   |
|----------------|-----------------------------------------------------------|
| `Authors`      | Author bio — separated to eliminate repeating data in Books |
| `Books`        | Catalogue entry per title/edition; tracks available copies |
| `BookCopies`   | One row per physical copy — supports per-copy status tracking |
| `Members`      | Library card holders                                      |
| `Transactions` | Every issue/return event (FK → BookCopies, Members)       |
| `Fines`        | One overdue fine per transaction (FK → Transactions)      |

All tables use `ON DELETE CASCADE` foreign keys so that removing a parent record
automatically removes dependent child records.

### Entity-Relationship Overview

```
Authors ──< Books ──< BookCopies ──< Transactions >── Members
                                          │
                                        Fines
```

---

## How to Run

### Prerequisites

| Requirement     | Version |
|-----------------|---------|
| MySQL / MariaDB | ≥ 8.0   |
| Python          | ≥ 3.9   |
| pip             | latest  |

---

### Step 1 — Set Up the Database Environment

1. **Install MySQL** (if not already installed):
   - **Ubuntu / Debian**: `sudo apt install mysql-server`
   - **macOS (Homebrew)**: `brew install mysql`
   - **Windows**: Download the installer from https://dev.mysql.com/downloads/installer/

2. **Start MySQL**:
   ```bash
   # Linux (systemd)
   sudo systemctl start mysql

   # macOS (Homebrew)
   brew services start mysql
   ```

3. **Log in**:
   ```bash
   mysql -u root -p
   ```

---

### Step 2 — Execute the SQL Scripts

Run the scripts in the following order from the MySQL shell or command line:

```bash
# Option A — run from the OS shell (recommended)
mysql -u root -p < database/schema.sql
mysql -u root -p < database/triggers.sql
mysql -u root -p < database/procedures.sql
mysql -u root -p < database/data.sql
```

```sql
-- Option B — run from inside the MySQL shell
SOURCE /full/path/to/database/schema.sql;
SOURCE /full/path/to/database/triggers.sql;
SOURCE /full/path/to/database/procedures.sql;
SOURCE /full/path/to/database/data.sql;
```

> **Order matters**: `schema.sql` first (creates tables), then `triggers.sql` and
> `procedures.sql`, and finally `data.sql` (inserts seed data).

---

### Step 3 — Configure the Application

Open `app/app.py` and update the `DB_CONFIG` dictionary near the top of the file:

```python
DB_CONFIG = {
    "host":     "127.0.0.1",
    "port":     3306,
    "user":     "root",       # ← your MySQL username
    "password": "your_pass",  # ← your MySQL password
    "database": "library_db",
}
```

---

### Step 4 — Install Python Dependencies

```bash
# Create and activate a virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate

# Install mysql-connector-python
pip install -r app/requirements.txt
```

---

### Step 5 — Run the Application

#### Option A — Web Interface (recommended)

```bash
python app/web_app.py
```

Then open your browser at **http://127.0.0.1:5000**.

The web interface provides:
- **Dashboard** — live stats (total books, members, active loans, unpaid fines) plus recent transactions and overdue summary
- **Books** — searchable catalogue with available-copy badges and quick "Issue" links
- **Members** — list of all registered members
- **Issue Book** — dropdown form that calls `sp_issue_book`
- **Transactions** — filterable list (all / issued / returned / overdue) with one-click "Return" action
- **Fines** — list of all fines with "Calculate Fines" (calls `sp_calculate_fines`) and "Mark Paid" buttons

You can also configure the database connection via environment variables instead of editing the source file:

```bash
export DB_HOST=127.0.0.1
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=your_pass
export DB_NAME=library_db
python app/web_app.py
```

#### Option B — CLI

#### Option B — CLI

```bash
python app/app.py
```


```
=======================================================
   Library Management System — Python CLI
=======================================================
  Connected to library_db successfully.

  Options:
    1. Search for a book by title
    2. Issue a book to a member
    3. List all members
    0. Exit

  Enter your choice:
```

#### Example — Search for a book

```
Enter your choice: 1
Enter title keyword to search: dune

  Search results for "dune":

  ID    Title                                         Author                    Genre                Year   Avail/Total
  -----------------------------------------------------------------------------------------------------------------------
  3     Dune                                          Frank Herbert             Science Fiction      1965   3/3
```

#### Example — Issue a book

```
Enter your choice: 2
  (member list is displayed)
Enter Book ID to issue: 3
Enter Member ID       : 2
Loan period in days [default 14]: 14

  SUCCESS: Copy ID 10 of Book ID 3 issued to Member ID 2. Due: 2025-05-11
```

---

### Step 6 — Running the Stored Procedures Manually

#### Calculate fines for all overdue books

```sql
USE library_db;
CALL sp_calculate_fines(0.50);   -- $0.50 fine per overdue day
```

#### Issue a book via stored procedure

```sql
CALL sp_issue_book(
    1,          -- book_id
    3,          -- member_id
    14,         -- loan days
    @result
);
SELECT @result;
```

---

## Advanced SQL Features

### Trigger — `trg_after_issue`

Fires **AFTER INSERT** on `Transactions`.  When a new issued-transaction is created it:
1. Sets `BookCopies.status = 'issued'` for the selected copy.
2. Decrements `Books.available_copies` by 1.

### Trigger — `trg_after_return`

Fires **AFTER UPDATE** on `Transactions`.  When `return_date` changes from NULL to a real
date it:
1. Sets `BookCopies.status = 'available'`.
2. Increments `Books.available_copies` by 1.

### Stored Procedure — `sp_calculate_fines`

Iterates over all unreturned, overdue transactions and inserts or updates a row in the
`Fines` table.  Fine = `days_overdue × rate_per_day`.

### Stored Procedure — `sp_issue_book`

Validates member, checks availability, selects the first available physical copy, and
inserts a `Transactions` row (which fires `trg_after_issue` automatically).

---

## License

This project is intended for educational use (DBMS 4th semester course work).
