import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screen_retriever/screen_retriever.dart';

/// macOS title-bar inset. Without it parent-relative dialogs sit too low.
const int _macTopRectInset = 38;

@internal
Future<Offset> calcWindowPosition(Size windowSize, Alignment alignment) async {
  final currentDisplay = await _getCurrentDisplay();
  final num visibleWidth = currentDisplay.visibleSize?.width ?? currentDisplay.size.width;
  final num visibleHeight = currentDisplay.visibleSize?.height ?? currentDisplay.size.height;
  final num visibleStartX = currentDisplay.visiblePosition?.dx ?? 0;
  final num visibleStartY = currentDisplay.visiblePosition?.dy ?? 0;

  final Offset position = calcPosition(
    alignment: alignment,
    windowSize: windowSize,
    visibleWidth: visibleWidth,
    visibleHeight: visibleHeight,
    visibleStartX: visibleStartX,
    visibleStartY: visibleStartY,
  );

  return position;
}

int get _platformTopRectAddSize {
  if (Platform.isMacOS) {
    return _macTopRectInset;
  }
  return 0;
}

@internal
Future<Offset> calcWindowPositionByParent(
  Alignment alignment, {
  required Size windowSize,
  required Rect parentBounds,
}) async {
  const defaultMaxSidebarLinuxSize = 150;
  const defaultMaxTopbarLinuxSize = 100;
  final currentDisplay = await _getCurrentDisplay();
  Offset currDisplayLinuxCorrectPos = Offset.zero;
  if (Platform.isLinux) {
    final dy = currentDisplay.visiblePosition?.dy ?? 0;
    final dx = currentDisplay.visiblePosition?.dx ?? 0;
    if (dy > 1 && dy < defaultMaxTopbarLinuxSize || dx > 1 && dx < defaultMaxSidebarLinuxSize) {
      currDisplayLinuxCorrectPos = Offset(dx, dy);
    }
  }

  final num visibleWidth = parentBounds.size.width;
  final num visibleHeight = parentBounds.size.height;
  final num visibleStartX =
      (currentDisplay.visiblePosition?.dx ?? 0) + parentBounds.left - currDisplayLinuxCorrectPos.dx;
  final num visibleStartY =
      (currentDisplay.visiblePosition?.dy ?? 0) +
      parentBounds.top -
      _platformTopRectAddSize -
      currDisplayLinuxCorrectPos.dy;

  final Offset position = calcPosition(
    alignment: alignment,
    windowSize: windowSize,
    visibleWidth: visibleWidth,
    visibleHeight: visibleHeight,
    visibleStartX: visibleStartX,
    visibleStartY: visibleStartY,
  );

  return position;
}

@internal
@visibleForTesting
Offset calcPosition({
  required Alignment alignment,
  required Size windowSize,
  required num visibleWidth,
  required num visibleHeight,
  required num visibleStartX,
  required num visibleStartY,
}) {
  Offset forDefault() {
    final left = (visibleWidth - windowSize.width) / 2 + alignment.x * ((visibleWidth - windowSize.width) / 2);
    final top = (visibleHeight - windowSize.height) / 2 + alignment.y * ((visibleHeight - windowSize.height) / 2);
    return Offset(visibleStartX + left, visibleStartY + top);
  }

  final position = switch (alignment) {
    Alignment.topLeft => Offset(visibleStartX.toDouble(), visibleStartY.toDouble()),
    Alignment.topCenter => Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY.toDouble(),
    ),
    Alignment.topRight => Offset(visibleStartX + visibleWidth - windowSize.width, visibleStartY.toDouble()),
    Alignment.centerLeft => Offset(
      visibleStartX.toDouble(),
      visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
    ),
    Alignment.center => Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
    ),
    Alignment.centerRight => Offset(
      visibleStartX + visibleWidth - windowSize.width,
      visibleStartY + (visibleHeight / 2) - (windowSize.height / 2),
    ),
    Alignment.bottomLeft => Offset(visibleStartX.toDouble(), visibleStartY + visibleHeight - windowSize.height),
    Alignment.bottomCenter => Offset(
      visibleStartX + (visibleWidth / 2) - (windowSize.width / 2),
      visibleStartY + visibleHeight - windowSize.height,
    ),
    Alignment.bottomRight => Offset(
      visibleStartX + visibleWidth - windowSize.width,
      visibleStartY + visibleHeight - windowSize.height,
    ),
    _ => forDefault(),
  };

  return position;
}

Future<Display> _getCurrentDisplay() async {
  final screenRetriever = ScreenRetriever.instance;
  final Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final List<Display> allDisplays = await screenRetriever.getAllDisplays();
  final Offset cursorScreenPoint = await screenRetriever.getCursorScreenPoint();

  return allDisplays.firstWhere(
    (display) => Rect.fromLTWH(
      display.visiblePosition?.dx ?? 0,
      display.visiblePosition?.dy ?? 0,
      display.size.width,
      display.size.height,
    ).contains(cursorScreenPoint),
    orElse: () => primaryDisplay,
  );
}
