import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../parsing.dart';
import '../store.dart';
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final b = s.current;
        final visible = <int>[];
        if (b != null) {
          for (var i = 0; i < b.contacts.length; i++) {
            final c = b.contacts[i];
            if (s.group != null && c.carrier != s.group) continue;
            final q = _qc.text.trim().toLowerCase();
            if (_search &&
                q.isNotEmpty &&
                !c.name.toLowerCase().contains(q) &&
                !c.phone.contains(q)) {
              continue;
            }
            visible.add(i);
          }
        }
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(context, b)),
              SliverToBoxAdapter(child: _listCard(cs, b)),
              SliverToBoxAdapter(child: _messageCard(cs)),
              if (b != null && visible.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, k) => _tile(cs, b, visible[k]),
                  ),
                ),
              SliverToBoxAdapter(child: _tips(cs)),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
          bottomNavigationBar: _bottomBar(cs, b),
        );
      },
    );
  }

  Widget _header(BuildContext context, Batch? b) {
    final top = MediaQuery.of(context).padding.top;

    int total = 0, sentC = 0, failedC = 0, remaining = 0;
    if (s.hasJob) {
      total = s.total;
      sentC = s.sentN;
      failedC = s.failedN;
      remaining = (s.total - s.index).clamp(0, s.total);
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
      padding: EdgeInsets.fromLTRB(8, top + 8, 20, 22),
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
              IconButton(
                onPressed: widget.onMenu,
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                tooltip: 'Menu',
              ),
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
                  color: s.running ? Colors.white : Colors.white.withAlpha(50),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: s.running ? const Color(0xFF00695C) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Container(
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
                            _stat(Icons.check_circle_rounded, 'Đã gửi', sentC),
                            _stat(Icons.error_rounded, 'Lỗi', failedC),
                            _stat(Icons.hourglass_bottom_rounded, 'Còn lại',
                                remaining),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _live(b, remaining),
                ],
              ),
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
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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

  Widget _live(Batch? b, int remaining) {
    final lines = <Widget>[];
    const style = TextStyle(color: Colors.white, fontSize: 13.5);

    Contact? at(int pos) {
      if (b == null || pos < 0 || pos >= s.jobIdx.length) return null;
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
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 8));
      lines.add(_liveRow(
          Icons.schedule_rounded, 'Tiếp theo (sau ${sec}s): ${_label(next)}'));
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
      lines.add(Text('Ước tính xong sau ${_eta(remaining)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12)));
    } else if (s.jobFinished) {
      lines.add(const SizedBox(height: 4));
      lines.add(const Text('Đã gửi xong phiên này.', style: style));
    } else if (s.jobActive) {
      lines.add(const SizedBox(height: 4));
      lines.add(Text(
          'Đã dừng ở người thứ ${s.index}/${s.total}. Bấm "Tiếp tục" để gửi tiếp.',
          style: style));
    } else {
      lines.add(Text(
        b == null
            ? 'Chọn file Excel hoặc nhập tay để bắt đầu.'
            : (remaining == 0
                ? 'Không còn người chờ gửi ở nhóm này.'
                : 'Sẵn sàng. Chọn nhóm + mẫu tin rồi bấm nút bên dưới.'),
        style: style,
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  // ----- thẻ danh sách + nhóm nhà mạng -------------------------------------------

  Widget _listCard(ColorScheme cs, Batch? b) {
    final busy = s.jobActive;
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
                Icon(Icons.groups_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b == null
                        ? 'Danh sách người nhận'
                        : 'Người nhận (${b.total()})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (b != null && !s.running)
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Bỏ'),
                  ),
              ],
            ),
            if (b != null)
              Padding(
                padding: const EdgeInsets.only(left: 32, bottom: 4),
                child: Text(
                  'File: ${b.name} · nhập lúc ${fmtDateTime(b.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: (s.running || busy) ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Chọn file Excel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (s.running || busy) ? null : _manualInput,
                    icon: const Icon(Icons.keyboard_alt_outlined),
                    label: const Text('Nhập tay'),
                  ),
                ),
              ],
            ),
            if (b == null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'File Excel cần có cột tên và cột số điện thoại, app tự nhận '
                  'diện cột và tự phân nhóm theo nhà mạng (Viettel, VinaPhone, '
                  'MobiFone...). Số bị mất số 0 đầu vẫn được nhận.',
                  style: TextStyle(color: cs.outline, fontSize: 12.5),
                ),
              )
            else ...[
              const SizedBox(height: 14),
              Text('Chọn nhóm để gửi',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Tất cả · ${b.total()}'),
                      selected: s.group == null,
                      onSelected: (_) => s.selectGroup(null),
                    ),
                    for (final c in Carrier.values)
                      if (b.total(c) > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            avatar: Icon(Icons.circle, size: 10, color: c.color),
                            label: Text('${c.label} · ${b.total(c)}'),
                            selected: s.group == c,
                            onSelected: (_) => s.selectGroup(c),
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Nhóm ${s.group?.label ?? "tất cả"}: '
                'đã gửi ${b.sent(s.group)} · lỗi ${b.failed(s.group)} · '
                'chờ ${b.pending(s.group)}'
                '${b.skipped(s.group) > 0 ? " · bỏ qua ${b.skipped(s.group)} (đã gửi trước đó)" : ""}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  Checkbox(
                    value: s.allSelected,
                    onChanged: (s.running || busy)
                        ? null
                        : (v) => s.setSelAll(v ?? false),
                  ),
                  const Text('Chọn tất cả'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Tìm kiếm',
                    icon: Icon(
                        _search ? Icons.search_off_rounded : Icons.search_rounded),
                    onPressed: () => setState(() {
                      _search = !_search;
                      if (!_search) _qc.clear();
                    }),
                  ),
                  OutlinedButton(
                    onPressed: (s.running || busy) ? null : _deleteGroup,
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    child: const Text('Xóa tất cả'),
                  ),
                ],
              ),
              if (_search)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextField(
                    controller: _qc,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surface,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Tìm theo tên hoặc số điện thoại',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Bỏ qua số đã gửi thành công trước đây'),
                subtitle: const Text('Tránh gửi lặp khi nhập lại file cũ'),
                value: s.skipSent,
                onChanged: busy ? null : (v) => s.setSkipSent(v),
              ),
              if (b.failed(s.group) > 0 && !s.running && !busy)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _retryFailed,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Gửi lại ${b.failed(s.group)} số bị lỗi'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ----- thẻ nội dung tin nhắn ----------------------------------------------------

  Widget _messageCard(ColorScheme cs) {
    final text = s.msgCtrl.text;
    final t = s.selectedTemplate;
    final edited = t != null && t.text != text;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  onPressed: s.running ? null : _insertName,
                ),
              ],
            ),
            const SizedBox(height: 10),
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
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Đã chỉnh sửa so với mẫu "${t!.name}" (chỉ áp dụng cho '
                        'lần gửi này).',
                        style: TextStyle(color: cs.tertiary, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _updateTemplate(t!),
                      child: const Text('Cập nhật mẫu'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: s.msgCtrl,
              enabled: !s.running,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                hintText: 'Chọn một mẫu ở trên, hoặc gõ nội dung tin nhắn vào đây...',
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

  Widget _tile(ColorScheme cs, Batch b, int i) {
    final c = b.contacts[i];
    final st = c.status;
    final isNext = s.running &&
        s.hasJob &&
        s.index < s.jobIdx.length &&
        s.jobIdx[s.index] == i;

    Widget trailing;
    if (st == 'S') {
      trailing = const Icon(Icons.check_circle_rounded, color: Colors.green);
    } else if (st == 'F') {
      trailing = Icon(Icons.error_rounded, color: cs.error);
    } else if (st == 'K') {
      trailing = Icon(Icons.history_toggle_off_rounded, color: cs.outline);
    } else if (isNext) {
      trailing = Icon(Icons.hourglass_top_rounded, color: cs.primary);
    } else {
      trailing = Checkbox(
        value: c.sel,
        onChanged: s.running ? null : (v) => s.toggleSel(c, v ?? false),
      );
    }
    trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        trailing,
        IconButton(
          tooltip: 'Xóa',
          icon: Icon(Icons.delete_rounded, color: cs.error),
          onPressed: s.running ? null : () => _deleteOne(c),
        ),
      ],
    );

    final title = c.name.isEmpty ? c.phone : c.name;
    final car = c.carrier;
    String sub = '${c.phone} · ${car.label}';
    if (st == 'S' && c.sentAt > 0) sub += ' · ${fmtTime(c.sentAt)}';
    if (st == 'F') sub += ' · ${c.error.isEmpty ? "lỗi" : c.error}';
    if (st == 'K') sub += ' · đã gửi trước đó';
    final initial = String.fromCharCode(title.runes.first).toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isNext ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: car.color.withAlpha(40),
          foregroundColor: car.color,
          child: c.name.isEmpty
              ? const Icon(Icons.person_rounded)
              : Text(initial,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
      ),
    );
  }

  Widget _bottomBar(ColorScheme cs, Batch? b) {
    Widget content;
    const minSize = Size.fromHeight(54);

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
