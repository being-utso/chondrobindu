import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_preloader.dart';

class AppLoadingScreen extends StatelessWidget {
  final String? message;
  const AppLoadingScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF110D0C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppPreloader(size: 42),
            if (message != null) ...[
              const SizedBox(height: 18),
              Text(
                message!,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFABA093),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
