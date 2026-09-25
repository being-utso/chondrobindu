import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final foregroundFile = File('assets/images/logo_foreground.png');
  if (!foregroundFile.existsSync()) {
    print('Error: assets/images/logo_foreground.png not found');
    return;
  }

  print('Reading logo_foreground.png...');
  final srcImage = img.decodePng(foregroundFile.readAsBytesSync());
  if (srcImage == null) {
    print('Failed to decode source image');
    return;
  }

  // 1. Find the exact bounding box of the glyph (non-transparent pixels)
  int minX = srcImage.width;
  int maxX = 0;
  int minY = srcImage.height;
  int maxY = 0;

  for (int y = 0; y < srcImage.height; y++) {
    for (int x = 0; x < srcImage.width; x++) {
      final pixel = srcImage.getPixel(x, y);
      if (pixel.a > 15) { // non-transparent
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  final glyphW = maxX - minX + 1;
  final glyphH = maxY - minY + 1;
  print('Detected glyph bounding box: $minX, $minY to $maxX, $maxY ($glyphW x $glyphH)');

  // Crop the glyph tightly
  final glyphCrop = img.copyCrop(srcImage, x: minX, y: minY, width: glyphW, height: glyphH);

  // 2. Generate assets/icons/logo_ember.png (Clean, prominent glyph for in-app header & splash)
  // Target 1024x1024 square with ~6% margin so glyph fills the space cleanly
  final emberCanvasSize = 1024;
  final emberGlyphTargetSize = (emberCanvasSize * 0.88).round(); // 88% of canvas, tight 6% padding
  
  // Scale glyph proportionally
  final double scaleEmber = emberGlyphTargetSize / (glyphW > glyphH ? glyphW : glyphH);
  final scaledEmberW = (glyphW * scaleEmber).round();
  final scaledEmberH = (glyphH * scaleEmber).round();

  final scaledEmberGlyph = img.copyResize(
    glyphCrop,
    width: scaledEmberW,
    height: scaledEmberH,
    interpolation: img.Interpolation.cubic,
  );

  final emberCanvas = img.Image(
    width: emberCanvasSize,
    height: emberCanvasSize,
    numChannels: 4,
  );
  img.fill(emberCanvas, color: img.ColorRgba8(0, 0, 0, 0)); // transparent background

  final emberOffsetX = (emberCanvasSize - scaledEmberW) ~/ 2;
  final emberOffsetY = (emberCanvasSize - scaledEmberH) ~/ 2;

  img.compositeImage(
    emberCanvas,
    scaledEmberGlyph,
    dstX: emberOffsetX,
    dstY: emberOffsetY,
  );

  Directory('assets/icons').createSync(recursive: true);
  File('assets/icons/logo_ember.png').writeAsBytesSync(img.encodePng(emberCanvas));
  print('Saved assets/icons/logo_ember.png (1024x1024, glyph fills 88% of canvas)');

  // 3. Generate assets/images/logo_foreground.png for Android Adaptive Icons
  // Android adaptive safe area is 66.7% diameter.
  // We place the glyph so its maximum dimension occupies ~50% of the 1024x1024 canvas
  // That provides 25-30% padding around the glyph, so no part is clipped by squircle/circle masks!
  final adaptiveCanvasSize = 1024;
  final adaptiveGlyphTargetSize = (adaptiveCanvasSize * 0.50).round(); // 50% of canvas

  final double scaleAdaptive = adaptiveGlyphTargetSize / (glyphW > glyphH ? glyphW : glyphH);
  final scaledAdaptiveW = (glyphW * scaleAdaptive).round();
  final scaledAdaptiveH = (glyphH * scaleAdaptive).round();

  final scaledAdaptiveGlyph = img.copyResize(
    glyphCrop,
    width: scaledAdaptiveW,
    height: scaledAdaptiveH,
    interpolation: img.Interpolation.cubic,
  );

  final adaptiveCanvas = img.Image(
    width: adaptiveCanvasSize,
    height: adaptiveCanvasSize,
    numChannels: 4,
  );
  img.fill(adaptiveCanvas, color: img.ColorRgba8(0, 0, 0, 0)); // transparent background

  final adaptiveOffsetX = (adaptiveCanvasSize - scaledAdaptiveW) ~/ 2;
  final adaptiveOffsetY = (adaptiveCanvasSize - scaledAdaptiveH) ~/ 2;

  img.compositeImage(
    adaptiveCanvas,
    scaledAdaptiveGlyph,
    dstX: adaptiveOffsetX,
    dstY: adaptiveOffsetY,
  );

  File('assets/images/logo_foreground.png').writeAsBytesSync(img.encodePng(adaptiveCanvas));
  print('Saved assets/images/logo_foreground.png with 50% glyph size (adaptive icon padding)');

  // 4. Generate assets/images/logo.png (Full icon with #110D0C background and centered glyph)
  final fullLogoCanvas = img.Image(
    width: 1024,
    height: 1024,
    numChannels: 4,
  );
  // #110D0C: R=17, G=13, B=12
  img.fill(fullLogoCanvas, color: img.ColorRgba8(17, 13, 12, 255));

  // In full logo, glyph occupies ~60% of canvas
  final fullGlyphTargetSize = (1024 * 0.60).round();
  final double scaleFull = fullGlyphTargetSize / (glyphW > glyphH ? glyphW : glyphH);
  final scaledFullW = (glyphW * scaleFull).round();
  final scaledFullH = (glyphH * scaleFull).round();

  final scaledFullGlyph = img.copyResize(
    glyphCrop,
    width: scaledFullW,
    height: scaledFullH,
    interpolation: img.Interpolation.cubic,
  );

  final fullOffsetX = (1024 - scaledFullW) ~/ 2;
  final fullOffsetY = (1024 - scaledFullH) ~/ 2;

  img.compositeImage(
    fullLogoCanvas,
    scaledFullGlyph,
    dstX: fullOffsetX,
    dstY: fullOffsetY,
  );

  File('assets/images/logo.png').writeAsBytesSync(img.encodePng(fullLogoCanvas));
  print('Saved assets/images/logo.png with #110D0C background');

  // 5. Generate @drawable/splash_logo with ~20% inner padding (transparent background)
  // Transparent copper version centered cleanly with 20% padding so 110dp bitmap never clips
  final splashCanvasSize = 512;
  final splashGlyphTargetSize = (splashCanvasSize * 0.60).round(); // ~20% margin on each side
  final double scaleSplash = splashGlyphTargetSize / (glyphW > glyphH ? glyphW : glyphH);
  final scaledSplashW = (glyphW * scaleSplash).round();
  final scaledSplashH = (glyphH * scaleSplash).round();

  final scaledSplashGlyph = img.copyResize(
    glyphCrop,
    width: scaledSplashW,
    height: scaledSplashH,
    interpolation: img.Interpolation.cubic,
  );

  final splashCanvas = img.Image(
    width: splashCanvasSize,
    height: splashCanvasSize,
    numChannels: 4,
  );
  img.fill(splashCanvas, color: img.ColorRgba8(0, 0, 0, 0)); // transparent background

  final splashOffsetX = (splashCanvasSize - scaledSplashW) ~/ 2;
  final splashOffsetY = (splashCanvasSize - scaledSplashH) ~/ 2;

  img.compositeImage(
    splashCanvas,
    scaledSplashGlyph,
    dstX: splashOffsetX,
    dstY: splashOffsetY,
  );

  final splashBytes = img.encodePng(splashCanvas);
  final splashDirs = [
    'android/app/src/main/res/drawable',
    'android/app/src/main/res/drawable-nodpi',
    'android/app/src/main/res/drawable-mdpi',
    'android/app/src/main/res/drawable-hdpi',
    'android/app/src/main/res/drawable-xhdpi',
    'android/app/src/main/res/drawable-xxhdpi',
    'android/app/src/main/res/drawable-xxxhdpi',
    'android/app/src/main/res/drawable-night-mdpi',
    'android/app/src/main/res/drawable-night-hdpi',
    'android/app/src/main/res/drawable-night-xhdpi',
    'android/app/src/main/res/drawable-night-xxhdpi',
    'android/app/src/main/res/drawable-night-xxxhdpi',
  ];

  for (final dir in splashDirs) {
    Directory(dir).createSync(recursive: true);
    File('$dir/splash_logo.png').writeAsBytesSync(splashBytes);
    File('$dir/android12splash.png').writeAsBytesSync(splashBytes);
  }
  print('Saved splash_logo.png and android12splash.png with 20% padding across all drawable folders');
}
