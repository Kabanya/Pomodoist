class NormalizedQuickAddDateTimeInput {
  const NormalizedQuickAddDateTimeInput({
    required this.text,
    required this.hasInvalidExplicitDate,
  });

  final String text;
  final bool hasInvalidExplicitDate;
}

class QuickAddDateTimeNormalizer {
  QuickAddDateTimeNormalizer(this.today);

  final DateTime today;
  bool _hasInvalidExplicitDate = false;

  static const _monthNumbers = <String, int>{
    'january': 1,
    'jan': 1,
    'январь': 1,
    'января': 1,
    'januar': 1,
    'enero': 1,
    'janvier': 1,
    'يناير': 1,
    'february': 2,
    'feb': 2,
    'февраль': 2,
    'февраля': 2,
    'februar': 2,
    'febrero': 2,
    'février': 2,
    'fevrier': 2,
    'فبراير': 2,
    'march': 3,
    'mar': 3,
    'март': 3,
    'марта': 3,
    'märz': 3,
    'maerz': 3,
    'marzo': 3,
    'mars': 3,
    'مارس': 3,
    'april': 4,
    'apr': 4,
    'апрель': 4,
    'апреля': 4,
    'abril': 4,
    'avril': 4,
    'أبريل': 4,
    'ابريل': 4,
    'may': 5,
    'май': 5,
    'мая': 5,
    'mai': 5,
    'mayo': 5,
    'مايو': 5,
    'june': 6,
    'jun': 6,
    'июнь': 6,
    'июня': 6,
    'juni': 6,
    'junio': 6,
    'juin': 6,
    'يونيو': 6,
    'july': 7,
    'jul': 7,
    'июль': 7,
    'июля': 7,
    'juli': 7,
    'julio': 7,
    'juillet': 7,
    'يوليو': 7,
    'august': 8,
    'aug': 8,
    'август': 8,
    'августа': 8,
    'agosto': 8,
    'août': 8,
    'aout': 8,
    'أغسطس': 8,
    'اغسطس': 8,
    'september': 9,
    'sept': 9,
    'sep': 9,
    'сентябрь': 9,
    'сентября': 9,
    'septiembre': 9,
    'septembre': 9,
    'سبتمبر': 9,
    'october': 10,
    'oct': 10,
    'октябрь': 10,
    'октября': 10,
    'oktober': 10,
    'octubre': 10,
    'octobre': 10,
    'أكتوبر': 10,
    'اكتوبر': 10,
    'november': 11,
    'nov': 11,
    'ноябрь': 11,
    'ноября': 11,
    'noviembre': 11,
    'novembre': 11,
    'نوفمبر': 11,
    'december': 12,
    'dec': 12,
    'декабрь': 12,
    'декабря': 12,
    'dezember': 12,
    'diciembre': 12,
    'décembre': 12,
    'decembre': 12,
    'ديسمبر': 12,
  };

  static final _monthPattern = _monthNumbers.keys.map(RegExp.escape).toList()
    ..sort((left, right) => right.length.compareTo(left.length));

  NormalizedQuickAddDateTimeInput normalize(String input) {
    _hasInvalidExplicitDate = false;
    var value = _normalizeDigits(
      input,
    ).replaceAll('\u00a0', ' ').replaceAll('\u202f', ' ');
    value = _replaceSharedMeridiemRanges(value);
    value = _replaceChineseDates(value);
    value = _replaceNamedDates(value);
    value = _replaceNumericDates(value);
    value = _replaceSpanishTimes(value);
    value = _replaceEnglishTimes(value);
    value = _replaceRussianTimes(value);
    value = _replaceGermanTimes(value);
    value = _replaceFrenchTimes(value);
    value = _replaceArabicTimes(value);
    value = _replaceChineseTimes(value);
    value = _collapseTimeRanges(value);
    return NormalizedQuickAddDateTimeInput(
      text: value.replaceAll(RegExp(r'\s+'), ' ').trim(),
      hasInvalidExplicitDate: _hasInvalidExplicitDate,
    );
  }

  String _normalizeDigits(String value) {
    const digits = <String, String>{
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
      '０': '0',
      '１': '1',
      '２': '2',
      '３': '3',
      '４': '4',
      '５': '5',
      '６': '6',
      '７': '7',
      '８': '8',
      '９': '9',
    };
    for (final entry in digits.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    return value;
  }

  String _replaceSharedMeridiemRanges(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*[-–]\s*'
      r'(\d{1,2})(?::(\d{2}))?\s*'
      r'(a\.?\s*m\.?|p\.?\s*m\.?)\s*(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) {
      final isPm = match.group(6)!.toLowerCase().startsWith('p');
      final startHour = _hourForMeridiem(int.parse(match.group(2)!), isPm);
      final endHour = _hourForMeridiem(int.parse(match.group(4)!), isPm);
      final startMinute = match.group(3) == null
          ? 0
          : int.parse(match.group(3)!);
      final endMinute = match.group(5) == null ? 0 : int.parse(match.group(5)!);
      if (startHour == null ||
          endHour == null ||
          startMinute > 59 ||
          endMinute > 59) {
        return match.group(0)!;
      }
      return '${match.group(1)}'
          '${_timeToken(startHour, startMinute)}-'
          '${_timeToken(endHour, endMinute)}';
    },
  );

  String _replaceChineseDates(String value) => value.replaceAllMapped(
    RegExp(r'(^|\s)(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日?'),
    (match) => _dateReplacement(
      match,
      day: int.parse(match.group(4)!),
      month: int.parse(match.group(3)!),
      year: match.group(2) == null ? null : int.parse(match.group(2)!),
    ),
  );

  String _replaceNamedDates(String value) {
    final months = _monthPattern.join('|');
    value = value.replaceAllMapped(
      RegExp(
        '(^|\\s)((?:on|le|am|el|на)\\s+)?'
        '(\\d{1,2})(?:er|e|ème)?\\.?\\s+(?:de\\s+)?'
        '($months)(?:\\s+de)?(?:\\s*,?\\s*(\\d{4}))?'
        '(?=\\s|\$|[,.;!؟،])',
        caseSensitive: false,
      ),
      (match) => _dateReplacement(
        match,
        day: int.parse(match.group(3)!),
        month: _monthNumbers[match.group(4)!.toLowerCase()]!,
        year: match.group(5) == null ? null : int.parse(match.group(5)!),
        prefix: match.group(1),
      ),
    );
    return value.replaceAllMapped(
      RegExp(
        '(^|\\s)($months)\\s+(\\d{1,2})(?:st|nd|rd|th)?'
        '(?:\\s*,?\\s*(\\d{4}))?(?=\\s|\$|[,.;!؟،])',
        caseSensitive: false,
      ),
      (match) => _dateReplacement(
        match,
        day: int.parse(match.group(3)!),
        month: _monthNumbers[match.group(2)!.toLowerCase()]!,
        year: match.group(4) == null ? null : int.parse(match.group(4)!),
      ),
    );
  }

  String _replaceNumericDates(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)((?:on|le|am|el|на)\s+)?(\d{1,2})([./-])(\d{1,2})'
      r'(?:[./-](\d{4}))?(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) {
      final day = int.parse(match.group(3)!);
      final month = int.parse(match.group(5)!);
      final year = match.group(6) == null ? null : int.parse(match.group(6)!);
      final isAmbiguousHyphen =
          match.group(4) == '-' &&
          year == null &&
          match.group(2) == null &&
          day <= 12 &&
          month <= 12;
      if (isAmbiguousHyphen) {
        return match.group(0)!;
      }
      return _dateReplacement(
        match,
        day: day,
        month: month,
        year: year,
        prefix: match.group(1),
      );
    },
  );

  String _replaceSpanishTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:(?:a\s+las?|a\s+la)\s+)?(\d{1,2})(?::(\d{2}))?\s*'
      r'(a\.?\s*m\.?|p\.?\s*m\.?|de\s+la\s+mañana|'
      r'de\s+la\s+tarde|de\s+la\s+noche)(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) {
      final period = match.group(4)!.toLowerCase();
      final isMeridiem = period.startsWith('a') || period.startsWith('p');
      if (isMeridiem &&
          !RegExp(
            r'a\s+las?',
            caseSensitive: false,
          ).hasMatch(match.group(0)!)) {
        return match.group(0)!;
      }
      final hour = period.startsWith('p')
          ? _hourForMeridiem(int.parse(match.group(2)!), true)
          : period.startsWith('a')
          ? _hourForMeridiem(int.parse(match.group(2)!), false)
          : _hourForDayPeriod(int.parse(match.group(2)!), period);
      return _timeReplacement(match, hour: hour, minuteGroup: 3);
    },
  );

  String _replaceEnglishTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*'
      r'(a\.?\s*m\.?|p\.?\s*m\.?)\s*(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) => _timeReplacement(
      match,
      hour: _hourForMeridiem(
        int.parse(match.group(2)!),
        match.group(4)!.toLowerCase().startsWith('p'),
      ),
      minuteGroup: 3,
    ),
  );

  String _replaceRussianTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:в\s+)?(\d{1,2})(?::(\d{2}))?\s*'
      r'(утра|дня|вечера|ночи)(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) => _timeReplacement(
      match,
      hour: _hourForDayPeriod(
        int.parse(match.group(2)!),
        match.group(4)!.toLowerCase(),
      ),
      minuteGroup: 3,
    ),
  );

  String _replaceGermanTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:um\s+)?(\d{1,2})(?::(\d{2}))?\s*Uhr'
      r'(?:\s+(morgens|vormittags|nachmittags|abends|nachts))?'
      r'(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) => _timeReplacement(
      match,
      hour: _hourForDayPeriod(
        int.parse(match.group(2)!),
        match.group(4)?.toLowerCase(),
      ),
      minuteGroup: 3,
    ),
  );

  String _replaceFrenchTimes(String value) => value.replaceAllMapped(
    RegExp(
      r"(^|\s)(?:à\s+)?(\d{1,2})\s*h\s*(\d{2})?"
      r"(?:\s+(du\s+matin|de\s+l['’]après-midi|du\s+soir|de\s+nuit))?"
      r'(?=$|[\s,.;!؟،])',
      caseSensitive: false,
    ),
    (match) {
      if (match.group(3) == null &&
          match.group(4) == null &&
          !match.group(0)!.contains('à')) {
        return match.group(0)!;
      }
      return _timeReplacement(
        match,
        hour: _hourForDayPeriod(
          int.parse(match.group(2)!),
          match.group(4)?.toLowerCase(),
        ),
        minuteGroup: 3,
      );
    },
  );

  String _replaceArabicTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(?:الساعة\s*)?(\d{1,2})(?::(\d{2}))?\s*'
      r'(ص|صباحًا|صباحا|صباحاً|م|مساءً|مساءا)(?=$|[\s,.;!؟،])',
    ),
    (match) {
      final period = match.group(4)!;
      return _timeReplacement(
        match,
        hour: _hourForMeridiem(
          int.parse(match.group(2)!),
          period == 'م' || period.startsWith('مساء'),
        ),
        minuteGroup: 3,
      );
    },
  );

  String _replaceChineseTimes(String value) => value.replaceAllMapped(
    RegExp(
      r'(^|\s)(上午|早上|下午|晚上|中午)?\s*(\d{1,2})点'
      r'(?:(\d{1,2})分?|(半))?(?=$|[\s,.;!？、])',
    ),
    (match) {
      final minute = match.group(5) == '半'
          ? 30
          : match.group(4) == null
          ? 0
          : int.parse(match.group(4)!);
      return _timeReplacement(
        match,
        hour: _hourForDayPeriod(int.parse(match.group(3)!), match.group(2)),
        minute: minute,
      );
    },
  );

  String _dateReplacement(
    Match match, {
    required int day,
    required int month,
    required int? year,
    String? prefix,
  }) {
    final date = _dateToken(day: day, month: month, year: year);
    if (date == null) {
      _hasInvalidExplicitDate = true;
      return match.group(0)!;
    }
    return '${prefix ?? match.group(1)}$date';
  }

  String _timeReplacement(
    Match match, {
    required int? hour,
    int? minuteGroup,
    int? minute,
  }) {
    final resolvedMinute =
        minute ??
        (minuteGroup == null || match.group(minuteGroup) == null
            ? 0
            : int.parse(match.group(minuteGroup)!));
    if (hour == null || resolvedMinute > 59) {
      return match.group(0)!;
    }
    return '${match.group(1)}${_timeToken(hour, resolvedMinute)}';
  }

  int? _hourForMeridiem(int hour, bool isPm) {
    if (hour < 1 || hour > 12) {
      return null;
    }
    if (hour == 12) {
      return isPm ? 12 : 0;
    }
    return isPm ? hour + 12 : hour;
  }

  int? _hourForDayPeriod(int hour, String? period) {
    if (hour < 0 || hour > 23) {
      return null;
    }
    if (period == null || hour > 12) {
      return hour;
    }
    final normalized = period.toLowerCase();
    final isAfternoon =
        normalized.contains('дня') ||
        normalized.contains('вечера') ||
        normalized.contains('nachmittag') ||
        normalized.contains('abend') ||
        normalized.contains('tarde') ||
        normalized.contains('noche') ||
        normalized.contains('après-midi') ||
        normalized.contains('soir') ||
        normalized == '下午' ||
        normalized == '晚上' ||
        normalized == '中午';
    final isNight =
        normalized.contains('ночи') ||
        normalized.contains('nacht') ||
        normalized.contains('nuit');
    if (isNight && hour == 12) {
      return 0;
    }
    if (isAfternoon && hour < 12) {
      return hour + 12;
    }
    if (normalized == '上午' || normalized == '早上') {
      return hour == 12 ? 0 : hour;
    }
    return hour;
  }

  String _collapseTimeRanges(String value) => value.replaceAllMapped(
    RegExp(r'(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})'),
    (match) => '${match.group(1)}-${match.group(2)}',
  );

  String? _dateToken({
    required int day,
    required int month,
    required int? year,
  }) {
    if (year != null && year < 1) {
      return null;
    }
    var targetYear = year ?? today.year;
    var candidate = DateTime(targetYear, month, day);
    if (candidate.year != targetYear ||
        candidate.month != month ||
        candidate.day != day) {
      return null;
    }
    if (year == null && candidate.isBefore(today)) {
      targetYear++;
      candidate = DateTime(targetYear, month, day);
    }
    return '${candidate.year.toString().padLeft(4, '0')}-'
        '${candidate.month.toString().padLeft(2, '0')}-'
        '${candidate.day.toString().padLeft(2, '0')}';
  }

  String _timeToken(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}
