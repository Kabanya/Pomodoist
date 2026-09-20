import 'dart:math';

const quickAddHintHistoryLimit = 10;
const quickAddHintMaxLength = 120;
const _quickAddHintMaxSavedHints = 5;

class QuickAddHintException implements Exception {
  const QuickAddHintException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? normalizeQuickAddHint(String value) {
  final hint = value.trim();
  if (hint.isEmpty ||
      hint.length > quickAddHintMaxLength ||
      hint.contains(RegExp(r'[\r\n]'))) {
    return null;
  }
  final tokens = hint.split(RegExp(r'\s+'));
  if (tokens.where(_isQuickAddProjectToken).length != 1 ||
      tokens.where(_isQuickAddLabelToken).length != 1 ||
      tokens.where(_isQuickAddTimeToken).length != 1) {
    return null;
  }
  return hint;
}

bool _isQuickAddProjectToken(String token) =>
    RegExp(r'^#[^\s#@]+$').hasMatch(token);

bool _isQuickAddLabelToken(String token) =>
    RegExp(r'^@[^\s#@]+$').hasMatch(token);

bool _isQuickAddTimeToken(String token) =>
    RegExp(r'^(?:[01]?\d|2[0-3]):[0-5]\d$').hasMatch(token);

class QuickAddHint {
  const QuickAddHint({required this.text, required this.locale});

  final String text;
  final String locale;

  Map<String, String> toJson() => {'text': text, 'locale': locale};
}

List<QuickAddHint> retainRecentQuickAddHints(Iterable<QuickAddHint> hints) {
  final items = hints.toList(growable: false);
  final start = items.length > _quickAddHintMaxSavedHints
      ? items.length - _quickAddHintMaxSavedHints
      : 0;
  return List.unmodifiable(items.sublist(start));
}

String? selectRandomQuickAddHintForLocale(
  Iterable<QuickAddHint> hints,
  String locale, {
  int Function(int upperBound)? randomIndex,
}) {
  final matching = hints.where((hint) => hint.locale == locale).toList();
  if (matching.isEmpty) {
    return null;
  }
  final index = (randomIndex ?? _randomQuickAddHintIndex)(matching.length);
  return matching[index].text;
}

int _randomQuickAddHintIndex(int upperBound) => Random().nextInt(upperBound);

class QuickAddHintState {
  QuickAddHintState({
    required this.createdTaskCount,
    required this.nextRefreshAt,
    required this.retryPending,
    this.starterConsumed = false,
    List<QuickAddHint> recentHints = const [],
  }) : recentHints = List.unmodifiable(recentHints);

  final int createdTaskCount;
  final int nextRefreshAt;
  final bool retryPending;
  final bool starterConsumed;
  final List<QuickAddHint> recentHints;

  String? hintForLocale(
    String locale, {
    int Function(int upperBound)? randomIndex,
  }) {
    return selectRandomQuickAddHintForLocale(
      recentHints,
      locale,
      randomIndex: randomIndex,
    );
  }

  QuickAddHintState copyWith({
    int? createdTaskCount,
    int? nextRefreshAt,
    bool? retryPending,
    bool? starterConsumed,
    List<QuickAddHint>? recentHints,
  }) {
    return QuickAddHintState(
      createdTaskCount: createdTaskCount ?? this.createdTaskCount,
      nextRefreshAt: nextRefreshAt ?? this.nextRefreshAt,
      retryPending: retryPending ?? this.retryPending,
      starterConsumed: starterConsumed ?? this.starterConsumed,
      recentHints: recentHints ?? this.recentHints,
    );
  }
}
