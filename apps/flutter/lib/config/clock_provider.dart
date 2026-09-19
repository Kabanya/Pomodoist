import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/utils/clock.dart';

final clockProvider = Provider<Clock>((ref) => const SystemClock());
