import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/core/themes/app_theme.dart';

class AccountNicknameDialog extends StatefulWidget {
  const AccountNicknameDialog({
    required this.nickname,
    required this.onSave,
    super.key,
  });

  final String nickname;
  final Future<void> Function(String) onSave;

  @override
  State<AccountNicknameDialog> createState() => _AccountNicknameDialogState();
}

class _AccountNicknameDialogState extends State<AccountNicknameDialog> {
  late final _controller = TextEditingController(text: widget.nickname);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.l10n.nameRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.accountNicknameSaveError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(l10n.accountChangeNickname),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.accountNickname),
              const SizedBox(height: 8),
              Semantics(
                label: l10n.accountNickname,
                child: ShadInput(
                  key: const Key('account-nickname-input'),
                  controller: _controller,
                  autofocus: true,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.appColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          ShadButton.ghost(
            enabled: !_saving,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          ShadButton(
            key: const Key('account-nickname-save'),
            enabled: !_saving,
            onPressed: _save,
            leading: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}
