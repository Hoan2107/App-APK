# SMS Tool (Flutter, Android)

Dán nội dung → chọn file Excel danh sách (tên + số điện thoại) → bấm **một lần**.
App chạy nền và tự gửi SMS, **cứ 15 giây gửi cho 1 người**, cho tới khi hết danh sách hoặc bạn bấm Dừng.

## Cấu trúc app (3 trang, mở bằng nút menu ☰ góc trên trái)

1. **Tổng quan & gửi tin**: nhập file Excel, xem nhóm nhà mạng, chọn mẫu, gửi tự động.
2. **Mẫu tin nhắn**: thêm / sửa / nhân bản / xoá mẫu, đặt tên cho từng mẫu (Mẫu 1, Mẫu 2...). Có thể gắn mỗi mẫu làm mặc định cho 1 nhà mạng.
3. **Lịch sử gửi**:
   - *Theo ngày*: nhật ký từng tin (giờ gửi, tên, số, nhà mạng, mẫu đã dùng, thành công/lỗi), có tổng kết theo nhà mạng, chọn ngày bất kỳ.
   - *Danh sách đã nhập*: mỗi file Excel là 1 danh sách, thấy tiến độ từng nhóm, bấm **Mở & gửi tiếp** để gửi tiếp cho những người chưa gửi.

## Chọn người gửi

- Mỗi người có ô tick để chọn/bỏ chọn, nút thùng rác để xoá, có "Chọn tất cả", "Xóa tất cả" và ô tìm kiếm (biểu tượng kính lúp).
- Chỉ những người được tick và đang "chờ" mới được gửi.

## Phân nhóm theo nhà mạng

Khi nhập file, số điện thoại (kể cả bị mất số 0 đầu như `342558948`) được chuẩn hoá rồi xếp nhóm theo 3 số đầu:

- Viettel: 032, 033, 034, 035, 036, 037, 038, 039, 086, 096, 097, 098
- VinaPhone: 081, 082, 083, 084, 085, 088, 091, 094
- MobiFone: 070, 076, 077, 078, 079, 089, 090, 093
- Vietnamobile: 052, 056, 058, 092
- Gmobile: 059, 099
- Khác: các đầu số còn lại / số quốc tế

Chọn chip nhóm ở trang Tổng quan để chỉ gửi cho nhóm đó (ví dụ Viettel + Mẫu 1).

## Tránh gửi lặp

- Mọi danh sách, trạng thái từng người và giờ gửi được lưu trong máy.
- Dừng giữa chừng rồi bấm **Tiếp tục**: chỉ gửi cho người chưa gửi. Dù đã tắt app, mở lại danh sách trong Lịch sử rồi bấm gửi, app chỉ gửi người còn "chờ".
- Công tắc **Bỏ qua số đã gửi thành công trước đây** (mặc định bật): nhập file mới có người đã gửi ở file cũ sẽ tự bỏ qua.
- Số bị lỗi có nút **Gửi lại số bị lỗi**.

## Tính năng

- Tự nhận cột tên và cột số điện thoại trong file `.xlsx` (hoặc `.csv`, `.txt`), bỏ qua các cột mã khác (CIF, số hợp đồng...).
- Chấp nhận `+84346046203`, `84346046203`, `0346046203`, `346046203` (Excel mất số 0 đầu → tự thêm). Tự loại số trùng và số sai.
- Chèn `{ten}` vào nội dung để thay bằng tên từng người. Ví dụ: `Chào {ten}, ...`
- Gửi bằng dịch vụ nền (có thông báo trên thanh trạng thái), vẫn chạy khi tắt màn hình hoặc chuyển sang app khác.
- Màn hình hiển thị: đã gửi / lỗi / còn lại, người vừa gửi, người tiếp theo kèm đếm ngược, thời gian ước tính còn lại, trạng thái từng người trong danh sách.
- Dừng bất kỳ lúc nào; bấm **Tiếp tục** để gửi tiếp từ chỗ đã dừng. Nếu vuốt tắt hẳn app (kill) thì việc gửi dừng lại, nhưng tiến độ đã lưu nên mở lại gửi tiếp được.

## Lấy file APK (không cần cài Flutter)

1. Giải nén zip này, upload toàn bộ lên repo GitHub, ghi đè các file cũ (giữ nguyên thư mục `.github` và `tools/icons` đang có).
2. Tab **Actions** → **Build APK** → **Run workflow**. Đợi 5–8 phút.
3. Tải `sms-bulk-apk` ở mục Artifacts, giải nén lấy `app-release.apk`, cài vào điện thoại.

> Cài bản mới đè lên bản cũ được. Nếu báo xung đột chữ ký, hãy gỡ bản cũ rồi cài lại.

## Hoặc build trên máy có Flutter

```bash
flutter create --platforms=android --org vn.smsbulk --project-name sms_bulk /tmp/scaffold
cp -r /tmp/scaffold/android ./android
python3 tools/patch_android.py
flutter pub get
flutter build apk --release
# kết quả: build/app/outputs/flutter-apk/app-release.apk
```

## Cấp quyền (lần đầu)

- Cho phép **SMS** và **Thông báo** khi app hỏi.
- Android 13+ với app cài ngoài CH Play: vào **Cài đặt > Ứng dụng > SMS Tool > ⋮ > Cho phép cài đặt bị hạn chế**, rồi cấp lại quyền SMS.
- Để chạy ổn định khi tắt màn hình: **Cài đặt > Ứng dụng > SMS Tool > Tiết kiệm pin > Không hạn chế**. Máy Xiaomi nên bật thêm **Tự khởi động**.

## Nếu máy vẫn hỏi xác nhận từng tin

Đây là hộp thoại của hệ điều hành, app không tự tắt được:

- Xiaomi/Redmi: **Cài đặt > Ứng dụng > Quản lý ứng dụng > SMS Tool > Quyền > Gửi tin nhắn SMS** (hoặc Quyền khác) → chọn **Luôn cho phép**.
- Android giới hạn khoảng 30 SMS / 30 phút cho mỗi app và sẽ hỏi xác nhận khi vượt. Chọn **Luôn cho phép / Không hỏi lại** nếu có tuỳ chọn đó.

## Lưu ý

- Cước SMS tính theo gói của SIM. Tiếng Việt có dấu: 70 ký tự/SMS (67 nếu tin dài).
- Chỉ nên gửi cho người đã đồng ý nhận tin; gửi tin rác có thể bị nhà mạng khoá SIM.
- "Đã gửi" nghĩa là máy đã chuyển tin cho nhà mạng, chưa phải người nhận đã nhận được.
- App chỉ để dùng cá nhân (cài APK), không phát hành lên Google Play do chính sách SMS.
