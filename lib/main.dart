import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _ch = MethodChannel('sms_bulk');

/// Mỗi bao nhiêu giây gửi cho 1 người.
const int kDelaySeconds = 15;

void main() => runApp(const SmsToolApp());

class SmsToolApp extends StatelessWidget {
  const SmsToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF00897B);
    return MaterialApp(
      title: 'SMS Tool',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Dữ liệu & đọc file
// ---------------------------------------------------------------------------

class Contact {
  final String name;
  final String phone;
  const Contact(this.name, this.phone);
}

final RegExp _letter = RegExp(r'\p{L}', unicode: true);

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Chuẩn hoá thành số điện thoại. Chỉ nhận số di động Việt Nam
/// (03x, 05x, 07x, 08x, 09x / +84...) hoặc số quốc tế có dấu +.
/// Các mã dài khác (CIF, số hợp đồng...) bị loại để không gửi nhầm.
String? normalizePhone(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  if (RegExp(r'^\d+(\.\d+)?[eE]\+?\d+$').hasMatch(s)) {
    final d = double.tryParse(s);
    if (d == null) return null;
    s = d.toStringAsFixed(0);
  } else if (RegExp(r'^\d+\.0+$').hasMatch(s)) {
    s = s.split('.').first;
  }

  if (!RegExp(r'^[+\d\s().\-]+$').hasMatch(s)) return null;

  final hasPlus = s.startsWith('+');
  final d = s.replaceAll(RegExp(r'\D'), '');

  if (hasPlus) {
    return (d.length >= 9 && d.length <= 15) ? '+$d' : null;
  }
  if (d.length == 11 && RegExp(r'^84[35789]').hasMatch(d)) return '+$d';
  if (d.length == 10 && RegExp(r'^0[35789]').hasMatch(d)) return d;
  // Excel hay làm mất số 0 đầu: 859318869 -> 0859318869
  if (d.length == 9 && RegExp(r'^[35789]').hasMatch(d)) return '0$d';
  return null;
}

/// Khoá để loại trùng: +84346046203 và 0346046203 là cùng 1 người.
String _phoneKey(String phone) {
  var key = phone.replaceAll('+', '');
  if (key.startsWith('84')) {
    key = key.substring(2);
  } else if (key.startsWith('0')) {
    key = key.substring(1);
  }
  return key;
}

int _colIndex(String letters) {
  var n = 0;
  for (final u in letters.codeUnits) {
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

/// Đọc .xlsx thành các dòng, mỗi dòng là danh sách ô theo đúng vị trí cột.
List<List<String>> xlsxToRows(List<int> bytes) {
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

  final rows = <List<String>>[];
  for (final f in arc.files) {
    if (!f.isFile ||
        !f.name.startsWith('xl/worksheets/') ||
        !f.name.endsWith('.xml')) {
      continue;
    }
    final xml = utf8.decode(f.content as List<int>, allowMalformed: true);
    for (final r in RegExp(r'<row\b[^>]*?(?:/>|>(.*?)</row>)', dotAll: true)
        .allMatches(xml)) {
      final body = r.group(1);
      if (body == null) continue;
      final cells = <String>[];
      for (final c in RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
          .allMatches(body)) {
        final inner = c.group(2);
        if (inner == null) continue;
        final attrs = c.group(1) ?? '';
        final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1);
        String? val;
        if (type == 'inlineStr') {
          val = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
              .firstMatch(inner)
              ?.group(1);
        } else {
          final v = RegExp(r'<v>(.*?)</v>', dotAll: true)
              .firstMatch(inner)
              ?.group(1);
          if (v != null) {
            if (type == 's') {
              final si = int.tryParse(v);
              if (si != null && si >= 0 && si < shared.length) {
                val = shared[si];
              }
            } else {
              val = v;
            }
          }
        }
        if (val == null) continue;
        final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
        final idx = ref != null ? _colIndex(ref) : cells.length;
        while (cells.length <= idx) {
          cells.add('');
        }
        cells[idx] = _unescapeXml(val);
      }
      rows.add(cells);
    }
  }
  return rows;
}

List<List<String>> textToRows(String text) {
  return text
      .split(RegExp(r'[\r\n]+'))
      .where((l) => l.trim().isNotEmpty)
      .map((l) => l
          .split(RegExp(r'[,;\t|]'))
          .map((c) => c.trim().replaceAll('"', ''))
          .toList())
      .toList();
}

/// Số dòng bị bỏ qua (trùng số / số không hợp lệ) ở lần đọc gần nhất.
int lastSkipped = 0;

/// Tự tìm cột số điện thoại (cột có nhiều số hợp lệ nhất) và cột tên.
List<Contact> contactsFromRows(List<List<String>> rows) {
  lastSkipped = 0;
  var maxCols = 0;
  final phoneVotes = <int, int>{};
  for (final row in rows) {
    if (row.length > maxCols) maxCols = row.length;
    for (var c = 0; c < row.length; c++) {
      if (normalizePhone(row[c]) != null) {
        phoneVotes[c] = (phoneVotes[c] ?? 0) + 1;
      }
    }
  }
  if (phoneVotes.isEmpty) return [];

  var phoneCol = -1;
  var best = 0;
  phoneVotes.forEach((col, v) {
    if (v > best || (v == best && col < phoneCol)) {
      best = v;
      phoneCol = col;
    }
  });

  final simple = maxCols <= 3; // danh sách đơn giản: nhập tay / csv gọn

  // Cột tên: ưu tiên theo tiêu đề (dòng đầu), nếu không có thì đoán theo nội dung.
  var nameCol = -1;
  if (!simple && rows.isNotEmpty) {
    final header = rows.first;
    final re = RegExp(r'ten|tên|name|họ|khách|khach', caseSensitive: false);
    for (var c = 0; c < header.length; c++) {
      if (c != phoneCol && re.hasMatch(header[c])) {
        nameCol = c;
        break;
      }
    }
    if (nameCol < 0) {
      final votes = <int, int>{};
      final plain = RegExp(r'^[^\d_#<>=/\\]+$');
      for (final row in rows) {
        for (var c = 0; c < row.length; c++) {
          if (c == phoneCol) continue;
          final cell = row[c].trim();
          if (_letter.hasMatch(cell) &&
              cell.contains(' ') &&
              plain.hasMatch(cell)) {
            votes[c] = (votes[c] ?? 0) + 1;
          }
        }
      }
      var bv = 0;
      votes.forEach((col, v) {
        if (v > bv || (v == bv && col < nameCol)) {
          bv = v;
          nameCol = col;
        }
      });
    }
  }

  final seen = <String>{};
  final out = <Contact>[];
  for (final row in rows) {
    String? phone;
    if (phoneCol < row.length) phone = normalizePhone(row[phoneCol]);
    if (phone == null && simple) {
      for (final cell in row) {
        final p = normalizePhone(cell);
        if (p != null) {
          phone = p;
          break;
        }
      }
    }
    if (phone == null) {
      if (phoneCol < row.length && RegExp(r'\d').hasMatch(row[phoneCol])) {
        lastSkipped++; // có số nhưng không hợp lệ
      }
      continue;
    }
    if (!seen.add(_phoneKey(phone))) {
      lastSkipped++; // trùng số
      continue;
    }

    var name = '';
    if (simple) {
      for (final cell in row) {
        final c = cell.trim();
        if (_letter.hasMatch(c) && normalizePhone(c) == null) {
          name = c;
          break;
        }
      }
    } else if (nameCol >= 0 && nameCol < row.length) {
      final c = row[nameCol].trim();
      if (_letter.hasMatch(c)) name = c;
    }
    out.add(Contact(name, phone));
  }
  return out;
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
  List<Contact> _contacts = [];
  String? _fileName;
  Timer? _timer;

  bool _running = false;
  int _sent = 0;
  int _failed = 0;
  int _total = 0;
  int _index = 0;
  int _nextAt = 0;
  String _results = '';
  Map<int, String> _errors = {};

  @override
  void initState() {
    super.initState();
    _restore();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msg.dispose();
    super.dispose();
  }

  // ----- trạng thái từ phần gửi nền (Kotlin) --------------------------------

  bool get _hasJob => _total > 0 && (_running || _index > 0);
  bool get _finished => _total > 0 && _index >= _total && !_running;
  int get _remaining {
    final r = _total - _index;
    return r < 0 ? 0 : r;
  }

  int get _secondsLeft {
    if (!_running || _nextAt == 0) return 0;
    final ms = _nextAt - DateTime.now().millisecondsSinceEpoch;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  Future<void> _restore() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getJob');
      if (m == null || !mounted) return;
      final total = (m['total'] as num).toInt();
      if (total > 0 && _contacts.isEmpty) {
        final names = List<String>.from(m['names'] as List);
        final phones = List<String>.from(m['phones'] as List);
        setState(() {
          _contacts = [
            for (var i = 0; i < phones.length; i++) Contact(names[i], phones[i])
          ];
          _msg.text = (m['message'] as String?) ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      if (m == null || !mounted) return;
      final errs = <int, String>{};
      final raw = m['errors'];
      if (raw is Map) {
        raw.forEach((k, v) {
          final i = int.tryParse(k.toString());
          if (i != null) errs[i] = v.toString();
        });
      }
      setState(() {
        _running = m['running'] == true;
        _total = (m['total'] as num).toInt();
        _sent = (m['sent'] as num).toInt();
        _failed = (m['failed'] as num).toInt();
        _index = (m['index'] as num).toInt();
        _nextAt = (m['nextAt'] as num).toInt();
        _results = (m['results'] as String?) ?? '';
        _errors = errs;
      });
    } catch (_) {}
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ----- thao tác -------------------------------------------------------------

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
      final rows = ext == 'xlsx'
          ? xlsxToRows(bytes)
          : textToRows(utf8.decode(bytes, allowMalformed: true));
      final found = contactsFromRows(rows);
      final skipped = lastSkipped;
      await _ch.invokeMethod('clear');
      setState(() {
        _contacts = found;
        _fileName = f.name;
        _total = 0;
        _index = 0;
        _sent = 0;
        _failed = 0;
        _results = '';
        _errors = {};
      });
      _snack(found.isEmpty
          ? 'Không tìm thấy số điện thoại nào trong file.'
          : 'Đã đọc ${found.length} người từ ${f.name}'
              '${skipped > 0 ? " (bỏ qua $skipped dòng trùng hoặc số không hợp lệ)" : ""}');
    } catch (e) {
      _snack('Lỗi đọc file: $e\n(File .xls cũ: hãy lưu lại thành .xlsx)');
    }
  }

  Future<void> _manualInput() async {
    final ctrl = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nhập tay danh sách',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Mỗi dòng 1 người: "Tên, SĐT" hoặc chỉ SĐT',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 5,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nguyễn Văn A, 0346046203\n+84912345678',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Thêm vào danh sách'),
            ),
          ],
        ),
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final rows = <List<String>>[
      for (final c in _contacts) [c.name, c.phone],
      ...textToRows(text),
    ];
    final merged = contactsFromRows(rows);
    final added = merged.length - _contacts.length;
    await _ch.invokeMethod('clear');
    setState(() {
      _contacts = merged;
      _total = 0;
      _index = 0;
      _sent = 0;
      _failed = 0;
      _results = '';
      _errors = {};
    });
    _snack(added > 0
        ? 'Đã thêm $added người'
        : 'Không có số mới hợp lệ (hoặc bị trùng)');
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá danh sách?'),
        content: const Text('Danh sách người nhận và tiến độ gửi sẽ bị xoá.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    await _ch.invokeMethod('clear');
    setState(() {
      _contacts = [];
      _fileName = null;
      _total = 0;
      _index = 0;
      _sent = 0;
      _failed = 0;
      _results = '';
      _errors = {};
    });
  }

  void _insertName() {
    final t = _msg.text;
    final sel = _msg.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final nt = t.replaceRange(start, end, '{ten}');
    _msg.value = TextEditingValue(
      text: nt,
      selection: TextSelection.collapsed(offset: start + 5),
    );
    setState(() {});
  }

  Future<bool> _ensurePermission() async {
    try {
      final ok = await _ch.invokeMethod<bool>('requestPermission') ?? false;
      if (!ok) {
        _snack('Cần cấp quyền SMS: Cài đặt > Ứng dụng > SMS Tool > Quyền.');
      }
      return ok;
    } on PlatformException catch (e) {
      _snack('Lỗi cấp quyền: ${e.message ?? e.code}');
      return false;
    }
  }

  Future<void> _start() async {
    final message = _msg.text.trim();
    if (message.isEmpty) {
      _snack('Hãy nhập nội dung tin nhắn.');
      return;
    }
    if (_contacts.isEmpty) {
      _snack('Chưa có người nhận nào.');
      return;
    }
    if (!await _ensurePermission()) return;
    if (!mounted) return;

    final segs = smsSegments(message);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bắt đầu gửi tự động?'),
        content: Text(
          'Gửi cho ${_contacts.length} người, cứ mỗi $kDelaySeconds giây tự '
          'gửi 1 người, chạy nền cho tới khi hết danh sách hoặc bạn bấm Dừng.\n\n'
          'Khoảng $segs SMS / người (cước theo gói SIM).',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bắt đầu')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _ch.invokeMethod('start', {
        'contacts': [
          for (final c in _contacts) {'name': c.name, 'phone': c.phone}
        ],
        'message': message,
        'delaySec': kDelaySeconds,
      });
      await _poll();
    } on PlatformException catch (e) {
      _snack('Không bắt đầu được: ${e.message ?? e.code}');
    }
  }

  Future<void> _resume() async {
    if (!await _ensurePermission()) return;
    try {
      await _ch.invokeMethod('resume', {'message': _msg.text.trim()});
      await _poll();
    } on PlatformException catch (e) {
      _snack('Không tiếp tục được: ${e.message ?? e.code}');
    }
  }

  Future<void> _stop() async {
    await _ch.invokeMethod('stop');
    await _poll();
  }

  // ----- dựng giao diện ---------------------------------------------------------

  String _label(Contact c) =>
      c.name.isEmpty ? c.phone : '${c.name} · ${c.phone}';

  String _eta() {
    final s = _remaining * kDelaySeconds;
    if (s < 60) return '$s giây';
    final m = (s / 60).ceil();
    if (m < 60) return '$m phút';
    return '${m ~/ 60} giờ ${m % 60} phút';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _hasJob ? _total : _contacts.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, total)),
          SliverToBoxAdapter(child: _messageCard(cs)),
          SliverToBoxAdapter(child: _recipientsHeader(cs, total)),
          if (_contacts.isEmpty)
            SliverToBoxAdapter(child: _emptyState(cs))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, i) => _tile(cs, i),
              ),
            ),
          SliverToBoxAdapter(child: _tips(cs)),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
      bottomNavigationBar: _bottomBar(cs, total),
    );
  }

  Widget _header(BuildContext context, int total) {
    final top = MediaQuery.of(context).padding.top;
    final done = _hasJob ? _sent + _failed : 0;
    final progress =
        total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();
    final remaining = _hasJob ? _remaining : total;

    String status;
    if (_running) {
      status = 'ĐANG GỬI';
    } else if (_finished) {
      status = 'HOÀN TẤT';
    } else if (_hasJob) {
      status = 'ĐÃ DỪNG';
    } else {
      status = 'SẴN SÀNG';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00BFA5), Color(0xFF00695C)],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.sms_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SMS Tool',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text('Tự động gửi mỗi $kDelaySeconds giây / 1 người',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _running
                      ? Colors.white
                      : Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _running ? const Color(0xFF00695C) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(36),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 9,
                              backgroundColor: Colors.white.withAlpha(60),
                              color: Colors.white,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat(Icons.check_circle_rounded, 'Đã gửi',
                              _hasJob ? _sent : 0),
                          _stat(Icons.error_rounded, 'Lỗi',
                              _hasJob ? _failed : 0),
                          _stat(Icons.hourglass_bottom_rounded, 'Còn lại',
                              remaining),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _live(total),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String label, int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text('$value',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _liveRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
          ),
        ),
      ],
    );
  }

  Widget _live(int total) {
    final lines = <Widget>[];
    const style = TextStyle(color: Colors.white, fontSize: 13.5);

    if (_hasJob && _index > 0 && _index - 1 < _contacts.length) {
      final c = _contacts[_index - 1];
      final ok = _results.length >= _index && _results[_index - 1] == 'S';
      lines.add(_liveRow(
        ok ? Icons.check_circle_rounded : Icons.error_rounded,
        '${ok ? "Vừa gửi" : "Lỗi"}: ${_label(c)}',
      ));
    }

    if (_running && _index < _total && _index < _contacts.length) {
      final c = _contacts[_index];
      final s = _secondsLeft;
      final frac = (1 - s / kDelaySeconds).clamp(0.0, 1.0).toDouble();
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 8));
      lines.add(_liveRow(Icons.schedule_rounded,
          'Tiếp theo (sau ${s}s): ${_label(c)}'));
      lines.add(const SizedBox(height: 10));
      lines.add(ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: frac,
          minHeight: 6,
          backgroundColor: Colors.white24,
          color: Colors.white,
        ),
      ));
      lines.add(const SizedBox(height: 8));
      lines.add(Text('Ước tính xong sau ${_eta()}',
          style: const TextStyle(color: Colors.white70, fontSize: 12)));
    } else if (_finished) {
      lines.add(const SizedBox(height: 4));
      lines.add(const Text('Đã gửi xong toàn bộ danh sách.', style: style));
    } else if (_hasJob) {
      lines.add(const SizedBox(height: 4));
      lines.add(Text(
          'Đã dừng ở người thứ $_index/$_total. Bấm "Tiếp tục" để gửi tiếp.',
          style: style));
    } else {
      lines.add(Text(
        total == 0
            ? 'Chọn file Excel hoặc nhập tay để bắt đầu.'
            : 'Sẵn sàng. Bấm nút bên dưới, app tự gửi mỗi $kDelaySeconds giây.',
        style: style,
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  Widget _messageCard(ColorScheme cs) {
    final text = _msg.text;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Nội dung tin nhắn',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: const Text('Chèn {ten}'),
                  onPressed: _running ? null : _insertName,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msg,
              enabled: !_running,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                hintText: 'Dán hoặc gõ nội dung tin nhắn vào đây...',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${text.runes.length} ký tự · ~${smsSegments(text)} SMS / người'
              '  ·  {ten} sẽ được thay bằng tên từng người',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipientsHeader(ColorScheme cs, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Người nhận ($total)',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (_contacts.isNotEmpty && !_running)
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Xoá'),
                ),
            ],
          ),
          if (_fileName != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 6),
              child: Text('File: $_fileName',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : _pickFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Chọn file Excel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _running ? null : _manualInput,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('Nhập tay'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        children: [
          Icon(Icons.contact_phone_outlined, size: 56, color: cs.outline),
          const SizedBox(height: 10),
          Text(
            'Chưa có người nhận.\nFile Excel cần có cột tên và cột số điện thoại, '
            'app tự nhận diện cột.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
        ],
      ),
    );
  }

  Widget _tile(ColorScheme cs, int i) {
    final c = _contacts[i];
    final st = _results.length > i ? _results[i] : 'P';
    final isNext = _running && i == _index;

    Widget trailing;
    if (st == 'S') {
      trailing = const Icon(Icons.check_circle_rounded, color: Colors.green);
    } else if (st == 'F') {
      trailing = Icon(Icons.error_rounded, color: cs.error);
    } else if (isNext) {
      trailing = Icon(Icons.hourglass_top_rounded, color: cs.primary);
    } else {
      trailing = Icon(Icons.schedule_rounded, color: cs.outline);
    }

    final title = c.name.isEmpty ? c.phone : c.name;
    final subtitle =
        st == 'F' ? '${c.phone} · ${_errors[i] ?? "lỗi"}' : c.phone;
    final initial = String.fromCharCode(title.runes.first).toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isNext ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: st == 'S'
              ? Colors.green.withAlpha(40)
              : (st == 'F' ? cs.errorContainer : cs.primary.withAlpha(30)),
          foregroundColor: cs.onSurface,
          child: c.name.isEmpty
              ? const Icon(Icons.person_rounded)
              : Text(initial),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing,
      ),
    );
  }

  Widget _tips(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Text(
        'Mẹo: để app chạy ổn định khi tắt màn hình, vào Cài đặt > Ứng dụng > '
        'SMS Tool > Tiết kiệm pin và chọn "Không hạn chế". '
        '"Đã gửi" nghĩa là máy đã chuyển tin cho nhà mạng.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: cs.outline),
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs, int total) {
    Widget content;
    const minSize = Size.fromHeight(54);

    if (_running) {
      content = FilledButton.icon(
        onPressed: _stop,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Dừng gửi'),
        style: FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          minimumSize: minSize,
        ),
      );
    } else if (_hasJob && !_finished) {
      content = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _start,
              style: OutlinedButton.styleFrom(minimumSize: minSize),
              child: const Text('Gửi lại từ đầu'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _resume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Tiếp tục ($_remaining còn lại)'),
              style: FilledButton.styleFrom(minimumSize: minSize),
            ),
          ),
        ],
      );
    } else {
      content = FilledButton.icon(
        onPressed: total == 0 ? null : _start,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(_finished
            ? 'Gửi lại từ đầu'
            : 'Bắt đầu gửi tự động ($total người)'),
        style: FilledButton.styleFrom(minimumSize: minSize),
      );
    }

    return Material(
      elevation: 12,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: content,
        ),
      ),
    );
  }
}
