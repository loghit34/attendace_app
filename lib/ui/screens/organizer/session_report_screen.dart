import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/session_member_model.dart';
import '../../../core/state/session_provider.dart';
import '../../widgets/presence_badge.dart';

class SessionReportScreen extends StatelessWidget {
  const SessionReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final provider = context.watch<SessionProvider>();
    final session = provider.activeSession;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Report')),
        body: const Center(child: Text('No active session.')),
      );
    }

    final total = provider.totalCount;
    final present = provider.presentCount;
    final missing = provider.missingCount;
    final away = provider.possiblyAwayCount;
    final rate = total > 0 ? ((present / total) * 100).toStringAsFixed(1) : '0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presence Audit Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Summary',
            onPressed: () => provider.shareSummary(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Executive summary header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          session.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark ? AppColors.darkText : AppColors.lightText,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          (session.category.isNotEmpty && session.category != 'General')
                              ? session.category
                              : session.status.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Code: ${session.joinCode} • ${DateFormat('d MMM yyyy, h:mm a').format(session.startTime)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 14),

                  // Stat Grid (2x2 layout prevents text clipping and overflow)
                  Row(
                    children: [
                      _buildMetric(
                        label: 'Verification Rate',
                        value: '$rate%',
                        color: AppColors.present,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      _buildMetric(
                        label: 'Present Members',
                        value: '$present / $total',
                        color: AppColors.present,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildMetric(
                        label: 'Missing',
                        value: '$missing',
                        color: AppColors.missing,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      _buildMetric(
                        label: 'Possibly Away',
                        value: '$away',
                        color: AppColors.possiblyAway,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Share & Export Actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => provider.shareSummary(),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share Summary'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final csv = provider.exportCsv();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Generated CSV (${csv.length} bytes) ready for export.'),
                          action: SnackBarAction(
                            label: 'Copy CSV',
                            onPressed: () {},
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Member Roster Table
            Text(
              'MEMBER VERIFICATION ROSTER',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: provider.members.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final member = provider.members[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      child: Text(
                        member.userName[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkText : AppColors.lightText,
                        ),
                      ),
                    ),
                    title: Text(
                      member.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      member.status == PresenceStatus.present ||
                              member.status == PresenceStatus.manuallyConfirmed
                          ? 'Verified: ${member.relativeTimeAgo}'
                          : 'Not verified during check',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                    trailing: PresenceBadge(status: member.status),
                  );
                },
              ),
            ),

            const SizedBox(height: 28),

            // Real-time Event Audit Log
            Text(
              'REAL-TIME AUDIT LOG',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: provider.events.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No events recorded yet.')),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: provider.events.take(15).length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final event = provider.events[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.circle, size: 8, color: AppColors.accent),
                          title: Text(
                            event.readableMessage,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          trailing: Text(
                            DateFormat('h:mm:ss a').format(event.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
