import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Nhà mạng
// ---------------------------------------------------------------------------

enum Carrier { viettel, vina, mobi, vnm, gmobile, other }

const Map<Carrier, List<String>> kCarrierPrefixes = {
  Carrier.viettel: [
    '032', '033', '034', '035', '036', '037', '038', '039',
    '086', '096', '097', '098',
  ],
  Carrier.vina: ['081', '082', '083', '084', '085', '088', '091', '094'],
  Carrier.mobi: ['070', '076', '077', '078', '079', '089', '090', '093'],
  Carrier.vnm: ['052', '056', '058', '092'],
  Carrier.gmobile: ['059', '099'],
};

extension CarrierInfo on Carrier {
  String get label {
    switch (this) {
      case Carrier.viettel:
        return 'Viettel';
      case Carrier.vina:
        return 'VinaPhone';
      case Carrier.mobi:
        return 'MobiFone';
      case Carrier.vnm:
        return 'Vietnamobile';
      case Carrier.gmobile:
        return 'Gmobile';
      case Carrier.other:
        return 'Khác';
    }
  }

  Color get color {
    switch (this) {
      case Carrier.viettel:
        return const Color(0xFFD32F2F);
      case Carrier.vina:
        return const Color(0xFF1976D2);
      case Carrier.mobi:
        return const Color(0xFFEF6C00);
      case Carrier.vnm:
        return const Color(0xFF7B1FA2);
      case Carrier.gmobile:
        return const Color(0xFF455A64);
      case Carrier.other:
        return const Color(0xFF757575);
    }
  }
}

Carrier? carrierFromName(String? name) {
  if (name == null) return null;
  for (final c in Carrier.values) {
    if (c.name == name) return c;
  }
  return null;
}

/// +84346046203 -> 0346046203. Số quốc tế khác giữ nguyên.
String nationalPhone(String phone) {
  if (phone.startsWith('+84')) return '0${phone.substring(3)}';
  return phone;
}

/// Nhận biết nhà mạng theo 3 số đầu (đầu số 0xx).
Carrier carrierOf(String phone) {
  final n = nationalPhone(phone);
  if (!n.startsWith('0') || n.length < 10) return Carrier.other;
  final prefix = n.substring(0, 3);
  for (final e in kCarrierPrefixes.entries) {
    if (e.value.contains(prefix)) return e.key;
  }
  return Carrier.other;
}

// ---------------------------------------------------------------------------
// Người nhận
// ---------------------------------------------------------------------------

/// status: P = chờ gửi, S = đã gửi, F = lỗi, K = bỏ qua (đã gửi ở lần trước)
class Contact {
  String name;
  String phone;
  String status;
  int sentAt; // ms, 0 = chưa gửi
  String tpl; // tên mẫu tin đã dùng
  String error;
  bool sel; // được tick chọn để gửi

  Contact(
    this.name,
    this.phone, {
    this.status = 'P',
    this.sentAt = 0,
    this.tpl = '',
    this.error = '',
    this.sel = true,
  });

  Carrier get carrier => carrierOf(phone);

  Map<String, dynamic> toJson() => {
        'n': name,
        'p': phone,
        's': status,
        't': sentAt,
        'm': tpl,
        'e': error,
        'x': sel,
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        (j['n'] ?? '') as String,
        (j['p'] ?? '') as String,
        status: (j['s'] ?? 'P') as String,
        sentAt: ((j['t'] ?? 0) as num).toInt(),
        tpl: (j['m'] ?? '') as String,
        error: (j['e'] ?? '') as String,
        sel: (j['x'] ?? true) as bool,
      );
}

// ---------------------------------------------------------------------------
// Mẫu tin nhắn
// ---------------------------------------------------------------------------

class MsgTemplate {
  String id;
  String name;
  String text;

  /// Nhóm nhà mạng mặc định (Carrier.name) hoặc null.
  String? carrier;

  MsgTemplate({
    required this.id,
    required this.name,
    required this.text,
    this.carrier,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'text': text, 'carrier': carrier};

  factory MsgTemplate.fromJson(Map<String, dynamic> j) => MsgTemplate(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        carrier: j['carrier'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Danh sách đã nhập (1 file Excel = 1 batch)
// ---------------------------------------------------------------------------

class Batch {
  String id;
  String name;
  int createdAt;
  List<Contact> contacts;

  Batch({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.contacts,
  });

  Iterable<Contact> _of(Carrier? g) =>
      g == null ? contacts : contacts.where((c) => c.carrier == g);

  int total([Carrier? g]) => _of(g).length;
  int sent([Carrier? g]) => _of(g).where((c) => c.status == 'S').length;
  int failed([Carrier? g]) => _of(g).where((c) => c.status == 'F').length;
  int pending([Carrier? g]) => _of(g).where((c) => c.status == 'P').length;
  int selectedPending([Carrier? g]) =>
      _of(g).where((c) => c.status == 'P' && c.sel).length;
  int skipped([Carrier? g]) => _of(g).where((c) => c.status == 'K').length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'at': createdAt,
        'c': [for (final c in contacts) c.toJson()],
      };

  factory Batch.fromJson(Map<String, dynamic> j) => Batch(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        createdAt: ((j['at'] ?? 0) as num).toInt(),
        contacts: [
          for (final c in (j['c'] as List? ?? const []))
            Contact.fromJson(Map<String, dynamic>.from(c as Map))
        ],
      );
}

// ---------------------------------------------------------------------------
// Tiện ích ngày giờ
// ---------------------------------------------------------------------------

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(int ms, {bool seconds = true}) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return seconds
      ? '${two(d.hour)}:${two(d.minute)}:${two(d.second)}'
      : '${two(d.hour)}:${two(d.minute)}';
}

String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String fmtDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${fmtDate(d)} ${two(d.hour)}:${two(d.minute)}';
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _weekdays = [
  'Thứ Hai',
  'Thứ Ba',
  'Thứ Tư',
  'Thứ Năm',
  'Thứ Sáu',
  'Thứ Bảy',
  'Chủ Nhật',
];

String dayTitle(DateTime d) {
  final now = DateTime.now();
  if (sameDay(d, now)) return 'Hôm nay';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Hôm qua';
  return _weekdays[d.weekday - 1];
}

/// Một lần gửi (từ lúc bấm bắt đầu): hiện ở lịch sử theo ngày.
class SessionLog {
  String id;
  String batch;
  String tpl;
  int startedAt;
  int total;
  int sent;
  int failed;

  SessionLog({
    required this.id,
    required this.batch,
    required this.tpl,
    required this.startedAt,
    required this.total,
    this.sent = 0,
    this.failed = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'b': batch,
        'm': tpl,
        'at': startedAt,
        't': total,
        's': sent,
        'f': failed,
      };

  factory SessionLog.fromJson(Map<String, dynamic> j) => SessionLog(
        id: (j['id'] ?? '') as String,
        batch: (j['b'] ?? '') as String,
        tpl: (j['m'] ?? '') as String,
        startedAt: ((j['at'] ?? 0) as num).toInt(),
        total: ((j['t'] ?? 0) as num).toInt(),
        sent: ((j['s'] ?? 0) as num).toInt(),
        failed: ((j['f'] ?? 0) as num).toInt(),
      );
}
