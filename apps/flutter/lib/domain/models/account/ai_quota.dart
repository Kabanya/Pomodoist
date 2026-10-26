final class AiQuota {
  const AiQuota({
    required this.used,
    required this.limit,
    required this.resetsAt,
  });
  factory AiQuota.fromJson(Map<String, dynamic> json) {
    final used = json['used'], limit = json['limit'];
    final reset = DateTime.tryParse('${json['resetsAt']}');
    if (used is! int ||
        used < 0 ||
        limit is! int ||
        limit < 0 ||
        reset == null) {
      throw const FormatException('Invalid AI quota response');
    }
    return AiQuota(used: used, limit: limit, resetsAt: reset.toUtc());
  }
  final int used, limit;
  final DateTime resetsAt;
  int get remaining => (limit - used).clamp(0, limit);
}
