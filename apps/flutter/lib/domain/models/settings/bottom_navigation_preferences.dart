import 'dart:convert';

const bottomNavigationPreferenceKey = 'navigation.bottom';
const bottomNavigationMaxDestinations = 5;

enum BottomNavigationStyle { soft, labels }

enum BottomNavigationDestination {
  today('/today'),
  upcoming('/upcoming'),
  focus('/focus'),
  inbox('/inbox'),
  projects('/projects'),
  browse('/browse'),
  search('/search'),
  calendar('/calendar'),
  timeline('/timeline'),
  kanban('/kanban'),
  priorityMatrix('/priority-matrix'),
  reports('/reports'),
  settings('/settings');

  const BottomNavigationDestination(this.path);
  final String path;

  bool matches(String location) {
    final current = Uri.tryParse(location)?.path;
    return current != null &&
        (current == path ||
            current.startsWith('$path/') ||
            (this == projects && current.startsWith('/project/')));
  }
}

class BottomNavigationPreferences {
  BottomNavigationPreferences({
    this.style = BottomNavigationStyle.soft,
    Iterable<BottomNavigationDestination> destinations = defaultDestinations,
  }) : destinations = List.unmodifiable(
         destinations.toSet().take(bottomNavigationMaxDestinations),
       );

  static const defaultDestinations = [
    BottomNavigationDestination.today,
    BottomNavigationDestination.upcoming,
    BottomNavigationDestination.focus,
    BottomNavigationDestination.inbox,
    BottomNavigationDestination.projects,
  ];

  final BottomNavigationStyle style;
  final List<BottomNavigationDestination> destinations;

  BottomNavigationPreferences copyWith({
    BottomNavigationStyle? style,
    Iterable<BottomNavigationDestination>? destinations,
  }) => BottomNavigationPreferences(
    style: style ?? this.style,
    destinations: destinations ?? this.destinations,
  );

  BottomNavigationPreferences add(BottomNavigationDestination destination) =>
      copyWith(destinations: [...destinations, destination]);

  BottomNavigationPreferences remove(BottomNavigationDestination destination) =>
      copyWith(
        destinations: destinations.where((value) => value != destination),
      );

  BottomNavigationPreferences move(int from, int to) {
    if (from < 0 ||
        from >= destinations.length ||
        to < 0 ||
        to >= destinations.length) {
      return this;
    }
    final next = [...destinations];
    next.insert(to, next.removeAt(from));
    return copyWith(destinations: next);
  }

  BottomNavigationDestination? selectedFor(String location) =>
      destinations.where((value) => value.matches(location)).firstOrNull;

  String encode() => jsonEncode({
    'style': style.name,
    'destinations': destinations.map((value) => value.name).toList(),
  });

  static BottomNavigationPreferences decode(Object? value) {
    if (value is! String) return BottomNavigationPreferences();
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return BottomNavigationPreferences();
      final stored = json['destinations'];
      return BottomNavigationPreferences(
        style:
            BottomNavigationStyle.values
                .where((style) => style.name == json['style'])
                .firstOrNull ??
            BottomNavigationStyle.soft,
        destinations: stored is List
            ? stored.expand(
                (name) => BottomNavigationDestination.values.where(
                  (d) => d.name == name,
                ),
              )
            : defaultDestinations,
      );
    } on FormatException {
      return BottomNavigationPreferences();
    }
  }
}
