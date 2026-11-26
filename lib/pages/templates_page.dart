import 'package:flutter/material.dart';

import '../models.dart';
import '../parsing.dart';
import '../store.dart';
import '../theme.dart';

/// Trang quản lý các mẫu tin nhắn.
class TemplatesPage extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onGoHome;
  const TemplatesPage({super.key, required this.onMenu, required this.onGoHome});

  Future<void> _add(BuildContext context) async {
    await Navigator.of(context).push<MsgTemplate>(
      MaterialPageRoute(builder: (_) => const TemplateEditorPage()),
    );
  }

  Future<void> _edit(BuildContext context, MsgTemplate t) async {
    await Navigator.of(context).push<MsgTemplate>(
      MaterialPageRoute(builder: (_) => TemplateEditorPage(template: t)),
    );
  }

  Future<void> _delete(BuildContext context, MsgTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá mẫu này?'),
        content: Text('Mẫu "${t.name}" sẽ bị xoá. Lịch sử gửi không bị ảnh hưởng.'),
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
    if (ok == true) await appState.deleteTemplate(t.id);
  }

  void _use(BuildContext context, MsgTemplate t) {
    if (appState.running) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Đang gửi, hãy dừng trước khi đổi mẫu.')));
      return;
    }
    appState.applyTemplate(t);
    onGoHome();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: onMenu,
          tooltip: 'Menu',
        ),
        title: const Text('Mẫu tin nhắn'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm mẫu'),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final list = appState.templates;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.article_outlined, size: 64, color: cs.outline),
                    const SizedBox(height: 12),
                    Text(
                      'Chưa có mẫu tin nhắn nào.\n\n'
                      'Tạo sẵn mỗi nhóm khách hàng một mẫu (ví dụ Mẫu 1 cho '
                      'Viettel, Mẫu 2 cho VinaPhone). Khi gửi chỉ cần chọn mẫu, '
                      'nội dung tự điền và vẫn sửa được.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.outline),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final t = list[i];
              final bound = carrierFromName(t.carrier);
              final selected = t.id == appState.selectedTplId;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                color: selected ? cs.primaryContainer : cs.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                      color: selected
                          ? cs.primary
                          : cs.outlineVariant.withAlpha(130)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _edit(context, t),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (bound != null) Pill(bound.label, bound.color),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'edit') _edit(context, t);
                                if (v == 'dup') appState.duplicateTemplate(t);
                                if (v == 'del') _delete(context, t);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Sửa')),
                                PopupMenuItem(
                                    value: 'dup', child: Text('Nhân bản')),
                                PopupMenuItem(value: 'del', child: Text('Xoá')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            t.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t.text.runes.length} ký tự · '
                                '~${smsSegments(t.text)} SMS',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: cs.outline),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _use(context, t),
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Dùng để gửi'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Màn hình thêm / sửa 1 mẫu tin. Trả về MsgTemplate khi lưu.
class TemplateEditorPage extends StatefulWidget {
  final MsgTemplate? template;
  final String initialText;
  final Carrier? initialCarrier;

  const TemplateEditorPage({
    super.key,
    this.template,
    this.initialText = '',
    this.initialCarrier,
  });

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _text;
  String? _carrier;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _name = TextEditingController(text: t?.name ?? '');
    _text = TextEditingController(text: t?.text ?? widget.initialText);
    _carrier = t != null ? t.carrier : widget.initialCarrier?.name;
    if (_carrier == Carrier.other.name) _carrier = null;
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _insertName() {
    final t = _text.text;
    final sel = _text.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    _text.value = TextEditingValue(
      text: t.replaceRange(start, end, '{ten}'),
      selection: TextSelection.collapsed(offset: start + 5),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final text = _text.text.trim();
    if (name.isEmpty) {
      _snack('Hãy đặt tên cho mẫu (ví dụ: Mẫu Viettel).');
      return;
    }
    if (text.isEmpty) {
      _snack('Nội dung mẫu đang trống.');
      return;
    }
    final existing = widget.template;
    MsgTemplate saved;
    if (existing != null) {
      await appState.updateTemplate(existing, name, text, _carrier);
      saved = existing;
    } else {
      saved = await appState.addTemplate(name, text, _carrier);
    }
    if (mounted) Navigator.pop(context, saved);
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = _text.text;
    final editing = widget.template != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Sửa mẫu tin' : 'Thêm mẫu tin'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Lưu'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Tên mẫu',
              hintText: 'Ví dụ: Mẫu Viettel',
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Dùng mặc định cho nhóm',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            'Khi chọn nhóm này ở trang Tổng quan, mẫu tự được điền sẵn.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Không gắn'),
                selected: _carrier == null,
                onSelected: (_) => setState(() => _carrier = null),
              ),
              for (final c in Carrier.values)
                if (c != Carrier.other)
                  ChoiceChip(
                    avatar: Icon(Icons.circle, size: 10, color: c.color),
                    label: Text(c.label),
                    selected: _carrier == c.name,
                    onSelected: (_) => setState(() => _carrier = c.name),
                  ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('Nội dung',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              ActionChip(
                avatar: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Chèn {ten}'),
                onPressed: _insertName,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            minLines: 8,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: 'Chào {ten}, ...',
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
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
    );
  }
}
