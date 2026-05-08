import 'local_cache.dart';

class OfflineQueue {
  static const _key = 'offline_mutations';

  static List<Map<String, dynamic>> getAll() {
    final raw = LocalCache.get<List>(_key);
    if (raw == null) return [];
    return raw.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  static bool get isEmpty => getAll().isEmpty;

  static Future<void> add(String type, Map<String, dynamic> payload) async {
    final mutations = getAll();
    mutations.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type,
      'payload': payload,
    });
    await LocalCache.put(_key, mutations);
  }

  static Future<void> remove(String id) async {
    final mutations = getAll()..removeWhere((m) => m['id'] == id);
    await LocalCache.put(_key, mutations);
  }

  static Future<void> clear() async => LocalCache.remove(_key);
}
