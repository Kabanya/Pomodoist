typedef SyncQueueStatus = ({
  int pending,
  int rejected,
  int repair,
  bool recovering,
});

enum SyncRestartPhase { idle, running, complete, pending, failed }
