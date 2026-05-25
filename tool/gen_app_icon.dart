// Generates Karlshare's launcher icon as a 1024×1024 PNG, plus the
// adaptive-icon foreground and background layers for Android.
//
// Run:  dart run tool/gen_app_icon.dart
//
// Output:
//   assets/icon/karlshare.png            — full icon (used for iOS, web,
//                                          legacy Android, and as the
//                                          adaptive-icon preview)
//   assets/icon/karlshare_foreground.png — adaptive foreground (transparent
//                                          background, glyph centered inside
//                                          the safe zone)
//   assets/icon/karlshare_background.png — adaptive background (gradient,
//                                          full bleed, no glyph)
//
// The glyph is a stylised "K-as-arrow" — a vertical bar plus two diagonals
// that suggest both the letter K and a "send-from-here" arrow. Drawn with
// the `image` package by filling rectangles + polygons (which antialias
// reliably) instead of thick strokes (which produce ghost columns).
//
// Brand gradient stays in sync with `lib/core/theme/app_colors.dart`.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _size = 1024;
const _safeFraction = 0.68; // adaptive foreground safe zone

const _orange = (r: 0xFF, g: 0x6B, b: 0x1A);
const _magenta = (r: 0xD8, g: 0x1E, b: 0x5B);
const _purple = (r: 0x7B, g: 0x2C, b: 0xBF);
const _white = (r: 0xFF, g: 0xFF, b: 0xFF);

void main() {
  // Full icon — gradient bg + glyph + rounded corners (alpha-channeled so
  // the corners can be punched out).
  final full = img.Image(width: _size, height: _size, numChannels: 4);
  _paintGradient(full);
  _paintGlyph(full, scale: 1.0);
  _roundCorners(full, radius: (_size * 0.22).round());
  _writePng(full, 'assets/icon/karlshare.png');

  // Adaptive foreground — transparent background, glyph inside the safe
  // zone so the system mask doesn't crop it.
  final fg = img.Image(width: _size, height: _size, numChannels: 4);
  _clearTransparent(fg);
  _paintGlyph(fg, scale: _safeFraction);
  _writePng(fg, 'assets/icon/karlshare_foreground.png');

  // Adaptive background — gradient, full bleed.
  final bg = img.Image(width: _size, height: _size, numChannels: 4);
  _paintGradient(bg);
  _writePng(bg, 'assets/icon/karlshare_background.png');
}

void _writePng(img.Image image, String path) {
  File(path).writeAsBytesSync(img.encodePng(image));
  // ignore: avoid_print — this is a dev-only generator, not app code.
  print('wrote $path');
}

void _clearTransparent(img.Image image) {
  for (final pixel in image) {
    pixel.setRgba(0, 0, 0, 0);
  }
}

void _paintGradient(img.Image image) {
  // Diagonal sweep with stops at 0 / 0.5 / 1 — matches AppGradients.signature.
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final t = ((x + y) / (image.width + image.height)).clamp(0.0, 1.0);
      final (:r, :g, :b) = _lerp3(_orange, _magenta, _purple, t);
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

({int r, int g, int b}) _lerp3(
  ({int r, int g, int b}) a,
  ({int r, int g, int b}) b,
  ({int r, int g, int b}) c,
  double t,
) {
  if (t < 0.5) {
    return _lerp(a, b, t / 0.5);
  }
  return _lerp(b, c, (t - 0.5) / 0.5);
}

({int r, int g, int b}) _lerp(
  ({int r, int g, int b}) a,
  ({int r, int g, int b}) b,
  double t,
) =>
    (
      r: (a.r + (b.r - a.r) * t).round(),
      g: (a.g + (b.g - a.g) * t).round(),
      b: (a.b + (b.b - a.b) * t).round(),
    );

void _paintGlyph(img.Image canvas, {required double scale}) {
  final white = img.ColorRgba8(_white.r, _white.g, _white.b, 255);
  final base = canvas.width.toDouble();
  final inner = base * scale;

  final cx = canvas.width / 2;
  final cy = canvas.height / 2;
  final h = inner * 0.62;
  final w = inner * 0.50;
  final stroke = inner * 0.13;

  final left = cx - w / 2;
  final right = cx + w / 2;
  final top = cy - h / 2;
  final bottom = cy + h / 2;
  final pivotX = left + stroke;
  // Pivot is the inner corner where both diagonals meet the bar.
  final pivot = math.Point(pivotX, cy);

  // Vertical bar — clean rectangle with rounded caps (two filled circles).
  img.fillRect(
    canvas,
    x1: left.round(),
    y1: top.round(),
    x2: (left + stroke).round(),
    y2: bottom.round(),
    color: white,
  );
  _capCircle(canvas, x: left + stroke / 2, y: top, r: stroke / 2, color: white);
  _capCircle(canvas, x: left + stroke / 2, y: bottom, r: stroke / 2, color: white);

  // Upper diagonal — filled quad from the pivot to the top-right corner.
  _strokeQuad(
    canvas,
    a: img.Point(pivot.x, pivot.y),
    b: img.Point(right, top),
    thickness: stroke,
    color: white,
  );
  // Lower diagonal — pivot to bottom-right corner.
  _strokeQuad(
    canvas,
    a: img.Point(pivot.x, pivot.y),
    b: img.Point(right, bottom),
    thickness: stroke,
    color: white,
  );
}

void _capCircle(img.Image canvas,
    {required double x, required double y, required double r, required img.Color color}) {
  img.fillCircle(
    canvas,
    x: x.round(),
    y: y.round(),
    radius: r.round(),
    color: color,
    antialias: true,
  );
}

/// Renders a thick "line" segment as a filled polygon — produces clean
/// edges without the ghost-column artifacts of `drawLine(thickness: …)`.
void _strokeQuad(
  img.Image canvas, {
  required img.Point a,
  required img.Point b,
  required double thickness,
  required img.Color color,
}) {
  final dx = (b.x - a.x).toDouble();
  final dy = (b.y - a.y).toDouble();
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return;
  // Perpendicular unit vector × half-thickness.
  final px = -dy / len * thickness / 2;
  final py = dx / len * thickness / 2;
  img.fillPolygon(
    canvas,
    vertices: [
      img.Point(a.x + px, a.y + py),
      img.Point(b.x + px, b.y + py),
      img.Point(b.x - px, b.y - py),
      img.Point(a.x - px, a.y - py),
    ],
    color: color,
  );
  // Round the ends.
  _capCircle(canvas, x: a.x.toDouble(), y: a.y.toDouble(), r: thickness / 2, color: color);
  _capCircle(canvas, x: b.x.toDouble(), y: b.y.toDouble(), r: thickness / 2, color: color);
}

/// Punch the four corners outside a quarter-circle of [radius] so the icon
/// reads as a squircle even without the system mask. Requires an
/// alpha-channeled (`numChannels: 4`) canvas.
void _roundCorners(img.Image canvas, {required int radius}) {
  final w = canvas.width;
  final h = canvas.height;
  final rr = radius * radius;
  for (var y = 0; y < radius; y++) {
    for (var x = 0; x < radius; x++) {
      final cornerDx = radius - x;
      final cornerDy = radius - y;
      if (cornerDx * cornerDx + cornerDy * cornerDy > rr) {
        canvas.setPixelRgba(x, y, 0, 0, 0, 0);
        canvas.setPixelRgba(w - 1 - x, y, 0, 0, 0, 0);
        canvas.setPixelRgba(x, h - 1 - y, 0, 0, 0, 0);
        canvas.setPixelRgba(w - 1 - x, h - 1 - y, 0, 0, 0, 0);
      }
    }
  }
}
