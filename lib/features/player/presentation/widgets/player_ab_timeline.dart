import 'package:flutter/material.dart';

/// Loop playback above, full-video AB selection below.
class PlayerAbTimeline extends StatelessWidget {
  const PlayerAbTimeline({
    required this.seekBar,
    required this.durationMs,
    required this.positionMs,
    required this.startMs,
    required this.endMs,
    required this.onRangeChanged,
    required this.onSeekPosition,
    required this.onClear,
    this.fullscreen = false,
    super.key,
  });

  final Widget seekBar;
  final int durationMs;
  final int positionMs;
  final int? startMs;
  final int? endMs;
  final void Function(int start, int end) onRangeChanged;
  final ValueChanged<int> onSeekPosition;
  final VoidCallback onClear;
  final bool fullscreen;

  static String timeLabel(int milliseconds) {
    final int seconds = milliseconds ~/ 1000;
    final String fraction = ((milliseconds % 1000) ~/ 100).toString();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}.$fraction';
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRange =
        startMs != null && endMs != null && endMs! > startMs! && durationMs > 0;
    if (!hasRange) return seekBar;
    final Color color = fullscreen ? Colors.white : const Color(0xFF216B47);
    final int length = endMs! - startMs!;
    final int elapsed = (positionMs - startMs!).clamp(0, length);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: 32,
          child: Row(
            children: <Widget>[
              Text(
                '本轮 ${timeLabel(elapsed)}',
                style: TextStyle(color: color, fontSize: 11),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: color,
                    thumbColor: color,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    key: const ValueKey<String>('player-loop-progress'),
                    value: elapsed / length,
                    semanticFormatterCallback: (double value) =>
                        '本轮 ${timeLabel((value * length).round())}，共 ${timeLabel(length)}',
                    onChanged: (double value) => onSeekPosition(
                      (startMs! + (value * length).round()).clamp(
                        startMs!,
                        endMs! - 1,
                      ),
                    ),
                  ),
                ),
              ),
              Text(
                timeLabel(length),
                style: TextStyle(color: color, fontSize: 11),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              rangeThumbShape: const RoundRangeSliderThumbShape(
                enabledThumbRadius: 8,
              ),
              rangeTrackShape: _LoopProgressTrackShape(
                progress: elapsed / length,
              ),
              // Pixel spacing becomes a large time limit in long videos.
              // Keep only the state's positive-duration constraint.
              minThumbSeparation: 0,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: Overlay.wrap(
              alwaysSizeToContent: true,
              clipBehavior: Clip.none,
              child: _LockedRangeSlider(
                key: const ValueKey<String>('player-ab-range'),
                max: durationMs.toDouble(),
                values: RangeValues(
                  startMs!.clamp(0, durationMs).toDouble(),
                  endMs!.clamp(0, durationMs).toDouble(),
                ),
                labels: RangeLabels(
                  'A ${timeLabel(startMs!)}',
                  'B ${timeLabel(endMs!)}',
                ),
                semanticFormatterCallback: (double value) =>
                    timeLabel(value.round()),
                onChanged: (RangeValues values) {
                  if (values.end.round() > values.start.round()) {
                    onRangeChanged(values.start.round(), values.end.round());
                  }
                },
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '全片  A ${timeLabel(startMs!)}  —  B ${timeLabel(endMs!)}',
              style: TextStyle(color: color, fontSize: 11),
            ),
            IconButton(
              key: const ValueKey<String>('player-clear-ab'),
              tooltip: '退出 AB 循环',
              visualDensity: VisualDensity.compact,
              color: color,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}

/// Paint playback progress on the selected segment of the existing track.
class _LoopProgressTrackShape extends RoundedRectRangeSliderTrackShape {
  const _LoopProgressTrackShape({required this.progress});

  final double progress;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset startThumbCenter,
    required Offset endThumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      startThumbCenter: startThumbCenter,
      endThumbCenter: endThumbCenter,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final Offset playhead = Offset.lerp(
      startThumbCenter,
      endThumbCenter,
      progress,
    )!;
    final Paint progressPaint = Paint()
      ..color = const Color(0xFF216B47)
      ..strokeWidth =
          (sliderTheme.trackHeight ?? 6) + additionalActiveTrackHeight;
    context.canvas.drawLine(startThumbCenter, playhead, progressPaint);
  }
}

/// Select the endpoint at pointer-down, before Flutter's drag slop is crossed.
/// Otherwise a fast drag toward the other endpoint can select the wrong thumb.
class _LockedRangeSlider extends StatefulWidget {
  const _LockedRangeSlider({
    required this.max,
    required this.values,
    required this.labels,
    required this.semanticFormatterCallback,
    required this.onChanged,
    super.key,
  });
  final double max;
  final RangeValues values;
  final RangeLabels labels;
  final SemanticFormatterCallback semanticFormatterCallback;
  final ValueChanged<RangeValues> onChanged;

  @override
  State<_LockedRangeSlider> createState() => _LockedRangeSliderState();
}

class _LockedRangeSliderState extends State<_LockedRangeSlider> {
  double? _pointerX;
  Thumb? _thumb;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) => Listener(
      onPointerDown: (PointerDownEvent event) {
        _pointerX = event.localPosition.dx;
        _thumb = null;
      },
      onPointerUp: (_) {
        _pointerX = null;
        _thumb = null;
      },
      onPointerCancel: (_) {
        _pointerX = null;
        _thumb = null;
      },
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbSelector:
              (
                TextDirection direction,
                RangeValues values,
                double tapValue,
                Size thumbSize,
                Size trackSize,
                double dx,
              ) {
                if (_thumb != null) return _thumb;
                double value = _pointerX == null
                    ? tapValue
                    : (_pointerX! -
                              (constraints.maxWidth - trackSize.width) / 2) /
                          trackSize.width;
                if (_pointerX != null && direction == TextDirection.rtl) {
                  value = 1 - value;
                }
                final double startDistance = (value - values.start).abs();
                final double endDistance = (value - values.end).abs();
                if ((startDistance - endDistance).abs() * trackSize.width < 1) {
                  if (dx == 0) return null;
                  _thumb = (direction == TextDirection.ltr ? dx < 0 : dx > 0)
                      ? Thumb.start
                      : Thumb.end;
                } else {
                  _thumb = startDistance < endDistance
                      ? Thumb.start
                      : Thumb.end;
                }
                return _thumb;
              },
        ),
        child: RangeSlider(
          max: widget.max,
          values: widget.values,
          labels: widget.labels,
          semanticFormatterCallback: widget.semanticFormatterCallback,
          onChanged: widget.onChanged,
        ),
      ),
    ),
  );
}
