import 'dart:async';

import 'package:alpha4sport_app/core/network/request_memo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parallel calls share one request', () async {
    var calls = 0;
    final completer = Completer<int>();
    final memo = RequestMemo();

    final a = memo.run('k', () {
      calls++;
      return completer.future;
    });
    final b = memo.run('k', () {
      calls++;
      return completer.future;
    });
    completer.complete(42);

    expect(await a, 42);
    expect(await b, 42);
    expect(calls, 1);
  });

  test('reloads after ttl and after invalidate', () async {
    var now = DateTime(2026, 10, 27, 12);
    var calls = 0;
    final memo = RequestMemo(
      ttl: const Duration(seconds: 20),
      now: () => now,
    );
    Future<int> load() async => ++calls;

    expect(await memo.run('k', load), 1);
    expect(await memo.run('k', load), 1);

    now = now.add(const Duration(seconds: 21));
    expect(await memo.run('k', load), 2);

    memo.invalidate('k');
    expect(await memo.run('k', load), 3);
  });

  test('does not remember failures', () async {
    var calls = 0;
    final memo = RequestMemo();

    await expectLater(
      memo.run<int>('k', () async {
        calls++;
        throw StateError('offline');
      }),
      throwsStateError,
    );
    expect(await memo.run('k', () async => ++calls), 2);
  });
}
