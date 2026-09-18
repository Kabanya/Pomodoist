import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../collaboration/domain/collaboration_models.dart';

SharedScope? sharedScopeFromRow(SharedScopeRow? row) =>
    row == null ? null : SharedScope.fromJson(jsonDecode(row.dataJson));
