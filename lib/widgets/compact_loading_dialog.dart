import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_preloader.dart';

/// Stage configuration for progressive loading messages based on elapsed time.
class ProgressiveLoadingStage {
  final Duration elapsedAfter;
  final String message;

  const ProgressiveLoadingStage({
    required this.elapsedAfter,
    required this.message,
  });
}

/// A compact, vertically constrained loading modal dialog designed for Chondrobindu.
///
/// Prevents the default unbounded vertical stretching issue by wrapping the content
/// in a constrained Container (`maxWidth: 340`, `MainAxisSize.min`), framed in dark
/// espresso surface tokens with subtle borders and shadows.
///
/// Supports static messages, dynamic [messageNotifier], and progressive timer-based
/// stages (0.0s–3.0s, 3.1s–6.0s, >6.0s) for multi-model AI failover pipelines.
class CompactLoadingDialog extends StatefulWidget {
  final String message;
  final ValueNotifier<String>? messageNotifier;
  final bool isProgressive;
  final List<ProgressiveLoadingStage>? stages;
  final Color? indicatorColor;
  final TextStyle? textStyle;

  const CompactLoadingDialog({
    super.key,
    required this.message,
    this.messageNotifier,
    this.isProgressive = false,
    this.stages,
    this.indicatorColor,
    this.textStyle,
  });

  /// Default 3-stage progressive loading sequence for syllabus ingestion
  static const List<ProgressiveLoadingStage> defaultSyllabusStages = [
    ProgressiveLoadingStage(
      elapsedAfter: Duration.zero,
      message: 'Extracting syllabus structure...',
    ),
    ProgressiveLoadingStage(
      elapsedAfter: Duration(milliseconds: 3000),
      message: 'Synthesizing topics & structuring modules...',
    ),
    ProgressiveLoadingStage(
      elapsedAfter: Duration(milliseconds: 6000),
      message: 'Finalizing checklist items & chapters...',
    ),
  ];

  /// Static helper to display the non-dismissible compact loading dialog.
  static Future<T?> show<T>({
    required BuildContext context,
    required String message,
    Color? indicatorColor,
    TextStyle? textStyle,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CompactLoadingDialog(
        message: message,
        indicatorColor: indicatorColor,
        textStyle: textStyle,
      ),
    );
  }

  /// Static helper to display progressive loading dialog with dynamic status text based on elapsed time:
  /// - 0.0s – 3.0s: "Extracting syllabus structure..."
  /// - 3.1s – 6.0s: "Synthesizing topics & structuring modules..."
  /// - > 6.0s: "Finalizing checklist items & chapters..."
  static Future<T?> showProgressive<T>({
    required BuildContext context,
    List<ProgressiveLoadingStage>? stages,
    Color? indicatorColor,
    TextStyle? textStyle,
  }) {
    final effectiveStages = stages ?? defaultSyllabusStages;
    final initialMessage = effectiveStages.isNotEmpty
        ? effectiveStages.first.message
        : 'Extracting syllabus structure...';
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CompactLoadingDialog(
        message: initialMessage,
        isProgressive: true,
        stages: effectiveStages,
        indicatorColor: indicatorColor,
        textStyle: textStyle,
      ),
    );
  }

  @override
  State<CompactLoadingDialog> createState() => _CompactLoadingDialogState();
}

class _CompactLoadingDialogState extends State<CompactLoadingDialog> {
  late String _currentMessage;
  Timer? _progressiveTimer;
  Duration _elapsedDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;

    if (widget.messageNotifier != null) {
      _currentMessage = widget.messageNotifier!.value;
      widget.messageNotifier!.addListener(_onNotifierChanged);
    } else if (widget.isProgressive) {
      final stages = widget.stages ?? CompactLoadingDialog.defaultSyllabusStages;
      if (stages.isNotEmpty) {
        _currentMessage = stages.first.message;
      }
      _progressiveTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _elapsedDuration += const Duration(milliseconds: 100);
        String nextMessage = _currentMessage;
        for (final stage in stages) {
          if (_elapsedDuration >= stage.elapsedAfter) {
            nextMessage = stage.message;
          }
        }
        if (nextMessage != _currentMessage && mounted) {
          setState(() {
            _currentMessage = nextMessage;
          });
        }
      });
    }
  }

  void _onNotifierChanged() {
    if (mounted && widget.messageNotifier != null) {
      setState(() {
        _currentMessage = widget.messageNotifier!.value;
      });
    }
  }

  @override
  void dispose() {
    _progressiveTimer?.cancel();
    widget.messageNotifier?.removeListener(_onNotifierChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816), // Dark espresso surface
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF382A24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppPreloader(
                  size: 24,
                  strokeWidth: 2.5,
                  color: widget.indicatorColor ?? const Color(0xFFF2B78A),
                ),
                const SizedBox(width: 18),
                Flexible(
                  child: Text(
                    _currentMessage,
                    style: widget.textStyle ??
                        GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFF5EBE6),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
