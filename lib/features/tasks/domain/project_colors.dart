import '../../../core/db/app_database.dart';
import 'task_models.dart';

const inboxProjectColorHex = '#6B7280';

const projectColorPalette = <String>[
  '#E44332',
  '#E8793E',
  '#C58A16',
  '#8A9A2D',
  '#36A269',
  '#2A9D8F',
  '#2F9CB3',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#B657C4',
  '#D45584',
  '#9B6B4F',
  '#64748B',
];

String effectiveProjectColor(ProjectItem project) {
  if (project.id == inboxProjectId) {
    return inboxProjectColorHex;
  }
  return normalizeProjectColor(project.color) ??
      projectColorPalette[_stableHash(project.id) % projectColorPalette.length];
}

String nextProjectColor(Iterable<ProjectItem> projects) {
  final counts = {for (final color in projectColorPalette) color: 0};
  for (final project in projects) {
    if (project.id == inboxProjectId || project.isDeleted) {
      continue;
    }
    final color = effectiveProjectColor(project);
    if (counts.containsKey(color)) {
      counts[color] = counts[color]! + 1;
    }
  }
  return projectColorPalette.reduce(
    (best, color) => counts[color]! < counts[best]! ? color : best,
  );
}

String? normalizeProjectColor(String? raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.trim().toUpperCase();
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(value) ? value : null;
}

bool isPaletteProjectColor(String? raw) {
  final normalized = normalizeProjectColor(raw);
  return normalized != null && projectColorPalette.contains(normalized);
}

int _stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash ^ codeUnit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}
