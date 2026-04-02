import 'package:flutter/material.dart';

import '../../../core/widgets/user_avatar.dart';
import '../application/progression_controller.dart';

class ProgressionCompactBadge extends StatelessWidget {
  const ProgressionCompactBadge({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: ProgressionController.instance,
      builder: (context, _) {
        final controller = ProgressionController.instance;
        final profile = controller.profile;
        final chromeOn = Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;

        final levelRange = profile != null
            ? (profile.nextLevelXp - profile.levelStartXp)
            : 1;
        final xpProgress = profile != null && levelRange > 0
            ? (profile.xpInLevel / levelRange).clamp(0.0, 1.0)
            : 0.0;

        final isCompact = width < 420;
        final nameText = profile?.displayName ?? 'Профиль';
        final levelText = profile != null ? 'Lv.${profile.level}' : '';
        final streakText =
            profile != null && profile.currentStreak > 0
                ? '🔥${profile.currentStreak}'
                : '';
        final titleText = !isCompact && profile != null ? profile.title : '';

        final parts = [
          nameText,
          if (levelText.isNotEmpty) levelText,
          if (titleText.isNotEmpty) titleText,
          if (streakText.isNotEmpty) streakText,
        ];
        final maxTextWidth = isCompact ? 200.0 : 380.0;

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: chromeOn.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: chromeOn.withValues(alpha: 0.10)),
            ),
            child: controller.isLoading && profile == null
                ? const SizedBox(
                    width: 116,
                    height: 28,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(
                        radius: 14,
                        avatarUrl: profile?.avatarUrl,
                        fallbackText: profile?.avatarText ?? 'A',
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: maxTextWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              parts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: chromeOn,
                                    height: 1.2,
                                  ),
                            ),
                            if (profile != null) ...[
                              const SizedBox(height: 3),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(999),
                                child: SizedBox(
                                  height: 3,
                                  width: isCompact ? 120 : 180,
                                  child: LinearProgressIndicator(
                                    value: xpProgress,
                                    backgroundColor: chromeOn
                                        .withValues(alpha: 0.10),
                                    valueColor:
                                        AlwaysStoppedAnimation<
                                            Color>(
                                      scheme.secondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
