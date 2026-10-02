import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class UseCaseItem {
  final String title;
  final String category;
  final String subtitle;
  final IconData icon;
  final String sampleHeadcount;
  final Color accentColor;

  const UseCaseItem({
    required this.title,
    required this.category,
    required this.subtitle,
    required this.icon,
    required this.sampleHeadcount,
    required this.accentColor,
  });
}

class UseCaseCard extends StatelessWidget {
  final UseCaseItem item;
  final VoidCallback onTap;

  const UseCaseCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  static const List<UseCaseItem> presets = [
    UseCaseItem(
      title: 'Corporate Retreat',
      category: 'Corporate Retreat',
      subtitle: 'Headcount before departure to retreat',
      icon: Icons.business_center_rounded,
      sampleHeadcount: '39 / 40 Present',
      accentColor: AppColors.accent,
    ),
    UseCaseItem(
      title: 'Tourist Bus Tour',
      category: 'Tourist Group',
      subtitle: 'Guide checks tourists before moving to next stop',
      icon: Icons.directions_bus_rounded,
      sampleHeadcount: '35 / 36 Present',
      accentColor: AppColors.present,
    ),
    UseCaseItem(
      title: 'Sports Team',
      category: 'Sports Team',
      subtitle: 'Coach verifies players before departure',
      icon: Icons.sports_soccer_rounded,
      sampleHeadcount: '18 / 18 Present',
      accentColor: Color(0xFFF97316), // Orange
    ),
    UseCaseItem(
      title: 'Field Operations',
      category: 'Field Team',
      subtitle: 'Supervisor verifies crew at the worksite',
      icon: Icons.engineering_rounded,
      sampleHeadcount: '12 / 12 Present',
      accentColor: Color(0xFF8B5CF6), // Purple
    ),
    UseCaseItem(
      title: 'Event Staff',
      category: 'Event Staff',
      subtitle: 'Check staff presence across stage & entrance gates',
      icon: Icons.badge_rounded,
      sampleHeadcount: '24 / 25 Present',
      accentColor: Color(0xFFEC4899), // Pink
    ),
    UseCaseItem(
      title: 'Family & Friends',
      category: 'Family Trip',
      subtitle: 'Private group check at airport or theme park',
      icon: Icons.family_restroom_rounded,
      sampleHeadcount: '6 / 6 Present',
      accentColor: AppColors.accentCyan,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 250,
      margin: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: item.accentColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.accentColor, size: 18),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.present.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.sampleHeadcount,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.presentDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
