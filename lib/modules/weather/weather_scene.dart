import 'package:flutter/material.dart';

import '../../core/time.dart';
import '../../theme/weather_palette.dart';
import 'weather_model.dart';

enum WeatherSky { clear, cloudy, overcast, fog, rain, snow, storm, unknown }

enum WeatherDaylight { dawn, day, dusk, night }

/// A deterministic scene, including when displaying an offline snapshot.
/// For a stale day, reuse its solar wall-clock times on today's campus date.
@immutable
class WeatherSceneData {
  const WeatherSceneData({required this.sky, required this.daylight});

  factory WeatherSceneData.fromSnapshot(
    WeatherSnapshot snapshot,
    DateTime now,
  ) {
    final local = campusFromEpochMs(now.millisecondsSinceEpoch);
    DateTime today(DateTime value) {
      final solar = campusFromEpochMs(value.millisecondsSinceEpoch);
      return campusInstant(
        DateTime(local.year, local.month, local.day, solar.hour, solar.minute),
      );
    }

    final sunrise = today(snapshot.sunrise);
    final sunset = today(snapshot.sunset);
    const twilight = Duration(minutes: 40);
    final WeatherDaylight daylight;
    if (now.isBefore(sunrise.subtract(twilight)) ||
        !now.isBefore(sunset.add(twilight))) {
      daylight = WeatherDaylight.night;
    } else if (now.isBefore(sunrise.add(twilight))) {
      daylight = WeatherDaylight.dawn;
    } else if (!now.isBefore(sunset.subtract(twilight))) {
      daylight = WeatherDaylight.dusk;
    } else {
      daylight = WeatherDaylight.day;
    }

    return WeatherSceneData(
      sky: switch (snapshot.weatherCode) {
        0 => WeatherSky.clear,
        1 || 2 => WeatherSky.cloudy,
        3 => WeatherSky.overcast,
        45 || 48 => WeatherSky.fog,
        51 ||
        53 ||
        55 ||
        56 ||
        57 ||
        61 ||
        63 ||
        65 ||
        66 ||
        67 ||
        80 ||
        81 ||
        82 => WeatherSky.rain,
        71 || 73 || 75 || 77 || 85 || 86 => WeatherSky.snow,
        95 || 96 || 99 => WeatherSky.storm,
        _ => WeatherSky.unknown,
      },
      daylight: daylight,
    );
  }

  final WeatherSky sky;
  final WeatherDaylight daylight;

  bool get isNight => daylight == WeatherDaylight.night;

  WeatherPalette get palette {
    if (isNight) return WeatherPalette.night;
    // Precipitation remains recognisable even during golden hour.
    if (sky == WeatherSky.snow) return WeatherPalette.snow;
    if (sky == WeatherSky.rain || sky == WeatherSky.storm) {
      return WeatherPalette.rain;
    }
    if (daylight == WeatherDaylight.dawn || daylight == WeatherDaylight.dusk) {
      return WeatherPalette.twilight;
    }
    return switch (sky) {
      WeatherSky.clear || WeatherSky.cloudy => WeatherPalette.day,
      _ => WeatherPalette.overcast,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is WeatherSceneData &&
      sky == other.sky &&
      daylight == other.daylight;

  @override
  int get hashCode => Object.hash(sky, daylight);
}

/// Original campus-inspired artwork, not a map of actual campus buildings.
/// The quiet upper-left sky is reserved for live, accessible weather text.
class WeatherScene extends StatelessWidget {
  const WeatherScene({super.key, required this.data});

  final WeatherSceneData data;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(painter: _CampusWeatherPainter(data)),
    ),
  );
}

class _CampusWeatherPainter extends CustomPainter {
  const _CampusWeatherPainter(this.data);

  final WeatherSceneData data;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = data.palette;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = p.sky.createShader(Offset.zero & size),
    );

    // Normalised illustration coordinates preserve proportions at all widths.
    // Anchor the landscape to the bottom so enlarged text has its own space.
    canvas.save();
    canvas.translate(0, size.height - size.width * .46);
    canvas.scale(size.width / 400);

    if (data.isNight &&
        (data.sky == WeatherSky.clear || data.sky == WeatherSky.cloudy)) {
      for (var i = 0; i < 18; i++) {
        final x = 20.0 + (i * 67 % 370);
        final y = -35.0 + (i * 29 % 110);
        if (y < 0 && x < 250) continue;
        canvas.drawCircle(
          Offset(x, y),
          i.isEven ? 1.2 : .7,
          Paint()..color = p.celestial.withValues(alpha: .7),
        );
      }
    }

    if (data.sky == WeatherSky.clear || data.sky == WeatherSky.cloudy) {
      final orb = Offset(
        322,
        data.daylight == WeatherDaylight.dusk ||
                data.daylight == WeatherDaylight.dawn
            ? 40
            : -10,
      );
      if (data.isNight) {
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: orb, radius: 21)),
          Path()..addOval(
            Rect.fromCircle(center: orb + const Offset(10, -8), radius: 20),
          ),
        );
        canvas.drawPath(moon, Paint()..color = p.celestial);
      } else {
        canvas.drawCircle(
          orb,
          39,
          Paint()..color = p.celestial.withValues(alpha: .18),
        );
        canvas.drawCircle(orb, 28, Paint()..color = p.celestial);
      }
    }

    if (data.sky != WeatherSky.clear && data.sky != WeatherSky.unknown) {
      _cloud(canvas, const Offset(287, 30), .85, p.cloud);
      _cloud(canvas, const Offset(374, 2), .75, p.cloud.withValues(alpha: .7));
      if (data.sky != WeatherSky.cloudy) {
        _cloud(
          canvas,
          const Offset(66, 45),
          1.1,
          p.cloud.withValues(alpha: .65),
        );
        _cloud(
          canvas,
          const Offset(200, 30),
          .6,
          p.cloud.withValues(alpha: .55),
        );
      }
    }

    final rear = Path()
      ..moveTo(0, 103)
      ..cubicTo(85, 68, 118, 105, 206, 87)
      ..cubicTo(290, 65, 340, 93, 400, 70)
      ..lineTo(400, 184)
      ..lineTo(0, 184)
      ..close();
    canvas.drawPath(rear, Paint()..color = p.distant);
    final lawn = Path()
      ..moveTo(0, 127)
      ..quadraticBezierTo(200, 100, 400, 119)
      ..lineTo(400, 184)
      ..lineTo(0, 184)
      ..close();
    canvas.drawPath(lawn, Paint()..color = p.ground);

    // A curving pedestrian path leads through the scene.
    final path = Path()
      ..moveTo(200, 117)
      ..cubicTo(255, 133, 258, 151, 324, 184)
      ..lineTo(239, 184)
      ..cubicTo(224, 154, 207, 137, 190, 117)
      ..close();
    canvas.drawPath(path, Paint()..color = p.path);

    _building(canvas, const Rect.fromLTWH(99, 70, 124, 62), p);
    _building(canvas, const Rect.fromLTWH(75, 93, 63, 43), p);

    _tree(canvas, const Offset(36, 135), 1.0, p);
    _tree(canvas, const Offset(62, 146), .7, p);
    _tree(canvas, const Offset(321, 134), 1.1, p);
    _tree(canvas, const Offset(366, 147), .8, p);

    // Low foreground planting gives the illustration depth without shadows.
    for (var i = 0; i < 6; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(12.0 + i * 19, 183),
          width: 42,
          height: 22.0 + (i % 3) * 8,
        ),
        Paint()..color = p.leaf,
      );
    }
    _bicycle(canvas, const Offset(274, 151), p);

    if (data.sky == WeatherSky.rain || data.sky == WeatherSky.storm) {
      final rain = Paint()
        ..color = p.window.withValues(alpha: .42)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 36; i++) {
        final start = Offset(
          (i * 79 % 400).toDouble(),
          (i * 43 % 170).toDouble(),
        );
        canvas.drawLine(start, start + const Offset(-4, 10), rain);
      }
      final puddle = Paint()..color = p.skyBottom.withValues(alpha: .5);
      canvas.drawOval(const Rect.fromLTWH(265, 164, 27, 3), puddle);
      canvas.drawOval(const Rect.fromLTWH(221, 145, 17, 2), puddle);
    }
    if (data.sky == WeatherSky.storm) {
      final bolt = Path()
        ..moveTo(296, 37)
        ..lineTo(282, 57)
        ..lineTo(294, 56)
        ..lineTo(285, 73)
        ..lineTo(312, 48)
        ..lineTo(298, 49)
        ..close();
      canvas.drawPath(bolt, Paint()..color = p.celestial);
    }
    if (data.sky == WeatherSky.snow) {
      final snow = Paint()..color = WeatherPalette.snow.cloud;
      canvas.drawRect(const Rect.fromLTWH(95, 67, 131, 5), snow);
      for (var i = 0; i < 38; i++) {
        canvas.drawCircle(
          Offset((i * 73 % 400).toDouble(), (i * 37 % 180).toDouble()),
          i.isEven ? 2 : 1.3,
          snow,
        );
      }
    }
    if (data.sky == WeatherSky.fog) {
      final mist = Paint()
        ..color = p.skyBottom.withValues(alpha: .62)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final y = 58.0 + i * 27;
        canvas.drawLine(
          Offset(i.isEven ? 0 : 95, y),
          Offset(i.isEven ? 290 : 420, y),
          mist,
        );
      }
    }
    canvas.restore();
  }

  void _cloud(Canvas canvas, Offset origin, double scale, Color color) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final shape = Path()
      ..moveTo(-48, 8)
      ..cubicTo(-63, 6, -61, -13, -45, -15)
      ..cubicTo(-45, -41, -13, -46, -3, -24)
      ..cubicTo(14, -33, 31, -19, 29, -6)
      ..cubicTo(55, -6, 58, 16, 35, 16)
      ..lineTo(-44, 16)
      ..close();
    canvas.drawPath(shape, Paint()..color = color);
    canvas.restore();
  }

  void _building(Canvas canvas, Rect r, WeatherPalette p) {
    canvas.drawRect(r, Paint()..color = p.building);
    canvas.drawRect(
      Rect.fromLTWH(r.right - 17, r.top, 17, r.height),
      Paint()..color = p.buildingSide,
    );
    canvas.drawRect(
      Rect.fromLTWH(r.left - 3, r.top - 3, r.width + 6, 4),
      Paint()..color = p.path,
    );
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < (r.width - 24) ~/ 16; col++) {
        canvas.drawRect(
          Rect.fromLTWH(r.left + 9 + col * 16, r.top + 10 + row * 15, 9, 7),
          Paint()..color = p.window,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(r.right - 15, r.bottom - 19, 10, 19),
      Paint()..color = p.window,
    );
  }

  void _tree(Canvas canvas, Offset base, double scale, WeatherPalette p) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.scale(scale);
    final trunk = Paint()
      ..color = p.buildingSide
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(
      const Rect.fromLTWH(-20, -76, 40, 61),
      Paint()..color = p.leaf,
    );
    canvas.drawOval(
      const Rect.fromLTWH(-22, -54, 33, 31),
      Paint()..color = p.leaf,
    );
    canvas.drawLine(Offset.zero, const Offset(0, -50), trunk);
    canvas.drawLine(const Offset(0, -26), const Offset(-9, -37), trunk);
    canvas.drawLine(const Offset(0, -39), const Offset(8, -49), trunk);
    canvas.restore();
  }

  void _bicycle(Canvas canvas, Offset origin, WeatherPalette p) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final line = Paint()
      ..color = p.leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(-12, 0), 7, line);
    canvas.drawCircle(const Offset(12, 0), 7, line);
    final frame = Path()
      ..moveTo(-12, 0)
      ..lineTo(-5, -12)
      ..lineTo(2, 0)
      ..close()
      ..moveTo(-5, -12)
      ..lineTo(7, -12)
      ..lineTo(2, 0)
      ..moveTo(12, 0)
      ..lineTo(6, -18)
      ..lineTo(10, -18)
      ..moveTo(-8, -15)
      ..lineTo(-3, -15);
    canvas.drawPath(frame, line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CampusWeatherPainter oldDelegate) =>
      oldDelegate.data != data;
}
