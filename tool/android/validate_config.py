#!/usr/bin/env python3
"""Validate the public dart-defines for an official Android production build."""
import base64
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit

ALLOWED = {
    'POMODOIST_ENVIRONMENT', 'WEB_APP_URL', 'POMODOIST_REGISTRATION_URL',
    'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'TURNSTILE_SITE_KEY', 'SENTRY_DSN',
    'GOOGLE_WEB_CLIENT_ID', 'POMODOIST_BILLING_CHANNEL',
    'POMODOIST_DEV_UNLOCK', 'POMODOIST_LOCAL_STOREKIT',
}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate configuration field: ' + key)
        result[key] = value
    return result


def https_url(value, field):
    try:
        url = urlsplit(value)
        valid = (url.scheme == 'https' and url.hostname and not url.username
                 and not url.password and not url.fragment and not url.query
                 and url.port in (None, 443))
    except ValueError:
        valid = False
    if not valid:
        raise ValueError(field + ' must be a public HTTPS URL without credentials, query or fragment.')
    if url.hostname in {'localhost', '127.0.0.1', '0.0.0.0', '::1'}:
        raise ValueError(field + ' must not point to a local server.')
    return url


def validate(config):
    if not isinstance(config, dict) or any(not isinstance(v, str) for v in config.values()):
        raise ValueError('Configuration must be a JSON object containing string values.')
    unknown = set(config) - ALLOWED
    if unknown:
        raise ValueError('Non-public or unknown dart-defines: ' + ', '.join(sorted(unknown)))
    if config.get('POMODOIST_ENVIRONMENT') != 'production':
        raise ValueError('POMODOIST_ENVIRONMENT must be production.')
    web = https_url(config.get('WEB_APP_URL', ''), 'WEB_APP_URL')
    if web.path not in ('', '/'):
        raise ValueError('WEB_APP_URL must be an origin.')
    registration = https_url(config.get('POMODOIST_REGISTRATION_URL', ''), 'POMODOIST_REGISTRATION_URL')
    if (registration.netloc != web.netloc or registration.path != '/auth/challenge'):
        raise ValueError('POMODOIST_REGISTRATION_URL must be /auth/challenge on WEB_APP_URL.')
    if not config.get('TURNSTILE_SITE_KEY', '').strip():
        raise ValueError('TURNSTILE_SITE_KEY is required for production account flows.')
    for field in ('POMODOIST_DEV_UNLOCK', 'POMODOIST_LOCAL_STOREKIT'):
        if config.get(field, '').lower() not in ('', '0', 'false'):
            raise ValueError(field + ' must be disabled.')
    # Existing Apple-platform guard makes this channel account-only on Android.
    # Do not silently ship Stripe checkout in a Google Play bundle.
    if config.get('POMODOIST_BILLING_CHANNEL') != 'storekit':
        raise ValueError('Android uses the guarded storekit channel: account entitlements, no native checkout.')
    backend = config.get('SUPABASE_URL', '')
    key = config.get('SUPABASE_ANON_KEY', '')
    if bool(backend) != bool(key):
        raise ValueError('SUPABASE_URL and SUPABASE_ANON_KEY must be provided together or both omitted.')
    if backend:
        https_url(backend, 'SUPABASE_URL')
        if not key.startswith('sb_publishable_'):
            try:
                payload = key.split('.')[1]
                claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
                valid_key = claims.get('role') == 'anon'
            except (ValueError, IndexError, UnicodeError, AttributeError):
                valid_key = False
            if not valid_key:
                raise ValueError('SUPABASE_ANON_KEY must be a public publishable key or an anon-role JWT.')
    dsn = config.get('SENTRY_DSN', '')
    if dsn:
        url = urlsplit(dsn)
        if url.scheme != 'https' or not url.hostname or not url.username or url.password or url.query or url.fragment:
            raise ValueError('SENTRY_DSN must be a public HTTPS DSN, not an auth token.')
    return config


def main():
    if len(sys.argv) != 2:
        print('Usage: python3 tool/android/validate_config.py CONFIG.json', file=sys.stderr)
        return 64
    try:
        config = json.loads(Path(sys.argv[1]).read_text(), object_pairs_hook=unique_object)
        validate(config)
    except (OSError, ValueError) as error:
        # Never print configuration values: callers may accidentally include a secret.
        print('Android production configuration rejected: ' + str(error), file=sys.stderr)
        return 1
    print('Android production configuration is valid (public values only).')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
