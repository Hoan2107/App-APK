# Gửi SMS hàng loạt (Flutter, Android)

Ứng dụng đơn giản: dán nội dung → chọn file Excel/CSV/TXT (hoặc gõ số) → bấm gửi.
Tin nhắn được gửi bằng SMS thường qua SIM trong máy, không cần chọn từng người trong danh bạ.

## Cách lấy file APK (không cần cài Flutter)

1. Tạo tài khoản và 1 repository mới (private cũng được) trên https://github.com
2. Upload toàn bộ nội dung thư mục này lên repo (kể cả thư mục `.github`).
3. Vào tab **Actions** → chọn **Build APK** → **Run workflow**. Đợi khoảng 5–8 phút.
4. Mở lần chạy vừa xong → mục **Artifacts** → tải `sms-bulk-apk` (file zip, giải nén ra `app-release.apk`).
5. Chép APK vào điện thoại và cài (cho phép "Cài ứng dụng từ nguồn không xác định").

## Hoặc build trên máy có Flutter

```bash
flutter create --platforms=android --org vn.smsbulk --project-name sms_bulk /tmp/scaffold
cp -r /tmp/scaffold/android ./android
python3 tools/patch_android.py
flutter pub get
flutter build apk --release
# kết quả: build/app/outputs/flutter-apk/app-release.apk
```

## Định dạng file danh sách

- `.xlsx`, `.csv`, `.txt`. File `.xls` đời cũ: mở bằng Excel rồi Save As `.xlsx`.
- App quét **mọi ô** trong mọi sheet, ô nào là số điện thoại thì lấy (cột bất kỳ, có tiêu đề cũng được).
- Hiểu các dạng: `+84346046203`, `84346046203`, `0346046203`, `346046203` (Excel mất số 0 đầu → app tự thêm).
- Tự loại số trùng. Có thể sửa danh sách trực tiếp trong ô nhập trước khi gửi.

## Lưu ý khi dùng

- Lần đầu gửi, Android hỏi quyền SMS → chọn **Cho phép**.
- Android 13+ với app cài ngoài CH Play: nếu không cấp được quyền SMS, vào **Cài đặt > Ứng dụng > Gửi SMS hàng loạt > ⋮ (3 chấm) > Cho phép cài đặt bị hạn chế**, rồi cấp lại quyền.
- App nghỉ 1,5 giây giữa các tin. Android có thể hiện hộp thoại xác nhận khi 1 app gửi nhiều hơn khoảng 30 SMS trong 30 phút — chọn **Cho phép** để tiếp tục.
- Cước SMS tính theo gói của SIM. Tiếng Việt có dấu: 70 ký tự/SMS (67 nếu tin dài).
- Chỉ nên gửi cho người đã đồng ý nhận tin; gửi tin rác có thể bị nhà mạng khoá SIM.
- Phát hành lên Google Play sẽ bị chặn do chính sách SMS, nên app này chỉ để dùng cá nhân (cài APK).
