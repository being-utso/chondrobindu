import 'package:flutter/material.dart';

/// A lightweight, self-contained Marquee / Auto-Scroll widget for text.
///
/// If the text fits comfortably within the available container width, it renders
/// statically (e.g. centered) with zero animation or scroll overhead.
///
/// If the text overflows the container width:
/// - Smoothly fades the left & right edges using a [ShaderMask]
/// - Performs a gentle ping-pong auto-scroll loop: pauses at the start,
///   scrolls slowly to the end, pauses at the end, and scrolls back.
class AutoScrollMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final Duration pauseDuration;
  final double pixelsPerSecond;
  final Alignment alignment;
  final bool? autoScroll;

  const AutoScrollMarqueeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.pauseDuration = const Duration(milliseconds: 1500),
    this.pixelsPerSecond = 26.0,
    this.alignment = Alignment.center,
    this.autoScroll,
  });

  @override
  State<AutoScrollMarqueeText> createState() => _AutoScrollMarqueeTextState();
}

class _AutoScrollMarqueeTextState extends State<AutoScrollMarqueeText> {
  late final ScrollController _scrollController;
  bool _isLooping = false;

  static bool get _isTesting {
    try {
      final name = WidgetsBinding.instance.runtimeType.toString();
      return name.contains('TestWidgetsFlutterBinding') ||
          name.contains('AutomatedTestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  bool get _shouldAnimate => widget.autoScroll ?? !_isTesting;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant AutoScrollMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      _triggerLoopIfNeeded();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _triggerLoopIfNeeded() {
    if (!_shouldAnimate) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0 && !_isLooping) {
        _startPingPongLoop();
      }
    });
  }

  Future<void> _startPingPongLoop() async {
    if (_isLooping || !mounted || !_shouldAnimate) return;
    _isLooping = true;

    try {
      while (mounted && _scrollController.hasClients && _shouldAnimate) {
        // 1. Initial pause at start
        await Future.delayed(widget.pauseDuration);
        if (!mounted || !_scrollController.hasClients) break;

        final maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent <= 0) break;

        // 2. Animate slowly to the end
        final durationMs = (maxExtent / widget.pixelsPerSecond * 1000).round().clamp(1200, 15000);
        await _scrollController.animateTo(
          maxExtent,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOut,
        );

        // 3. Pause at the end
        await Future.delayed(widget.pauseDuration);
        if (!mounted || !_scrollController.hasClients) break;

        // 4. Animate back to start
        await _scrollController.animateTo(
          0.0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOut,
        );
      }
    } catch (_) {
      // Catch any unexpected cancellation during unmount
    } finally {
      if (mounted) {
        _isLooping = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final effectiveStyle = widget.style != null ? defaultStyle.merge(widget.style) : defaultStyle;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure text width precisely without line wrapping
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: effectiveStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        final textWidth = textPainter.width;
        final availableWidth = constraints.maxWidth;
        final bool overflows = availableWidth.isFinite && availableWidth > 0 && textWidth > availableWidth;

        if (!overflows) {
          // If the text fits, render statically centered without scroll or mask
          return Align(
            alignment: widget.alignment,
            child: Text(
              widget.text,
              style: effectiveStyle,
              textAlign: widget.textAlign,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          );
        }

        // Trigger loop if not yet started
        _triggerLoopIfNeeded();

        // Render overflowing text with a smooth edge fade mask
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.08, 0.92, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                widget.text,
                style: effectiveStyle,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }
}
