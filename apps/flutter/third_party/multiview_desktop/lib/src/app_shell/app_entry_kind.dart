/// Which root widget type is mirrored on secondary and dialog views.
///
/// The library detects the entry widget in the main `homeBuilder` tree
/// (`MaterialApp`, `CupertinoApp`, or `WidgetsApp`) and builds the same kind
/// of shell around content passed to `openWindow` and `openDialog`.
enum AppEntryKind {
  /// Shell based on `MaterialApp` (theme, locale, shortcuts, and so on).
  material,

  /// Shell based on `CupertinoApp`.
  cupertino,

  /// Shell based on `WidgetsApp`.
  widgets,
}
