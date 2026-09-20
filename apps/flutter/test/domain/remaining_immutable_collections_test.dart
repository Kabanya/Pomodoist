import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/domain/models/billing/billing_store_models.dart';
import 'package:pomodoist/domain/models/planning/quick_add_parser.dart';
import 'package:pomodoist/domain/models/planning/task_decomposition.dart';
import 'package:pomodoist/domain/models/settings/task_preferences.dart';
import 'package:pomodoist/domain/models/tasks/csv_task_import.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/updates/update_contracts.dart';
import 'package:pomodoist/domain/models/updates/update_release.dart';
import 'package:pomodoist/domain/models/voice/voice_capture_state.dart';
import 'package:pomodoist/domain/models/voice/voice_quick_add_state.dart';

void main() {
  final listModels = <String, List<String> Function(List<String>)>{
    'create task': (items) =>
        CreateTaskInput(content: 'task', labelNames: items).labelNames,
    'update task': (items) => UpdateTaskPatch(labelNames: items).labelNames!,
    'parsed quick add': (items) =>
        ParsedQuickAdd(content: 'task', labels: items).labels,
    'CSV draft': (items) => draft(items).labelNames,
    'CSV preview projects': (items) => CsvTaskImportPreview(
      document: CsvTaskImportDocument([]),
      newProjects: items,
      newLabels: [],
      newKanbanStatuses: [],
    ).newProjects,
    'CSV preview labels': (items) => CsvTaskImportPreview(
      document: CsvTaskImportDocument([]),
      newProjects: [],
      newLabels: items,
      newKanbanStatuses: [],
    ).newLabels,
    'CSV preview statuses': (items) => CsvTaskImportPreview(
      document: CsvTaskImportDocument([]),
      newProjects: [],
      newLabels: [],
      newKanbanStatuses: items,
    ).newKanbanStatuses,
    'CSV result': (items) => CsvTaskImportResult(items).taskIds,
  };
  for (final entry in listModels.entries) {
    test(
      '${entry.key} owns its immutable list',
      () => checkList('original', entry.value),
    );
  }
  final setModels = <String, Set<String> Function(Set<String>)>{
    'delete undo': (items) =>
        DeletedTaskBatch(taskIds: items, undoUntil: DateTime.utc(2026)).taskIds,
    'update preferences': (items) =>
        SavedUpdatePreferences(seenTags: items).seenTags,
    'task preferences': (items) =>
        TaskPreferences(collapsedProjectIds: items).collapsedProjectIds,
    'task preferences copy': (items) => TaskPreferences()
        .copyWith(collapsedProjectIds: items)
        .collapsedProjectIds,
    'billing missing': (items) =>
        BillingState(missingProductIds: items).missingProductIds,
    'billing eligible': (items) => BillingState(
      eligibleIntroductoryProductIds: items,
    ).eligibleIntroductoryProductIds,
    'billing purchased': (items) =>
        BillingState(purchasedProductIds: items).purchasedProductIds,
    'billing active': (items) =>
        BillingState(activeStoreKitProductIds: items).activeStoreKitProductIds,
    'billing copy': (items) => BillingState()
        .copyWith(activeStoreKitProductIds: items)
        .activeStoreKitProductIds,
    'catalog returned': (items) => BillingCatalogSnapshot(
      products: {},
      returnedProductIds: items,
    ).returnedProductIds,
  };
  for (final entry in setModels.entries) {
    test('${entry.key} owns its immutable set', () {
      final source = {'original'};
      final snapshot = entry.value(source);
      source.clear();
      expect(snapshot, {'original'});
      expect(() => snapshot.clear(), throwsUnsupportedError);
      expect(() => snapshot.add('other'), throwsUnsupportedError);
    });
  }
  test('nullable task patch preserves absent labels', () {
    expect(UpdateTaskPatch().labelNames, isNull);
    expect(UpdateTaskPatch(labelNames: []).labelNames, isEmpty);
  });
  test('update version cannot change after parsing', () {
    final version = UpdateVersion.parse('1.2.3-rc.1');
    expect(() => version.numbers[0] = BigInt.from(9), throwsUnsupportedError);
    expect(() => version.prerelease.clear(), throwsUnsupportedError);
    expect(version.compareTo(UpdateVersion.parse('1.2.3')), lessThan(0));
  });
  test('billing models own immutable catalogs and nested offers', () {
    final product = BillingProduct(
      id: 'p',
      title: 'Pro',
      description: '',
      price: '1',
      rawPrice: 1,
      currencyCode: 'USD',
      currencySymbol: r'$',
      offers: [],
    );
    checkMap(
      product,
      (items) => BillingState(productDetailsById: items).productDetailsById,
    );
    checkMap(
      product,
      (items) =>
          BillingState().copyWith(productDetailsById: items).productDetailsById,
    );
    checkMap(
      product,
      (items) => BillingCatalogSnapshot(
        products: items,
        returnedProductIds: {},
      ).products,
    );
    checkMap(
      'price',
      (items) => StripeBillingCatalog(
        enabled: true,
        introEligible: false,
        launchOfferEligible: false,
        launchOfferEndsAt: null,
        prices: items,
      ).prices,
    );
    checkMap('offer', (items) => BillingReturnOffers(offerIds: items).offerIds);
    final offer = BillingOffer(
      id: null,
      type: BillingOfferType.introductory,
      paymentMode: BillingOfferPaymentMode.freeTrial,
      price: 0,
      periodUnit: BillingOfferPeriodUnit.month,
      periodValue: 1,
      periodCount: 1,
    );
    checkList(
      offer,
      (items) => BillingProduct(
        id: 'p',
        title: 'Pro',
        description: '',
        price: '1',
        rawPrice: 1,
        currencyCode: 'USD',
        currencySymbol: r'$',
        offers: items,
      ).offers,
    );
  });
  test('CSV and parser snapshots own their nested collections', () {
    checkList(draft([]), (items) => CsvTaskImportDocument(items).tasks);
    checkList(
      const CsvTaskImportIssue(row: 1, message: 'bad', code: 'bad'),
      (items) => CsvTaskImportException(items).issues,
    );
    checkList(
      const QuickAddTokenMatch(kind: QuickAddTokenKind.label, start: 0, end: 2),
      (items) => QuickAddAnalysis(
        parsed: ParsedQuickAdd(content: 'task'),
        matches: items,
      ).matches,
    );
  });
  test('voice state protects drafts regardless of its producer', () {
    checkList(
      DecomposedTaskDraft(quickAdd: 'task'),
      (items) => VoiceQuickAddState(
        status: VoiceCaptureStatus.idle,
        transcript: '',
        error: null,
        recognitionErrorMessage: '',
        voiceErrorCode: null,
        restoring: false,
        accessBusy: false,
        analyzing: false,
        saving: false,
        stopping: false,
        captureActive: false,
        smartMode: false,
        amplitudeLevel: 0,
        recordingSecondsRemaining: 0,
        isCapturing: false,
        isTranscribing: false,
        canStart: true,
        motionActive: false,
        canUseCloudFallback: false,
        needsPermissionRequest: false,
        settingsDestination: null,
        canRetryTranscription: false,
        cloudMode: false,
        drafts: items,
        draftRevision: 0,
      ).drafts,
    );
  });
}

CsvTaskImportDraft draft(List<String> labels) => CsvTaskImportDraft(
  rowNumber: 1,
  content: 'task',
  labelNames: labels,
  priority: 4,
  recurrenceInterval: 1,
);
void checkList<T>(T value, List<T> Function(List<T>) create) {
  final source = [value];
  final snapshot = create(source);
  source.clear();
  expect(snapshot, [value]);
  expect(() => snapshot[0] = value, throwsUnsupportedError);
  expect(() => snapshot.clear(), throwsUnsupportedError);
}

void checkMap<T>(T value, Map<String, T> Function(Map<String, T>) create) {
  final source = {'original': value};
  final snapshot = create(source);
  source.clear();
  expect(snapshot, {'original': value});
  expect(() => snapshot['other'] = value, throwsUnsupportedError);
  expect(() => snapshot.clear(), throwsUnsupportedError);
}
