import 'package:graphic/graphic.dart';
import 'package:graphic/src/util/collection.dart';
import 'package:flutter/painting.dart';
import 'package:graphic/src/util/path.dart';

List<MarkElement> drawLineLabels(
    List<Attributes> group, CoordConv coord, Offset origin) {
  final labels = <Attributes, Offset>{};
  for (var item in group) {
    final position = item.position;
    if (position.every((point) => point.dy.isFinite)) {
      final end = coord.convert(position.last);
      labels[item] = end;
    }
  }
  final labelElements = <MarkElement>[];
  for (var item in labels.keys) {
    if (item.label != null && item.label!.haveText) {
      labelElements.add(LabelElement(
          text: item.label!.text!,
          anchor: labels[item]!,
          defaultAlign:
              coord.transposed ? Alignment.centerRight : Alignment.topCenter,
          style: item.label!.style));
    }
  }
  return labelElements;
}

/// The shape for the line mark.
///
/// See also:
///
/// - [LineMark], which this shape is for.
abstract class LineShape extends FunctionShape {
  @override
  double get defaultSize => 2;
}

/// A basic line shape.
class BasicLineShape extends LineShape {
  /// Creates a basic line shape.
  BasicLineShape({
    this.smooth = false,
    this.loop = false,
    this.stepped = false,
    this.dash,
  });

  /// Whether this line is smooth.
  final bool smooth;

  /// Whether to connect the last point to the first point.
  ///
  /// It is usefull in the polar coordinate.
  final bool loop;

  /// Whether this line is stepped.
  final bool stepped;

  /// The circular array of dash offsets and lengths.
  ///
  /// For example, the array `[5, 10]` would result in dashes 5 pixels long
  /// followed by blank spaces 10 pixels long.  The array `[5, 10, 5]` would
  /// result in a 5 pixel dash, a 10 pixel gap, a 5 pixel dash, a 5 pixel gap,
  /// a 10 pixel dash, etc.
  final List<double>? dash;

  @override
  bool equalTo(Object other) =>
      other is BasicLineShape &&
      smooth == other.smooth &&
      loop == other.loop &&
      stepped == other.stepped &&
      deepCollectionEquals(dash, other.dash);

  @override
  List<MarkElement> drawGroupPrimitives(
    List<Attributes> group,
    CoordConv coord,
    Offset origin,
  ) {
    assert(!(coord is PolarCoordConv && coord.transposed));

    final contours = <List<Offset>>[];

    var currentContour = <Offset>[];
    for (var item in group) {
      assert(item.shape is BasicLineShape);

      if (item.position.last.dy.isFinite) {
        final point = coord.convert(item.position.last);
        currentContour.add(point);
      } else if (currentContour.isNotEmpty) {
        contours.add(currentContour);
        currentContour = [];
      }
    }
    if (currentContour.isNotEmpty) {
      contours.add(currentContour);
    }

    if (loop &&
        group.first.position.last.dy.isFinite &&
        group.last.position.last.dy.isFinite) {
      // Because lines may be broken by NaN, don't loop by Path.close.
      contours.last.add(contours.first.first);
    }

    final primitives = <MarkElement>[];

    final represent = group.first;
    final strokeWidth = represent.size ?? defaultSize;
    final style =
        getPaintStyle(represent, true, strokeWidth, coord.region, dash);

    for (var contour in contours) {
      if (contour.length == 1) {
        primitives.add(CircleElement(
            center: contour[0],
            radius: strokeWidth / 2,
            style: style));
      } else if (smooth) {
        primitives.add(SplineElement(
            start: contour.first,
            cubics: getCubicControls(contour, false, true),
            style: style));
      } else {
        primitives.add(PolylineElement(
            points: stepped ? getSteppedPoints(contour) : contour,
            style: style));
      }
    }

    return primitives;
  }

  @override
  List<MarkElement> drawGroupLabels(
          List<Attributes> group, CoordConv coord, Offset origin) =>
      drawLineLabels(group, coord, origin);
}

class MultiColoredLineShape extends LineShape {
  /// Creates a basic line shape.
  MultiColoredLineShape({
    this.smooth = false,
    this.loop = false,
    this.dash,
  });

  /// Whether this line is smooth.
  final bool smooth;

  /// Whether to connect the last point to the first point.
  ///
  /// It is usefull in the polar coordinate.
  final bool loop;

  /// The circular array of dash offsets and lengths.
  ///
  /// For example, the array `[5, 10]` would result in dashes 5 pixels long
  /// followed by blank spaces 10 pixels long.  The array `[5, 10, 5]` would
  /// result in a 5 pixel dash, a 10 pixel gap, a 5 pixel dash, a 5 pixel gap,
  /// a 10 pixel dash, etc.
  final List<double>? dash;

  @override
  bool equalTo(Object other) =>
      other is MultiColoredLineShape &&
      smooth == other.smooth &&
      loop == other.loop &&
      deepCollectionEquals(dash, other.dash);

  @override
  List<MarkElement> drawGroupPrimitives(
    List<Attributes> group,
    CoordConv coord,
    Offset origin,
  ) {
    assert(!(coord is PolarCoordConv && coord.transposed));

    final primitives = <MarkElement>[];
    final represent = group.first;
    final defaultSize = represent.size ?? this.defaultSize;

    List<Offset> currentBatch = [];
    Color? currentColor;

    void addBatchToPath(bool isLastBatch) {
      if (currentBatch.length < 2) return;

      if (smooth) {
        primitives.add(SplineElement(
          start: currentBatch.first,
          cubics: getCubicControls(currentBatch, false, isLastBatch),
          style: PaintStyle(
            strokeColor: currentColor,
            strokeWidth: defaultSize,
            elevation: represent.elevation,
            gradientBounds: coord.region,
            dash: dash,
          ),
        ));
      } else {
        primitives.add(PolylineElement(
          points: currentBatch,
          style: PaintStyle(
            strokeColor: currentColor,
            strokeWidth: defaultSize,
            elevation: represent.elevation,
            gradientBounds: coord.region,
            dash: dash,
          ),
        ));
      }
    }

    for (int i = 0; i < group.length; i++) {
      final item = group[i];
      assert(item.shape is MultiColoredLineShape);

      final y = item.position.last.dy;
      if (y.isFinite) {
        final point = coord.convert(item.position.last);

        if (currentColor != item.color) {
          if (currentBatch.isNotEmpty) {
            currentBatch
                .add(point); // Add this point to complete the previous segment
            addBatchToPath(false);
            currentBatch = [point]; // Start new batch with this point
          } else {
            currentBatch.add(point);
          }
          currentColor = item.color;
        } else {
          currentBatch.add(point);
        }
      } else {
        if (currentBatch.isNotEmpty) {
          addBatchToPath(true);
        }
        currentBatch = [];
        currentColor = null;
      }
    }

    // Add any remaining points
    if (currentBatch.isNotEmpty) {
      addBatchToPath(true);
    }

    // Handle looping if necessary
    if (loop &&
        group.first.position.last.dy.isFinite &&
        group.last.position.last.dy.isFinite) {
      final firstPoint = coord.convert(group.first.position.last);
      primitives.add(PolylineElement(
        points: [currentBatch.last, firstPoint],
        style: PaintStyle(
          strokeColor: currentColor,
          strokeWidth: defaultSize,
          elevation: represent.elevation,
          gradientBounds: coord.region,
          dash: dash,
        ),
      ));
    }

    return primitives;
  }

  @override
  List<MarkElement> drawGroupLabels(
          List<Attributes> group, CoordConv coord, Offset origin) =>
      drawLineLabels(group, coord, origin);
}
