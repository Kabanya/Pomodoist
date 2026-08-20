import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/app/providers.dart';
import 'package:pomodoist/features/tasks/domain/task_models.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_bar.dart';
import 'package:pomodoist/features/tasks/presentation/widgets/quick_add_text_controller.dart';
import 'package:pomodoist/l10n/app_localizations.dart';

void main() {
  testWidgets('quick-add input displays the shared effective hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quickAddHintTextProvider.overrideWithValue(
            'Plan the next review 09:00 #App @coding',
          ),
          projectsProvider.overrideWith(
            (ref) => Stream.value(const <ProjectItem>[]),
          ),
          labelsProvider.overrideWith(
            (ref) => Stream.value(const <LabelItem>[]),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuickAddBar()),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration!.hintText,
      'Plan the next review 09:00 #App @coding',
    );
    expect(field.controller, isA<QuickAddTextController>());
  });

  testWidgets('quick-add controller highlights only recognized commands', (
    tester,
  ) async {
    final controller = QuickAddTextController(
      text: 'Plan @work #family 7 PM 8 march !!3 invalid',
      now: () => DateTime(2026, 7, 10, 12),
    );
    addTearDown(controller.dispose);
    late TextSpan span;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(color: Colors.black),
              withComposing: true,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final leaves = span.children!.cast<TextSpan>();
    final highlighted = leaves
        .where((child) => child.style?.fontWeight == FontWeight.w600)
        .map((child) => child.text)
        .toList();
    expect(highlighted, ['@work', '#family', '7 PM', '8 march', '!!3']);
    expect(leaves.last.text, ' invalid');
    expect(leaves.last.style?.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('quick-add highlighting preserves composing decoration', (
    tester,
  ) async {
    final controller = QuickAddTextController(text: 'Plan @work')
      ..value = const TextEditingValue(
        text: 'Plan @work',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 5, end: 10),
      );
    addTearDown(controller.dispose);
    late TextSpan span;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(),
              withComposing: true,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final work = span.children!.cast<TextSpan>().singleWhere(
      (child) => child.text == '@work',
    );
    expect(work.style?.fontWeight, FontWeight.w600);
    expect(work.style?.decoration, TextDecoration.underline);
  });
}
