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

A được ép `ts_utc` sang timestamp có múi giờ và giữ tốc độ m/s. B dùng `(timestamp_ms - 1500) / 1000` để đưa về cùng đồng hồ UTC, chia `spd_kmh` cho 3,6 và chia bàn đạp phần trăm cho 100, rồi đổi tên các cột về schema chung. Mẫu đầu B sau chuẩn hóa là `2025-10-08 14:30:00.009 UTC`, chỉ cách thời điểm video bắt đầu 9 ms; tốc độ tối đa A/B lần lượt khoảng 71/100 km/h.

| Drive | Trùng | Thiếu tốc độ | Ngoài khoảng tốc độ | Tổng cách ly | Sạch | Nhận vào |
|---|---:|---:|---:|---:|---:|---:|
| A | 20 | 30 | 3 | 53 | 2968 | 3021 |
| B | 20 | 30 | 3 | 53 | 3181 | 3234 |

Hai phép bảo toàn đều đúng: `2968 + 53 = 3021` và `3181 + 53 = 3234`. Dòng lỗi được giữ trong `silver_telemetry_rejects` cùng lý do để truy vết, đo chất lượng nguồn và xử lý lại; xóa im lặng sẽ làm mất bằng chứng. Module 2 đạt 7/7 (`step_2.txt`).

### Câu 3

Cổng chất lượng: error, warn và thí nghiệm break-gate.

`max_gap_ms` có severity `warn`: khoảng trống cảm biến cần được báo và đo mức ảnh hưởng, nhưng không làm mọi dữ liệu của chuyến xe mất giá trị. `in_range` mặc định là `error`, vì tốc độ ngoài 0–70 m/s không được phép lọt vào bảng sạch/dataset. Với luật gốc, dbt test Silver đạt `PASS=6 WARN=1 ERROR=0 SKIP=0`.

Thí nghiệm nâng giới hạn làm sạch lên 1000 m/s khiến 6 dòng tốc độ vô lý lọt qua; test `in_range_silver_telemetry_speed_mps__70__0` vẫn giữ miền 0–70 nên bắt đủ 6 dòng, cho `PASS=5 WARN=1 ERROR=1 SKIP=0`. Khôi phục luật gốc đưa kết quả về `PASS=6 WARN=1 ERROR=0 SKIP=0`. Cổng chất lượng kiểm tra độc lập với biến đổi; một luật làm sạch bị nới không đồng nghĩa dữ liệu xấu được xuất xuống Gold. Bằng chứng: `break_gate.json` và `experiment_break_gate.txt`.

## Bước 3 · Silver frames

### Câu 4

Idempotency và ghi lại dữ liệu theo trip.

Thí nghiệm chọn `trip-06570` có 45 khung. Trước và sau hai lần chạy lại, toàn bảng `silver.frames` đều có 1246 dòng và fingerprint `6c7480dfde7e`; `unchanged=true`. Bảng thử dùng append chứa 90 dòng sau hai lần ghi cùng 45 khung, tức nhân đôi 2 lần.

Pipeline dùng Delta overwrite với predicate `trip_id = 'trip-06570'`, nên mỗi lần chỉ thay tập dòng của trip này trong một commit; partition vật lý của bảng là `drive_id`. Commit Delta công bố phiên bản bảng nguyên tử, tránh trạng thái đã xóa trip nhưng chưa ghi lại như cách xóa-rồi-ghi. Nếu job lỗi trước commit, phiên bản cũ vẫn đọc được; nếu chạy lại sau commit, các dòng được thay thay vì cộng thêm. Tính idempotent ở đây xét dữ liệu/frame và tín hiệu chất lượng; thời điểm xử lý và số commit Delta vẫn có thể thay đổi. Bằng chứng: `idempotency.json`.

### Câu 5

Khung đen, khung tối và ngưỡng phát hiện khung trùng.

Mã dbt coi brightness <12 là đen, còn 12≤brightness<40 là tối. Khung đen bị loại; khung tối chỉ bị gắn cờ để giữ điều kiện đường hầm/bóng râm hữu ích cho huấn luyện, nhưng vẫn có thể bị loại nếu đồng thời mờ, trùng hoặc mất đồng bộ. A có 6 khung đen, 9 mờ, 4 tối, 149 trùng và 7 mất đồng bộ; B có 4 đen, 0 mờ, 61 tối, 53 trùng và 7 mất đồng bộ. Các cờ có thể chồng lên nhau.

| dHash khác tối đa | Khung trùng A | Khung trùng B |
|---|---:|---:|
| 0 | 61 | 8 |
| 2 | 149 | 53 |
| 6 | 363 | 244 |

Giữ ngưỡng mặc định 2 là lựa chọn cân bằng cho bộ dữ liệu này: ngưỡng 6 đánh dấu hơn một nửa số khung A là trùng và có nguy cơ loại biến đổi cảnh có ích; ngưỡng 0 bỏ sót khung gần trùng do nén hoặc nhiễu nhỏ. Xe chạy chậm/dừng làm cảnh ít đổi ngay cả khi camera hoạt động tốt, nên cần xét tốc độ và xem ảnh để phân biệt trùng do cảnh với camera đứng hình. Ngưỡng dHash không tự chứng minh lỗi camera. Bằng chứng: `threshold.json`, `step_3.txt`; 9 unit test đều đạt.

## Bước 4 · Gold

### Câu 6

Rò rỉ dữ liệu khi chia theo frame và theo trip.

Trên 1019 khung đủ chất lượng thuộc 26 trip, chia theo frame làm 26/26 trip nằm trong nhiều split và cả 26 trip có khung ở train lẫn test. Khi chia theo trip trong Gold, số trip bị chia cắt là 0. Mỗi drive có 9 trip train, 2 val, 2 test, nên cả hai nguồn đều có mặt trong từng split.

Các khung liền nhau cùng cảnh có tương quan mạnh; nếu mô hình đã học cảnh ở train rồi gặp khung gần giống ở test, điểm kiểm thử phản ánh khả năng nhớ cảnh nhiều hơn khả năng tổng quát sang chuyến xe mới. Đây là nguy cơ tạo điểm đẹp giả tạo, không phải bằng chứng đã đo mức tăng điểm của một mô hình cụ thể: lab không huấn luyện mô hình. Bằng chứng: `leakage.json` và `step_4.txt`.

### Câu 7

Dataset version, tính tái lập và MSSV.

Lần tạo Gold và lần `export-dataset` kế tiếp đều cho `dataset_version=1ab78ac6d23b`, 1019 ảnh, train/val/test = 693/159/167. Trong mã hiện tại, version là 12 ký tự đầu SHA256 của danh sách `frame_id|split` đã sắp xếp, nên cùng tập frame và split cho cùng tên dataset, dù giờ tạo hoặc số commit Delta thay đổi. Dùng ngày giờ/số đếm sẽ tạo tên mới cho cùng nội dung và khó đối chiếu tái lập.

MSSV đầy đủ `2A202602599` tham gia `md5(trip_id || LAB_STUDENT_ID)` khi xếp trip trong từng drive; thay MSSV có thể thay split và kéo theo version khác. Tính cá nhân hóa không phải bảo đảm toán học mọi MSSV đều tạo split khác nhau. Version cũng không băm toàn bộ pixel hoặc mọi giá trị telemetry, nên không thay thế SHA256 nguồn, manifest và lineage. Bằng chứng: `step_4.txt`, `dataset_export_repeat.txt` và `run_summary.json`.

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
