#!/usr/bin/env python3
"""Gắn quyền, dịch vụ gửi nền, icon vào thư mục android do `flutter create` sinh ra.

Chạy từ thư mục gốc của project (nơi có pubspec.yaml và thư mục android/).
"""
import glob
import os
import re
import shutil
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"

PERMISSIONS = """    <uses-permission android:name="android.permission.SEND_SMS"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-feature android:name="android.hardware.telephony" android:required="false"/>
"""

SERVICE = """        <service
            android:name=".SmsService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="bulk_sms_sender"/>
        </service>
    """

with open(MANIFEST, encoding="utf-8") as f:
    manifest = f.read()

if "android.permission.SEND_SMS" not in manifest:
    manifest = manifest.replace("<application", PERMISSIONS + "    <application", 1)

if "SmsService" not in manifest:
    manifest = manifest.replace("</application>", SERVICE + "</application>", 1)

manifest = re.sub(r'android:label="[^"]*"', 'android:label="SMS Tool"', manifest, count=1)

with open(MANIFEST, "w", encoding="utf-8") as f:
    f.write(manifest)

# --- Code Kotlin ---------------------------------------------------------
kt_files = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if not kt_files:
    sys.exit("Không tìm thấy MainActivity.kt trong android/app/src/main/kotlin")

main_kt = kt_files[0]
kt_dir = os.path.dirname(main_kt)

with open(main_kt, encoding="utf-8") as f:
    package = re.search(r"^package\s+([\w.]+)", f.read(), re.M).group(1)

for src, dst in (("tools/MainActivity.kt.txt", main_kt),
                 ("tools/SmsService.kt.txt", os.path.join(kt_dir, "SmsService.kt"))):
    with open(src, encoding="utf-8") as f:
        code = f.read().replace("__PACKAGE__", package)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(code)

# --- Icon ----------------------------------------------------------------
res = "android/app/src/main/res"
adaptive = os.path.join(res, "mipmap-anydpi-v26")
if os.path.isdir(adaptive):
    shutil.rmtree(adaptive)  # dùng icon PNG của mình thay vì icon mặc định

for d in glob.glob("tools/icons/mipmap-*"):
    target = os.path.join(res, os.path.basename(d))
    os.makedirs(target, exist_ok=True)
    shutil.copy(os.path.join(d, "ic_launcher.png"), os.path.join(target, "ic_launcher.png"))

# --- Ép compileSdk 36 cho mọi plugin (tránh lỗi AAR metadata) -------------
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

print(f"OK: đã vá {MANIFEST}, {main_kt}, SmsService.kt (package {package}) và icon")
