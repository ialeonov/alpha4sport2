import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;

  Stream<bool> get onlineStream => _controller.stream;
  bool get isOnline => _isOnline;

  Future<void> init() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = _connected(results);

    _connectivity.onConnectivityChanged.listen((results) {
      final online = _connected(results);
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(online);
      }
    });
  }

  bool _connected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
