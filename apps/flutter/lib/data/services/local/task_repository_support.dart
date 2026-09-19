import 'dart:convert';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/domain/models/collaboration/collaboration_models.dart';

SharedScope? sharedScopeFromRow(SharedScopeRow? row) =>
    row == null ? null : SharedScope.fromJson(jsonDecode(row.dataJson));
