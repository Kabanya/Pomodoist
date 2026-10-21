import 'package:flutter/material.dart';

class MappedValueNotifier<S, T> extends ValueNotifier<T> {
  MappedValueNotifier({required ValueNotifier<S> source, required T Function(S value) transform})
      : _source = source,
        _transform = transform,
        super(transform(source.value)) {
    _source.addListener(_sync);
  }

  final ValueNotifier<S> _source;
  final T Function(S value) _transform;

  void _sync() => value = _transform(_source.value);

  @override
  void dispose() {
    _source.removeListener(_sync);
    super.dispose();
  }
}
