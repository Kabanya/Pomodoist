class GlobalQuickAddBinding {
  const GlobalQuickAddBinding({
    required this.keyCode,
    required this.keyLabel,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  final int keyCode;
  final String keyLabel;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;

  factory GlobalQuickAddBinding.defaultFor({required bool isMacOS}) {
    if (isMacOS) {
      return macOSDefaultGlobalShortcut;
    }
    return const GlobalQuickAddBinding(
      keyCode: 32,
      keyLabel: 'Space',
      control: true,
      alt: true,
    );
  }

  String get displaySignature =>
      '${keyLabel.trim().toUpperCase()}:${meta ? 1 : 0}:${control ? 1 : 0}:${alt ? 1 : 0}:${shift ? 1 : 0}';
}

typedef MacOSGlobalShortcut = GlobalQuickAddBinding;

const macOSDefaultGlobalShortcut = GlobalQuickAddBinding(
  keyCode: 49,
  keyLabel: 'Space',
  alt: true,
);

class GlobalQuickAddState {
  const GlobalQuickAddState({
    required this.enabled,
    required this.binding,
    this.registrationError,
  });

  final bool enabled;
  final GlobalQuickAddBinding binding;
  final Object? registrationError;

  GlobalQuickAddState copyWith({
    bool? enabled,
    GlobalQuickAddBinding? binding,
    Object? registrationError,
    bool clearRegistrationError = false,
  }) {
    return GlobalQuickAddState(
      enabled: enabled ?? this.enabled,
      binding: binding ?? this.binding,
      registrationError: clearRegistrationError
          ? null
          : registrationError ?? this.registrationError,
    );
  }
}
