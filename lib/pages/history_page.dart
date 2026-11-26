import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';

/// Lịch sử gửi: tab "Theo ngày" (nhật ký từng tin) và tab "Danh sách" (các file đã nhập).
class HistoryPage extends StatefulWidget {
  final VoidCallback onMenu;
  final VoidCallback onGoHome;
  const HistoryPage({super.key, required this.onMenu, required this.onGoHome});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _day = DateTime.now();

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: widget.onMenu,
            tooltip: 'Menu',
          ),
          title: const Text('Lịch sử gửi'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Theo ngày'),
              Tab(text: 'Danh sách đã nhập'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: appState,
          builder: (context, _) => TabBarView(
            children: [
              _dayTab(context),
              _batchTab(context),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab theo ngày
  // ---------------------------------------------------------------------------

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(now) ? now : _day,
      firstDate: DateTime(2023),
      lastDate: now,
      helpText: 'Chọn ngày xem lịch sử',
    );
    if (d != null) setState(() => _day = d);
  }

  void _shift(int days) {
    final n = _day.add(Duration(days: days));
    if (n.isAfter(DateTime.now())) return;
    setState(() => _day = n);
  }

  Widget _dayTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logs = appState.logsOn(_day);
    final sessions = appState.sessionsOn(_day);
    final ok = logs.where((e) => e.contact.status == 'S').length;
    final bad = logs.length - ok;
    final isToday = sameDay(_day, DateTime.now());

    final perCarrier = <Carrier, int>{};
    for (final e in logs) {
      if (e.contact.status != 'S') continue;
      perCarrier[e.contact.carrier] = (perCarrier[e.contact.carrier] ?? 0) + 1;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Ngày trước',
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickDay,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Text(dayTitle(_day),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        Text('${fmtDate(_day)} · chạm để chọn ngày',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.outline)),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: isToday ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Ngày sau',
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          elevation: 0,
          color: cs.primaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _num(context, 'Tổng', logs.length, cs.onPrimaryContainer),
                    _num(context, 'Thành công', ok, Colors.green.shade700),
                    _num(context, 'Lỗi', bad, cs.error),
                  ],
                ),
                if (perCarrier.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in Carrier.values)
                        if ((perCarrier[c] ?? 0) > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: c.color.withAlpha(30),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${c.label}: ${perCarrier[c]}',
                                style: TextStyle(
                                    color: c.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (sessions.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lịch sử nhắn tin trong ngày',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final x in sessions)
                        Container(
                          width: (MediaQuery.of(context).size.width - 40) / 2,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tệp tin: ${x.batch}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5)),
                              Text('Mẫu tin: ${x.tpl}'),
                              Text('Đã gửi: ${x.sent} khách hàng'
                                  '${x.failed > 0 ? " (lỗi ${x.failed})" : ""}'),
                              Text('Thời gian: ${fmtTime(x.startedAt)}',
                                  style: TextStyle(
                                      color: cs.outline, fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => _clearSessions(),
                      child: const Text('XÓA LỊCH SỬ NHẮN TIN'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      isToday
                          ? 'Hôm nay chưa gửi tin nào.'
                          : 'Ngày này không có tin nào được gửi.',
                      style: TextStyle(color: cs.outline),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: logs.length,
                  itemBuilder: (context, i) => _logTile(cs, logs[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _clearSessions() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch sử nhắn tin?'),
        content: const Text(
            'Chỉ xóa các thẻ tóm tắt của ngày này. Danh sách người đã gửi vẫn '
            'được nhớ để không gửi lặp.'),
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
    if (yes == true) await appState.clearSessionsOn(_day);
  }

  Widget _num(BuildContext context, String label, int v, Color color) {
    return Column(
      children: [
        Text('$v',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _logTile(ColorScheme cs, LogEntry e) {
    final c = e.contact;
    final ok = c.status == 'S';
    final car = c.carrier;
    final title = c.name.isEmpty ? c.phone : c.name;
    final parts = <String>[
      if (c.name.isNotEmpty) c.phone,
      car.label,
      if (c.tpl.isNotEmpty) c.tpl,
      if (!ok) (c.error.isEmpty ? 'lỗi' : c.error),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_rounded,
              color: ok ? Colors.green : cs.error,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(fmtTime(c.sentAt),
                style: const TextStyle(fontSize: 10.5)),
          ],
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(parts.join(' · '),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(Icons.circle, size: 12, color: car.color),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab danh sách đã nhập
  // ---------------------------------------------------------------------------

  Widget _batchTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = appState.batches;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Chưa có danh sách nào. Hãy nhập file Excel ở trang Tổng quan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      itemBuilder: (context, i) => _batchCard(context, cs, list[i]),
    );
  }

  Widget _batchCard(BuildContext context, ColorScheme cs, Batch b) {
    final isCurrent = b.id == appState.currentId;
    final done = b.sent() + b.failed();
    final denom = b.total() - b.skipped();
    final progress = denom <= 0 ? 1.0 : (done / denom).clamp(0.0, 1.0);
    final pending = b.pending();
    final working = isCurrent && appState.running;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isCurrent ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart_rounded, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (working)
                  const _Tag('ĐANG GỬI', Colors.green)
                else if (isCurrent)
                  const _Tag('ĐANG MỞ', Colors.teal)
                else if (pending == 0)
                  const _Tag('XONG', Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 4),
            Text('Nhập lúc ${fmtDateTime(b.createdAt)} · ${b.total()} người',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Đã gửi ${b.sent()} · lỗi ${b.failed()} · chờ $pending'
              '${b.skipped() > 0 ? " · bỏ qua ${b.skipped()}" : ""}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in Carrier.values)
                  if (b.total(c) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${c.label} ${b.sent(c)}/${b.total(c) - b.skipped(c)}',
                        style: TextStyle(
                            color: c.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: working ? null : () => _delete(b),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Xoá'),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => _open(b),
                  icon: Icon(
                      pending > 0
                          ? Icons.play_arrow_rounded
                          : Icons.visibility_rounded,
                      size: 20),
                  label: Text(pending > 0 ? 'Mở & gửi tiếp' : 'Mở xem'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Batch b) async {
    final ok = await appState.openBatch(b.id);
    if (!ok) {
      _snack('Đang có phiên gửi dở ở danh sách khác. Hãy hoàn tất hoặc hủy phiên trước.');
      return;
    }
    widget.onGoHome();
  }

  Future<void> _delete(Batch b) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá danh sách này?'),
        content: Text(
          '"${b.name}" và lịch sử gửi của nó sẽ bị xoá. Những người đã gửi '
          'trong danh sách này sẽ không còn được nhớ để tránh gửi lặp.',
        ),
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
    if (yes != true) return;
    final ok = await appState.deleteBatch(b.id);
    if (!ok) _snack('Đang gửi dở, không thể xoá danh sách này.');
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
    );
  }
}
