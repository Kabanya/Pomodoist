import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/data/services/agent_settings/agent_app_settings_runtime.dart';

void main() {
  test(
    'one primary runtime journals before apply and acknowledges once',
    () async {
      final events = <String>[];
      var claimed = false;
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'device',
        instanceId: 'instance',
        name: 'Mac',
        platform: 'macOS',
        capabilities: {},
        isCurrent: () => true,
        invoke: (body) async {
          events.add(body['action'] as String);
          if (body['action'] == 'register') return {'registered': true};
          if (body['action'] == 'claim') {
            if (claimed) return {'commands': []};
            claimed = true;
            return {
              'commands': [
                {
                  'request_id': 'request',
                  'operation': 'appearance',
                  'setting': 'theme',
                  'value': 'ocean',
                },
              ],
            };
          }
          return {};
        },
        snapshot: () async => {'status': 'applied'},
        apply: (_) async {
          events.add('apply');
          return {'status': 'applied', 'value': 'ocean'};
        },
        readJournal: () async => null,
        writeJournal: (value) async {
          events.add(value?['phase']?.toString() ?? 'clear');
        },
      );
      await runtime.pulse();
      expect(events.indexOf('executing'), lessThan(events.indexOf('apply')));
      expect(events.indexOf('completed'), lessThan(events.indexOf('finish')));
      expect(events.where((e) => e == 'apply'), hasLength(1));
      runtime.dispose();
    },
  );
  test(
    'competing tab does not claim, read journal, or change settings',
    () async {
      final actions = <String>[];
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'd',
        instanceId: 'i',
        name: 'Web',
        platform: 'web',
        capabilities: {},
        isCurrent: () => true,
        invoke: (b) async {
          actions.add(b['action'] as String);
          return {'registered': false, 'code': 'device_in_use'};
        },
        snapshot: () async => throw StateError('must not read'),
        apply: (_) async => throw StateError('must not apply'),
        readJournal: () async =>
            throw StateError('must not inspect another tab'),
        writeJournal: (_) async {},
      );
      await runtime.pulse();
      expect(actions, ['register']);
      runtime.dispose();
    },
  );
  test(
    'lost finish response retries acknowledgment without applying again',
    () async {
      var applied = 0, finishes = 0, claims = 0;
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'd',
        instanceId: 'i',
        name: 'Web',
        platform: 'web',
        capabilities: {},
        isCurrent: () => true,
        invoke: (b) async {
          if (b['action'] == 'register') return {'registered': true};
          if (b['action'] == 'finish' && ++finishes == 1) {
            throw StateError('timeout');
          }
          if (b['action'] == 'claim' && claims++ == 0) {
            return {
              'commands': [
                {'request_id': 'r', 'operation': 'appearance'},
              ],
            };
          }
          return {'commands': []};
        },
        snapshot: () async => {},
        apply: (_) async {
          applied++;
          return {'status': 'applied'};
        },
        readJournal: () async => null,
        writeJournal: (_) async {},
      );
      await runtime.pulse();
      await runtime.pulse();
      expect(applied, 1);
      expect(finishes, 2);
      runtime.dispose();
    },
  );
  test(
    'account switch during claim prevents local write and acknowledgment',
    () async {
      var current = true;
      var applied = false;
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'd',
        instanceId: 'i',
        name: 'Web',
        platform: 'web',
        capabilities: {},
        isCurrent: () => current,
        invoke: (b) async {
          if (b['action'] == 'register') return {'registered': true};
          if (b['action'] == 'claim') {
            current = false;
            return {
              'commands': [
                {'request_id': 'r', 'operation': 'appearance'},
              ],
            };
          }
          fail('must not finish after account change');
        },
        snapshot: () async => {},
        apply: (_) async {
          applied = true;
          return {};
        },
        readJournal: () async => null,
        writeJournal: (_) async {},
      );
      await runtime.pulse();
      expect(applied, false);
      runtime.dispose();
    },
  );
  test(
    'new instance reconciles an interrupted local journal without replay',
    () async {
      var snapshots = 0, applied = 0;
      Map<String, dynamic>? saved;
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'd',
        instanceId: 'new',
        name: 'Web',
        platform: 'web',
        capabilities: {},
        isCurrent: () => true,
        invoke: (b) async =>
            b['action'] == 'register' ? {'registered': true} : {'commands': []},
        snapshot: () async {
          snapshots++;
          return {
            'values': {'theme': 'ocean'},
          };
        },
        apply: (_) async {
          applied++;
          return {};
        },
        readJournal: () async => {
          'requestId': 'r',
          'instanceId': 'old',
          'phase': 'executing',
        },
        writeJournal: (v) async {
          saved = v;
        },
      );
      await runtime.pulse();
      expect(snapshots, 1);
      expect(applied, 0);
      expect(saved?['phase'], 'uncertain');
      runtime.dispose();
    },
  );
  test(
    'lost claim response recovers without a duplicate local effect',
    () async {
      var claims = 0, applied = 0, finished = false;
      final command = {
        'request_id': 'r',
        'operation': 'appearance',
        'setting': 'theme',
        'value': 'ocean',
      };
      final runtime = AgentAppSettingsRuntime(
        deviceId: 'd',
        instanceId: 'i',
        name: 'Mac',
        platform: 'macOS',
        capabilities: {},
        isCurrent: () => true,
        invoke: (body) async {
          if (body['action'] == 'register') return {'registered': true};
          if (body['action'] == 'claim') {
            if (claims++ == 0) {
              throw StateError('response lost after server claim');
            }
            return {
              'commands': finished ? [] : [command],
            };
          }
          if (body['action'] == 'finish') finished = true;
          return {};
        },
        snapshot: () async => {},
        apply: (_) async {
          applied++;
          return {'status': 'applied'};
        },
        readJournal: () async => null,
        writeJournal: (_) async {},
      );
      await runtime.pulse();
      expect(applied, 0);
      await runtime.pulse();
      expect(applied, 1);
      expect(finished, true);
      runtime.dispose();
    },
  );
}
