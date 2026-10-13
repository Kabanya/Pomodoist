enum FocusSoundSet {
  softKalimba('soft_kalimba', 'Soft kalimba'),
  neonPulse('neon_pulse', 'Neon pulse'),
  orbitBloom('orbit_bloom', 'Orbit bloom');

  const FocusSoundSet(this.storageValue, this.displayName);

  final String storageValue;
  final String displayName;

  static FocusSoundSet fromStorageValue(Object? value) => switch (value) {
    'neon_pulse' => neonPulse,
    'orbit_bloom' => orbitBloom,
    _ => softKalimba,
  };
}
