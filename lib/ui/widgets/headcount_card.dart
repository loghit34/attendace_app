import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class HeadcountCard extends StatelessWidget {
  final int presentCount;
  final int totalCount;
  final int awayCount;
  final int missingCount;
  final VoidCallback? onFilterPresent;
  final VoidCallback? onFilterAway;
  final VoidCallback? onFilterMissing;

  const HeadcountCard({
    super.key,
    required this.presentCount,
    required this.totalCount,
    required this.awayCount,
    required this.missingCount,
    this.onFilterPresent,
    this.onFilterAway,
    this.onFilterMissing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progress = totalCount > 0 ? (presentCount / totalCount).clamp(0.0, 1.0) : 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT HEADCOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$presentCount',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                              letterSpacing: -1,
                            ),
                          ),
                          Text(
                            ' / $totalCount',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Present',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.present,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.presentContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$percentage%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.presentDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.present),
            ),
          ),
          const SizedBox(height: 18),
          // State breakdown pills
          Row(
            children: [
              Expanded(
                child: _buildStateChip(
                  context: context,
                  label: 'Present',
                  count: presentCount,
                  color: AppColors.present,
                  bgColor: isDark ? AppColors.present.withAlpha(35) : AppColors.presentContainer,
                  onTap: onFilterPresent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStateChip(
                  context: context,
                  label: 'Away',
                  count: awayCount,
                  color: AppColors.possiblyAway,
                  bgColor: isDark ? AppColors.possiblyAway.withAlpha(35) : AppColors.possiblyAwayContainer,
                  onTap: onFilterAway,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStateChip(
                  context: context,
                  label: 'Missing',
                  count: missingCount,
                  color: AppColors.missing,
                  bgColor: isDark ? AppColors.missing.withAlpha(35) : AppColors.missingContainer,
                  onTap: onFilterMissing,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStateChip({
    required BuildContext context,
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
