import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/models/session_member_model.dart';

class PresenceBadge extends StatelessWidget {
  final PresenceStatus status;
  final bool isCompact;

  const PresenceBadge({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    String label;
    IconData icon;

    switch (status) {
      case PresenceStatus.present:
        bg = AppColors.presentContainer;
        text = AppColors.presentDark;
        label = 'Present';
        icon = Icons.check_circle_rounded;
        break;
      case PresenceStatus.possiblyAway:
        bg = AppColors.possiblyAwayContainer;
        text = AppColors.possiblyAwayDark;
        label = 'Possibly Away';
        icon = Icons.access_time_filled_rounded;
        break;
      case PresenceStatus.missing:
        bg = AppColors.missingContainer;
        text = AppColors.missingDark;
        label = 'Missing';
        icon = Icons.error_rounded;
        break;
      case PresenceStatus.manuallyConfirmed:
        bg = AppColors.manuallyConfirmedContainer;
        text = AppColors.manuallyConfirmed;
        label = 'Confirmed';
        icon = Icons.verified_user_rounded;
        break;
      case PresenceStatus.left:
        bg = AppColors.leftContainer;
        text = AppColors.left;
        label = 'Left';
        icon = Icons.exit_to_app_rounded;
        break;
    }

    if (isCompact) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: text,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: text.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: text),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: text,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
