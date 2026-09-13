enum UpdateChannel { stable, rc }
enum UpdateOS { windows, linux }
enum UpdateArch { x64, arm64 }

class UpdateTarget {
  const UpdateTarget(this.os, this.arch);
  final UpdateOS os;
  final UpdateArch arch;

  List<String> get artifactNames => switch ((os, arch)) {
    (UpdateOS.windows, UpdateArch.x64) => const [
      'Pomodoist-Setup-x64.exe', 'Pomodoist-Setup.exe',
    ],
    (UpdateOS.windows, UpdateArch.arm64) => const ['Pomodoist-Setup-arm64.exe'],
    (UpdateOS.linux, UpdateArch.x64) => const ['Pomodoist-x86_64.AppImage'],
    (UpdateOS.linux, UpdateArch.arm64) => const ['Pomodoist-aarch64.AppImage'],
  };
}

/// SemVer precedence deliberately ignores build metadata, including Flutter's
/// build number. Numeric identifiers use BigInt to avoid overflow/lexical order.
class UpdateVersion implements Comparable<UpdateVersion> {
  UpdateVersion._(this.text, this.numbers, this.prerelease);
  final String text;
  final List<BigInt> numbers;
  final List<String> prerelease;
  bool get isStable => prerelease.isEmpty;
  bool get isRc => prerelease.length == 2 && prerelease.first == 'rc' &&
      RegExp(r'^\d+$').hasMatch(prerelease.last);

  static UpdateVersion parse(String text) => tryParse(text) ??
      (throw FormatException('Invalid semantic version: $text'));

  static UpdateVersion? tryParse(String text) {
    if (text.length > 256) return null;
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(text);
    if (match == null) return null;
    final pre = match.group(4)?.split('.') ?? const <String>[];
    for (final part in pre) {
      if (RegExp(r'^\d+$').hasMatch(part) && part.length > 1 && part.startsWith('0')) {
        return null;
      }
    }
    return UpdateVersion._(text.replaceFirst(RegExp(r'^v'), ''),
      [for (var i = 1; i <= 3; i++) BigInt.parse(match.group(i)!)], pre);
  }

  @override
  int compareTo(UpdateVersion other) {
    for (var i = 0; i < 3; i++) {
      final comparison = numbers[i].compareTo(other.numbers[i]);
      if (comparison != 0) return comparison;
    }
    if (isStable || other.isStable) {
      return isStable == other.isStable ? 0 : (isStable ? 1 : -1);
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final left = prerelease[i];
      final right = other.prerelease[i];
      final leftNumber = RegExp(r'^\d+$').hasMatch(left) ? BigInt.parse(left) : null;
      final rightNumber = RegExp(r'^\d+$').hasMatch(right) ? BigInt.parse(right) : null;
      final comparison = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftNumber != null ? -1
          : rightNumber != null ? 1 : left.compareTo(right);
      if (comparison != 0) return comparison;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, required this.size,
    this.sha256});
  final String name;
  final Uri url;
  final int size;
  final String? sha256;
}

class UpdateOffer {
  const UpdateOffer({required this.tag, required this.version, required this.notes,
    required this.asset, this.checksum});
  final String tag;
  final UpdateVersion version;
  final String notes;
  final UpdateAsset asset;
  final UpdateAsset? checksum;
  Uri get releaseUrl => Uri.https('github.com', '/Kabanya/Pomodoist/releases/tag/$tag');
}

bool isTrustedUpdateUrl(Uri uri, String tag, String name) {
  final parts = uri.pathSegments;
  return uri.scheme == 'https' && uri.host == 'github.com' && uri.port == 443 &&
      uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment &&
      parts.length == 6 && parts[0] == 'Kabanya' && parts[1] == 'Pomodoist' &&
      parts[2] == 'releases' && parts[3] == 'download' &&
      parts[4] == tag && parts[5] == name;
}

UpdateAsset? _asset(Object? raw, String tag) {
  if (raw is! Map) return null;
  final name = raw['name'];
  final size = raw['size'];
  final url = raw['browser_download_url'];
  if (name is! String || size is! int || size <= 0 ||
      size > 512 * 1024 * 1024 || url is! String || raw['state'] != 'uploaded') {
    return null;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !isTrustedUpdateUrl(uri, tag, name)) return null;
  final digest = raw['digest'];
  final hash = digest is String && RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
      ? digest.substring(7).toLowerCase() : null;
  return UpdateAsset(name: name, url: uri, size: size, sha256: hash);
}

UpdateOffer? selectUpdate(List<Object?> releases, {required UpdateVersion current,
  required UpdateTarget target, required UpdateChannel channel}) {
  UpdateOffer? best;
  for (final raw in releases) {
    if (raw is! Map || raw['draft'] != false || raw['tag_name'] is! String) continue;
    final tag = raw['tag_name'] as String;
    final version = UpdateVersion.tryParse(tag);
    if (version == null || version.compareTo(current) <= 0) continue;
    final stable = version.isStable && raw['prerelease'] == false;
    if (!stable && !(channel == UpdateChannel.rc && version.isRc)) continue;
    if (best != null && version.compareTo(best.version) <= 0) continue;
    final assetsRaw = raw['assets'];
    if (assetsRaw is! List) continue;
    final assets = assetsRaw.map((a) => _asset(a, tag)).whereType<UpdateAsset>().toList();
    for (final name in target.artifactNames) {
      final matches = assets.where((a) => a.name == name).toList();
      if (matches.length != 1) continue;
      final artifact = matches.single;
      final checksums = assets.where((a) => a.name == '$name.sha256' && a.size <= 4096).toList();
      final checksum = checksums.length == 1 ? checksums.single : null;
      if (artifact.sha256 == null && checksum == null) continue;
      final notes = raw['body'] is String ? raw['body'] as String : '';
      best = UpdateOffer(tag: tag, version: version,
        notes: notes.length > 8000 ? '${notes.substring(0, 8000)}…' : notes,
        asset: artifact, checksum: checksum);
      break;
    }
  }
  return best;
}

String parseUpdateChecksum(String text, String artifactName) {
  if (text.length > 4096) throw const FormatException('Checksum file is too large.');
  String? result;
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final match = RegExp(r'^([a-fA-F0-9]{64})[ \t]+\*?(.+)$').firstMatch(line.trim());
    if (match != null && match.group(2) == artifactName) {
      final hash = match.group(1)!.toLowerCase();
      if (result != null && result != hash) {
        throw const FormatException('Conflicting SHA-256 entries.');
      }
      result = hash;
    }
  }
  return result ?? (throw const FormatException('No SHA-256 for the exact update artifact.'));
}
