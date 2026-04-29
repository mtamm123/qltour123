CREATE DATABASE QL_TOUR;
GO
USE QL_TOUR;
GO

-- ======================
-- 1. NGƯỜI DÙNG & VAI TRÒ
-- ======================
CREATE TABLE nguoi_dung (
    ma_nguoi_dung NVARCHAR(10) PRIMARY KEY,
    ho_ten NVARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(25) UNIQUE,
    email NVARCHAR(255) NOT NULL UNIQUE,
    mat_khau VARBINARY(256) NOT NULL, -- lưu hash
    anh_dai_dien NVARCHAR(MAX),
    trang_thai NVARCHAR(20) DEFAULT N'active',
    ngay_tao DATETIME2 DEFAULT GETDATE()
);

CREATE TABLE vai_tro (
    ma_vai_tro NVARCHAR(10) PRIMARY KEY,
    ten_vai_tro NVARCHAR(50) NOT NULL
);

CREATE TABLE nguoi_dung_vai_tro (
    ma_nguoi_dung NVARCHAR(10),
    ma_vai_tro NVARCHAR(10),
    PRIMARY KEY (ma_nguoi_dung, ma_vai_tro),
    FOREIGN KEY (ma_nguoi_dung) REFERENCES nguoi_dung(ma_nguoi_dung),
    FOREIGN KEY (ma_vai_tro) REFERENCES vai_tro(ma_vai_tro)
);

-- ======================
-- 2. TOUR & LỊCH
-- ======================
CREATE TABLE tour (
    ma_tour NVARCHAR(10) PRIMARY KEY,
    ten_tour NVARCHAR(255) NOT NULL,
    mo_ta NVARCHAR(MAX),
    so_ngay INT CHECK (so_ngay > 0),
    gia DECIMAL(12,2) NOT NULL CHECK (gia > 0),
    suc_chua INT CHECK (suc_chua > 0),
    trang_thai NVARCHAR(20) DEFAULT N'đang mở',
    ngay_tao DATETIME2 DEFAULT GETDATE()
);

CREATE TABLE lich_khoi_hanh (
    ma_lich NVARCHAR(10) PRIMARY KEY,
    ma_tour NVARCHAR(10),
    ngay_bat_dau DATE NOT NULL,
    ngay_ket_thuc DATE NOT NULL,
    so_cho_con_lai INT CHECK (so_cho_con_lai >= 0),

    FOREIGN KEY (ma_tour) REFERENCES tour(ma_tour),
    CHECK (ngay_ket_thuc > ngay_bat_dau)
);

-- ======================
-- 3. ĐƠN & CHI TIẾT
-- ======================
CREATE TABLE don_dat_tour (
    ma_don NVARCHAR(10) PRIMARY KEY,
    ma_nguoi_dung NVARCHAR(10),
    ma_lich NVARCHAR(10),
    tong_tien DECIMAL(12,2),
    trang_thai NVARCHAR(20),
    ngay_dat DATETIME2 DEFAULT GETDATE(),

    FOREIGN KEY (ma_nguoi_dung) REFERENCES nguoi_dung(ma_nguoi_dung),
    FOREIGN KEY (ma_lich) REFERENCES lich_khoi_hanh(ma_lich)
);

CREATE TABLE chi_tiet_hoa_don (
    ma_chi_tiet NVARCHAR(20) PRIMARY KEY,
    ma_don NVARCHAR(10),
    ho_ten NVARCHAR(255),
    loai_khach NVARCHAR(20),
    giay_to NVARCHAR(50),

    FOREIGN KEY (ma_don) REFERENCES don_dat_tour(ma_don)
);

-- ======================
-- 4. THANH TOÁN
-- ======================
CREATE TABLE thanh_toan (
    ma_thanh_toan NVARCHAR(10) PRIMARY KEY,
    ma_don NVARCHAR(10),
    so_tien DECIMAL(12,2),
    phuong_thuc NVARCHAR(50),
    trang_thai NVARCHAR(20),
    ngay_thanh_toan DATETIME2,

    FOREIGN KEY (ma_don) REFERENCES don_dat_tour(ma_don)
);

-- ======================
-- 5. ĐÁNH GIÁ
-- ======================
CREATE TABLE danh_gia (
    ma_danh_gia NVARCHAR(10) PRIMARY KEY,
    ma_nguoi_dung NVARCHAR(10),
    ma_tour NVARCHAR(10),
    so_sao INT CHECK (so_sao BETWEEN 1 AND 5),
    noi_dung NVARCHAR(MAX),
    trang_thai NVARCHAR(20) DEFAULT N'hiển thị',
    ngay_tao DATETIME2 DEFAULT GETDATE(),

    FOREIGN KEY (ma_nguoi_dung) REFERENCES nguoi_dung(ma_nguoi_dung),
    FOREIGN KEY (ma_tour) REFERENCES tour(ma_tour)
);

-- ======================
-- 6. TRIGGER CHUẨN (FIX LOGIC)
-- ======================
GO
CREATE TRIGGER trg_tru_cho_khi_dat_tour
ON chi_tiet_hoa_don
AFTER INSERT
AS
BEGIN
    -- kiểm tra hết chỗ
    IF EXISTS (
        SELECT 1
        FROM lich_khoi_hanh l
        JOIN don_dat_tour d ON l.ma_lich = d.ma_lich
        JOIN inserted i ON d.ma_don = i.ma_don
        GROUP BY l.ma_lich, l.so_cho_con_lai
        HAVING l.so_cho_con_lai < COUNT(i.ma_chi_tiet)
    )
    BEGIN
        RAISERROR (N'Không đủ chỗ!',16,1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    -- trừ đúng số khách
    UPDATE l
    SET so_cho_con_lai = so_cho_con_lai - x.so_khach
    FROM lich_khoi_hanh l
    JOIN don_dat_tour d ON l.ma_lich = d.ma_lich
    JOIN (
        SELECT ma_don, COUNT(*) AS so_khach
        FROM inserted
        GROUP BY ma_don
    ) x ON d.ma_don = x.ma_don;
END;
GO

-- ======================
-- 7. PROCEDURE CHUẨN
-- ======================
GO
CREATE PROCEDURE sp_dat_tour_nhieu_khach
    @ma_don NVARCHAR(10),
    @ma_nguoi_dung NVARCHAR(10),
    @ma_lich NVARCHAR(10),
    @danh_sach_khach NVARCHAR(MAX)
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN

        INSERT INTO don_dat_tour(ma_don, ma_nguoi_dung, ma_lich, trang_thai)
        VALUES (@ma_don, @ma_nguoi_dung, @ma_lich, N'đã đặt');

        DECLARE @xml XML;
        SET @xml = CAST('<x>' + REPLACE(@danh_sach_khach, ',', '</x><x>') + '</x>' AS XML);

        INSERT INTO chi_tiet_hoa_don
        SELECT 
            CONCAT(@ma_don, ROW_NUMBER() OVER(ORDER BY (SELECT 1))),
            @ma_don,
            PARSENAME(REPLACE(value,'|','.'),3),
            PARSENAME(REPLACE(value,'|','.'),2),
            PARSENAME(REPLACE(value,'|','.'),1)
        FROM (
            SELECT T.c.value('.', 'NVARCHAR(MAX)') AS value
            FROM @xml.nodes('/x') T(c)
        ) A;

        -- tự tính tổng tiền
        UPDATE d
        SET tong_tien = t.gia * x.so_khach
        FROM don_dat_tour d
        JOIN lich_khoi_hanh l ON d.ma_lich = l.ma_lich
        JOIN tour t ON l.ma_tour = t.ma_tour
        JOIN (
            SELECT ma_don, COUNT(*) AS so_khach
            FROM chi_tiet_hoa_don
            GROUP BY ma_don
        ) x ON d.ma_don = x.ma_don
        WHERE d.ma_don = @ma_don;

        COMMIT
    END TRY
    BEGIN CATCH
        ROLLBACK
           RAISERROR (N'Có lỗi xảy ra khi đặt tour',16,1)
    END CATCH
END;
GO

-- ======================
-- 8. VIEW
-- ======================
CREATE VIEW v_doanh_thu_theo_tour
AS
SELECT 
    t.ma_tour,
    t.ten_tour,
    COUNT(DISTINCT d.ma_don) AS so_don,
    SUM(d.tong_tien) AS tong_doanh_thu
FROM tour t
LEFT JOIN lich_khoi_hanh l ON t.ma_tour = l.ma_tour
LEFT JOIN don_dat_tour d ON l.ma_lich = d.ma_lich
GROUP BY t.ma_tour, t.ten_tour;
GO

-- ======================
-- 9. INDEX (QUAN TRỌNG)
-- ======================
CREATE INDEX idx_don_ma_lich ON don_dat_tour(ma_lich);
CREATE INDEX idx_lich_ma_tour ON lich_khoi_hanh(ma_tour);
CREATE INDEX idx_cthd_ma_don ON chi_tiet_hoa_don(ma_don);
GO

INSERT INTO nguoi_dung VALUES
('ND01', N'Nguyễn Văn An', '0901111111', 'an@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND02', N'Trần Thị Bình', '0901111112', 'binh@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND03', N'Lê Văn Cường', '0901111113', 'cuong@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND04', N'Phạm Thị Dung', '0901111114', 'dung@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND05', N'Hoàng Văn Em', '0901111115', 'em@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND06', N'Vũ Thị Phương', '0901111116', 'phuong@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND07', N'Đặng Văn Giang', '0901111117', 'giang@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND08', N'Bùi Thị Hạnh', '0901111118', 'hanh@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND09', N'Đỗ Văn Khoa', '0901111119', 'khoa@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE()),
('ND10', N'Ngô Thị Lan', '0901111120', 'lan@gmail.com', CAST('123' AS VARBINARY), NULL, N'active', GETDATE());

INSERT INTO vai_tro VALUES
('VT01', N'Admin'),
('VT02', N'Nhân viên'),
('VT03', N'Khách hàng');

INSERT INTO nguoi_dung_vai_tro VALUES
('ND01','VT01'),
('ND02','VT03'),
('ND03','VT03'),
('ND04','VT03'),
('ND05','VT03'),
('ND06','VT02'),
('ND07','VT03'),
('ND08','VT03'),
('ND09','VT03'),
('ND10','VT03');

INSERT INTO tour VALUES
('T01', N'Tour Đà Lạt', N'Khám phá Đà Lạt', 3, 2500000, 30, N'đang mở', GETDATE()),
('T02', N'Tour Nha Trang', N'Biển đẹp', 4, 3200000, 25, N'đang mở', GETDATE()),
('T03', N'Tour Phú Quốc', N'Đảo ngọc', 5, 5000000, 20, N'đang mở', GETDATE()),
('T04', N'Tour Sapa', N'Tây Bắc', 3, 2800000, 30, N'đang mở', GETDATE()),
('T05', N'Tour Hạ Long', N'Vịnh đẹp', 2, 1800000, 40, N'đang mở', GETDATE()),
('T06', N'Tour Huế', N'Cố đô', 3, 2200000, 30, N'đang mở', GETDATE()),
('T07', N'Tour Hội An', N'Phố cổ', 2, 2000000, 25, N'đang mở', GETDATE()),
('T08', N'Tour Đà Nẵng', N'Biển & núi', 3, 2700000, 35, N'đang mở', GETDATE()),
('T09', N'Tour Côn Đảo', N'Lịch sử', 4, 4500000, 20, N'đang mở', GETDATE()),
('T10', N'Tour Tây Ninh', N'Núi Bà Đen', 1, 900000, 50, N'đang mở', GETDATE());

INSERT INTO lich_khoi_hanh (ma_lich, ma_tour, ngay_bat_dau, ngay_ket_thuc, so_cho_con_lai)
VALUES
('LK01', 'T01', '2026-05-10', '2026-05-13', 25),
('LK02', 'T02', '2026-05-15', '2026-05-19', 18),
('LK03', 'T03', '2026-05-20', '2026-05-23', 12),
('LK04', 'T04', '2026-05-25', '2026-05-30', 20),
('LK05', 'T05', '2026-06-01', '2026-06-04', 30),
('LK06', 'T06', '2026-06-05', '2026-06-09', 15),
('LK07', 'T07', '2026-06-10', '2026-06-14', 22),
('LK08', 'T08', '2026-06-15', '2026-06-18', 10),
('LK09', 'T09', '2026-06-20', '2026-06-24', 28),
('LK10', 'T10', '2026-06-25', '2026-06-29', 16),
('LK11', 'T01', '2026-07-02', '2026-07-05', 24),
('LK12', 'T02', '2026-07-08', '2026-07-12', 19),
('LK13', 'T03', '2026-07-15', '2026-07-18', 14),
('LK14', 'T04', '2026-07-20', '2026-07-25', 21),
('LK15', 'T05', '2026-07-28', '2026-07-31', 26);
INSERT INTO don_dat_tour VALUES
('DH21','ND02','L21',2500000,N'đã đặt',GETDATE()),
('DH22','ND03','L22',3200000,N'đã đặt',GETDATE()),
('DH23','ND04','L23',5000000,N'đã đặt',GETDATE()),
('DH24','ND05','L24',2800000,N'đã đặt',GETDATE()),
('DH25','ND06','L25',1800000,N'đã đặt',GETDATE()),
('DH26','ND07','L26',2200000,N'đã đặt',GETDATE()),
('DH27','ND08','L27',2000000,N'đã đặt',GETDATE()),
('DH28','ND09','L28',2700000,N'đã đặt',GETDATE()),
('DH29','ND10','L29',4500000,N'đã đặt',GETDATE()),
('DH30','ND02','L30',900000,N'đã đặt',GETDATE());

INSERT INTO chi_tiet_hoa_don VALUES
('CT21','DH21',N'Nguyễn A',N'Người lớn','111'),
('CT22','DH21',N'Trần B',N'Trẻ em','222'),

('CT23','DH22',N'Lê C',N'Người lớn','333'),
('CT24','DH23',N'Phạm D',N'Người lớn','444'),
('CT25','DH24',N'Hoàng E',N'Trẻ em','555'),

('CT26','DH25',N'Vũ F',N'Người lớn','666'),
('CT27','DH26',N'Đặng G',N'Người lớn','777'),
('CT28','DH27',N'Bùi H',N'Trẻ em','888'),

('CT29','DH28',N'Đỗ K',N'Người lớn','999'),
('CT30','DH29',N'Ngô L',N'Người lớn','101');


INSERT INTO thanh_toan VALUES
('TT21','DH21',2500000,N'Momo',N'thành công',GETDATE()),
('TT22','DH22',3200000,N'Chuyển khoản',N'thành công',GETDATE()),
('TT23','DH23',5000000,N'Tiền mặt',N'thành công',GETDATE()),
('TT24','DH24',2800000,N'ATM',N'thành công',GETDATE()),
('TT25','DH25',1800000,N'Momo',N'thành công',GETDATE()),

('TT26','DH26',2200000,N'Chuyển khoản',N'thành công',GETDATE()),
('TT27','DH27',2000000,N'Tiền mặt',N'thành công',GETDATE()),
('TT28','DH28',2700000,N'Momo',N'thành công',GETDATE()),
('TT29','DH29',4500000,N'ATM',N'thành công',GETDATE()),
('TT30','DH30',900000,N'Tiền mặt',N'thành công',GETDATE());


INSERT INTO danh_gia VALUES
('DG21','ND02','T01',5,N'Rất tốt',N'hiển thị',GETDATE()),
('DG22','ND03','T02',4,N'Ổn',N'hiển thị',GETDATE()),
('DG23','ND04','T03',5,N'Tuyệt vời',N'hiển thị',GETDATE()),
('DG24','ND05','T04',4,N'Hài lòng',N'hiển thị',GETDATE()),
('DG25','ND06','T05',5,N'Xuất sắc',N'hiển thị',GETDATE()),

('DG26','ND07','T06',4,N'Khá ổn',N'hiển thị',GETDATE()),
('DG27','ND08','T07',3,N'Bình thường',N'hiển thị',GETDATE()),
('DG28','ND09','T08',5,N'Rất đẹp',N'hiển thị',GETDATE()),
('DG29','ND10','T09',5,N'Tuyệt',N'hiển thị',GETDATE()),
('DG30','ND02','T10',4,N'Ok',N'hiển thị',GETDATE());

CREATE TABLE nha_cung_cap (
    ma_ncc NVARCHAR(10) PRIMARY KEY,
    ten_ncc NVARCHAR(255) NOT NULL,
    loai_dich_vu NVARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(20),
    email NVARCHAR(255),
    dia_chi NVARCHAR(255),
    trang_thai NVARCHAR(20) DEFAULT N'hoạt động'
);

CREATE TABLE ho_tro (
    ma_ho_tro NVARCHAR(10) PRIMARY KEY,
    ma_nguoi_dung NVARCHAR(10) NOT NULL,
    tieu_de NVARCHAR(255) NOT NULL,
    noi_dung NVARCHAR(MAX) NOT NULL,
    trang_thai NVARCHAR(20) DEFAULT N'đang xử lý',
    ngay_tao DATETIME DEFAULT GETDATE(),

    CONSTRAINT FK_ho_tro_nguoi_dung
    FOREIGN KEY (ma_nguoi_dung) REFERENCES nguoi_dung(ma_nguoi_dung)
);


CREATE TABLE phan_hoi_ho_tro (
    ma_phan_hoi NVARCHAR(10) PRIMARY KEY,
    ma_ho_tro NVARCHAR(10) NOT NULL,
    ma_nhan_vien NVARCHAR(10) NOT NULL,
    noi_dung NVARCHAR(MAX),
    ngay_phan_hoi DATETIME DEFAULT GETDATE(),

    CONSTRAINT FK_phan_hoi_ho_tro
    FOREIGN KEY (ma_ho_tro) REFERENCES ho_tro(ma_ho_tro),

    CONSTRAINT FK_phan_hoi_nhan_vien
    FOREIGN KEY (ma_nhan_vien) REFERENCES nguoi_dung(ma_nguoi_dung)
);

INSERT INTO nha_cung_cap VALUES
('NCC01',N'Khách sạn Đà Lạt',N'Lưu trú','0909000001','hotel1@gmail.com',N'Đà Lạt',N'hoạt động'),
('NCC02',N'Xe du lịch Nha Trang',N'Ve xe','0909000002','bus2@gmail.com',N'Nha Trang',N'hoạt động'),
('NCC03',N'Resort Phú Quốc',N'Lưu trú','0909000003','resort3@gmail.com',N'Phú Quốc',N'hoạt động'),
('NCC04',N'Nhà hàng Sapa',N'Ăn uống','0909000004','food4@gmail.com',N'Sapa',N'hoạt động'),
('NCC05',N'Du thuyền Hạ Long',N'Du lịch','0909000005','ship5@gmail.com',N'Hạ Long',N'hoạt động');

INSERT INTO ho_tro VALUES
('HT01','ND02',N'Hỏi thông tin tour',N'Tour Đà Lạt còn chỗ không?',N'đang xử lý',GETDATE()),
('HT02','ND03',N'Hủy đơn',N'Mình muốn hủy đơn DH21',N'đang xử lý',GETDATE()),
('HT03','ND04',N'Lỗi thanh toán',N'Thanh toán không thành công',N'đang xử lý',GETDATE()),
('HT04','ND05',N'Đổi lịch',N'Có thể đổi ngày không?',N'đang xử lý',GETDATE()),
('HT05','ND07',N'Hỏi giá',N'Giá đã bao gồm ăn uống chưa?',N'đang xử lý',GETDATE());

INSERT INTO phan_hoi_ho_tro VALUES
('PH01','HT01','ND06',N'Tour vẫn còn chỗ bạn nhé',GETDATE()),
('PH02','HT02','ND06',N'Đã hỗ trợ hủy đơn cho bạn',GETDATE()),
('PH03','HT03','ND06',N'Bạn vui lòng thử lại hoặc đổi phương thức thanh toán',GETDATE()),
('PH04','HT04','ND06',N'Bạn có thể chọn lịch khác trong hệ thống',GETDATE()),
('PH05','HT05','ND06',N'Giá đã bao gồm ăn uống cơ bản',GETDATE());

USE QL_TOUR;
GO

-- nếu đã tồn tại thì bỏ qua
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'ROLE_ADMIN')
    CREATE ROLE ROLE_ADMIN;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'ROLE_EMPLOYEE')
    CREATE ROLE ROLE_EMPLOYEE;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'ROLE_CUSTOMER')
    CREATE ROLE ROLE_CUSTOMER;
GO
USE QL_TOUR;
GO

-- ADMIN
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.nguoi_dung TO ROLE_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.tour TO ROLE_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.don_dat_tour TO ROLE_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.thanh_toan TO ROLE_ADMIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ho_tro TO ROLE_ADMIN;

-- EMPLOYEE
GRANT SELECT ON dbo.tour TO ROLE_EMPLOYEE;
GRANT SELECT, UPDATE ON dbo.don_dat_tour TO ROLE_EMPLOYEE;
GRANT SELECT, UPDATE ON dbo.thanh_toan TO ROLE_EMPLOYEE;

GRANT SELECT, INSERT, UPDATE ON dbo.phan_hoi_ho_tro TO ROLE_EMPLOYEE;
GRANT SELECT ON dbo.ho_tro TO ROLE_EMPLOYEE;

-- CUSTOMER
GRANT SELECT ON dbo.tour TO ROLE_CUSTOMER;
GRANT INSERT ON dbo.don_dat_tour TO ROLE_CUSTOMER;
GRANT INSERT ON dbo.danh_gia TO ROLE_CUSTOMER;
GRANT INSERT, SELECT ON dbo.ho_tro TO ROLE_CUSTOMER;

-- tạo login (server)
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'employee_login')
    CREATE LOGIN employee_login WITH PASSWORD = '123456';
GO

-- vào đúng DB
USE QL_TOUR;
GO

-- tạo user (database)
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'employee_user')
    CREATE USER employee_user FOR LOGIN employee_login;
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'admin_login')
    CREATE LOGIN admin_login WITH PASSWORD = '123456';

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'customer_login')
    CREATE LOGIN customer_login WITH PASSWORD = '123456';
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'admin_login')
    CREATE LOGIN admin_login WITH PASSWORD = '123456';

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'customer_login')
    CREATE LOGIN customer_login WITH PASSWORD = '123456';
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'admin_user')
    CREATE USER admin_user FOR LOGIN admin_login;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'customer_user')
    CREATE USER customer_user FOR LOGIN customer_login;
GO

ALTER ROLE ROLE_ADMIN ADD MEMBER admin_user;
ALTER ROLE ROLE_CUSTOMER ADD MEMBER customer_user;

SELECT name FROM sys.database_principals;

SELECT 
    r.name AS role_name,
    u.name AS user_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals u ON rm.member_principal_id = u.principal_id;

SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES

CREATE TABLE lich_khoi_hanh (
    ma_lich NVARCHAR(10) PRIMARY KEY,
    ma_tour NVARCHAR(10) NOT NULL,
    ngay_bat_dau DATE NOT NULL,
    ngay_ket_thuc DATE NOT NULL,
    so_cho_con_lai INT CHECK (so_cho_con_lai >= 0),

    FOREIGN KEY (ma_tour) REFERENCES dbo.tour(ma_tour),

    CHECK (ngay_ket_thuc > ngay_bat_dau)
);

INSERT INTO lich_khoi_hanh
(ma_lich, ma_tour, ngay_bat_dau, ngay_ket_thuc, so_cho_con_lai)
VALUES
('LK01','T01','2026-05-10','2026-05-13',25),
('LK02','T02','2026-05-15','2026-05-18',18),
('LK03','T03','2026-05-20','2026-05-23',12),
('LK04','T04','2026-05-25','2026-05-29',20),
('LK05','T05','2026-06-01','2026-06-04',30);

SELECT 
    name AS UserName,
    type_desc AS Type,
    create_date
FROM sys.database_principals
WHERE type IN ('S', 'U', 'G');

SELECT 
    dp.name AS UserName,
    rp.name AS RoleName
FROM sys.database_role_members rm
JOIN sys.database_principals rp 
    ON rm.role_principal_id = rp.principal_id
JOIN sys.database_principals dp 
    ON rm.member_principal_id = dp.principal_id
ORDER BY dp.name;

SELECT 
    r.name AS RoleName,
    perm.permission_name,
    perm.state_desc,
    obj.name AS ObjectName
FROM sys.database_permissions perm
JOIN sys.database_principals r 
    ON perm.grantee_principal_id = r.principal_id
LEFT JOIN sys.objects obj 
    ON perm.major_id = obj.object_id
ORDER BY r.name;

CREATE VIEW vw_tour_public AS
SELECT 
    ma_tour,
    ten_tour,
    gia,
    ngay_khoi_hanh,
    ngay_ket_thuc
FROM tour;

SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tour';

CREATE OR ALTER VIEW vw_tour_public AS
SELECT
    ma_tour,
    ten_tour,
    mo_ta,
    so_ngay,
    gia,
    suc_chua,
    trang_thai
FROM tour;


SELECT * FROM lich_khoi_hanh

CREATE OR ALTER VIEW vw_tour_lich AS
SELECT
    t.ma_tour,
    t.ten_tour,
    t.gia,
    t.suc_chua,
    l.ma_lich,
    l.ngay_khoi_hanh,
    l.ngay_ket_thuc,
    l.so_cho_con_lai
FROM tour t
JOIN lich_khoi_hanh l ON t.ma_tour = l.ma_tour;

CREATE OR ALTER VIEW vw_tour_lich AS
SELECT
    t.ma_tour,
    t.ten_tour,
    t.mo_ta,
    t.so_ngay,
    t.gia,
    t.suc_chua,
    t.trang_thai,

    l.ma_lich,
    l.ngay_bat_dau,
    l.ngay_ket_thuc,
    l.so_cho_con_lai

FROM tour t
JOIN lich_khoi_hanh l
    ON t.ma_tour = l.ma_tour;

    CREATE OR ALTER VIEW vw_tour_lich_employee AS
SELECT
    t.*,
    l.ma_lich,
    l.ngay_bat_dau,
    l.ngay_ket_thuc,
    l.so_cho_con_lai
FROM tour t
JOIN lich_khoi_hanh l
    ON t.ma_tour = l.ma_tour;

    CREATE OR ALTER VIEW vw_tour_public AS
SELECT
    t.ma_tour,
    t.ten_tour,
    t.mo_ta,
    t.gia,
    l.ma_lich,
    l.ngay_bat_dau,
    l.ngay_ket_thuc,
    l.so_cho_con_lai
FROM tour t
JOIN lich_khoi_hanh l
    ON t.ma_tour = l.ma_tour
WHERE t.trang_thai = 'HoatDong';

GRANT SELECT ON vw_tour_public TO ROLE_CUSTOMER;
GRANT SELECT ON vw_tour_lich_employee TO ROLE_EMPLOYEE;
GRANT SELECT ON vw_tour_lich TO ROLE_ADMIN;

USE QL_TOUR1;
GO

DROP ROLE IF EXISTS ROLE_ADMIN;
DROP ROLE IF EXISTS ROLE_EMPLOYEE;
DROP ROLE IF EXISTS ROLE_CUSTOMER;
GO


SELECT 
    r.name AS role_name,
    m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id;

USE QL_TOUR1;
GO

ALTER ROLE ROLE_ADMIN DROP MEMBER admin_user;
ALTER ROLE ROLE_EMPLOYEE DROP MEMBER employee_user;
ALTER ROLE ROLE_CUSTOMER DROP MEMBER customer_user;
GO

DROP ROLE ROLE_ADMIN;
DROP ROLE ROLE_EMPLOYEE;
DROP ROLE ROLE_CUSTOMER;

ALTER TABLE nguoi_dung ADD role NVARCHAR(20);

SELECT * FROM nguoi_dung

SELECT * FROM nguoi_dung WHERE email='an@gmail.com'

SELECT email, mat_khau, role
FROM nguoi_dung

UPDATE nguoi_dung
SET role = 'ROLE_ADMIN'
WHERE email = 'an@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_CUSTOMER'
WHERE email = 'binh@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_CUSTOMER'
WHERE email = 'cuong@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_CUSTOMER'
WHERE email = 'dung@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_CUSTOMER'
WHERE email = 'em@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_EMPLOYEE'
WHERE email = 'phuong@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_EMPLOYEE'
WHERE email = 'giang@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_EMPLOYEE'
WHERE email = 'hanh@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_EMPLOYEE'
WHERE email = 'khoa@gmail.com';

UPDATE nguoi_dung
SET role = 'ROLE_CUSTOMER'
WHERE email = 'lan@gmail.com';

SELECT email, mat_khau, role FROM nguoi_dung

UPDATE nguoi_dung
SET mat_khau = '123'
ALTER TABLE nguoi_dung
ALTER COLUMN mat_khau VARCHAR(100);

UPDATE nguoi_dung
SET mat_khau = '123';


USE QL_TOUR1;
GO

CREATE ROLE AdminRole;
CREATE ROLE StaffRole;
CREATE ROLE CustomerRole;
GO

GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.tour TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.vai_tro TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.thanh_toan TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.phan_hoi_ho_tro TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.nguoi_dung_vai_tro TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.lich_khoi_hanh TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.nha_cung_cap TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.don_dat_tour TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ho_tro TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.nguoi_dung TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.chi_tiet_hoa_don TO AdminRole;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.danh_gia TO AdminRole;


GRANT SELECT ON dbo.tour TO StaffRole;
GRANT INSERT, UPDATE ON dbo.lich_khoi_hanh TO StaffRole;
GRANT SELECT, UPDATE ON dbo.don_dat_tour TO StaffRole;
GRANT SELECT, INSERT, UPDATE ON dbo.thanh_toan TO StaffRole;
GRANT SELECT ON dbo.nguoi_dung TO StaffRole;
GRANT SELECT, UPDATE ON dbo.ho_tro TO StaffRole;
GRANT SELECT ON dbo.danh_gia TO StaffRole;


GRANT SELECT ON dbo.tour TO CustomerRole;
GRANT INSERT, SELECT ON dbo.don_dat_tour TO CustomerRole;
GRANT INSERT, SELECT ON dbo.thanh_toan TO CustomerRole;
GRANT INSERT, SELECT ON dbo.danh_gia TO CustomerRole;
GRANT INSERT, SELECT ON dbo.ho_tro TO CustomerRole;

CREATE LOGIN an WITH PASSWORD = '123';
CREATE LOGIN phuong WITH PASSWORD = '123';
CREATE LOGIN binh WITH PASSWORD = '123';

USE QL_TOUR1;
GO

CREATE USER an FOR LOGIN an;
CREATE USER phuong FOR LOGIN phuong;
CREATE USER binh FOR LOGIN binh;

ALTER ROLE AdminRole ADD MEMBER an;
ALTER ROLE StaffRole ADD MEMBER phuong;
ALTER ROLE CustomerRole ADD MEMBER binh;

SELECT name
FROM sys.sql_logins
WHERE name = 'an';

SELECT name
FROM sys.sql_logins
ORDER BY name;

SELECT * FROM nguoi_dung

SELECT email, mat_khau, trang_thai FROM nguoi_dung;