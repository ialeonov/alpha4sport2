import 'dart:async';

import 'package:flutter/material.dart';

import '../network/connectivity_service.dart';
import '../storage/offline_queue.dart';
import '../sync/sync_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late bool _isOnline;
  late bool _hasPending;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _hasPending = !OfflineQueue.isEmpty;
    _sub = ConnectivityService.instance.onlineStream.listen((online) {
      if (!mounted) return;
      setState(() {
        _isOnline = online;
        _hasPending = !OfflineQueue.isEmpty;
      });
      if (online && _hasPending) {
        SyncService.instance.drainQueue().then((_) {
          if (mounted) setState(() => _hasPending = !OfflineQueue.isEmpty);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBanner = !_isOnline || _hasPending;
    return Column(
      children: [
        if (showBanner)
          Material(
            color: _isOnline ? Colors.orange.shade700 : Colors.grey.shade800,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _isOnline
                            ? Icons.sync_rounded
                            : Icons.wifi_off_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isOnline
                            ? 'Синхронизация...'
                            : 'Нет соединения — данные сохраняются локально',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
