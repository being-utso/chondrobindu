import 'package:flutter/material.dart';

/// Reusable global app logo widget encapsulating assets/icons/logo_ember.png logic and fallback icon.
class AppLogo extends StatelessWidget {
  final double size;
  final BoxFit fit;
  final bool showContainer;

  const AppLogo({
    super.key,
    this.size = 38,
    this.fit = BoxFit.contain,
    this.showContainer = true,
  });

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFF2B78A);

    final imageWidget = Image.asset(
      'assets/icons/logo_ember.png',
      fit: fit,
      errorBuilder: (_, __, ___) => Icon(
        Icons.menu_book_rounded,
        color: accentColor,
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

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF4A3830),
          width: 0.8,
        ),
      ),
      padding: const EdgeInsets.all(7),
      child: imageWidget,
    );
  }
}
