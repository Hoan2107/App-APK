import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'parsing.dart';

const MethodChannel kChannel = MethodChannel('sms_bulk');

/// Mỗi bao nhiêu giây gửi cho 1 người.
const int kDelaySeconds = 15;

class LogEntry {
  final Batch batch;
  final Contact contact;
  const LogEntry(this.batch, this.contact);
}

/// Trạng thái dùng chung cho cả 3 trang. Lưu bền vào SharedPreferences,
/// đồng bộ với dịch vụ gửi nền (Kotlin) mỗi 500ms.
class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;
  Timer? _timer;
  bool loaded = false;

  // ----- dữ liệu lưu bền ------------------------------------------------------
  List<MsgTemplate> templates = [];
  List<Batch> batches = []; // mới nhất ở đầu
  List<SessionLog> sessions = [];
  String? _sessionId;
  String? currentId;
  String? selectedTplId;
  bool skipSent = true;
  final TextEditingController msgCtrl = TextEditingController();
  String _lastText = '';

  /// Nhóm nhà mạng đang chọn (null = tất cả).
  Carrier? group;

  // ----- phiên gửi hiện tại (khớp với SmsJob bên Kotlin) --------------------
  List<int> jobIdx = []; // vị trí trong batch của từng người trong phiên gửi
  String? jobBatchId;
  String jobTpl = '';
  bool running = false;
  int total = 0;
  int sentN = 0;
  int failedN = 0;
  int index = 0;
  int nextAt = 0;
  String results = '';

  Batch? get current {
    final id = currentId;
    if (id == null) return null;
    for (final b in batches) {
      if (b.id == id) return b;
    }
    return null;
  }

  MsgTemplate? get selectedTemplate {
    final id = selectedTplId;
    if (id == null) return null;
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Có phiên gửi đang chạy hoặc đang tạm dừng giữa chừng.
  bool get jobActive =>
      jobIdx.isNotEmpty &&
      jobBatchId == currentId &&
      total > 0 &&
      index < total;

  bool get hasJob =>
      jobIdx.isNotEmpty && jobBatchId == currentId && total > 0;

  bool get jobFinished => hasJob && index >= total && !running;

  int get secondsLeft {
    if (!running || nextAt == 0) return 0;
    final ms = nextAt - DateTime.now().millisecondsSinceEpoch;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  // ---------------------------------------------------------------------------
  // Khởi tạo & lưu trữ
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;

    try {
      final raw = p.getString('templates');
      if (raw != null) {
        templates = [
          for (final j in jsonDecode(raw) as List)
            MsgTemplate.fromJson(Map<String, dynamic>.from(j as Map))
        ];
      }
    } catch (_) {}
    try {
      final raw = p.getString('batches');
      if (raw != null) {
        batches = [
          for (final j in jsonDecode(raw) as List)
            Batch.fromJson(Map<String, dynamic>.from(j as Map))
        ];
      }
    } catch (_) {}

    try {
      final raw = p.getString('sessions');
      if (raw != null) {
        sessions = [
          for (final j in jsonDecode(raw) as List)
            SessionLog.fromJson(Map<String, dynamic>.from(j as Map))
        ];
      }
    } catch (_) {}

    currentId = p.getString('currentId');
    if (current == null) currentId = null;
    selectedTplId = p.getString('tplId');
    if (selectedTemplate == null) selectedTplId = null;
    skipSent = p.getBool('skipSent') ?? true;
    jobTpl = p.getString('jobTpl') ?? '';
    msgCtrl.text = p.getString('draft') ?? '';
    _lastText = msgCtrl.text;
    msgCtrl.addListener(_onText);

    await _restoreJob();
    loaded = true;
    notifyListeners();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    msgCtrl.dispose();
    super.dispose();
  }

  void _onText() {
    if (msgCtrl.text != _lastText) {
      _lastText = msgCtrl.text;
      _prefs?.setString('draft', _lastText);
    }
    notifyListeners();
  }

  Future<void> _saveTemplates() async {
    await _prefs?.setString(
        'templates', jsonEncode([for (final t in templates) t.toJson()]));
  }

  Future<void> _saveBatches() async {
    await _prefs?.setString(
        'batches', jsonEncode([for (final b in batches) b.toJson()]));
  }

  Future<void> _saveSessions() async {
    if (sessions.length > 300) sessions = sessions.sublist(0, 300);
    await _prefs?.setString(
        'sessions', jsonEncode([for (final x in sessions) x.toJson()]));
  }

  Future<void> _saveMeta() async {
    final p = _prefs;
    if (p == null) return;
    if (currentId == null) {
      await p.remove('currentId');
    } else {
      await p.setString('currentId', currentId!);
    }
    if (selectedTplId == null) {
      await p.remove('tplId');
    } else {
      await p.setString('tplId', selectedTplId!);
    }
    await p.setBool('skipSent', skipSent);
    await p.setString('jobTpl', jobTpl);
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Nếu app bị đóng nhưng dịch vụ nền vẫn còn phiên gửi, nối lại với danh sách.
  Future<void> _restoreJob() async {
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('getJob');
      if (m == null) return;
      final n = (m['total'] as num).toInt();
      if (n <= 0) return;
      final b = current;
      if (b == null) return;
      final phones = List<String>.from(m['phones'] as List);
      final pos = <String, int>{};
      for (var i = 0; i < b.contacts.length; i++) {
        pos[b.contacts[i].phone] = i;
      }
      final idx = <int>[];
      for (final ph in phones) {
        final i = pos[ph];
        if (i == null) return;
        idx.add(i);
      }
      jobIdx = idx;
      jobBatchId = b.id;
      if (sessions.isNotEmpty) _sessionId = sessions.first.id;
      if (msgCtrl.text.trim().isEmpty) {
        msgCtrl.text = (m['message'] as String?) ?? '';
        _lastText = msgCtrl.text;
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Đồng bộ với dịch vụ gửi nền
  // ---------------------------------------------------------------------------

  Future<void> poll() async {
    try {
      final m = await kChannel.invokeMapMethod<String, dynamic>('status');
      if (m == null) return;
      final newRunning = m['running'] == true;
      final newTotal = (m['total'] as num).toInt();
      final newSent = (m['sent'] as num).toInt();
      final newFailed = (m['failed'] as num).toInt();
      final newIndex = (m['index'] as num).toInt();
      final newNext = (m['nextAt'] as num).toInt();
      final newResults = (m['results'] as String?) ?? '';
      final times = <int>[
        for (final t in (m['times'] as List? ?? const [])) (t as num).toInt()
      ];
      final errs = <int, String>{};
      final raw = m['errors'];
      if (raw is Map) {
        raw.forEach((k, v) {
          final i = int.tryParse(k.toString());
          if (i != null) errs[i] = v.toString();
        });
      }

      var changed = newRunning != running ||
          newTotal != total ||
          newSent != sentN ||
          newFailed != failedN ||
          newIndex != index ||
          newNext != nextAt ||
          newResults != results;

      var dataChanged = false;
      final b = current;
      if (b != null &&
          jobIdx.isNotEmpty &&
          jobBatchId == b.id &&
          newResults.length == jobIdx.length) {
        for (var p = 0; p < jobIdx.length; p++) {
          final ch = newResults[p];
          if (ch == 'P') continue;
          final ci = jobIdx[p];
          if (ci < 0 || ci >= b.contacts.length) continue;
          final c = b.contacts[ci];
          if (c.status != ch) {
            c.status = ch;
            c.sentAt = (p < times.length && times[p] > 0)
                ? times[p]
                : DateTime.now().millisecondsSinceEpoch;
            c.tpl = jobTpl;
            c.error = ch == 'F' ? (errs[p] ?? 'lỗi') : '';
            dataChanged = true;
          }
        }
      }

      var sessChanged = false;
      if (_sessionId != null &&
          jobIdx.isNotEmpty &&
          jobBatchId == currentId) {
        for (final x in sessions) {
          if (x.id == _sessionId) {
            if (x.sent != newSent || x.failed != newFailed) {
              x.sent = newSent;
              x.failed = newFailed;
              sessChanged = true;
            }
            break;
          }
        }
      }

      running = newRunning;
      total = newTotal;
      sentN = newSent;
      failedN = newFailed;
      index = newIndex;
      nextAt = newNext;
      results = newResults;

      if (dataChanged) await _saveBatches();
      if (sessChanged) await _saveSessions();
      if (changed || sessChanged || dataChanged || running) notifyListeners();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Danh sách người nhận
  // ---------------------------------------------------------------------------

  Set<String> _sentKeysExcept(Batch b) {
    final s = <String>{};
    for (final o in batches) {
      if (o.id == b.id) continue;
      for (final c in o.contacts) {
        if (c.status == 'S') s.add(phoneKey(c.phone));
      }
    }
    return s;
  }

  /// Đánh dấu K (bỏ qua) cho người đã được gửi thành công ở danh sách khác.
  /// Trả về số người bị đánh dấu.
  int applyDupPolicy(Batch b) {
    var n = 0;
    if (skipSent) {
      final keys = _sentKeysExcept(b);
      for (final c in b.contacts) {
        if (c.status == 'P' && keys.contains(phoneKey(c.phone))) {
          c.status = 'K';
          n++;
        }
      }
    } else {
      for (final c in b.contacts) {
        if (c.status == 'K') c.status = 'P';
      }
    }
    return n;
  }

  Future<void> setSkipSent(bool v) async {
    if (jobActive) return;
    skipSent = v;
    final b = current;
    if (b != null) {
      applyDupPolicy(b);
      await _saveBatches();
    }
    await _saveMeta();
    notifyListeners();
  }

  Future<void> _resetNativeJob() async {
    try {
      await kChannel.invokeMethod('clear');
    } catch (_) {}
    jobIdx = [];
    jobBatchId = null;
    _sessionId = null;
    total = 0;
    index = 0;
    sentN = 0;
    failedN = 0;
    results = '';
  }

  /// Tạo danh sách mới từ file. Trả về số người bị bỏ qua vì đã gửi trước đó,
  /// hoặc -1 nếu không thể (đang gửi).
  Future<int> addBatch(String name, List<Contact> list) async {
    if (jobActive) return -1;
    await _resetNativeJob();
    final b = Batch(
      id: _newId(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      contacts: list,
    );
    batches.insert(0, b);
    if (batches.length > 100) batches.removeLast();
    currentId = b.id;
    group = null;
    final k = applyDupPolicy(b);
    await _saveBatches();
    await _saveMeta();
    notifyListeners();
    return k;
  }

  /// Thêm người nhập tay vào danh sách hiện tại. Trả về số người mới thêm.
  Future<int> addManual(List<Contact> list) async {
    if (jobActive) return -1;
    var b = current;
    if (b == null) {
      await _resetNativeJob();
      b = Batch(
        id: _newId(),
        name: 'Nhập tay ${fmtDate(DateTime.now())}',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        contacts: [],
      );
      batches.insert(0, b);
      currentId = b.id;
    }
    final keys = {for (final c in b.contacts) phoneKey(c.phone)};
    var added = 0;
    for (final c in list) {
      if (keys.add(phoneKey(c.phone))) {
        b.contacts.add(c);
        added++;
      }
    }
    applyDupPolicy(b);
    await _saveBatches();
    await _saveMeta();
    notifyListeners();
    return added;
  }

  Future<bool> openBatch(String id) async {
    if (jobActive && id != currentId) return false;
    if (id != currentId) {
      await _resetNativeJob();
      currentId = id;
      group = null;
      final b = current;
      if (b != null) applyDupPolicy(b);
      await _saveBatches();
      await _saveMeta();
      notifyListeners();
    }
    return true;
  }

  /// Đóng danh sách hiện tại nhưng vẫn giữ trong lịch sử.
  Future<bool> closeCurrent() async {
    if (jobActive) return false;
    await _resetNativeJob();
    currentId = null;
    group = null;
    await _saveMeta();
    notifyListeners();
    return true;
  }

  Future<bool> deleteBatch(String id) async {
    if (id == currentId && jobActive) return false;
    if (id == currentId) {
      await _resetNativeJob();
      currentId = null;
      group = null;
    }
    batches.removeWhere((b) => b.id == id);
    await _saveBatches();
    await _saveMeta();
    notifyListeners();
    return true;
  }

  /// Chuyển các số bị lỗi (trong nhóm đang chọn) về trạng thái chờ gửi.
  Future<int> retryFailed() async {
    final b = current;
    if (b == null || jobActive) return 0;
    var n = 0;
    for (final c in b.contacts) {
      if (c.status == 'F' && (group == null || c.carrier == group)) {
        c.status = 'P';
        c.sentAt = 0;
        c.error = '';
        c.sel = true;
        n++;
      }
    }
    if (n > 0) {
      await _resetNativeJob();
      await _saveBatches();
      notifyListeners();
    }
    return n;
  }

  // ----- chọn / xoá từng người ---------------------------------------------

  Future<void> toggleSel(Contact c, bool v) async {
    c.sel = v;
    await _saveBatches();
    notifyListeners();
  }

  bool get allSelected {
    final b = current;
    if (b == null) return false;
    var any = false;
    for (final c in b.contacts) {
      if (c.status != 'P' || (group != null && c.carrier != group)) continue;
      any = true;
      if (!c.sel) return false;
    }
    return any;
  }

  Future<void> setSelAll(bool v) async {
    final b = current;
    if (b == null) return;
    for (final c in b.contacts) {
      if (c.status == 'P' && (group == null || c.carrier == group)) c.sel = v;
    }
    await _saveBatches();
    notifyListeners();
  }

  /// Xoá người khỏi danh sách (không thể khi đang có phiên gửi dở).
  Future<bool> deleteContacts(List<Contact> list) async {
    final b = current;
    if (b == null || jobActive) return false;
    final set = Set<Contact>.identity()..addAll(list);
    b.contacts.removeWhere(set.contains);
    if (jobIdx.isNotEmpty) await _resetNativeJob();
    await _saveBatches();
    notifyListeners();
    return true;
  }

  List<SessionLog> sessionsOn(DateTime day) => [
        for (final x in sessions)
          if (sameDay(DateTime.fromMillisecondsSinceEpoch(x.startedAt), day)) x
      ];

  Future<void> clearSessionsOn(DateTime day) async {
    sessions.removeWhere(
        (x) => sameDay(DateTime.fromMillisecondsSinceEpoch(x.startedAt), day));
    await _saveSessions();
    notifyListeners();
  }

  void selectGroup(Carrier? g) {
    group = g;
    if (g != null && !jobActive) {
      MsgTemplate? bound;
      for (final t in templates) {
        if (t.carrier == g.name) {
          bound = t;
          break;
        }
      }
      if (bound != null) {
        final cur = selectedTemplate;
        final untouched = msgCtrl.text.trim().isEmpty ||
            (cur != null && cur.text == msgCtrl.text);
        if (untouched) applyTemplate(bound);
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mẫu tin nhắn
  // ---------------------------------------------------------------------------

  void applyTemplate(MsgTemplate? t) {
    selectedTplId = t?.id;
    if (t != null) {
      msgCtrl.text = t.text;
      msgCtrl.selection = TextSelection.collapsed(offset: t.text.length);
    }
    _saveMeta();
    notifyListeners();
  }

  Future<MsgTemplate> addTemplate(
      String name, String text, String? carrier) async {
    final t = MsgTemplate(
      id: _newId(),
      name: name,
      text: text,
      carrier: carrier,
    );
    _unbindCarrier(carrier, t.id);
    templates.add(t);
    await _saveTemplates();
    notifyListeners();
    return t;
  }

  Future<void> updateTemplate(
      MsgTemplate t, String name, String text, String? carrier) async {
    t.name = name;
    t.text = text;
    t.carrier = carrier;
    _unbindCarrier(carrier, t.id);
    await _saveTemplates();
    notifyListeners();
  }

  /// Mỗi nhóm nhà mạng chỉ gắn với 1 mẫu mặc định.
  void _unbindCarrier(String? carrier, String keepId) {
    if (carrier == null) return;
    for (final o in templates) {
      if (o.id != keepId && o.carrier == carrier) o.carrier = null;
    }
  }

  Future<void> deleteTemplate(String id) async {
    templates.removeWhere((t) => t.id == id);
    if (selectedTplId == id) {
      selectedTplId = null;
      await _saveMeta();
    }
    await _saveTemplates();
    notifyListeners();
  }

  Future<void> duplicateTemplate(MsgTemplate t) async {
    templates.add(MsgTemplate(
      id: _newId(),
      name: '${t.name} (bản sao)',
      text: t.text,
    ));
    await _saveTemplates();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Điều khiển gửi
  // ---------------------------------------------------------------------------

  List<int> pendingIndexes(Batch b, Carrier? g) => [
        for (var i = 0; i < b.contacts.length; i++)
          if (b.contacts[i].status == 'P' &&
              b.contacts[i].sel &&
              (g == null || b.contacts[i].carrier == g))
            i
      ];

  /// Số thứ tự mẫu (hiển thị kiểu "Mẫu tin: 3").
  String tplLabelFor(String msg) {
    final t = selectedTemplate;
    if (t == null) return 'Tự soạn';
    final n = templates.indexOf(t) + 1;
    return t.text.trim() == msg.trim() ? '$n' : '$n (đã chỉnh)';
  }

  String tplNameFor(String msg) {
    final t = selectedTemplate;
    if (t == null) return 'Tự soạn';
    return t.text.trim() == msg.trim() ? t.name : '${t.name} (đã chỉnh)';
  }

  /// Trả về null nếu thành công, hoặc thông báo lỗi.
  Future<String?> startJob(String message) async {
    final b = current;
    if (b == null) return 'Chưa có danh sách người nhận.';
    final idx = pendingIndexes(b, group);
    if (idx.isEmpty) return 'Không còn người chờ gửi trong nhóm này.';
    try {
      await kChannel.invokeMethod('start', {
        'contacts': [
          for (final i in idx)
            {'name': b.contacts[i].name, 'phone': b.contacts[i].phone}
        ],
        'message': message,
        'delaySec': kDelaySeconds,
      });
      jobIdx = idx;
      jobBatchId = b.id;
      jobTpl = tplNameFor(message);
      final sess = SessionLog(
        id: _newId(),
        batch: b.name,
        tpl: tplLabelFor(message),
        startedAt: DateTime.now().millisecondsSinceEpoch,
        total: idx.length,
      );
      sessions.insert(0, sess);
      _sessionId = sess.id;
      await _saveSessions();
      await _saveMeta();
      await poll();
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  Future<String?> resumeJob(String message) async {
    try {
      await kChannel.invokeMethod('resume', {'message': message});
      jobTpl = tplNameFor(message);
      await _saveMeta();
      await poll();
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    }
  }

  Future<void> stopJob() async {
    try {
      await kChannel.invokeMethod('stop');
    } catch (_) {}
    await poll();
  }

  /// Bỏ phiên gửi đang dở (những người chưa gửi vẫn ở trạng thái chờ).
  Future<void> cancelJob() async {
    await _resetNativeJob();
    notifyListeners();
  }

  Future<bool> ensurePermission() async {
    try {
      return await kChannel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Lịch sử
  // ---------------------------------------------------------------------------

  /// Tất cả tin đã xử lý (thành công hoặc lỗi) trong 1 ngày, mới nhất trước.
  List<LogEntry> logsOn(DateTime day) {
    final out = <LogEntry>[];
    for (final b in batches) {
      for (final c in b.contacts) {
        if (c.sentAt <= 0 || (c.status != 'S' && c.status != 'F')) continue;
        if (sameDay(DateTime.fromMillisecondsSinceEpoch(c.sentAt), day)) {
          out.add(LogEntry(b, c));
        }
      }
    }
    out.sort((a, b) => b.contact.sentAt.compareTo(a.contact.sentAt));
    return out;
  }
}

final AppState appState = AppState();
