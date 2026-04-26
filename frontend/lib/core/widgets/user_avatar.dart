import 'package:flutter/material.dart';

import '../network/backend_api.dart';

class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.fallbackText,
    this.radius = 20,
  });

  final String? avatarUrl;
  final String fallbackText;
  final double radius;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _imageError = false;

  String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    // URL from backend already includes /uploads/ prefix (e.g. /uploads/avatars/x.jpg)
    if (url.startsWith('/')) return '${BackendApi.configuredAssetBaseUrl}$url';
    return '${BackendApi.configuredAssetBaseUrl}/uploads/$url';
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _imageError = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fullUrl = _resolveUrl(widget.avatarUrl);
    final showImage = fullUrl != null && !_imageError;
    final fontSize = widget.radius * 0.85;

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      backgroundImage: showImage ? NetworkImage(fullUrl) : null,
      onBackgroundImageError: showImage
          ? (_, __) {
              if (mounted) setState(() => _imageError = true);
            }
          : null,
      child: showImage
          ? null
          : Text(
              widget.fallbackText,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: scheme.onSecondaryContainer,
              ),
            ),
    );
  }
}
