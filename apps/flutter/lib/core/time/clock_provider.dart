import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clock.dart';

final clockProvider = Provider<Clock>((ref) => const SystemClock());
