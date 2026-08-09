import 'package:flutter/widgets.dart';

import 'google_calendar_web_sign_in_button_stub.dart'
    if (dart.library.html) 'google_calendar_web_sign_in_button_web.dart'
    as platform;

class GoogleCalendarWebSignInButton extends StatelessWidget {
  const GoogleCalendarWebSignInButton({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 40, child: platform.buildWebSignInButton());
}
