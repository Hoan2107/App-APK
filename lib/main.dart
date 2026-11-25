import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('sms_bulk');

/// Khoảng nghỉ giữa 2 tin nhắn để tránh bị nhà mạng/Android chặn.
const _delayBetween = Duration(milliseconds: 1500);

void main() => runApp(const SmsBulkApp());

class SmsBulkApp extends StatelessWidget {
  const SmsBulkApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Gửi SMS hàng loạt',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const HomePage(),
      );
}

// ---------------------------------------------------------------------------
// Xử lý số điện thoại / file
// ---------------------------------------------------------------------------

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Chuẩn hoá 1 ô/chuỗi thành số điện thoại. Trả về null nếu không phải số.
String? normalizePhone(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Excel có thể lưu số lớn dạng 8.4346046203E10
  if (RegExp(r'^\d+(\.\d+)?[eE]\+?\d+$').hasMatch(s)) {
    final d = double.tryParse(s);
    if (d == null) return null;
    s = d.toStringAsFixed(0);
  }

  // Chỉ nhận ô chỉ gồm chữ số, +, khoảng trắng, dấu chấm, gạch, ngoặc.
  if (!RegExp(r'^[+\d\s().\-]+$').hasMatch(s)) return null;

  final hasPlus = s.startsWith('+');
  final digits = s.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9 || digits.length > 15) return null;

  if (hasPlus) return '+$digits';
  if (digits.startsWith('84') && digits.length == 11) return '+$digits';
  if (digits.startsWith('0') && digits.length == 10) return digits;
  // Excel hay làm mất số 0 đầu: 346046203 -> 0346046203
  if (digits.length == 9 && RegExp(r'^[35789]').hasMatch(digits)) {
    return '0$digits';
  }
  return digits;
}

/// Tách text thành danh sách số hợp lệ, bỏ trùng, giữ nguyên thứ tự.
List<String> parseNumbers(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in text.split(RegExp(r'[\n\r,;\t]+'))) {
    final n = normalizePhone(part);
    if (n == null) continue;
    // Khoá so trùng: bỏ +, đầu 84 hoặc 0 để +84346046203 == 0346046203
    var key = n.replaceAll('+', '');
    if (key.startsWith('84')) {
      key = key.substring(2);
    } else if (key.startsWith('0')) {
      key = key.substring(1);
    }
    if (seen.add(key)) out.add(n);
  }
  return out;
}

/// Đọc file .xlsx (không cần thư viện ngoài): lấy giá trị của mọi ô.
String xlsxToText(List<int> bytes) {
  final arc = ZipDecoder().decodeBytes(bytes);

  final shared = <String>[];
  final ss = arc.findFile('xl/sharedStrings.xml');
  if (ss != null) {
    final xml = utf8.decode(ss.content as List<int>, allowMalformed: true);
    for (final si in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(xml)) {
      final buf = StringBuffer();
      for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(si.group(1)!)) {
        buf.write(_unescapeXml(t.group(1)!));
      }
      shared.add(buf.toString());
    }
  }

  final out = <String>[];
  for (final f in arc.files) {
    if (!f.isFile ||
        !f.name.startsWith('xl/worksheets/') ||
        !f.name.endsWith('.xml')) {
      continue;
    }
    final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
    for (final c
        in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
            .allMatches(xml)) {
      final inner = c.group(2);
      if (inner == null) continue;
      final type = RegExp(r't="(\w+)"').firstMatch(c.group(1) ?? '')?.group(1);
      String? val;
      if (type == 'inlineStr') {
        val = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
            .firstMatch(inner)
            ?.group(1);
      } else {
        final v =
            RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(inner)?.group(1);
        if (v != null) {
          if (type == 's') {
            final idx = int.tryParse(v);
            if (idx != null && idx >= 0 && idx < shared.length) {
              val = shared[idx];
            }
          } else {
            val = v;
          }
        }
      }
      if (val != null) out.add(_unescapeXml(val));
    }
  }
  return out.join('\n');
}

/// Ước tính số SMS cho 1 người nhận.
int smsSegments(String msg) {
  if (msg.isEmpty) return 0;
  final unicode = msg.runes.any((r) => r > 127);
  final len = msg.runes.length;
  if (unicode) return len <= 70 ? 1 : (len / 67).ceil();
  return len <= 160 ? 1 : (len / 153).ceil();
}

// ---------------------------------------------------------------------------
// Giao diện
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _msg = TextEditingController();
  final _nums = TextEditingController();

  bool _sending = false;
  bool _stop = false;
  int _sent = 0;
  int _failed = 0;
  int _total = 0;
  String? _fileName;
  final List<String> _log = [];

  @override
  void dispose() {
    _msg.dispose();
    _nums.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv', 'txt'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        _snack('Không đọc được file.');
        return;
      }
      final ext = (f.extension ?? '').toLowerCase();
      final text = ext == 'xlsx'
          ? xlsxToText(bytes)
          : utf8.decode(bytes, allowMalformed: true);
      final found = parseNumbers(text);
      setState(() {
        _fileName = f.name;
        _nums.text = found.join('\n');
      });
      _snack(found.isEmpty
          ? 'Không tìm thấy số điện thoại nào trong file.'
          : 'Đã đọc ${found.length} số từ ${f.name}');
    } catch (e) {
      _snack('Lỗi đọc file: $e\n(File .xls cũ: hãy lưu lại thành .xlsx hoặc .csv)');
    }
  }

  Future<void> _send() async {
    final numbers = parseNumbers(_nums.text);
    final message = _msg.text.trim();

    if (message.isEmpty) {
      _snack('Hãy nhập nội dung tin nhắn.');
      return;
    }
    if (numbers.isEmpty) {
      _snack('Chưa có số điện thoại nào.');
      return;
    }

    bool granted = false;
    try {
      granted = await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      granted = false;
    }
    if (!granted) {
      _snack('Cần cấp quyền gửi SMS cho ứng dụng (Cài đặt > Ứng dụng > Quyền).');
      return;
    }
    if (!mounted) return;

    final segs = smsSegments(message);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận gửi'),
        content: Text(
          'Gửi tin nhắn tới ${numbers.length} số.\n'
          'Mỗi người nhận ~$segs SMS '
          '(tổng ~${numbers.length * segs} SMS, tính theo cước nhà mạng).\n\n'
          'Bạn có chắc chắn không?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gửi')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _sending = true;
      _stop = false;
      _sent = 0;
      _failed = 0;
      _total = numbers.length;
      _log.clear();
    });

    for (final n in numbers) {
      if (_stop) break;
      try {
        await _channel
            .invokeMethod('sendSms', {'phone': n, 'message': message});
        _sent++;
      } on PlatformException catch (e) {
        _failed++;
        _log.insert(0, '✗ $n: ${e.message ?? e.code}');
      }
      if (!mounted) return;
      setState(() {});
      await Future.delayed(_delayBetween);
    }

    if (!mounted) return;
    setState(() => _sending = false);
    _snack(_stop
        ? 'Đã dừng. Gửi: $_sent, lỗi: $_failed'
        : 'Hoàn tất. Gửi: $_sent, lỗi: $_failed');
  }

  @override
  Widget build(BuildContext context) {
    final numbers = parseNumbers(_nums.text);
    final segs = smsSegments(_msg.text);
    final done = _sent + _failed;

    return Scaffold(
      appBar: AppBar(title: const Text('Gửi SMS hàng loạt')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Bước 1: Nội dung tin nhắn',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _msg,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Dán hoặc gõ nội dung tin nhắn vào đây...',
                helperText:
                    '${_msg.text.runes.length} ký tự · ~$segs SMS / người nhận',
              ),
            ),
            const SizedBox(height: 24),
            Text('Bước 2: Danh sách số điện thoại',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sending ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Chọn file Excel (.xlsx) / CSV / TXT'),
            ),
            if (_fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('File: $_fileName',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nums,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText:
                    'Hoặc gõ/dán trực tiếp, mỗi số 1 dòng\nVí dụ: +84346046203',
                helperText: '${numbers.length} số hợp lệ (đã loại trùng)',
              ),
            ),
            const SizedBox(height: 24),
            if (!_sending)
              FilledButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.send),
                label: Text('Gửi cho ${numbers.length} số'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              )
            else
              FilledButton.icon(
                onPressed: () => setState(() => _stop = true),
                icon: const Icon(Icons.stop),
                label: Text(_stop ? 'Đang dừng...' : 'Dừng gửi'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: Colors.red),
              ),
            if (_total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: done / _total),
              const SizedBox(height: 6),
              Text('Đã xử lý $done/$_total · Thành công: $_sent · Lỗi: $_failed'),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final l in _log.take(30))
                Text(l, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            Text(
              '“Thành công” nghĩa là máy đã chuyển tin cho nhà mạng. '
              'Cước SMS tính theo gói của SIM bạn.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
