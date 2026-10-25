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
  bool _isSyncing = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService.instance.isOnline;
    _sub = ConnectivityService.instance.onlineStream.listen((online) {
      if (!mounted) return;
      setState(() {
        _isOnline = online;
      });
      if (online && !OfflineQueue.isEmpty) {
        setState(() => _isSyncing = true);
        SyncService.instance.drainQueue().whenComplete(() {
          if (mounted) setState(() => _isSyncing = false);
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
    final showBanner = !_isOnline || _isSyncing;
    return Column(
      children: [
        if (showBanner)
          Material(
            color: _isSyncing ? Colors.orange.shade700 : Colors.grey.shade800,
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
                        _isSyncing
                            ? Icons.sync_rounded
                            : Icons.wifi_off_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isSyncing
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
