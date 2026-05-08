import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/auth/auth_session.dart';
import 'core/network/backend_api.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/local_cache.dart';
import 'core/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Убираем полосу системного статус-бара — контент рисуется под него.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await LocalCache.init();
  AuthSession.instance.restoreFromCache();
  await BackendApi.initializeBaseUrl();
  await ConnectivityService.instance.init();
  SyncService.instance.init();
  runApp(const Alpha4SportApp());
}
