// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

const double _kLinearProgressIndicatorHeight = 6.0;
const double _kMinCircularProgressIndicatorSize = 36.0;
const double _kCircularProgressIndicatorStrokeWidth = 4.0;

// TODO(hansmuller): implement the support for buffer indicator

/// A base class for material design progress indicators
///
/// This widget cannot be instantiated directly. For a linear progress
/// indicator, see [LinearProgressIndicator]. For a circular progress indicator,
/// see [CircularProgressIndicator].
///
/// See also:
///
///  * <https://www.google.com/design/spec/components/progress-activity.html>
abstract class ProgressIndicator extends StatefulWidget {
  /// Creates a progress indicator.
  ///
  /// The [value] argument can be either null (corresponding to an indeterminate
  /// progress indcator) or non-null (corresponding to a determinate progress
  /// indicator). See [value] for details.
  ProgressIndicator({
    Key key,
    this.value
  }) : super(key: key);

  /// If non-null, the value of this progress indicator with 0.0 corresponding
  /// to no progress having been made and 1.0 corresponding to all the progress
  /// having been made.
  ///
  /// If null, this progress indicator is indeterminate, which means the
  /// indicator displays a predetermined animation that does not indicator how
  /// much actual progress is being made.
  final double value;

  Color _getBackgroundColor(BuildContext context) => Theme.of(context).backgroundColor;
  Color _getValueColor(BuildContext context) => Theme.of(context).primaryColor;

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('${(value.clamp(0.0, 1.0) * 100.0).toStringAsFixed(1)}%');
  }
}

class _LinearProgressIndicatorPainter extends CustomPainter {
  const _LinearProgressIndicatorPainter({
    this.backgroundColor,
    this.valueColor,
    this.value,
    this.animationValue
  });

  final Color backgroundColor;
  final Color valueColor;
  final double value;
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = new Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRect(Point.origin & size, paint);

    paint.color = valueColor;
    if (value != null) {
      double width = value.clamp(0.0, 1.0) * size.width;
      canvas.drawRect(Point.origin & new Size(width, size.height), paint);
    } else {
      double startX = size.width * (1.5 * animationValue - 0.5);
      double endX = startX + 0.5 * size.width;
      double x = startX.clamp(0.0, size.width);
      double width = endX.clamp(0.0, size.width) - x;
      canvas.drawRect(new Point(x, 0.0) & new Size(width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_LinearProgressIndicatorPainter oldPainter) {
    return oldPainter.backgroundColor != backgroundColor
        || oldPainter.valueColor != valueColor
        || oldPainter.value != value
        || oldPainter.animationValue != animationValue;
  }
}

/// A material design linear progress indicator.
///
/// A widget that shows progress along a line. There are two kinds of linear
/// progress indicators:
///
///  * _Determinate_. Determinate progress indicators have a specific value at
///    each point in time, and the value should increase monotonically from 0.0
///    to 1.0, at which time the indicator is complete. To create a determinate
///    progress indicator, use a non-null [value] between 0.0 and 1.0.
///  * _Indeterminate_. Indeterminate progress indicators do not have a specific
///    value at each point in time and instead indicate that progress is being
///    made without indicating how much progress remains. To create an
///    indeterminate progress indicator, use a null [value].
///
/// See also:
///
///  * [CircularProgressIndicator]
///  * <https://www.google.com/design/spec/components/progress-activity.html#progress-activity-types-of-indicators>
class LinearProgressIndicator extends ProgressIndicator {
  /// Creates a linear progress indicator.
  ///
  /// The [value] argument can be either null (corresponding to an indeterminate
  /// progress indcator) or non-null (corresponding to a determinate progress
  /// indicator). See [value] for details.
  LinearProgressIndicator({
    Key key,
    double value
  }) : super(key: key, value: value);

  @override
  _LinearProgressIndicatorState createState() => new _LinearProgressIndicatorState();
}

class _LinearProgressIndicatorState extends State<LinearProgressIndicator> {
  Animation<double> _animation;
  AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = new AnimationController(
      duration: const Duration(milliseconds: 1500)
    )..repeat();
    _animation = new CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn);
  }

  @override
  void dispose() {
    _controller.stop();
    super.dispose();
  }

  Widget _buildIndicator(BuildContext context, double animationValue) {
    return new Container(
      constraints: new BoxConstraints.tightFor(
        width: double.INFINITY,
        height: _kLinearProgressIndicatorHeight
      ),
      child: new CustomPaint(
        painter: new _LinearProgressIndicatorPainter(
          backgroundColor: config._getBackgroundColor(context),
          valueColor: config._getValueColor(context),
          value: config.value, // may be null
          animationValue: animationValue // ignored if config.value is not null
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (config.value != null)
      return _buildIndicator(context, _animation.value);

    return new AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget child) {
        return _buildIndicator(context, _animation.value);
      }
    );
  }
}

class _CircularProgressIndicatorPainter extends CustomPainter {
  static const double _kTwoPI = math.PI * 2.0;
  static const double _kEpsilon = .001;
  // Canavs.drawArc(r, 0, 2*PI) doesn't draw anything, so just get close.
  static const double _kSweep = _kTwoPI - _kEpsilon;
  static const double _kStartAngle = -math.PI / 2.0;

  const _CircularProgressIndicatorPainter({
    this.valueColor,
    this.value,
    this.headValue,
    this.tailValue,
    this.stepValue,
    this.rotationValue
  });

  final Color valueColor;
  final double value;
  final double headValue;
  final double tailValue;
  final int stepValue;
  final double rotationValue;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = new Paint()
      ..color = valueColor
      ..strokeWidth = _kCircularProgressIndicatorStrokeWidth
      ..style = PaintingStyle.stroke;

    if (value != null) {
      // Determinate
      double angle = value.clamp(0.0, 1.0) * _kSweep;
      Path path = new Path()
        ..arcTo(Point.origin & size, _kStartAngle, angle, false);
      canvas.drawPath(path, paint);

    } else {
      // Indeterminate
      paint.strokeCap = StrokeCap.square;

      double arcSweep = math.max(headValue * 3 / 2 * math.PI - tailValue * 3 / 2 * math.PI, _kEpsilon);
      Path path = new Path()
        ..arcTo(Point.origin & size,
                _kStartAngle + tailValue * 3 / 2 * math.PI + rotationValue * math.PI * 1.7 - stepValue * 0.8 * math.PI,
                arcSweep,
                false);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CircularProgressIndicatorPainter oldPainter) {
    return oldPainter.valueColor != valueColor
        || oldPainter.value != value
        || oldPainter.headValue != headValue
        || oldPainter.tailValue != tailValue
        || oldPainter.stepValue != stepValue
        || oldPainter.rotationValue != rotationValue;
  }
}

/// A material design circular progress indicator.
///
/// A widget that shows progress along a circle. There are two kinds of circular
/// progress indicators:
///
///  * _Determinate_. Determinate progress indicators have a specific value at
///    each point in time, and the value should increase monotonically from 0.0
///    to 1.0, at which time the indicator is complete. To create a determinate
///    progress indicator, use a non-null [value] between 0.0 and 1.0.
///  * _Indeterminate_. Indeterminate progress indicators do not have a specific
///    value at each point in time and instead indicate that progress is being
///    made without indicating how much progress remains. To create an
///    indeterminate progress indicator, use a null [value].
///
/// See also:
///
///  * [LinearProgressIndicator]
///  * <https://www.google.com/design/spec/components/progress-activity.html#progress-activity-types-of-indicators>
class CircularProgressIndicator extends ProgressIndicator {
  /// Creates a circular progress indicator.
  ///
  /// The [value] argument can be either null (corresponding to an indeterminate
  /// progress indcator) or non-null (corresponding to a determinate progress
  /// indicator). See [value] for details.
  CircularProgressIndicator({
    Key key,
    double value
  }) : super(key: key, value: value);

  @override
  _CircularProgressIndicatorState createState() => new _CircularProgressIndicatorState();
}

// Tweens used by circular progress indicator
final Animatable<double> _kStrokeHeadTween = new CurveTween(
  curve: new Interval(0.0, 0.5, curve: Curves.fastOutSlowIn)
).chain(new CurveTween(
  curve: new SawTooth(5)
));

final Animatable<double> _kStrokeTailTween = new CurveTween(
  curve: new Interval(0.5, 1.0, curve: Curves.fastOutSlowIn)
).chain(new CurveTween(
  curve: new SawTooth(5)
));

final Animatable<int> _kStepTween = new StepTween(begin: 0, end: 5);

final Animatable<double> _kRotationTween = new CurveTween(curve: new SawTooth(5));

class _CircularProgressIndicatorState extends State<CircularProgressIndicator> {
  AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = new AnimationController(
      duration: const Duration(milliseconds: 6666)
    )..repeat();
  }

  @override
  void dispose() {
    _controller.stop();
    super.dispose();
  }

  Widget _buildIndicator(BuildContext context, double headValue, double tailValue, int stepValue, double rotationValue) {
    return new Container(
      constraints: new BoxConstraints(
        minWidth: _kMinCircularProgressIndicatorSize,
        minHeight: _kMinCircularProgressIndicatorSize
      ),
      child: new CustomPaint(
        painter: new _CircularProgressIndicatorPainter(
          valueColor: config._getValueColor(context),
          value: config.value, // may be null
          headValue: headValue, // remaining arguments are ignored if config.value is not null
          tailValue: tailValue,
          stepValue: stepValue,
          rotationValue: rotationValue
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (config.value != null)
      return _buildIndicator(context, 0.0, 0.0, 0, 0.0);

    return new AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget child) {
        return _buildIndicator(
          context,
          _kStrokeHeadTween.evaluate(_controller),
          _kStrokeTailTween.evaluate(_controller),
          _kStepTween.evaluate(_controller),
          _kRotationTween.evaluate(_controller)
        );
      }
    );
  }
}
