// Generates assets/icons/radio_icon.png from the same design as radio_icon.svg.
// Run: dart run tool/generate_radio_icon.dart
// Scaled down and centered so the radio doesn't overflow launcher safe zone.

import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

void main() {
  const int size = 1024;
  final image = img.Image(width: size, height: size);

  // Scale and center: use ~51% of canvas (75% of previous 68%) so icon appears a bit smaller
  const double scale = 0.68 * 0.75; // 0.51
  final int pad = ((1 - scale) * size / 2).round(); // ~163

  int s(int x) => (x * scale).round() + pad;
  int r(int x) => (x * scale).round();

  final darkBlue = img.ColorRgba8(31, 42, 68, 255);
  final white = img.ColorRgba8(255, 255, 255, 255);
  final lightBlue = img.ColorRgba8(230, 236, 245, 255);

  img.fill(image, color: darkBlue);

  // White rounded rect (radio body)
  img.drawRect(
    image,
    x1: s(170),
    y1: s(300),
    x2: s(170 + 684),
    y2: s(300 + 424),
    color: white,
    radius: r(80),
  );

  // Light blue rect (speaker area)
  img.drawRect(
    image,
    x1: s(230),
    y1: s(360),
    x2: s(490),
    y2: s(620),
    color: lightBlue,
    radius: r(40),
  );

  // Dial circles
  img.drawCircle(image, x: s(360), y: s(490), radius: r(90), color: darkBlue);
  img.drawCircle(image, x: s(360), y: s(490), radius: r(50), color: lightBlue);

  // Antenna thickness; display bars are half that
  const int antennaH = 40;
  const int barH = antennaH ~/ 2;   // 20 – half of antenna thickness
  const int barR = 10;               // radius for bars (half of bar height)
  // Three horizontal bars (radio display) – half the thickness of antenna
  img.drawRect(image, x1: s(540), y1: s(390), x2: s(770), y2: s(390 + barH), color: darkBlue, radius: r(barR));
  img.drawRect(image, x1: s(540), y1: s(458), x2: s(720), y2: s(458 + barH), color: darkBlue, radius: r(barR));
  img.drawRect(image, x1: s(540), y1: s(526), x2: s(760), y2: s(526 + barH), color: darkBlue, radius: r(barR));

  // Antenna – diagonal (tilted ~-20°), sitting at top of radio (radio body starts at y=300)
  const int radioTop = 300;
  const int ay1 = radioTop - antennaH;  // top of antenna
  const int ay2 = radioTop;             // bottom of antenna = top of radio
  const double angleDeg = -20;
  final double angleRad = angleDeg * pi / 180;
  final double cosA = cos(angleRad), sinA = sin(angleRad);
  const int ax1 = 240, ax2 = 700;
  final double cx = (ax1 + ax2) / 2, cy = (ay1 + ay2) / 2;
  double rotX(double px, double py) => (px - cx) * cosA - (py - cy) * sinA + cx;
  double rotY(double px, double py) => (px - cx) * sinA + (py - cy) * cosA + cy;
  final ax1r = s(rotX(ax1.toDouble(), ay1.toDouble()).round());
  final ay1r = s(rotY(ax1.toDouble(), ay1.toDouble()).round());
  final ax2r = s(rotX(ax2.toDouble(), ay1.toDouble()).round());
  final ay2r = s(rotY(ax2.toDouble(), ay1.toDouble()).round());
  final ax3r = s(rotX(ax2.toDouble(), ay2.toDouble()).round());
  final ay3r = s(rotY(ax2.toDouble(), ay2.toDouble()).round());
  final ax4r = s(rotX(ax1.toDouble(), ay2.toDouble()).round());
  final ay4r = s(rotY(ax1.toDouble(), ay2.toDouble()).round());
  final antennaVertices = [
    img.Point(ax1r.toDouble(), ay1r.toDouble()),
    img.Point(ax2r.toDouble(), ay2r.toDouble()),
    img.Point(ax3r.toDouble(), ay3r.toDouble()),
    img.Point(ax4r.toDouble(), ay4r.toDouble()),
  ];
  img.fillPolygon(image, vertices: antennaVertices, color: white);

  // Right side knob
  img.drawCircle(image, x: s(750), y: s(610), radius: r(40), color: lightBlue);
  img.drawCircle(image, x: s(750), y: s(610), radius: r(20), color: darkBlue);

  final file = File('assets/icons/radio_icon.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  print('Wrote ${file.path}');
}
