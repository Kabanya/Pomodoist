part of 'calendar_screen.dart';

class _CalendarRoutineEditor extends StatefulWidget {
  const _CalendarRoutineEditor({required this.settings, required this.save});
  final CalendarSettings settings;
  final Future<void> Function(String, List<CalendarPeriod>) save;
  @override
  State<_CalendarRoutineEditor> createState() => _CalendarRoutineEditorState();
}

class _CalendarPeriodDraft {
  _CalendarPeriodDraft(String name, this.start, this.end)
    : name = TextEditingController(text: name);
  final TextEditingController name;
  int start;
  int end;
  void dispose() => name.dispose();
}

class _CalendarRoutineEditorState extends State<_CalendarRoutineEditor> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _name;
  final _periods = <_CalendarPeriodDraft>[];
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _name = TextEditingController(
      text: widget.settings.routineName.isEmpty
          ? context.l10n.calendarRoutineDefault
          : widget.settings.routineName,
    );
    for (var i = 0; i < widget.settings.periods.length; i++) {
      final period = widget.settings.periods[i];
      _periods.add(
        _CalendarPeriodDraft(
          _calendarPeriodName(context, period, i),
          period.startMinutes,
          period.endMinutes,
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final period in _periods) {
      period.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    late List<CalendarPeriod> periods;
    try {
      periods = [
        for (final draft in _periods)
          CalendarPeriod(
            name: draft.name.text.trim(),
            startMinutes: draft.start,
            endMinutes: draft.end,
          ),
      ]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      CalendarSettings.validateRoutine(_name.text.trim(), periods);
    } on ArgumentError {
      setState(() => _error = context.l10n.calendarRoutineInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_name.text.trim(), periods);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.calendarSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(context.l10n.calendarRoutineTitle),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.calendarRoutineDescription,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: context.l10n.calendarRoutineName,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? context.l10n.calendarRoutineInvalid
                      : null,
                ),
                const SizedBox(height: 6),
                for (final draft in _periods)
                  Padding(
                    key: ObjectKey(draft),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: draft.name,
                                enabled: !_saving,
                                maxLength: 40,
                                decoration: InputDecoration(
                                  labelText: context.l10n.calendarPeriodName,
                                  counterText: '',
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? context.l10n.calendarRoutineInvalid
                                    : null,
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.calendarRemovePeriod,
                              onPressed: _saving
                                  ? null
                                  : () {
                                      setState(() => _periods.remove(draft));
                                      draft.dispose();
                                    },
                              icon: const Icon(LucideIcons.x, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _timeField(draft, true)),
                            const SizedBox(width: 10),
                            Expanded(child: _timeField(draft, false)),
                          ],
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _periods.add(
                              _CalendarPeriodDraft(
                                context.l10n.calendarNewPeriod,
                                1140,
                                1260,
                              ),
                            ),
                          ),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: Text(context.l10n.calendarAddPeriod),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.appColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : () => unawaited(_save()),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.commonSave),
        ),
      ],
    ),
  );

  Widget _timeField(_CalendarPeriodDraft draft, bool start) =>
      DropdownButtonFormField<int>(
        initialValue: start ? draft.start : draft.end,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: start
              ? context.l10n.calendarPeriodStart
              : context.l10n.calendarPeriodEnd,
        ),
        items: [
          for (final minute in ({
            start ? draft.start : draft.end,
            for (var value = 0; value <= (start ? 1425 : 1440); value += 15)
              value,
          }.toList()..sort()))
            DropdownMenuItem(
              value: minute,
              child: Text(
                minute == 1440 ? '24:00' : _calendarTime(context, minute),
              ),
            ),
        ],
        onChanged: _saving
            ? null
            : (value) {
                if (value != null)
                  setState(() {
                    if (start) {
                      draft.start = value;
                    } else {
                      draft.end = value;
                    }
                  });
              },
      );
}
