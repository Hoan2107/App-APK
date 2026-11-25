#!/usr/bin/env python3
"""Gắn quyền SEND_SMS + code gửi SMS vào thư mục android do `flutter create` sinh ra.

Chạy từ thư mục gốc của project (nơi có pubspec.yaml và thư mục android/).
"""
import glob
import re
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"

with open(MANIFEST, encoding="utf-8") as f:
    manifest = f.read()

if "android.permission.SEND_SMS" not in manifest:
    manifest = manifest.replace(
        "<application",
        '<uses-permission android:name="android.permission.SEND_SMS"/>\n'
        '    <uses-feature android:name="android.hardware.telephony" android:required="false"/>\n'
        "    <application",
        1,
    )

manifest = re.sub(r'android:label="[^"]*"', 'android:label="Gửi SMS hàng loạt"', manifest, count=1)

with open(MANIFEST, "w", encoding="utf-8") as f:
    f.write(manifest)

kt_files = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not kt_files:
    sys.exit("Không tìm thấy MainActivity.kt trong android/app/src/main/kotlin")

with open(kt_files[0], encoding="utf-8") as f:
    package = re.search(r"^package\s+([\w.]+)", f.read(), re.M).group(1)

with open("tools/MainActivity.kt.txt", encoding="utf-8") as f:
    code = f.read().replace("__PACKAGE__", package)

with open(kt_files[0], "w", encoding="utf-8") as f:
    f.write(code)

print(f"OK: đã vá {MANIFEST} và {kt_files[0]} (package {package})")
