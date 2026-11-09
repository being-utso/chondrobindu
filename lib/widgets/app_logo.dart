import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Reusable global app logo widget that dynamically responds to the active visual theme.
///
/// Light Mode ("Lime Wash"): Uses [lightLogoAsset] (`assets/images/logo_chondrobindu_w.png`).
/// Dark Mode ("Indigo Slate"): Uses [darkLogoAsset] (`assets/images/logo_chondrobindu_d.png`).
class AppLogo extends StatelessWidget {
  static const String lightLogoAsset = 'assets/images/logo_chondrobindu_w.png';
  static const String darkLogoAsset = 'assets/images/logo_chondrobindu_d.png';

  final double size;
  final BoxFit fit;
  final bool showContainer;
  final bool? isDark;

  const AppLogo({
    super.key,
    this.size = 38,
    this.fit = BoxFit.contain,
    this.showContainer = true,
    this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bool effectiveIsDark = isDark ?? (Theme.of(context).brightness == Brightness.dark);
    final String assetPath = effectiveIsDark ? darkLogoAsset : lightLogoAsset;
    final Color fallbackColor = effectiveIsDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    final imageWidget = Image.asset(
      assetPath,
      key: ValueKey<String>(assetPath),
      fit: fit,
      errorBuilder: (_, __, ___) => Icon(
        Icons.menu_book_rounded,
        color: fallbackColor,
        size: size * 0.55,
      ),
    );

    if (!showContainer) {
      return SizedBox(
        width: size,
        height: size,
        child: imageWidget,
      );
    }

    final containerBg = effectiveIsDark ? AppColors.darkSurface : AppColors.lightSurface;
    final containerBorder = effectiveIsDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: containerBorder,
          width: 0.8,
        ),
      ),
      padding: EdgeInsets.all(size * 0.18),
      child: imageWidget,
    );
  }
}
