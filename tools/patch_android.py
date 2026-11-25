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

# Ép mọi module Android (kể cả plugin cũ như file_picker) dùng compileSdk 36
# để qua bước kiểm tra AAR metadata của Gradle/AGP bản mới.
SNIPPET = """// --- sms_bulk: ép compileSdk cho mọi plugin ---
subprojects {
    afterEvaluate {
        try {
            val ext = extensions.findByName("android")
            ext?.javaClass?.methods
                ?.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(ext, 36)
        } catch (e: Exception) {
            println("compileSdk override skipped for ${project.name}: ${e.message}")
        }
    }
}
// --- hết ---

"""

import os

gradle_kts = "android/build.gradle.kts"
if os.path.exists(gradle_kts):
    with open(gradle_kts, encoding="utf-8") as f:
        g = f.read()
    if "sms_bulk: ép compileSdk" not in g:
        # Phải đặt TRƯỚC khối evaluationDependsOn(":app") của template.
        with open(gradle_kts, "w", encoding="utf-8") as f:
            f.write(SNIPPET + g)
    print("OK: đã vá", gradle_kts)
else:
    print("CẢNH BÁO: không thấy android/build.gradle.kts, bỏ qua bước ép compileSdk")

print(f"OK: đã vá {MANIFEST} và {kt_files[0]} (package {package})")
