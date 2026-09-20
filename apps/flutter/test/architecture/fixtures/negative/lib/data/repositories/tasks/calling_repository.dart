import 'other_repository.dart';

class CallingRepository {
  CallingRepository(this.other);
  final OtherRepository other;
  void run() => other.run();
}
