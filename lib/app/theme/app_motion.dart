import 'package:flutter/widgets.dart';

abstract final class AppMotion {
  static const hover = Duration(milliseconds: 120);
  static const popup = Duration(milliseconds: 180);
  static const panel = Duration(milliseconds: 240);
  static const task = Duration(milliseconds: 240);
  static const highlight = Duration(milliseconds: 500);
  static const state = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}
