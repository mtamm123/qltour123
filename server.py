from flask import Flask, jsonify, request, render_template, session, redirect
from flask_cors import CORS
import pyodbc
from datetime import date, datetime
import decimal
import traceback


import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

app = Flask(
    __name__,
    template_folder=os.path.join(BASE_DIR, "templates"),
    static_folder=os.path.join(BASE_DIR, "static")
)
app.secret_key = "qltour1_secret_key_2026"
CORS(app)

# =============================================
# CẤU HÌNH KẾT NỐI SQL SERVER
# =============================================
def get_db():
    conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        "SERVER=localhost;"
        "DATABASE=QL_TOUR1;"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)



def row_to_dict(cursor, row):
    cols = [col[0] for col in cursor.description]
    d = {}
    for col, val in zip(cols, row):
        if isinstance(val, (date, datetime)):
            d[col] = val.isoformat()
        elif isinstance(val, decimal.Decimal):
            d[col] = float(val)
        elif isinstance(val, bytes):
            d[col] = val.decode("utf-8", errors="ignore")
        else:
            d[col] = val
    return d

# =============================================
# HÀM BẮT LỖI CHUNG
# =============================================
def handle_error(e):
    print("\n========== LOI ==========")
    print(str(e))
    traceback.print_exc()
    print("=========================\n")
    return jsonify({"error": str(e)}), 500

@app.route("/login")
def login_page():
    return render_template("login.html")

    return jsonify({
    "message": "success",
    "redirect": {
        "ROLE_ADMIN": "/admin",
        "ROLE_EMPLOYEE": "/employee",
        "ROLE_CUSTOMER": "/home"
    }[user["role"]]
})



def check_login(email, password):
    conn = get_db()
    cur = conn.cursor()

    cur.execute("""
        SELECT email, role
        FROM nguoi_dung
        WHERE email=? AND mat_khau=?
    """, (email, password))

    row = cur.fetchone()

    if not row:
        return None

    return {
        "email": row[0],
        "role": row[1]
    }

@app.route("/index")
def index():
    if "user_id" not in session:
        return redirect("/login")

    return render_template("index.html")

@app.route("/admin")
def admin():
    if session.get("role") != "ROLE_ADMIN":
        return "Không có quyền", 403

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT * FROM vw_tour_lich")
    data = cur.fetchall()

    return render_template("index.html", data=data)



@app.route("/employee")
def employee():
    if session.get("role") != "ROLE_EMPLOYEE":
        return "Không có quyền", 403

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT * FROM vw_tour_lich_employee")
    data = cur.fetchall()

    return render_template("index.html", data=data)


@app.route("/home")
def admin_home():
    if session.get("role") != "ROLE_CUSTOMER":
        return "Không có quyền", 403

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT * FROM vw_tour_public")
    data = cur.fetchall()

    return render_template("index.html", data=data)

@app.route("/logout")
def logout():
    session.clear()
    return redirect("/login")

# =============================================
# TRANG CHÍNH
# =============================================
@app.route("/")
def root():
    return redirect("/login")

from flask import request, jsonify, session


@app.route("/api/login", methods=["POST"])
def api_login():
    try:
        data = request.get_json(force=True)

        email = data.get("email")
        mat_khau = data.get("mat_khau")

        print("INPUT:", email, mat_khau)

        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT ma_nguoi_dung, email, role
            FROM nguoi_dung
            WHERE email = ?
              AND mat_khau = ?
              AND trang_thai = 'active'
        """, (email, mat_khau))

        user = cur.fetchone()

        print("DEBUG USER:", user)

        if not user:
            return jsonify({"error": "Sai email hoặc mật khẩu"}), 401

        session["user_id"] = user[0]
        session["email"] = user[1]
        session["role"] = user[2]

        return jsonify({"message": "success", "redirect": "/index"})

    except Exception as e:
        print("LOGIN ERROR:", e)
        return jsonify({"error": str(e)}), 500




# =============================================
# API DASHBOARD
# =============================================
@app.route("/api/dashboard")
def dashboard():
    try:
        conn = get_db()
        cur = conn.cursor()

        stats = {}

        cur.execute("SELECT COUNT(*) FROM tour WHERE trang_thai = N'đang mở'")
        stats["tour_active"] = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM nguoi_dung WHERE trang_thai = N'active'")
        stats["nguoi_dung"] = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM don_dat_tour WHERE trang_thai = N'đã đặt'")
        stats["don_dat"] = cur.fetchone()[0]

        cur.execute("SELECT COALESCE(SUM(so_tien),0) FROM thanh_toan WHERE trang_thai = N'thành công'")
        stats["doanh_thu"] = float(cur.fetchone()[0])

        conn.close()
        return jsonify(stats)

    except Exception as e:
        return handle_error(e)

# =============================================
# API TOUR
# =============================================
@app.route("/api/tours", methods=["GET"])
def get_tours():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM tour ORDER BY ngay_tao DESC")
        rows = cur.fetchall()
        conn.close()
        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)

@app.route("/api/tours", methods=["POST"])
def create_tour():
    try:
        data = request.json
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            INSERT INTO tour(ma_tour, ten_tour, mo_ta, so_ngay, gia, suc_chua, trang_thai)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            data["ma_tour"],
            data["ten_tour"],
            data.get("mo_ta", ""),
            data["so_ngay"],
            data["gia"],
            data["suc_chua"],
            data.get("trang_thai", "đang mở")
        ))

        conn.commit()
        conn.close()
        return jsonify({"message": "Thêm tour thành công"})

    except Exception as e:
        return handle_error(e)

@app.route("/api/tours/<id>", methods=["PUT"])
def update_tour(id):
    try:
        data = request.json
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            UPDATE tour
            SET ten_tour=?, mo_ta=?, so_ngay=?, gia=?, suc_chua=?, trang_thai=?
            WHERE ma_tour=?
        """, (
            data["ten_tour"],
            data.get("mo_ta", ""),
            data["so_ngay"],
            data["gia"],
            data["suc_chua"],
            data["trang_thai"],
            id
        ))

        conn.commit()
        conn.close()
        return jsonify({"message": "Cập nhật thành công"})

    except Exception as e:
        return handle_error(e)

@app.route("/api/tours/<id>", methods=["DELETE"])
def delete_tour(id):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("DELETE FROM tour WHERE ma_tour=?", (id,))
        conn.commit()
        conn.close()
        return jsonify({"message": "Xóa thành công"})

    except Exception as e:
        return handle_error(e)

# =============================================
# API NHÀ CUNG CẤP
# =============================================
@app.route("/api/nhacungcap", methods=["GET"])
def get_ncc():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM nha_cung_cap ORDER BY ten_ncc")
        rows = cur.fetchall()
        conn.close()
        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)

@app.route("/api/nhacungcap", methods=["POST"])
def create_ncc():
    try:
        data = request.json
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            INSERT INTO nha_cung_cap(ma_ncc, ten_ncc, loai_dich_vu, so_dien_thoai, email, dia_chi, trang_thai)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            data["ma_ncc"],
            data["ten_ncc"],
            data["loai_dich_vu"],
            data["so_dien_thoai"],
            data["email"],
            data["dia_chi"],
            data["trang_thai"]
        ))

        conn.commit()
        conn.close()
        return jsonify({"message": "Thêm NCC thành công"})

    except Exception as e:
        return handle_error(e)

@app.route("/api/nhacungcap/<id>", methods=["DELETE"])
def delete_ncc(id):
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("DELETE FROM nha_cung_cap WHERE ma_ncc=?", (id,))
        conn.commit()
        conn.close()
        return jsonify({"message": "Xóa NCC thành công"})

    except Exception as e:
        return handle_error(e)

# =============================================
# API THANH TOÁN
# =============================================
@app.route("/api/thanhtoan")
def thanhtoan():
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT
                tt.ma_thanh_toan,
                tt.ma_don,
                nd.ho_ten,
                t.ten_tour,
                tt.so_tien,
                tt.phuong_thuc,
                tt.trang_thai,
                tt.ngay_thanh_toan
            FROM thanh_toan tt
            JOIN don_dat_tour d ON tt.ma_don = d.ma_don
            JOIN nguoi_dung nd ON d.ma_nguoi_dung = nd.ma_nguoi_dung
            JOIN lich_khoi_hanh l ON d.ma_lich = l.ma_lich
            JOIN tour t ON l.ma_tour = t.ma_tour
            ORDER BY tt.ma_thanh_toan
        """)

        rows = cur.fetchall()
        conn.close()

        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)
# =============================================
# API NGƯỜI DÙNG
# =============================================
@app.route("/api/nguoidung")
def nguoidung():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM nguoi_dung")
        rows = cur.fetchall()
        conn.close()
        return jsonify([row_to_dict(cur, r) for r in rows])
    except Exception as e:
        return handle_error(e)


# =============================================
# API ĐÁNH GIÁ
# =============================================
@app.route("/api/danhgia")
def danhgia():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("SELECT * FROM danh_gia")
        rows = cur.fetchall()
        conn.close()
        return jsonify([row_to_dict(cur, r) for r in rows])
    except Exception as e:
        return handle_error(e)


# =============================================
# API HỖ TRỢ
# =============================================
@app.route("/api/hotro")
def hotro():
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT
                h.ma_ho_tro,
                nd.ho_ten,
                h.tieu_de,
                h.noi_dung,
                0 AS so_phan_hoi,
                h.trang_thai,
                h.ngay_tao
            FROM ho_tro h
            JOIN nguoi_dung nd
                ON h.ma_nguoi_dung = nd.ma_nguoi_dung
            ORDER BY h.ma_ho_tro
        """)

        rows = cur.fetchall()
        conn.close()

        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)


# =============================================
# API ĐƠN ĐẶT
# =============================================
@app.route("/api/dondat")
def dondat():
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT 
                d.ma_don,
                nd.ho_ten,
                t.ten_tour,
                l.ngay_bat_dau,
                l.ngay_ket_thuc,
                1 AS so_khach,
                d.tong_tien,
                d.trang_thai
            FROM don_dat_tour d
            JOIN nguoi_dung nd ON d.ma_nguoi_dung = nd.ma_nguoi_dung
            JOIN lich_khoi_hanh l ON d.ma_lich = l.ma_lich
            JOIN tour t ON l.ma_tour = t.ma_tour
            ORDER BY d.ma_don
        """)

        rows = cur.fetchall()
        conn.close()

        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)


# =============================================
# API LỊCH KHỞI HÀNH
# =============================================
@app.route("/api/lichkhaihanh")
def lich():
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT 
                l.ma_lich,
                l.ma_tour,
                t.ten_tour,
                t.gia,
                t.suc_chua,
                l.ngay_bat_dau,
                l.ngay_ket_thuc,
                l.so_cho_con_lai,
                t.trang_thai
            FROM lich_khoi_hanh l
            JOIN tour t ON l.ma_tour = t.ma_tour
            ORDER BY l.ngay_bat_dau
        """)

        rows = cur.fetchall()
        conn.close()

        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)
# =============================================
# API DOANH THU
# =============================================
@app.route("/api/doanhthu")
def doanhthu():
    try:
        conn = get_db()
        cur = conn.cursor()

        cur.execute("""
            SELECT
                t.ma_tour,
                t.ten_tour,
                COUNT(d.ma_don) AS so_don,
                ISNULL(SUM(d.tong_tien),0) AS tong_doanh_thu
            FROM tour t
            LEFT JOIN lich_khoi_hanh l ON t.ma_tour = l.ma_tour
            LEFT JOIN don_dat_tour d ON l.ma_lich = d.ma_lich
            GROUP BY t.ma_tour, t.ten_tour
            ORDER BY tong_doanh_thu DESC
        """)

        rows = cur.fetchall()
        conn.close()

        return jsonify([row_to_dict(cur, r) for r in rows])

    except Exception as e:
        return handle_error(e)
# =============================================
# RUN
# =============================================
if __name__ == "__main__":
    app.run(debug=True, port=5000)