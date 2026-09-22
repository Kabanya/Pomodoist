// Reviewed deployment origins. Add a future domain here only after ownership,
// Auth callbacks and deployment configuration are ready; never trust a runtime
// config value to extend its own allowlist.
const productionSupabaseUrl = 'https://ewauihswbwduvklrozke.supabase.co';
const productionSupabaseOrigins = {productionSupabaseUrl};
const stagingSupabaseOrigins = {'https://supabase-test.pomodoist.com'};

bool isApprovedBackendOrigin(Uri? uri, Set<String> origins) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    (uri.path.isEmpty || uri.path == '/') &&
    origins.contains(uri.origin);
