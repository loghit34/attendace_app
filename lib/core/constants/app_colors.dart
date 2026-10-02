import 'package:flutter/material.dart';

class AppColors {
  // Brand Primary & Accents
  static const Color primary = Color(0xFF0F172A); // Deep Slate Navy
  static const Color primaryLight = Color(0xFF1E293B);
  static const Color accent = Color(0xFF3B82F6); // Electric Blue
  static const Color accentCyan = Color(0xFF06B6D4);

  // Presence State Colors (Executive, Clear, High-Contrast)
  static const Color present = Color(0xFF10B981); // Emerald Green
  static const Color presentContainer = Color(0xFFD1FAE5);
  static const Color presentDark = Color(0xFF047857);

  static const Color possiblyAway = Color(0xFFF59E0B); // Amber / Warning
  static const Color possiblyAwayContainer = Color(0xFFFEF3C7);
  static const Color possiblyAwayDark = Color(0xFFB45309);

  static const Color missing = Color(0xFFEF4444); // Crimson / Coral
  static const Color missingContainer = Color(0xFFFEE2E2);
  static const Color missingDark = Color(0xFFB91C1C);

  static const Color manuallyConfirmed = Color(0xFF6366F1); // Indigo
  static const Color manuallyConfirmedContainer = Color(0xFFE0E7FF);

  static const Color left = Color(0xFF64748B); // Slate Gray
  static const Color leftContainer = Color(0xFFF1F5F9);

  // Surfaces & Backgrounds - Light
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightText = Color(0xFF0F172A);
  static const Color lightSubtext = Color(0xFF64748B);

  // Surfaces & Backgrounds - Dark
  static const Color darkBg = Color(0xFF090D16);
  static const Color darkCard = Color(0xFF131B2E);
  static const Color darkCardElevated = Color(0xFF1B243B);
  static const Color darkBorder = Color(0xFF1E293B);
  static const Color darkText = Color(0xFFF8FAFC);
  static const Color darkSubtext = Color(0xFF94A3B8);
}
