const distractionCategories = [
  'social',
  'messaging',
  'video',
  'music',
  'games',
  'news',
  'shopping',
  'education',
  'development',
  'productivity',
  'other',
  'unclassified',
];

String? normalizeDomain(String value) {
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (host == null ||
      !host.contains('.') ||
      host.length > 253 ||
      host.contains(':') ||
      RegExp(r'^[\d.]+$').hasMatch(host) ||
      !RegExp(r'^[a-z0-9.-]+$').hasMatch(host) ||
      host
          .split('.')
          .any((s) => s.isEmpty || s.startsWith('-') || s.endsWith('-')) ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.localhost')) {
    return null;
  }
  return host;
}

final class ResourceAssignment {
  ResourceAssignment.fromJson(Map<String, dynamic> value)
    : json = Map.unmodifiable(value) {
    if (!['domain', 'app'].contains(kind) ||
        id.isEmpty ||
        !distractionCategories.contains(category) ||
        !['manual', 'automatic'].contains(source)) {
      throw const FormatException('Invalid resource');
    }
    if (kind == 'domain' && normalizeDomain(id) != id) {
      throw const FormatException('Invalid domain');
    }
    if (kind == 'app' &&
        (!RegExp(r'^(macos|windows|linux):[^/\\]+$').hasMatch(id))) {
      throw const FormatException('Invalid application identity');
    }
  }
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get kind => json['kind'] as String;
  String get name => json['name'] as String? ?? id;
  String get category => json['category'] as String? ?? 'unclassified';
  String get source => json['source'] as String? ?? 'manual';
  bool get isDeleted => json['isDeleted'] == true;
}

ResourceAssignment mergeAssignment(
  ResourceAssignment? previous,
  ResourceAssignment next,
) => previous?.source == 'manual' && previous?.category != 'unclassified' && next.source == 'automatic'
    ? previous!
    : next;

final class DistractionProfile {
  DistractionProfile.fromJson(Map<String, dynamic> value)
    : json = Map.unmodifiable(value) {
    if (id.isEmpty || name.trim().isEmpty) {
      throw const FormatException('Invalid profile');
    }
  }
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get name => json['name'] as String;
  List<String> get blockedCategories =>
      List<String>.from(json['blockedCategories'] as List? ?? const []);
  List<Map<String, dynamic>> get overrides =>
      (json['overrides'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  bool get blockOnPause => json['blockOnPause'] != false;
  bool get blockOnShortBreak => json['blockOnShortBreak'] == true;
  bool get blockOnLongBreak => json['blockOnLongBreak'] == true;
  bool get isDeleted => json['isDeleted'] == true;
  bool applies(String phase, String status, bool strict) {
    if (!['running', 'paused'].contains(status)) return false;
    if (status == 'paused') return strict || blockOnPause;
    return switch (phase) {
      'work' => true,
      'shortBreak' => blockOnShortBreak,
      'longBreak' => blockOnLongBreak,
      _ => false,
    };
  }

  bool blocks(String kind, String id, String category) {
    Map<String, dynamic>? winner;
    for (final rule in overrides) {
      if (rule['kind'] != kind || !['allow', 'block'].contains(rule['action'])) {
        continue;
      }
      final target = rule['id'] as String;
      if (id == target || (kind == 'domain' && id.endsWith('.$target'))) {
        if (winner == null || target.length > (winner['id'] as String).length) {
          winner = rule;
        }
      }
    }
    return winner != null
        ? winner['action'] == 'block'
        : category != 'unclassified' && blockedCategories.contains(category);
  }
}
