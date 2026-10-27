/// Общий результат одинаковых запросов: пока запрос идёт или ответ свежее
/// [ttl], все экраны получают один и тот же Future вместо нового запроса.
/// После изменения данных ключ сбрасывается через [invalidate].
class RequestMemo {
  RequestMemo({this.ttl = const Duration(seconds: 20), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, ({DateTime startedAt, Future<Object?> future})> _entries =
      {};

  Future<T> run<T>(String key, Future<T> Function() load) {
    final entry = _entries[key];
    if (entry != null && _now().difference(entry.startedAt) < ttl) {
      return entry.future.then((value) => value as T);
    }

    final future = load();
    _entries[key] = (startedAt: _now(), future: future);
    // Ошибку не запоминаем: следующий вызов попробует снова.
    future.catchError((Object _) {
      if (identical(_entries[key]?.future, future)) _entries.remove(key);
      return Future<T>.value();
    }).ignore();
    return future;
  }

  void invalidate(String key) => _entries.remove(key);

  void clear() => _entries.clear();
}
