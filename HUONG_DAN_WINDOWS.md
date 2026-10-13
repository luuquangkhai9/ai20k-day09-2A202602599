# Hướng dẫn hoàn thành Lab Day 9 trên Windows

Hướng dẫn này được viết sau khi đọc README, GUIDE, RUBRIC, REPORT, các script chạy/kiểm tra và mã pipeline trong repo. Những số liệu chưa chạy phải lấy từ lần chạy thật của bạn.

## 1. Tình trạng dự án đã kiểm tra

- Dữ liệu trong `data/` đã đầy đủ: `python scripts/check_data.py` đạt **6/6 file khớp SHA256**. Không cần tải hoặc giải nén lại.
- Có Docker và Python; `docker compose ps` chưa liệt kê container nào của lab.
- Chưa có `.env`; `REPORT.md` còn là mẫu; `report/evidence/` và `report/screenshots/` chưa có bằng chứng.
- Có remote GitHub và 2 commit. `dataset/day09-data.zip` đang được Git theo dõi, cần bỏ khỏi bài nộp.
- `check_submission.py` hiện báo 13 mục FAIL. Ba file được bảo vệ bị báo khác checksum do checkout thành CRLF: khi đổi CRLF về LF, cả ba khớp checksum chuẩn; bản trong Git cũng khớp. Đây là vấn đề xuống dòng, không phải thay đổi logic.

Bài này yêu cầu vận hành pipeline có sẵn, 4 thí nghiệm, DAG Airflow, dashboard và báo cáo 10 câu. Điểm: hệ thống 40, bằng chứng 20, báo cáo 35, Git/trình bày 5.

## 2. Hiểu luồng dữ liệu

`Video + telemetry → Bronze → Silver → quality gate → Gold → Postgres → Metabase`

- **Bronze:** lưu video gốc và telemetry thô của A/B riêng biệt; nhận diện file bằng SHA256 để tránh nạp lặp.
- **Silver telemetry:** chuẩn hóa tên cột, đơn vị, timestamp và đồng hồ; cách ly dòng lỗi vào `telemetry_rejects`.
- **Silver frames:** FFmpeg lấy mẫu 2 khung/giây cho 26 trip; đo độ sáng, độ nét và dHash; nối telemetry theo event time.
- **Quality gate:** dbt test kiểm tra dữ liệu. `error` chặn các bước sau; `warn` cho phép tiếp tục nhưng cần giải thích.
- **Gold:** bỏ khung đen/mờ/trùng/mất đồng bộ; chia theo trip; xuất ảnh và manifest có phiên bản, lineage.
- **Warehouse:** xuất 6 mart vào Postgres để Metabase đọc. Airflow điều phối toàn bộ luồng.

## 3. Chuẩn bị bằng PowerShell

Chạy mọi lệnh tại thư mục gốc repo. Docker cần khoảng 6 GB RAM được cấp và khoảng 8 GB ổ đĩa trống theo README.

Trước tiên khôi phục kiểu xuống dòng LF để script Linux chạy được và checksum đúng. Đoạn sau chỉ đổi CRLF thành LF trong các shell script và ba file được bảo vệ; giữ nguyên nội dung khác:

```powershell
$env:PYTHONUTF8 = '1'
git config --local core.autocrlf input
@'
from pathlib import Path
files = [Path('tests/test_units.py'), Path('pipeline/verify.py'), Path('docker-compose.yml')]
files += list(Path('scripts').glob('*.sh'))
files += list(Path('docker').glob('*.sh'))
for p in files:
    raw = p.read_bytes()
    fixed = raw.replace(b'\r\n', b'\n')
    if fixed != raw:
        p.write_bytes(fixed)
        print('Restored LF:', p)
'@ | python -
git diff --stat
```

Tạo `.env`, rồi mở file và thay MSSV mẫu bằng MSSV thật:

```powershell
Copy-Item .env.example .env
notepad .env
python scripts/check_data.py
docker compose --profile orchestrate up -d --build
docker compose ps
```

Đợi Airflow, MinIO và Postgres healthy. Nếu container không khởi động, xem `docker compose logs --tail 80 airflow` (hoặc tên service gặp lỗi).

Giữ nguyên MSSV trong `.env`, `REPORT.md` và mọi lần chạy thí nghiệm. Gold hỗ trợ MSSV dạng chuỗi, kể cả có chữ. **Riêng công thức chọn trip trong GUIDE dùng `int(MSSV)` nên không dùng trực tiếp được với MSSV có chữ**; nếu MSSV của bạn có chữ, cần xác nhận quy ước chọn trip với giảng viên. Không tự bỏ phần chữ khỏi `LAB_STUDENT_ID`.

Định nghĩa lệnh ngắn dùng trong cửa sổ PowerShell hiện tại, tương đương phần gọi pipeline của `scripts/lab.sh`:

```powershell
function lab {
    docker compose exec -T -w /opt/lab airflow /home/airflow/lab-venv/bin/python -m pipeline.cli @args
}
lab step all --reset
```

Lần chạy thử phải đạt **27/27 checks passed** và tạo `report/evidence/run_summary.json`. `--reset` xóa dữ liệu trong lake; chỉ chạy khi muốn bắt đầu lại và không có DAG đang chạy.

## 4. Làm lần lượt 5 bước

### Bước 1: Bronze — trả lời câu 1

```powershell
lab step 1 --reset
lab sql 'select drive_id, telemetry_clock_offset_ms, sha256 from lake.bronze_video_files'
lab history bronze.raw_telemetry_a
```

Quan sát số dòng, dữ liệu thô và thông báo `already present` khi nạp lại. So sánh ít nhất 4 khác biệt: tên cột; tốc độ m/s và km/h; ISO UTC và epoch ms; bàn đạp tỷ lệ và phần trăm; độ lệch đồng hồ.

Giải thích việc lưu thô dưới dạng chữ giúp giữ nguyên dữ liệu nguồn để kiểm tra, chuẩn hóa hoặc xử lý lại sau này. Điền câu 1 vào REPORT rồi commit/push tiến độ thật.

### Bước 2: Silver telemetry — trả lời câu 2–3

```powershell
lab step 2
lab exp break-gate
```

Đọc `dbt/models/staging/stg_telemetry_a.sql`, `stg_telemetry_b.sql` và `dbt/models/schema.yml`.

- B đổi tốc độ bằng `/ 3.6`, bàn đạp bằng `/ 100`, epoch ms thành timestamp, **trừ 1500 ms** độ lệch đồng hồ.
- Chép bảng quarantine theo từng drive/lý do từ kết quả thật. Kiểm tra số sạch cộng số cách ly bằng số nhận vào.
- `max_gap_ms` là warn vì mất tín hiệu được ghi nhận; tốc độ ngoài miền hợp lệ là error vì không được đi vào dữ liệu sạch.
- Thí nghiệm nới luật làm sạch lên 1000 m/s nhưng test vẫn yêu cầu 0–70, rồi khôi phục. Việc test thất bại trong pha nới luật là kết quả mong đợi; đọc `break_gate.json` để lấy tên test và số dòng lỗi.

### Bước 3: Silver frames — trả lời câu 4–5

```powershell
lab step 3
docker compose exec -T -w /opt/lab airflow /home/airflow/lab-venv/bin/python -m unittest discover -s tests
lab exp idempotency
lab exp threshold
```

Ghi số khung đen, mờ, tối, trùng và mất đồng bộ theo drive. Một khung có thể mang nhiều cờ nên không cộng các cờ như các nhóm độc lập.

- `idempotency.json`: lấy số dòng và fingerprint trước/sau hai lần chạy lại; so với bảng thử ghi append. Pipeline thay các dòng của trip bằng một commit Delta. Mã thực tế partition vật lý theo drive và overwrite theo điều kiện `trip_id`.
- `threshold.json`: điền bảng số khung trùng ở ngưỡng 0, 2, 6; giải thích đánh đổi giữa giữ khung gần trùng và loại nhầm khung có ích.
- Khung tối được gắn cờ mà không bị loại chỉ vì tối; vẫn có thể bị loại bởi cờ mờ, trùng hoặc mất đồng bộ. Khung đen bị loại.

### Bước 4: Gold — trả lời câu 6–8

```powershell
lab step 4
lab exp leakage
lab export-dataset
```

Ghi số khung train/val/test và `dataset_version`; so phiên bản của bước 4 với lần export tiếp theo. Nếu dữ liệu và split không đổi thì phiên bản phải giữ nguyên.

Trong mã hiện tại, phiên bản là 12 ký tự đầu SHA256 của danh sách `frame_id|split` đã sắp xếp. MSSV tham gia xếp thứ tự trip để chia split. Không diễn giải phiên bản này là checksum của toàn bộ pixel hay mọi trường dữ liệu.

Mở MinIO tại http://localhost:9001 (`minioadmin` / `minioadmin`), đọc `lake/gold/datasets/<version>/manifest.json`: ghi các phiên bản Delta và SHA256 video trong `lineage`. Khi bàn về tái tạo, nêu thêm cần lưu dữ liệu nguồn, MSSV, mã/luật xử lý và môi trường chạy.

`leakage.json` cung cấp số trip nằm trong nhiều split, số trip xuất hiện cả train/test khi chia theo frame, và kết quả chia theo trip. Dùng số của bạn để giải thích rò rỉ cảnh.

### Bước 5: Warehouse và Airflow — trả lời câu 9–10

```powershell
lab step 5
```

Mở http://localhost:8080 (`admin` / `admin`):

1. Unpause `day09_reset` và `day09_video_pipeline`.
2. Trigger `day09_reset`, đợi thành công.
3. Trigger `day09_video_pipeline`, đợi toàn bộ xanh; chụp Graph thành `report/screenshots/airflow_graph.png`.

Bài tập lỗi một task: nếu MSSV hoàn toàn là số, lấy trip theo GUIDE bằng:

```powershell
$StudentId = (Get-Content .env | Where-Object { $_ -match '^LAB_STUDENT_ID=' }) -replace '^LAB_STUDENT_ID=', ''
$Trips = lab list-trips | ConvertFrom-Json
$Trip = $Trips[([long]$StudentId % 26)]
$Trip
```

Nếu MSSV có chữ, dùng trip theo quy ước giảng viên xác nhận. Ghi trip vào đầu REPORT, thêm `LAB_FAIL_ONCE=<trip đó>` vào `.env`, rồi:

```powershell
docker compose --profile orchestrate up -d
```

Trigger reset rồi pipeline. Chụp log task đỏ có dòng `simulated crash while extracting <trip>` thành `report/screenshots/airflow_failure_log.png`. Ghi số task đỏ và `upstream_failed` thực tế.

Clear đúng instance `silver_frames` bị lỗi trước, theo GUIDE. Nếu các task sau vẫn giữ trạng thái `upstream_failed`, clear các task đó để scheduler chạy lại; ghi rõ thao tác thực tế trong báo cáo. Đợi xanh, lưu `airflow_recovered_graph.png`, chạy `lab verify`, so phiên bản dataset với trước lỗi.

Mã mô phỏng hiện tại gây lỗi **trước khi decode**, dù tài liệu mô tả lỗi giữa chừng; mô tả đúng điều quan sát được. Khi xong, xóa `LAB_FAIL_ONCE` khỏi `.env` và chạy lại lệnh Compose.

Câu 10 là phân tích: có thể xét nút cổ chai decode video/IO, xử lý DuckDB trên một máy, và tài nguyên điều phối local; đề xuất worker phân tán, xử lý theo partition và lưu trữ/warehouse phù hợp. Liên hệ slide lớp; không khẳng định đã đo tải 500 xe nếu chưa thực nghiệm.

## 5. Dashboard và câu SQL riêng

```powershell
docker compose --profile bi up -d
python scripts/setup_metabase.py
```

Script in tài khoản và URL dashboard. Mở http://localhost:3000, thêm một câu hỏi SQL trên nguồn Postgres warehouse, lưu và đưa lên dashboard. Ví dụ:

```sql
SELECT drive_id, trip_id, frames, frames_kept,
       ROUND(100.0 * (frames - frames_kept) / NULLIF(frames, 0), 2) AS dropped_pct
FROM marts.mart_trip_summary
ORDER BY dropped_pct DESC NULLS LAST, trip_id;
```

Nêu trip có tỷ lệ loại cao, đối chiếu tín hiệu chất lượng trước khi kết luận nguyên nhân. Lưu ảnh dashboard có câu hỏi riêng thành `metabase_dashboard.png`, và ảnh bucket lake thành `minio_lake.png` trong `report/screenshots/`.

## 6. Hoàn thiện và nộp

Sau mỗi bước, điền phần báo cáo tương ứng, commit và push. Cần ít nhất 5 commit với thông điệp nêu số bước, ví dụ `Bước 3: silver frames và thí nghiệm idempotency`. Đừng tạo commit trống để bù số lượng.

Chạy lần cuối sau khi đã gỡ công tắc gây lỗi và không còn DAG đang chạy:

```powershell
lab step all --reset
lab verify 2>&1 | Out-File -Encoding utf8 report/verify.txt
Get-Content report/verify.txt
```

Trên PowerShell Windows, `check_submission.py --save-verify` gọi trực tiếp file `.sh` nên có thể lỗi thực thi. Lệnh `lab verify ... Out-File -Encoding utf8` ở trên tạo đúng bằng chứng mà không cần sửa script và tránh ghi UTF-16 mà checker không đọc được.

Bỏ ZIP khỏi danh sách Git theo dõi, vẫn giữ file trên máy:

```powershell
git rm --cached -- dataset/day09-data.zip
```

Kiểm tra trước khi commit cuối:

```powershell
$env:PYTHONUTF8 = '1'
python scripts/check_submission.py
git status --short
git diff --stat
```

Hoàn thành khi:

- `REPORT.md` có thông tin cá nhân, đúng MSSV, trip, phiên bản và số split; 10 câu trả lời khoảng 3–8 dòng/câu, SQL riêng và phần nhìn lại.
- `report/evidence/` có **5 JSON**: `run_summary`, `break_gate`, `idempotency`, `threshold`, `leakage`; số liệu và MSSV khớp báo cáo; `verify_all_passed` là true.
- `report/verify.txt` có `27/27 checks passed`.
- Có **ít nhất 4 ảnh** mà script yêu cầu, nên chuẩn bị **5 ảnh**: Graph xanh, MinIO, dashboard, log lỗi có trip, Graph sau phục hồi. Rubric yêu cầu bằng chứng phục hồi ngoài ba ảnh cơ bản.
- Không sửa logic các file đề, nhất là `tests/`, `pipeline/verify.py`, `docker-compose.yml`; không commit dữ liệu, work, ZIP, tar hoặc DuckDB.
- Checker không còn FAIL. Commit/push cuối, chạy checker lại để kiểm tra trạng thái Git. Xác nhận repo Public trên GitHub rồi nộp URL theo kênh giảng viên.

**Lưu ý:** checker chỉ hỗ trợ kiểm tra sơ bộ; vẫn đọc lại từng câu báo cáo và đối chiếu số liệu với JSON/ảnh. Không tự điền số liệu dự kiến của tài liệu thay cho số đã chạy.
