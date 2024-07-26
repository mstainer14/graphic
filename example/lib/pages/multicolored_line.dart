import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:graphic/graphic.dart';
import 'package:intl/intl.dart';

import '../data.dart';

final _monthDayFormat = DateFormat('MM-dd');

class MultiColorLinePage extends StatefulWidget {
  const MultiColorLinePage({Key? key}) : super(key: key);

  @override
  State<MultiColorLinePage> createState() => _MultiColorLinePageState();
}

class _MultiColorLinePageState extends State<MultiColorLinePage> {
  late final StreamController<GestureEvent> _localGestureStream;

  final int noOfGraphs = 3;
  bool syncGraphs = true;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _localGestureStream = StreamController<GestureEvent>.broadcast();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Multicolored Line'),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 5),
                child: const Text(
                  'Multicolored line chart',
                  style: TextStyle(fontSize: 20),
                ),
              ),
              for (int i = 0; i < noOfGraphs; i++)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 550,
                  height: 500,
                  child: Chart(
                    gestureStream: syncGraphs ? _localGestureStream : null,
                    data: generateRandomTimeSeriesSales(150),
                    variables: {
                      'time': Variable(
                        accessor: (ColorTimeSeriesSales datum) => datum.time,
                        scale: TimeScale(
                          formatter: (time) => _monthDayFormat.format(time),
                        ),
                      ),
                      'sales': Variable(
                        accessor: (ColorTimeSeriesSales datum) => datum.sales,
                      ),
                      'color': Variable(
                          accessor: (ColorTimeSeriesSales datum) =>
                              datum.color.value),
                    },
                    marks: [
                      LineMark(
                        shape: ShapeEncode(value: MultiColoredLineShape()),
                        color: ColorEncode(
                          encoder: (tuple) {
                            return Color(tuple['color']);
                          },
                        ),
                      )
                    ],
                    coord: RectCoord(
                      color: const Color(0xffdddddd),
                      horizontalRangeUpdater: _getRangeUpdate(true, false),
                    ),
                    axes: [
                      Defaults.horizontalAxis,
                      Defaults.verticalAxis,
                    ],
                    selections: {
                      'tooltipTouch': PointSelection(
                        on: {
                          GestureType.scaleUpdate,
                          GestureType.tapDown,
                          GestureType.longPressMoveUpdate,
                        },
                        devices: {PointerDeviceKind.touch},
                      ),
                      'groupTouch': PointSelection(
                        on: {
                          GestureType.scaleUpdate,
                          GestureType.tapDown,
                          GestureType.longPressMoveUpdate
                        },
                        devices: {PointerDeviceKind.touch},
                      ),
                    },
                    tooltip: TooltipGuide(
                      variables: ['time', 'sales'],
                      selections: {'tooltipTouch', 'tooltipMouse'},
                      followPointer: [false, true],
                      align: Alignment.topLeft,
                      offset: const Offset(-20, -20),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// This method is used to calcuate the range update on the sensor data graphs
  /// It will allow the user to pan, zoom and scroll the graphs.
  EventUpdater<List<double>> _getRangeUpdate(
    bool isHorizontal,
    bool focusMouseScale,
  ) {
    return (
      List<double> initialValue,
      List<double> previousBoundaries,
      Event event,
    ) {
      if (event is GestureEvent) {
        final Gesture gesture = event.gesture;

        if (gesture.type == GestureType.scaleUpdate) {
          final ScaleUpdateDetails details =
              gesture.details as ScaleUpdateDetails;

          if (details.pointerCount == 1) {
            /// Panning.

            final deltaRatio = isHorizontal
                ? gesture.preScaleDetail!.focalPointDelta.dx
                : -gesture.preScaleDetail!.focalPointDelta.dy;
            final delta = deltaRatio /
                (isHorizontal
                    ? gesture.chartSize.width
                    : gesture.chartSize.height);

            // Prevent the user from scrolling out of bounds on the left side.
            if (previousBoundaries.first >= 0 && !delta.isNegative) {
              return [0, previousBoundaries.last];
            }

            // Prevent the user from scrolling out of bounds on the right side.
            if (previousBoundaries.last <= 1 && delta.isNegative) {
              return [previousBoundaries.first, previousBoundaries.last];
            }

            return [
              previousBoundaries.first + delta,
              previousBoundaries.last + delta
            ];
          }

          // TODO: Add the below clause back to enable touch zooming on the graph.
          else {
            /// Scaling.

            /// Compute scaling strength [delta]
            final double previousScale = gesture.preScaleDetail!.scale;
            final double scale = details.scale;

            late final double deltaRatio;
            if (previousScale == 0) {
              deltaRatio = 0;
            } else {
              deltaRatio = scale - previousScale;
            }
            final double previousRange =
                previousBoundaries.last - previousBoundaries.first;
            final double delta = deltaRatio * previousRange;

            /// Special case of the graph bounds perfectly matching the viewport.
            if (previousBoundaries.first.abs() +
                    previousBoundaries.last.abs() -
                    1 ==
                0) {
              return [
                previousBoundaries.first - delta,
                previousBoundaries.last + delta
              ];
            }

            /// To prevent the graph from moving out of the viewport when zoomed we define a focus point in the
            /// viewport (e.g. 0.5 for the center of the viewport) and we weigh the movement of the returned first and last
            /// boundary of the graph by a value proportional to the distance of the boundary to the focus point.
            const double focusPoint = 0.5;
            double computeBoundaryRatio(bool isFirstBound) {
              final double boundaryValue = isFirstBound
                  ? previousBoundaries.first
                  : previousBoundaries.last;
              return (boundaryValue - focusPoint).abs() /
                  (previousBoundaries.first.abs() +
                      previousBoundaries.last.abs() -
                      focusPoint * 2);
            }

            double normalizeBoundaryRatio(bool isFirstBound,
                double newBoundaryStart, double newBoundaryEnd) {
              final double newBoundaryValue =
                  isFirstBound ? newBoundaryStart : newBoundaryEnd;
              return newBoundaryValue / (newBoundaryStart + newBoundaryEnd);
            }

            final double unnormalizedFirstBoundaryRatio =
                computeBoundaryRatio(true);
            final double unnormalizedLastBoundaryRatio =
                computeBoundaryRatio(false);

            /// We normalize the final ratio to make sure the sum of the 2 ratios is always 1 (which keeps the zoom strength constant).
            final double firstBoundaryRatio = normalizeBoundaryRatio(true,
                unnormalizedFirstBoundaryRatio, unnormalizedLastBoundaryRatio);
            final double lastBoundaryRatio = normalizeBoundaryRatio(false,
                unnormalizedFirstBoundaryRatio, unnormalizedLastBoundaryRatio);

            final double newFirstBoundary =
                previousBoundaries.first - firstBoundaryRatio * delta;
            final double newLastBoundary =
                previousBoundaries.last + lastBoundaryRatio * delta;

            if (newFirstBoundary > initialValue.first && newLastBoundary < 1) {
              print('Both');
              return [previousBoundaries.first, previousBoundaries.last];
            }

            if (newFirstBoundary > initialValue.first) {
              print('First');
              return [initialValue.first, newLastBoundary];
            }

            // if (newLastBoundary > (initialValue.last / 2) * 10) {
            //   print('3');
            //   // return [newFirstBoundary, (initialValue.last / 2) * 10];
            // }

            return [newFirstBoundary, newLastBoundary];
          }
        } else if (gesture.type == GestureType.scroll) {
          const step = -0.1;
          final scrollDelta = gesture.details as Offset;
          final deltaRatio = scrollDelta.dy == 0
              ? 0.0
              : scrollDelta.dy > 0
                  ? (step / 2)
                  : (-step / 2);
          final preRange = previousBoundaries.last - previousBoundaries.first;
          final delta = deltaRatio * preRange;
          if (!focusMouseScale) {
            return [
              previousBoundaries.first - delta,
              previousBoundaries.last + delta
            ];
          } else {
            double mousePos;
            if (isHorizontal) {
              mousePos = (gesture.localPosition.dx - 39.5) /
                  (gesture.chartSize.width - 51);
            } else {
              mousePos = 1 -
                  (gesture.localPosition.dy - 5) /
                      (gesture.chartSize.height - 25);
            }
            mousePos = (mousePos - previousBoundaries.first) /
                (previousBoundaries.last - previousBoundaries.first);
            return [
              previousBoundaries.first - delta * 2 * mousePos,
              previousBoundaries.last + delta * 2 * (1 - mousePos)
            ];
          }
        } else if (gesture.type == GestureType.doubleTap) {
          return initialValue;
        }
      }

      return previousBoundaries;
    };
  }
}
