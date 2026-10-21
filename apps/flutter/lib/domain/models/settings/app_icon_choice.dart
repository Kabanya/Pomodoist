enum AppIconChoice {
  pomo('icon-light-pomo'),
  classic('classic');

  const AppIconChoice(this.id);
  final String id;

  static AppIconChoice fromId(Object? value) =>
      value == classic.id ? classic : pomo;
}
