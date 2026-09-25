import 'package:flutter/material.dart';

/// Strict 8pt Grid & Spacing System for Chondrobindu.
/// Guarantees consistent rhythm, margins, and border radii across the application.
abstract class AppSpacing {
  // --- Strict 8pt Grid Values ---
  static const double micro = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double huge = 40.0;

  // --- Layout Insets ---
  static const EdgeInsets screenMargin = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets screenMarginWide = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPaddingCompact = EdgeInsets.all(sm);
  static const EdgeInsets cardPaddingComfortable = EdgeInsets.all(lg);
  static const EdgeInsets modalPadding = EdgeInsets.fromLTRB(lg, lg, lg, xxl);

  // --- Sized Gap Helpers ---
  static const SizedBox gapMicro = SizedBox(width: micro, height: micro);
  static const SizedBox gapXs = SizedBox(width: xs, height: xs);
  static const SizedBox gapSm = SizedBox(width: sm, height: sm);
  static const SizedBox gapMd = SizedBox(width: md, height: md);
  static const SizedBox gapLg = SizedBox(width: lg, height: lg);
  static const SizedBox gapXl = SizedBox(width: xl, height: xl);
  static const SizedBox gapXxl = SizedBox(width: xxl, height: xxl);

  // --- Standard Border Radii (TASK 4) ---
  static const double radiusMicro = 4.0;
  static const double radiusBadge = 12.0;
  static const double radiusButton = 10.0;
  static const double radiusCard = 12.0;
  static const double radiusModal = 12.0;
  static const double radiusActionContainer = 12.0;
  static const double radiusPill = 999.0;

  static final BorderRadius borderRadiusMicro = BorderRadius.circular(radiusMicro);
  static final BorderRadius borderRadiusBadge = BorderRadius.circular(radiusBadge);
  static final BorderRadius borderRadiusButton = BorderRadius.circular(radiusButton);
  static final BorderRadius borderRadiusCard = BorderRadius.circular(radiusCard);
  static final BorderRadius borderRadiusModal = BorderRadius.circular(radiusModal);
  static final BorderRadius borderRadiusActionContainer = BorderRadius.circular(radiusActionContainer);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(radiusPill);
}
