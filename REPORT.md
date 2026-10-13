# REPORT — Lab Day 9

| Thông tin | Giá trị |
|---|---|
| Họ và tên | Lưu Quang Khải |
| MSSV (đúng bằng `LAB_STUDENT_ID` trong `.env`) | `2A202602599` |
| GitHub | `luuquangkhai9` |
| Trip dùng cho bài tập sập và chạy lại | `trip-06570` |

## Kết quả cuối

- `dataset_version` của bạn: `1ab78ac6d23b`
- Số khung hình train / val / test của bạn: **693 / 159 / 167**.
- MSSV đầy đủ được giữ nguyên trong môi trường chạy và mọi bằng chứng.
- Số liệu dưới đây lấy từ các lần chạy tại máy cá nhân; pipeline và thí nghiệm được thực thi với hỗ trợ tự động của Codex. Phần nhận xét là bản tổng hợp từ kết quả và mã nguồn, cần được người nộp đọc lại để chuẩn bị vấn đáp.
- Log các bước và thí nghiệm nằm trong `report/evidence/`; ảnh giao diện nằm trong `report/screenshots/`.

## Bước 1 · Bronze

### Câu 1

Khác biệt giữa telemetry A/B và lý do giữ nguyên dữ liệu Bronze.

Nguồn A có 3021 dòng, nguồn B có 3234 dòng; bảng metadata có 26 trip và 2 video. A dùng `ts_utc` (ISO UTC), `speed_mps`, `heading_deg`, `gas/brake`; B dùng `timestamp_ms` (epoch ms), `spd_kmh`, `hdg`, `throttle_pct/brake_pct`. Đơn vị tốc độ tương ứng m/s và km/h; bàn đạp là tỷ lệ 0–1 và phần trăm; tên GPS là `lat/lon` và `latitude/longitude`. Đồng hồ B nhanh hơn video 1500 ms, còn A không lệch theo manifest.

Bronze giữ hai schema riêng và cột nguồn ở dạng chữ để bảo toàn dữ liệu gốc, kể cả ô trống hoặc giá trị lỗi, giúp kiểm toán và xử lý lại khi quy tắc chuẩn hóa thay đổi. Lần nạp lại A báo `already present`; số dòng không tăng vì pipeline nhận diện batch/video bằng SHA256. Module Bronze đạt 5/5; bằng chứng: `report/evidence/step_1.txt`.

## Bước 2 · Silver telemetry

### Câu 2

Chuẩn hóa schema, đồng hồ và cách ly dữ liệu lỗi.

(trả lời ở đây)

### Câu 3

Cổng chất lượng: error, warn và thí nghiệm break-gate.

(trả lời ở đây)

## Bước 3 · Silver frames

### Câu 4

Idempotency và ghi lại dữ liệu theo trip.

(trả lời ở đây)

### Câu 5

Khung đen, khung tối và ngưỡng phát hiện khung trùng.

(trả lời ở đây)

## Bước 4 · Gold

### Câu 6

Rò rỉ dữ liệu khi chia theo frame và theo trip.

(trả lời ở đây)

### Câu 7

Dataset version, tính tái lập và MSSV.

(trả lời ở đây)

### Câu 8

Lineage và khả năng tái tạo dataset.

(trả lời ở đây)

## Bước 5 · Điều phối và phục vụ

### Câu 9

Mô phỏng một task lỗi và phục hồi Airflow.

(trả lời ở đây)

### Câu 10

Mở rộng lên 500 xe mỗi ngày.

(trả lời ở đây)

## Câu hỏi riêng của bạn trên Metabase

(trả lời ở đây)

## Nhìn lại

(trả lời ở đây)
