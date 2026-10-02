import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/session_member_model.dart';
import '../../widgets/presence_badge.dart';

class MemberDetailSheet extends StatelessWidget {
  final SessionMemberModel member;
  final VoidCallback onManualConfirm;
  final VoidCallback onMarkMissing;
  final VoidCallback onMarkAway;

  const MemberDetailSheet({
    super.key,
    required this.member,
    required this.onManualConfirm,
    required this.onMarkMissing,
    required this.onMarkAway,
  });

  Future<void> _makeCall(BuildContext context, String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number recorded for this member.')),
      );
      return;
    }
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Simulated Call to $phone')),
        );
      }
    }
  }

  Future<void> _sendSms(BuildContext context, String? phone) async {
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number recorded for this member.')),
      );
      return;
    }
    final uri = Uri.parse('sms:${phone.replaceAll(' ', '')}?body=Hi%20${member.userName},%20we%20are%20doing%20a%20group%20headcount%20check.%20Please%20verify%20your%20presence%20on%20HereNow.');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Simulated Reminder SMS sent to $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Member Header
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.accent.withAlpha(30),
                child: Text(
                  member.userName.isNotEmpty ? member.userName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.userName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkText : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.userPhone ?? 'No phone recorded',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                  ],
                ),
              ),
              PresenceBadge(status: member.status),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 12),

          // Status & Verification Metadata
          _buildInfoRow(
            label: 'Role',
            value: member.role.toUpperCase(),
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            label: 'Last Verified',
            value: member.lastVerifiedAt != null
                ? '${member.relativeTimeAgo} (${member.lastVerifiedAt!.toLocal().toString().substring(11, 16)})'
                : 'Never during this check',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            label: 'Joined Session',
            value: member.joinedAt.toLocal().toString().substring(11, 16),
            isDark: isDark,
          ),

          const SizedBox(height: 24),

          // Direct Contact Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _makeCall(context, member.userPhone),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendSms(context, member.userPhone),
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: const Text('Send SMS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status Override Actions
          Text(
            'MANUAL OVERRIDE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    onManualConfirm();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Confirm'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.present,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    onMarkAway();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Away'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.possiblyAwayDark,
                    side: const BorderSide(color: AppColors.possiblyAway),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    onMarkMissing();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Missing'),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.missing,
                    side: const BorderSide(color: AppColors.missing),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
      ],
    );
  }
}
