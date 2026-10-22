import 'package:pomodoist/data/services/platform/pomo_follow_transport.dart';
import 'package:pomodoist/data/services/platform/pomo_follow_transport_stub.dart'
    if (dart.library.io) 'package:pomodoist/data/services/platform/pomo_follow_transport_io.dart'
    as platform;

PomoFollowTransport createPomoFollowTransport() => platform.createTransport();
