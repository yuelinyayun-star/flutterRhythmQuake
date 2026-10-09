import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/sidesis_socket_io_client.dart';

void main() {
  test('uses the confirmed Engine.IO 4 websocket URL', () {
    final client = SidesisSocketIoClient();
    expect(client.url, SidesisSocketIoClient.defaultUrl);
  });

  test('initial state is disconnected and no subscription is guessed', () {
    final states = <SidesisSocketIoState>[];
    final client = SidesisSocketIoClient(onStateChanged: states.add);

    expect(client.isRunning, isFalse);
    expect(client.isConnected, isFalse);
    expect(client.sendEvent('subscribe'), isFalse);
    client.stop();
    expect(states, [SidesisSocketIoState.disconnected]);
  });

  test('client does not invent a business event from a transport packet', () {
    final events = <String>[];
    final client = SidesisSocketIoClient(
      onEvent: (name, data) => events.add(name),
    );

    expect(client.isConnected, isFalse);
    expect(events, isEmpty);
  });

  test('matches the website heartbeat classification', () {
    final message = SidesisSocketIoMessage.tryParse('new_message', {
      'type': 'heartbeat',
      'station_name': 'TEST',
      'station_id': 'STA-1',
      'lat': 19.4,
      'lon': -99.1,
      'timestamp': '2026-10-07T13:35:16Z',
    });

    expect(message?.kind, SidesisSocketIoMessageKind.heartbeat);
    expect(message?.isHeartbeat, isTrue);
    expect(message?.data['station_id'], 'STA-1');
  });

  test('matches the website alert fields without renaming them', () {
    final message = SidesisSocketIoMessage.tryParse('message', {
      'title': 'Sismo',
      'updated': '2026-10-07T13:35:16Z',
      'identifier': 'CAP-1',
      'msgType': 'Alert',
      'severity': 'Severe',
      'info': [
        {'event': 'Sismo Severo', 'description': 'Descripción original'},
      ],
    });

    expect(message?.kind, SidesisSocketIoMessageKind.alert);
    expect(message?.title, 'Sismo');
    expect(message?.event, 'Sismo Severo');
    expect(message?.description, 'Descripción original');
    expect(message?.identifier, 'CAP-1');
    expect(message?.messageType, 'Alert');
    expect(message?.severity, 'Severe');
    expect(message?.rawSeverity, 'Severe');
    expect(message?.asMxLevel, SidesisSeverityLevel.severe);
    expect(message?.isOfficialAlert, isTrue);
    expect(message?.isNoAlertDetection, isFalse);
  });

  test('maps the ASMX three severity levels without changing raw values', () {
    final cases = <String, SidesisSeverityLevel>{
      'Minor': SidesisSeverityLevel.minor,
      'Moderate': SidesisSeverityLevel.moderate,
      'Severe': SidesisSeverityLevel.severe,
    };

    for (final entry in cases.entries) {
      final message = SidesisSocketIoMessage.tryParse('message', {
        'severity': entry.key,
      });

      expect(message?.rawSeverity, entry.key);
      expect(message?.severity, entry.key);
      expect(message?.asMxLevel, entry.value);
      expect(
        message?.isOfficialAlert,
        entry.value == SidesisSeverityLevel.severe,
      );
      expect(
        message?.isNoAlertDetection,
        entry.value != SidesisSeverityLevel.severe,
      );
    }
  });

  test('uses the website display precedence for the semantic level', () {
    final message = SidesisSocketIoMessage.tryParse('message', {
      'severity': 'Minor',
      'info': [
        {'severity': 'Moderate'},
      ],
    });

    expect(message?.rawSeverity, 'Minor');
    expect(message?.severity, 'Moderate');
    expect(message?.asMxLevel, SidesisSeverityLevel.moderate);
    expect(message?.isOfficialAlert, isFalse);
    expect(message?.isNoAlertDetection, isTrue);
  });

  test('keeps an unknown severity unknown', () {
    final message = SidesisSocketIoMessage.tryParse('message', {
      'severity': 'Unknown',
    });

    expect(message?.asMxLevel, SidesisSeverityLevel.unknown);
    expect(message?.isOfficialAlert, isFalse);
    expect(message?.isNoAlertDetection, isFalse);
  });
}
