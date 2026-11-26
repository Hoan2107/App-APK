import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../parsing.dart';
import '../store.dart';
import '../theme.dart';
import 'templates_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onMenu;
  const HomePage({super.key, required this.onMenu});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppState get s => appState;
  final _qc = TextEditingController();
  bool _search = false;

  @override
  void dispose() {
    _qc.dispose();
    super.dispose();
  }

  Future<void> _deleteGroup() async {
    final b = s.current;
    if (b == null) return;
    final list = [
      for (final c in b.contacts)
        if (s.group == null || c.carrier == s.group) c
    ];
    if (list.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tất cả?'),
        content: Text(
            'Xóa ${list.length} người (nhóm ${s.group?.label ?? "tất cả"}) khỏi danh sách này? '
            'Người đã gửi cũng mất khỏi lịch sử của danh sách.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      if (!await s.deleteContacts(list)) _blockedByJob();
    }
  }

  Future<void> _deleteOne(Contact c) async {
    if (!await s.deleteContacts([c])) _blockedByJob();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  bool _blockedByJob() {
    if (s.jobActive) {
      _snack('Đang có phiên gửi dở. Hãy bấm "Tiếp tục" cho xong, '
          'hoặc "Hủy phiên" rồi mới đổi danh sách.');
      return true;
    }
    return false;
  }

  // ----- danh sách người nhận --------------------------------------------------

  Future<void> _pickFile() async {
    if (_blockedByJob()) return;
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
      if (found.isEmpty) {
        _snack('Không tìm thấy số điện thoại nào trong file.');
        return;
      }
      final k = await s.addBatch(f.name, found);
      if (k < 0) return;
      final parts = <String>['Đã đọc ${found.length} người từ ${f.name}'];
      if (skipped > 0) parts.add('bỏ qua $skipped dòng trùng/sai số');
      if (k > 0) parts.add('$k người đã được gửi trước đó nên không gửi lại');
      _snack(parts.join(' · '));
    } catch (e) {
      _snack('Lỗi đọc file: $e\n(File .xls cũ: hãy lưu lại thành .xlsx)');
    }
  }

  Future<void> _manualInput() async {
    if (_blockedByJob()) return;
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
    ctrl.dispose();
    if (text == null || text.trim().isEmpty) return;
    final found = contactsFromRows(textToRows(text));
    if (found.isEmpty) {
      _snack('Không có số hợp lệ nào.');
      return;
    }
    final added = await s.addManual(found);
    if (added < 0) return;
    _snack(added > 0
        ? 'Đã thêm $added người'
        : 'Không có số mới (đã có trong danh sách)');
  }

  Future<void> _clearAll() async {
    if (_blockedByJob()) return;
    final b = s.current;
    if (b == null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ danh sách này?'),
        content: const Text(
          '"Đóng" chỉ gỡ khỏi màn hình, danh sách và tiến độ vẫn nằm trong '
          'Lịch sử để mở lại gửi tiếp.\n\n'
          '"Xoá hẳn" xoá cả lịch sử gửi của danh sách này.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Xoá hẳn')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: const Text('Đóng')),
        ],
      ),
    );
    if (choice == 'close') {
      await s.closeCurrent();
    } else if (choice == 'delete') {
      await s.deleteBatch(b.id);
    }
  }

  // ----- mẫu tin nhắn -------------------------------------------------------------

  void _insertName() {
    final c = s.msgCtrl;
    final t = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final nt = t.replaceRange(start, end, '{ten}');
    c.value = TextEditingValue(
      text: nt,
      selection: TextSelection.collapsed(offset: start + 5),
    );
  }

  Future<void> _pickTemplate() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Chọn mẫu tin nhắn',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              if (s.templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'Chưa có mẫu nào. Tạo mẫu để dùng lại cho từng nhóm khách hàng.',
                    style: TextStyle(color: cs.outline),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: s.templates.length,
                    itemBuilder: (_, i) {
                      final t = s.templates[i];
                      final bound = carrierFromName(t.carrier);
                      return ListTile(
                        selected: t.id == s.selectedTplId,
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(t.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(t.text,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: bound == null
                            ? null
                            : Text(bound.label,
                                style: TextStyle(
                                    color: bound.color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                        onTap: () {
                          Navigator.pop(ctx);
                          s.applyTemplate(t);
                        },
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Tạo mẫu mới'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveAsTemplate(blank: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveAsTemplate({bool blank = false}) async {
    final text = blank ? '' : s.msgCtrl.text;
    final saved = await Navigator.of(context).push<MsgTemplate>(
      MaterialPageRoute(
        builder: (_) => TemplateEditorPage(
          initialText: text,
          initialCarrier: s.group,
        ),
      ),
    );
    if (saved != null) {
      s.applyTemplate(saved);
      _snack('Đã lưu mẫu "${saved.name}"');
    }
  }

  Future<void> _updateTemplate(MsgTemplate t) async {
    await s.updateTemplate(t, t.name, s.msgCtrl.text.trim(), t.carrier);
    _snack('Đã cập nhật mẫu "${t.name}"');
  }

  // ----- gửi ------------------------------------------------------------------------

  String get _groupLabel => s.group?.label ?? 'tất cả các nhóm';

  Future<void> _start() async {
    final message = s.msgCtrl.text.trim();
    final b = s.current;
    if (b == null) {
      _snack('Chưa có người nhận nào.');
      return;
    }
    if (message.isEmpty) {
      _snack('Hãy nhập nội dung tin nhắn hoặc chọn một mẫu.');
      return;
    }
    final n = s.pendingIndexes(b, s.group).length;
    if (n == 0) {
      _snack('Không còn người chờ gửi trong nhóm này.');
      return;
    }
    if (!await s.ensurePermission()) {
      _snack('Cần cấp quyền SMS: Cài đặt > Ứng dụng > SMS Tool > Quyền.');
      return;
    }
    if (!mounted) return;

    final segs = smsSegments(message);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bắt đầu gửi tự động?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nhóm: $_groupLabel · $n người chờ gửi'),
              const SizedBox(height: 4),
              Text('Mẫu: ${s.tplNameFor(message)}'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(message,
                    maxLines: 6, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 10),
              Text(
                'Cứ mỗi $kDelaySeconds giây tự gửi 1 người, chạy nền cho tới '
                'khi hết hoặc bạn bấm Dừng. Dừng lúc nào cũng được, bấm '
                '"Tiếp tục" để gửi tiếp, không gửi lặp người đã gửi.\n\n'
                'Khoảng $segs SMS / người (cước theo gói SIM).',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
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
    final err = await s.startJob(message);
    if (err != null) _snack('Không bắt đầu được: $err');
  }

  Future<void> _resume() async {
    final message = s.msgCtrl.text.trim();
    if (message.isEmpty) {
      _snack('Nội dung tin nhắn đang trống.');
      return;
    }
    if (!await s.ensurePermission()) {
      _snack('Cần cấp quyền SMS: Cài đặt > Ứng dụng > SMS Tool > Quyền.');
      return;
    }
    final err = await s.resumeJob(message);
    if (err != null) _snack('Không tiếp tục được: $err');
  }

  Future<void> _retryFailed() async {
    final n = await s.retryFailed();
    _snack(n > 0
        ? 'Đã đưa $n số lỗi về hàng chờ. Bấm "Bắt đầu" để gửi lại.'
        : 'Không có số lỗi nào.');
  }

  // ----- giao diện -----------------------------------------------------------------

  String _label(Contact c) =>
      c.name.isEmpty ? c.phone : '${c.name} · ${c.phone}';

  String _eta(int remaining) {
    final sec = remaining * kDelaySeconds;
    if (sec < 60) return '$sec giây';
    final m = (sec / 60).ceil();
    if (m < 60) return '$m phút';
    return '${m ~/ 60} giờ ${m % 60} phút';
  }

  /// Bố cục 1 màn hình: tổng quan (trên) · danh sách (giữa, cuộn) · tin nhắn
  /// và nút gửi (dưới). Khi màn hình thấp (bàn phím mở, xoay ngang) tự thu gọn.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final b = s.current;
        final visible = <int>[];
        if (b != null) {
          final q = _qc.text.trim().toLowerCase();
          for (var i = 0; i < b.contacts.length; i++) {
            final c = b.contacts[i];
            if (s.group != null && c.carrier != s.group) continue;
            if (_search &&
                q.isNotEmpty &&
                !c.name.toLowerCase().contains(q) &&
                !c.phone.contains(q)) {
              continue;
            }
            visible.add(i);
          }
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            body: LayoutBuilder(
              builder: (context, box) {
                final compact = box.maxHeight < 560;
                final tiny = box.maxHeight < 380;
                // Các key giữ ô tìm kiếm không bị mất con trỏ khi bố cục đổi.
                return Column(
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('header'),
                      child: _header(context, b, compact),
                    ),
                    if (b != null && !compact)
                      KeyedSubtree(
                        key: const ValueKey('file'),
                        child: _fileBar(cs, b),
                      ),
                    if (b != null && !tiny)
                      KeyedSubtree(
                        key: const ValueKey('groups'),
                        child: _groupBar(cs, b, compact),
                      ),
                    if (b != null)
                      KeyedSubtree(
                        key: const ValueKey('tools'),
                        child: _toolBar(cs, b),
                      ),
                    if (b != null && _search)
                      KeyedSubtree(
                        key: const ValueKey('search'),
                        child: _searchField(cs),
                      ),
                    Expanded(
                      key: const ValueKey('list'),
                      child: b == null
                          ? _emptyState(cs)
                          : _contactList(cs, b, visible),
                    ),
                    if (!tiny)
                      KeyedSubtree(
                        key: const ValueKey('bottom'),
                        child: _bottomBar(cs, b, compact),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ----- phần tổng quan ------------------------------------------------------------

  Widget _header(BuildContext context, Batch? b, bool compact) {
    final top = MediaQuery.of(context).padding.top;

    int total = 0, sentC = 0, failedC = 0, remaining = 0;
    if (s.hasJob) {
      total = s.total;
      sentC = s.sentN;
      failedC = s.failedN;
      remaining = (s.total - s.index).clamp(0, s.total).toInt();
    } else if (b != null) {
      final g = s.group;
      sentC = b.sent(g);
      failedC = b.failed(g);
      remaining = b.pending(g);
      total = b.total(g) - b.skipped(g);
    }
    final done = sentC + failedC;
    final progress =
        total <= 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();

    String status;
    if (s.running) {
      status = 'ĐANG GỬI';
    } else if (s.jobFinished) {
      status = 'HOÀN TẤT';
    } else if (s.jobActive) {
      status = 'ĐÃ DỪNG';
    } else {
      status = 'SẴN SÀNG';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(4, top, 4, compact ? 4 : 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrand, kBrandDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onMenu,
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                tooltip: 'Menu',
              ),
              const Expanded(
                child: Text('SMS Tool',
                    maxLines: 1,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: s.running ? Colors.white : Colors.white.withAlpha(45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: s.running ? kBrandDark : Colors.white,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                onSelected: (v) {
                  if (v == 'skip') s.setSkipSent(!s.skipSent);
                  if (v == 'close') _clearAll();
                  if (v == 'tips') _showTips();
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem<String>(
                    value: 'skip',
                    checked: s.skipSent,
                    enabled: !s.jobActive,
                    child: const Text('Bỏ qua số đã gửi trước đây'),
                  ),
                  if (b != null && !s.running)
                    const PopupMenuItem<String>(
                        value: 'close', child: Text('Bỏ danh sách này')),
                  const PopupMenuItem<String>(
                      value: 'tips', child: Text('Mẹo sử dụng')),
                ],
              ),
            ],
          ),
          if (!compact && b != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 5,
                                backgroundColor: Colors.white.withAlpha(60),
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _stat('Đã gửi', sentC),
                      _stat('Lỗi', failedC),
                      _stat('Còn lại', remaining),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _live(b, remaining),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, int value) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _liveRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _live(Batch b, int remaining) {
    final lines = <Widget>[];

    Contact? at(int pos) {
      if (pos < 0 || pos >= s.jobIdx.length) return null;
      final ci = s.jobIdx[pos];
      return ci < b.contacts.length ? b.contacts[ci] : null;
    }

    if (s.hasJob && s.index > 0) {
      final c = at(s.index - 1);
      if (c != null) {
        final ok = s.results.length >= s.index && s.results[s.index - 1] == 'S';
        lines.add(_liveRow(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          '${ok ? "Vừa gửi" : "Lỗi"}: ${_label(c)}',
        ));
      }
    }

    final next = (s.running && s.index < s.total) ? at(s.index) : null;
    if (next != null) {
      final sec = s.secondsLeft;
      final frac = (1 - sec / kDelaySeconds).clamp(0.0, 1.0).toDouble();
      lines.add(_liveRow(
          Icons.schedule_rounded, 'Tiếp theo (sau ${sec}s): ${_label(next)}'));
      lines.add(const SizedBox(height: 6));
      lines.add(ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: frac,
          minHeight: 4,
          backgroundColor: Colors.white24,
          color: Colors.white,
        ),
      ));
      lines.add(const SizedBox(height: 4));
      lines.add(Text('Ước tính xong sau ${_eta(remaining)}',
          style: const TextStyle(color: Colors.white70, fontSize: 11.5)));
    } else if (s.jobFinished) {
      lines.add(_liveRow(Icons.done_all_rounded, 'Đã gửi xong phiên này.'));
    } else if (s.jobActive) {
      lines.add(_liveRow(Icons.pause_circle_rounded,
          'Đã dừng ở ${s.index}/${s.total}. Bấm "Tiếp tục" để gửi tiếp.'));
    } else {
      lines.add(_liveRow(
        Icons.info_outline_rounded,
        remaining == 0
            ? 'Không còn người chờ gửi ở nhóm này.'
            : 'Sẵn sàng. Chọn nhóm, mẫu tin rồi bấm Gửi.',
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  void _showTips() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mẹo sử dụng'),
        content: const Text(
          'Để app chạy ổn định khi tắt màn hình, vào Cài đặt > Ứng dụng > '
          'SMS Tool > Tiết kiệm pin và chọn "Không hạn chế".\n\n'
          '"Đã gửi" nghĩa là máy đã chuyển tin cho nhà mạng.\n\n'
          '"Bỏ qua số đã gửi trước đây" giúp tránh gửi lặp khi nhập lại file cũ.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
        ],
      ),
    );
  }

  // ----- thanh file, nhóm nhà mạng, công cụ ----------------------------------------

  Widget _fileBar(ColorScheme cs, Batch b) {
    final locked = s.running || s.jobActive;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: boxDecoration(cs),
      child: Row(
        children: [
          Icon(Icons.description_rounded, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${b.total()} người · ${fmtDateTime(b.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.outline, fontSize: 11.5)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Nhập tay',
            onPressed: locked ? null : _manualInput,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          FilledButton.tonalIcon(
            onPressed: locked ? null : _pickFile,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Chọn file'),
          ),
        ],
      ),
    );
  }

  Widget _groupChip(
      ColorScheme cs, String label, Color color, Carrier? value) {
    final selected = s.group == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        backgroundColor: cs.surface,
        selectedColor: color.withAlpha(45),
        side: BorderSide(color: selected ? color : cs.outlineVariant),
        labelStyle: TextStyle(
            color: selected ? cs.onSurface : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
        onSelected: (_) => s.selectGroup(value),
      ),
    );
  }

  Widget _groupBar(ColorScheme cs, Batch b, bool compact) {
    final failed = b.failed(s.group);
    final skipped = b.skipped(s.group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 0),
          child: Row(
            children: [
              _groupChip(cs, 'Tất cả · ${b.total()}', cs.primary, null),
              for (final c in Carrier.values)
                if (b.total(c) > 0)
                  _groupChip(cs, '${c.label} · ${b.total(c)}', c.color, c),
            ],
          ),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Đã gửi ${b.sent(s.group)} · lỗi $failed · '
                    'chờ ${b.pending(s.group)}'
                    '${skipped > 0 ? " · bỏ qua $skipped" : ""}',
                    style: TextStyle(color: cs.outline, fontSize: 12),
                  ),
                ),
                if (failed > 0 && !s.running && !s.jobActive)
                  TextButton.icon(
                    onPressed: _retryFailed,
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Gửi lại $failed số lỗi'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _toolBar(ColorScheme cs, Batch b) {
    final locked = s.running || s.jobActive;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
      child: Row(
        children: [
          Checkbox(
            value: s.allSelected,
            onChanged: locked ? null : (v) => s.setSelAll(v ?? false),
          ),
          const Expanded(
            child: Text('Chọn tất cả',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: 'Tìm kiếm',
            visualDensity: VisualDensity.compact,
            icon: Icon(
                _search ? Icons.search_off_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _search = !_search;
              if (!_search) _qc.clear();
            }),
          ),
          TextButton.icon(
            onPressed: locked ? null : _deleteGroup,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('Xóa tất cả'),
          ),
        ],
      ),
    );
  }

  Widget _searchField(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: TextField(
        controller: _qc,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: cs.surface,
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'Tìm theo tên hoặc số điện thoại',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ----- bảng người nhận -----------------------------------------------------------

  Widget _emptyState(ColorScheme cs) {
    final locked = s.running || s.jobActive;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.groups_rounded, size: 56, color: cs.primary),
            const SizedBox(height: 10),
            Text('Chưa có danh sách người nhận',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'File Excel cần có cột tên và cột số điện thoại, app tự nhận diện '
              'cột và phân nhóm theo nhà mạng. Số mất số 0 đầu vẫn được nhận.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: locked ? null : _pickFile,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Chọn file Excel'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: locked ? null : _manualInput,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Nhập tay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactList(ColorScheme cs, Batch b, List<int> visible) {
    final head = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: cs.onSecondaryContainer);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      clipBehavior: Clip.antiAlias,
      decoration: boxDecoration(cs),
      child: Column(
        children: [
          Container(
            color: cs.secondaryContainer,
            padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
            child: Row(
              children: [
                Expanded(flex: 11, child: Text('TÊN KHÁCH HÀNG', style: head)),
                Expanded(flex: 9, child: Text('SỐ ĐIỆN THOẠI', style: head)),
                SizedBox(
                    width: 40,
                    child: Center(child: Text('CHỌN', style: head))),
                SizedBox(
                    width: 40, child: Center(child: Text('XÓA', style: head))),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text('Không có người nào phù hợp.',
                        style: TextStyle(color: cs.outline)),
                  )
                : Material(
                    type: MaterialType.transparency,
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1, color: cs.outlineVariant.withAlpha(110)),
                      itemBuilder: (context, k) => _row(cs, b, visible[k]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, Batch b, int i) {
    final c = b.contacts[i];
    final st = c.status;
    final isNext = s.running &&
        s.hasJob &&
        s.index < s.jobIdx.length &&
        s.jobIdx[s.index] == i;

    Widget mark;
    if (st == 'S') {
      mark = Icon(Icons.check_circle_rounded, color: okColor(context));
    } else if (st == 'F') {
      mark = Icon(Icons.error_rounded, color: cs.error);
    } else if (st == 'K') {
      mark = Icon(Icons.history_toggle_off_rounded, color: cs.outline);
    } else if (isNext) {
      mark = Icon(Icons.hourglass_top_rounded, color: cs.primary);
    } else {
      mark = Checkbox(
        value: c.sel,
        visualDensity: VisualDensity.compact,
        onChanged: s.running ? null : (v) => s.toggleSel(c, v ?? false),
      );
    }

    final car = c.carrier;
    var sub = car.label;
    if (st == 'S' && c.sentAt > 0) sub += ' · ${fmtTime(c.sentAt)}';
    if (st == 'F') sub += ' · ${c.error.isEmpty ? "lỗi" : c.error}';
    if (st == 'K') sub += ' · đã gửi trước đó';

    return Container(
      color: isNext ? cs.primaryContainer : null,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(10, 3, 0, 3),
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Text(
              c.name.isEmpty ? '(không tên)' : c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  color: c.name.isEmpty ? cs.outline : cs.onSurface),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: car.color),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: st == 'F' ? cs.error : cs.outline),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 40, child: Center(child: mark)),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Xóa',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 21, color: s.running ? cs.outlineVariant : cs.error),
              onPressed: s.running ? null : () => _deleteOne(c),
            ),
          ),
        ],
      ),
    );
  }

  // ----- tin nhắn ------------------------------------------------------------------

  /// Bảng soạn tin nhắn mở từ dưới lên.
  Future<void> _openMessage() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ListenableBuilder(
          listenable: s,
          builder: (ctx, _) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _messageEditor(ctx),
          ),
        ),
      ),
    );
  }

  Widget _messageEditor(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final text = s.msgCtrl.text;
    final t = s.selectedTemplate;
    final edited = t != null && t.text != text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Nội dung tin nhắn',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ActionChip(
              avatar: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Chèn {ten}'),
              onPressed: s.running ? null : _insertName,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: s.running ? null : _pickTemplate,
                icon: const Icon(Icons.article_outlined),
                label: Text(
                  t == null ? 'Chọn mẫu tin' : t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: s.running || text.trim().isEmpty
                  ? null
                  : () => _saveAsTemplate(),
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Lưu mẫu'),
            ),
          ],
        ),
        if (edited && !s.running)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đã chỉnh so với mẫu "${t!.name}" (chỉ áp dụng lần này).',
                  style: TextStyle(color: cs.tertiary, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => _updateTemplate(t!),
                child: const Text('Cập nhật mẫu'),
              ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: s.msgCtrl,
          enabled: !s.running,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            hintText: 'Chọn một mẫu ở trên, hoặc gõ nội dung tin nhắn vào đây...',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${text.runes.length} ký tự · ~${smsSegments(text)} SMS / người'
          '  ·  {ten} sẽ được thay bằng tên từng người',
          style: Theme.of(ctx).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Xong'),
          ),
        ),
      ],
    );
  }

  /// Dòng xem trước tin nhắn, chạm để soạn / đổi mẫu.
  Widget _messageBar(ColorScheme cs) {
    final text = s.msgCtrl.text;
    final t = s.selectedTemplate;
    final title = t == null
        ? 'Tin nhắn tự soạn'
        : '${t.name}${t.text != text ? " (đã chỉnh)" : ""}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _openMessage,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration:
            boxDecoration(cs, color: cs.secondaryContainer.withAlpha(110)),
        child: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · ${text.runes.length} ký tự · '
                    '~${smsSegments(text)} SMS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    text.trim().isEmpty
                        ? 'Chạm để chọn mẫu hoặc soạn nội dung'
                        : text.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_up_rounded),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs, Batch? b, bool compact) {
    Widget content;
    const minSize = Size.fromHeight(48);

    if (s.running) {
      content = FilledButton.icon(
        onPressed: s.stopJob,
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('Dừng gửi'),
        style: FilledButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          minimumSize: minSize,
        ),
      );
    } else if (s.jobActive) {
      content = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: s.cancelJob,
              style: OutlinedButton.styleFrom(minimumSize: minSize),
              child: const Text('Hủy phiên'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _resume,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Tiếp tục (${s.total - s.index} còn lại)'),
              style: FilledButton.styleFrom(minimumSize: minSize),
            ),
          ),
        ],
      );
    } else {
      final n = b == null ? 0 : s.pendingIndexes(b, s.group).length;
      content = FilledButton.icon(
        onPressed: n == 0 ? null : _start,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(b == null
            ? 'Chưa có danh sách'
            : (n == 0
                ? 'Không còn người chờ gửi'
                : 'Gửi nhóm ${s.group?.label ?? "tất cả"} ($n người)')),
        style: FilledButton.styleFrom(minimumSize: minSize),
      );
    }

    return Material(
      elevation: 10,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact) ...[
                _messageBar(cs),
                const SizedBox(height: 8),
                content,
              ] else
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Nội dung tin nhắn',
                      onPressed: _openMessage,
                      icon: const Icon(Icons.edit_note_rounded),
                    ),
                    Expanded(child: content),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
