import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/ui/core/localization/app_l10n.dart';
import 'package:pomodoist/ui/settings/view_models/custom_model_settings.dart';
import 'package:pomodoist/ui/settings/widgets/settings_components.dart';

class CustomModelSettingsRow extends ConsumerWidget {
  const CustomModelSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customModelSettingsProvider);
    final owner = ref.watch(customModelOwnerProvider);
    return SettingsRow(
      title: context.l10n.customAnalysisTitle,
      subtitle: context.l10n.customAnalysisSubtitle,
      control: state.when(
        data: (config) => _Editor(key: ValueKey(owner), config: config),
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(customModelSettingsProvider),
          child: Text(context.l10n.commonRetry),
        ),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.config, super.key});
  final CustomModelConfig config;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late bool custom = widget.config.enabled;
  late final url = TextEditingController(text: widget.config.baseUrl);
  late final normal = TextEditingController(text: widget.config.normalModel);
  late final smart = TextEditingController(text: widget.config.smartModel);
  final secret = TextEditingController();
  bool busy = false;
  bool keyEdited = false;
  bool invalidUrl = false;
  bool invalidModel = false;
  Map<String, ModelCheck> checks = {};
  String? feedback;
  String? savedVersion;

  @override
  void didUpdateWidget(_Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.version == widget.config.version) return;
    custom = widget.config.enabled;
    url.text = widget.config.baseUrl;
    normal.text = widget.config.normalModel;
    smart.text = widget.config.smartModel;
    secret.clear();
    keyEdited = false;
    invalidUrl = invalidModel = false;
    checks = {};
    if (widget.config.version != savedVersion) feedback = null;
  }

  @override
  void dispose() {
    for (final c in [url, normal, smart, secret]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get retained =>
      widget.config.hasKey &&
      !keyEdited &&
      widget.config.baseUrl == url.text.trim();

  void edited() {
    setState(() {
      checks = {};
      feedback = null;
      invalidUrl = false;
      invalidModel = false;
    });
  }

  Future<void> switchDefault() async {
    setState(() {
      busy = true;
      feedback = null;
    });
    try {
      await ref
          .read(customModelSettingsProvider.notifier)
          .save(
            widget.config.withEnabled(false),
            expectedVersion: widget.config.version,
          );
      if (mounted) {
        setState(() {
          custom = false;
          secret.clear();
          keyEdited = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => feedback = context.l10n.settingsSaveError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit({required bool test}) async {
    final controller = ref.read(customModelSettingsProvider.notifier);
    String? base;
    try {
      base = controller.normalizeUrl(url.text);
    } on FormatException {
      /* Show field error. */
    }
    setState(() {
      invalidUrl = base == null;
      invalidModel = normal.text.trim().isEmpty;
      feedback = null;
    });
    if (base == null || invalidModel) return;
    final draft = CustomModelConfig(
      enabled: true,
      baseUrl: base,
      normalModel: normal.text.trim(),
      smartModel: smart.text.trim(),
    );
    final key = keyEdited ? secret.text : null;
    final version = widget.config.version;
    setState(() => busy = true);
    try {
      if (test) {
        final result = await controller.check(
          draft,
          apiKey: key,
          locale: Localizations.localeOf(context).toLanguageTag(),
        );
        if (mounted && widget.config.version == version) {
          setState(() => checks = result);
        }
      } else {
        final saved = await controller.save(
          draft,
          apiKey: key,
          expectedVersion: version,
        );
        if (mounted) {
          setState(() {
            savedVersion = saved.version;
            url.text = base!;
            secret.clear();
            keyEdited = false;
            feedback = context.l10n.customSaved;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => feedback = test
              ? context.l10n.customAnalysisFailed
              : context.l10n.settingsSaveError,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final helperStyle = Theme.of(context).textTheme.bodySmall;
    Widget field(
      TextEditingController c,
      String label, {
      String? hint,
      String? error,
      bool password = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: c,
        enabled: !busy,
        obscureText: password,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: c == url ? TextInputType.url : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 3,
          suffixIcon: password && retained
              ? IconButton(
                  tooltip: l.customRemoveKey,
                  icon: const Icon(LucideIcons.x),
                  onPressed: busy
                      ? null
                      : () {
                          keyEdited = true;
                          secret.clear();
                          edited();
                        },
                )
              : null,
        ),
        onChanged: (_) {
          if (c == url) {
            secret.clear();
            keyEdited = true;
          }
          if (password) keyEdited = true;
          edited();
        },
      ),
    );
    Widget checkFor(String model) {
      final check = checks[model.trim()];
      if (check == null) return const SizedBox.shrink();
      return Semantics(
        liveRegion: true,
        child: Text(modelCheckLabel(l, check), style: helperStyle),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.customDefault),
              selected: !custom,
              onSelected: busy || !custom ? null : (_) => switchDefault(),
            ),
            ChoiceChip(
              label: Text(l.customEndpoint),
              selected: custom,
              onSelected: busy
                  ? null
                  : (_) => setState(() {
                      custom = true;
                      feedback = null;
                    }),
            ),
          ],
        ),
        if (custom) ...[
          field(
            url,
            l.customBaseUrl,
            hint: 'https://example.com/v1',
            error: invalidUrl ? l.customInvalidUrl : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.customLocalhost, style: helperStyle),
          ),
          field(
            normal,
            l.customNormalModel,
            error: invalidModel ? l.customRequiredModel : null,
          ),
          checkFor(normal.text),
          field(smart, l.customSmartModel, hint: normal.text.trim()),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.customSmartFallback, style: helperStyle),
          ),
          if (smart.text.trim().isNotEmpty) checkFor(smart.text),
          field(
            secret,
            l.customApiKey,
            password: true,
            hint: retained ? '••••••••' : null,
          ),
          if (kIsWeb) Text(l.customBrowserKey, style: helperStyle),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => submit(test: true),
                child: Text(l.customTest),
              ),
              FilledButton(
                onPressed: busy ? null : () => submit(test: false),
                child: Text(l.commonSave),
              ),
            ],
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        if (feedback case final String message)
          Semantics(liveRegion: true, child: Text(message, style: helperStyle)),
      ],
    );
  }
}
