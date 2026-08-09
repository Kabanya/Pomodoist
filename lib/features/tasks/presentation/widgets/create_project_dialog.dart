import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_l10n.dart';
import '../../../../app/providers.dart';
import '../../../../app/widgets/resizable_dialog.dart';
import '../../domain/project_colors.dart';
import 'project_color_picker.dart';

Future<void> showCreateProjectDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const CreateProjectDialog(),
  );
}

Future<void> showCreateLabelDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const CreateLabelDialog(),
  );
}

class CreateProjectDialog extends ConsumerWidget {
  const CreateProjectDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final projects = ref.watch(projectsProvider).value ?? const [];
    return _CreateNamedItemDialog(
      title: l10n.addProject,
      hintText: l10n.projectName,
      inputKey: const Key('project-create-input'),
      submitKey: const Key('project-create-submit'),
      icon: Icons.tag,
      initialColor: nextProjectColor(projects),
      onCreate: (ref, name, color) async {
        await ref
            .read(projectRepositoryProvider)
            .createProject(name, color: color);
      },
      errorText: (context, error) => context.l10n.couldNotAddProject(error),
    );
  }
}

class CreateLabelDialog extends StatelessWidget {
  const CreateLabelDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CreateNamedItemDialog(
      title: l10n.addLabel,
      hintText: l10n.labelName,
      inputKey: const Key('label-create-input'),
      submitKey: const Key('label-create-submit'),
      icon: Icons.label_outline,
      onCreate: (ref, name, color) async {
        await ref.read(labelRepositoryProvider).createLabel(name);
      },
      errorText: (context, error) => context.l10n.couldNotAddLabel(error),
    );
  }
}

class _CreateNamedItemDialog extends ConsumerStatefulWidget {
  const _CreateNamedItemDialog({
    required this.title,
    required this.hintText,
    required this.inputKey,
    required this.submitKey,
    required this.icon,
    required this.onCreate,
    required this.errorText,
    this.initialColor,
  });

  final String title;
  final String hintText;
  final Key inputKey;
  final Key submitKey;
  final IconData icon;
  final Future<void> Function(WidgetRef ref, String name, String? color)
  onCreate;
  final String Function(BuildContext context, Object error) errorText;
  final String? initialColor;

  @override
  ConsumerState<_CreateNamedItemDialog> createState() =>
      _CreateNamedItemDialogState();
}

class _CreateNamedItemDialogState
    extends ConsumerState<_CreateNamedItemDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  late String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ResizableDialog(
      title: Text(widget.title),
      initialSize: Size(560, widget.initialColor == null ? 260 : 370),
      minSize: Size(320, widget.initialColor == null ? 220 : 340),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: widget.inputKey,
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: Icon(widget.icon),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_selectedColor != null) ...[
            const SizedBox(height: 20),
            ProjectColorPalettePicker(
              selectedColor: _selectedColor!,
              onSelected: (color) => setState(() => _selectedColor = color),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          key: widget.submitKey,
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(l10n.commonAdd),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onCreate(ref, name, _selectedColor);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.errorText(context, error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
