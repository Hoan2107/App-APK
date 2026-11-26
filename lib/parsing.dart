import 'dart:convert';

import 'package:archive/archive.dart';

import 'models.dart';

// Đọc file danh sách (xlsx/csv/txt), chuẩn hoá số điện thoại. Không phụ thuộc giao diện.

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
String phoneKey(String phone) {
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
    if (!seen.add(phoneKey(phone))) {
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
