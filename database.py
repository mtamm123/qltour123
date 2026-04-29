import pyodbc

# =============================================
# CONNECT SQL SERVER THEO USER LOGIN
# =============================================
def get_db(username=None, password=None):
    try:
        # Nếu có user/pass => đăng nhập SQL Server account
        if username and password:
            conn = pyodbc.connect(
                "DRIVER={ODBC Driver 17 for SQL Server};"
                "SERVER=localhost;"
                "DATABASE=QL_TOUR1;"
                f"UID={username};"
                f"PWD={password};"
                "TrustServerCertificate=yes;"
            )
        else:
            # Windows Auth (admin dev)
            conn = pyodbc.connect(
                "DRIVER={ODBC Driver 17 for SQL Server};"
                "SERVER=localhost;"
                "DATABASE=QL_TOUR1;"
                "Trusted_Connection=yes;"
                "TrustServerCertificate=yes;"
            )

        print("✅ CONNECT DATABASE OK")
        return conn

    except Exception as e:
        print("❌ DB CONNECTION ERROR:", e)
        return None


# =============================================
# TEST LOGIN SQL
# =============================================
def check_login(email, password):
    conn = get_db()
    cur = conn.cursor()

    cur.execute("""
        SELECT ma_nguoi_dung, ho_ten, email, vai_tro
        FROM nguoi_dung
        WHERE email=? AND mat_khau=? AND trang_thai='active'
    """, (email, password))

    row = cur.fetchone()
    conn.close()

    return row


# =============================================
# TEST CONNECTION
# =============================================
def test_connection():
    conn = get_db()
    if not conn:
        print("❌ Không kết nối được DB")
        return

    cur = conn.cursor()

    cur.execute("SELECT DB_NAME()")
    print("📌 DATABASE:", cur.fetchone()[0])

    cur.execute("SELECT COUNT(*) FROM tour")
    print("📌 TOUR COUNT:", cur.fetchone()[0])

    conn.close()


# =============================================
# ROW -> DICT
# =============================================
def row_to_dict(cursor, row):
    cols = [col[0] for col in cursor.description]
    return dict(zip(cols, row))

