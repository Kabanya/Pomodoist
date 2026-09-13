import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'app_l10n.dart';
import 'captcha_security.dart';

@JS('turnstile.render')
external JSAny? _renderTurnstile(JSAny container, JSAny options);

@JS('turnstile.remove')
external void _removeTurnstile(JSAny widgetId);

@JS('turnstile')
external JSObject? get _turnstileGlobal;

Future<void>? _turnstileReady;

Future<void> _ensureTurnstileReady(Duration loadTimeout) {
  if (_turnstileGlobal != null) return Future.value();
  final existing = _turnstileReady;
  if (existing != null) return existing;
  final completer = Completer<void>();
  _turnstileReady = completer.future;
  final script = web.HTMLScriptElement()
    ..id = 'pomodoist-turnstile-script'
    ..src =
        'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
    ..async = true;
  late final CaptchaLoadTimeoutGuard timeoutGuard;

  void failLoad(String message) {
    if (completer.isCompleted) return;
    timeoutGuard.complete();
    _turnstileReady = null;
    script.remove();
    completer.completeError(StateError(message));
  }

  timeoutGuard = CaptchaLoadTimeoutGuard(
    timeout: loadTimeout,
    onTimeout: () => failLoad('Turnstile API load timed out'),
  );
  script.addEventListener(
    'load',
    ((web.Event _) {
      if (completer.isCompleted) return;
      if (_turnstileGlobal == null) {
        failLoad('Turnstile API loaded without a global');
      } else {
        timeoutGuard.complete();
        completer.complete();
      }
    }).toJS,
  );
  script.addEventListener(
    'error',
    ((web.Event _) {
      if (completer.isCompleted) return;
      failLoad('Turnstile API could not load');
    }).toJS,
  );
  web.document.head?.append(script);
  return completer.future;
}

class TurnstileWidget extends StatefulWidget {
  const TurnstileWidget({
    required this.siteKey,
    required this.controller,
    required this.onChanged,
    this.onSolved,
    this.loadTimeout = const Duration(seconds: 10),
    super.key,
  });

  final String siteKey;
  final CaptchaTokenController controller;
  final VoidCallback onChanged;
  final ValueChanged<String>? onSolved;
  final Duration loadTimeout;

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  late final int _generation = widget.controller.generation;
  JSAny? _widgetId;

  @override
  void dispose() {
    final widgetId = _widgetId;
    _widgetId = null;
    if (widgetId != null) _removeTurnstile(widgetId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.siteKey.isEmpty) return const SizedBox.shrink();
    final semanticLabel = context.l10n.captchaSecurityLabel;
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: SizedBox(
        height: 72,
        child: HtmlElementView.fromTagName(
          tagName: 'div',
          onElementCreated: (element) => _createWidget(element, semanticLabel),
        ),
      ),
    );
  }

  Future<void> _createWidget(Object element, String semanticLabel) async {
    final container = element as web.HTMLDivElement;
    container.setAttribute('aria-label', semanticLabel);
    try {
      await _ensureTurnstileReady(widget.loadTimeout);
    } on Object {
      if (mounted) {
        widget.controller.reportError(_generation);
        widget.onChanged();
      }
      return;
    }
    if (!mounted || widget.controller.generation != _generation) return;
    _widgetId = renderTurnstileSafely<JSAny>(
      controller: widget.controller,
      generation: _generation,
      onChanged: widget.onChanged,
      render: () {
        final options = <String, Object?>{
          'sitekey': widget.siteKey,
          'callback': ((String token) {
            if (!mounted ||
                !widget.controller.acceptSolved(token, _generation)) {
              return;
            }
            widget.onSolved?.call(token);
            widget.onChanged();
          }).toJS,
          'expired-callback': (() {
            if (!mounted) return;
            widget.controller.expire(_generation);
            widget.onChanged();
          }).toJS,
          'error-callback': (() {
            if (!mounted) return;
            widget.controller.reportError(_generation);
            widget.onChanged();
          }).toJS,
        }.jsify();
        return options == null ? null : _renderTurnstile(container, options);
      },
    );
  }
}
