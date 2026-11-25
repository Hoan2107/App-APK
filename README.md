# SMS Tool (Flutter, Android)

Dán nội dung → chọn file Excel danh sách (tên + số điện thoại) → bấm **một lần**.
App chạy nền và tự gửi SMS, **cứ 15 giây gửi cho 1 người**, cho tới khi hết danh sách hoặc bạn bấm Dừng.

## Tính năng

- Tự nhận cột tên và cột số điện thoại trong file `.xlsx` (hoặc `.csv`, `.txt`), bỏ qua các cột mã khác (CIF, số hợp đồng...).
- Chấp nhận `+84346046203`, `84346046203`, `0346046203`, `346046203` (Excel mất số 0 đầu → tự thêm). Tự loại số trùng và số sai.
- Chèn `{ten}` vào nội dung để thay bằng tên từng người. Ví dụ: `Chào {ten}, ...`
- Gửi bằng dịch vụ nền (có thông báo trên thanh trạng thái), vẫn chạy khi tắt màn hình hoặc chuyển sang app khác.
- Màn hình hiển thị: đã gửi / lỗi / còn lại, người vừa gửi, người tiếp theo kèm đếm ngược, thời gian ước tính còn lại, trạng thái từng người trong danh sách.
- Dừng bất kỳ lúc nào; bấm **Tiếp tục** để gửi tiếp từ chỗ đã dừng. Nếu vuốt tắt hẳn app (kill) thì việc gửi dừng lại.

## Lấy file APK (không cần cài Flutter)

1. Giải nén zip này, upload toàn bộ lên repo GitHub (kể cả thư mục `.github`), ghi đè các file cũ.
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
