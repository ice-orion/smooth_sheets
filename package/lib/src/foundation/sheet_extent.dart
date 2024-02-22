import 'package:flutter/widgets.dart';
import 'package:smooth_sheets/src/foundation/sheet_activity.dart';
import 'package:smooth_sheets/src/foundation/sheet_controller.dart';
import 'package:smooth_sheets/src/foundation/sheet_physics.dart';
import 'package:smooth_sheets/src/internal/double_utils.dart';

/// Visible area of the sheet.
abstract interface class Extent {
  const factory Extent.pixels(double pixels) = FixedExtent;
  const factory Extent.proportional(double size) = ProportionalExtent;

  double resolve(Size contentDimensions);
}

class ProportionalExtent implements Extent {
  const ProportionalExtent(this.size) : assert(size >= 0);

  final double size;

  @override
  double resolve(Size contentDimensions) => contentDimensions.height * size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProportionalExtent &&
          runtimeType == other.runtimeType &&
          size == other.size);

  @override
  int get hashCode => Object.hash(runtimeType, size);
}

class FixedExtent implements Extent {
  const FixedExtent(this.pixels) : assert(pixels >= 0);

  final double pixels;

  @override
  double resolve(Size contentDimensions) => pixels;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FixedExtent &&
          runtimeType == other.runtimeType &&
          pixels == other.pixels);

  @override
  int get hashCode => Object.hash(runtimeType, pixels);
}

// TODO: Mention in the documentation that this notifier may notify the listeners during build or layout phase.
abstract class SheetExtent with ChangeNotifier, MaybeSheetMetrics {
  SheetExtent({
    required this.context,
    required this.physics,
    required this.minExtent,
    required this.maxExtent,
  }) {
    _metrics = _SheetMetricsRef(this);
    beginActivity(IdleSheetActivity());
  }

  final SheetContext context;
  final SheetPhysics physics;
  final Extent minExtent;
  final Extent maxExtent;

  SheetActivity? _activity;
  double? _minPixels;
  double? _maxPixels;
  Size? _contentDimensions;
  ViewportDimensions? _viewportDimensions;

  late final _SheetMetricsRef _metrics;
  SheetMetrics get metrics => _metrics;

  SheetMetricsSnapshot get snapshot {
    assert(hasPixels);
    return SheetMetricsSnapshot.from(metrics);
  }

  @override
  double? get pixels => _activity!.pixels;

  @override
  double? get minPixels => _minPixels;

  @override
  double? get maxPixels => _maxPixels;

  @override
  Size? get contentDimensions => _contentDimensions;

  @override
  ViewportDimensions? get viewportDimensions => _viewportDimensions;

  SheetActivity get activity => _activity!;

  void _invalidateBoundaryConditions() {
    _minPixels = minExtent.resolve(contentDimensions!);
    _maxPixels = maxExtent.resolve(contentDimensions!);
  }

  @mustCallSuper
  void takeOver(SheetExtent other) {
    if (other.viewportDimensions != null) {
      applyNewViewportDimensions(other.viewportDimensions!);
    }
    if (other.contentDimensions != null) {
      applyNewContentDimensions(other.contentDimensions!);
    }

    _activity!.takeOver(other._activity!);
  }

  @mustCallSuper
  void applyNewContentDimensions(Size contentDimensions) {
    if (_contentDimensions != contentDimensions) {
      _oldContentDimensions = _contentDimensions;
      _contentDimensions = contentDimensions;
      _invalidateBoundaryConditions();
      _activity!.didChangeContentDimensions(_oldContentDimensions);
    }
  }

  @mustCallSuper
  void applyNewViewportDimensions(ViewportDimensions viewportDimensions) {
    if (_viewportDimensions != viewportDimensions) {
      final oldPixels = pixels;
      final oldViewPixels = viewPixels;
      _oldViewportDimensions = _viewportDimensions;
      _viewportDimensions = viewportDimensions;
      _activity!.didChangeViewportDimensions(_oldViewportDimensions);
      if (oldPixels != pixels || oldViewPixels != viewPixels) {
        notifyListeners();
      }
    }
  }

  Size? _oldContentDimensions;
  ViewportDimensions? _oldViewportDimensions;
  int _markAsDimensionsWillChangeCallCount = 0;

  @mustCallSuper
  void markAsDimensionsWillChange() {
    assert(() {
      if (_markAsDimensionsWillChangeCallCount == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          assert(
            _markAsDimensionsWillChangeCallCount == 0,
            _markAsDimensionsWillChangeCallCount > 0
                ? 'markAsDimensionsWillChange() was called more times'
                    'than markAsDimensionsChanged() in a frame.'
                : 'markAsDimensionsChanged() was called more times'
                    'than markAsDimensionsWillChange() in a frame.',
          );
        });
      }
      return true;
    }());

    _markAsDimensionsWillChangeCallCount++;
  }

  @mustCallSuper
  void markAsDimensionsChanged() {
    assert(
      _markAsDimensionsWillChangeCallCount > 0,
      'markAsDimensionsChanged() called without '
      'a matching call to markAsDimensionsWillChange().',
    );

    _markAsDimensionsWillChangeCallCount--;
    if (_markAsDimensionsWillChangeCallCount == 0) {
      onDimensionsFinalized();
    }
  }

  @mustCallSuper
  void onDimensionsFinalized() {
    assert(
      _markAsDimensionsWillChangeCallCount == 0,
      'Do not call this method until all dimensions changes are finalized.',
    );

    _activity!.didFinalizeDimensions(
      _oldContentDimensions,
      _oldViewportDimensions,
    );

    _oldContentDimensions = null;
    _oldViewportDimensions = null;
  }

  @mustCallSuper
  void beginActivity(SheetActivity activity) {
    final oldActivity = _activity?..removeListener(notifyListeners);
    // Update the current activity before initialization.
    _activity = activity;

    activity
      ..initWith(this)
      ..addListener(notifyListeners);

    if (oldActivity != null) {
      activity.takeOver(oldActivity);
      oldActivity.dispose();
    }
  }

  void goIdle() {
    beginActivity(IdleSheetActivity());
  }

  void goBallistic(double velocity) {
    assert(hasPixels);
    final simulation = physics.createBallisticSimulation(velocity, metrics);
    if (simulation != null) {
      goBallisticWith(simulation);
    } else {
      goIdle();
    }
  }

  void goBallisticWith(Simulation simulation) {
    assert(hasPixels);
    beginActivity(BallisticSheetActivity(simulation: simulation));
  }

  void settle() {
    assert(hasPixels);
    final simulation = physics.createSettlingSimulation(metrics);
    if (simulation != null) {
      // TODO: Begin a SettlingSheetActivity
      goBallisticWith(simulation);
    } else {
      goIdle();
    }
  }

  @override
  void dispose() {
    activity
      ..removeListener(notifyListeners)
      ..dispose();

    super.dispose();
  }

  Future<void> animateTo(
    Extent newExtent, {
    Curve curve = Curves.easeInOut,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    assert(hasPixels);
    final destination = newExtent.resolve(contentDimensions!);
    if (pixels == destination) {
      return Future.value();
    } else {
      final activity = AnimatedSheetActivity(
        from: pixels!,
        to: destination,
        duration: duration,
        curve: curve,
      );

      beginActivity(activity);
      return activity.done;
    }
  }
}

class ViewportDimensions {
  const ViewportDimensions({
    required this.width,
    required this.height,
    required this.insets,
  });

  final double width;
  final double height;
  final EdgeInsets insets;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ViewportDimensions &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height &&
          insets == other.insets);

  @override
  int get hashCode => Object.hash(
        runtimeType,
        width,
        height,
        insets,
      );
}

mixin MaybeSheetMetrics {
  double? get pixels;
  double? get minPixels;
  double? get maxPixels;
  Size? get contentDimensions;
  ViewportDimensions? get viewportDimensions;

  double? get viewPixels => switch ((pixels, viewportDimensions)) {
        (final pixels?, final viewport?) => pixels + viewport.insets.bottom,
        _ => null,
      };

  double? get minViewPixels => switch ((minPixels, viewportDimensions)) {
        (final minPixels?, final viewport?) =>
          minPixels + viewport.insets.bottom,
        _ => null,
      };

  double? get maxViewPixels => switch ((maxPixels, viewportDimensions)) {
        (final maxPixels?, final viewport?) =>
          maxPixels + viewport.insets.bottom,
        _ => null,
      };

  bool get hasPixels =>
      pixels != null &&
      minPixels != null &&
      maxPixels != null &&
      contentDimensions != null &&
      viewportDimensions != null;

  bool get isPixelsInBounds =>
      hasPixels && pixels!.isInBounds(minPixels!, maxPixels!);

  bool get isPixelsOutOfBounds => !isPixelsInBounds;

  @override
  String toString() => (
        hasPixels: hasPixels,
        pixels: pixels,
        minPixels: minPixels,
        maxPixels: maxPixels,
        viewPixels: viewPixels,
        minViewPixels: minViewPixels,
        maxViewPixels: maxViewPixels,
        contentDimensions: contentDimensions,
        viewportDimensions: viewportDimensions,
      ).toString();
}

mixin SheetMetrics on MaybeSheetMetrics {
  @override
  double get pixels;

  @override
  double get minPixels;

  @override
  double get maxPixels;

  @override
  Size get contentDimensions;

  @override
  ViewportDimensions get viewportDimensions;

  @override
  double get viewPixels => super.viewPixels!;

  @override
  double get minViewPixels => super.minViewPixels!;

  @override
  double get maxViewPixels => super.maxViewPixels!;
}

class SheetMetricsSnapshot with MaybeSheetMetrics, SheetMetrics {
  const SheetMetricsSnapshot({
    required this.pixels,
    required this.minPixels,
    required this.maxPixels,
    required this.contentDimensions,
    required this.viewportDimensions,
  });

  factory SheetMetricsSnapshot.from(SheetMetrics other) {
    return SheetMetricsSnapshot(
      pixels: other.pixels,
      minPixels: other.minPixels,
      maxPixels: other.maxPixels,
      contentDimensions: other.contentDimensions,
      viewportDimensions: other.viewportDimensions,
    );
  }

  @override
  final double pixels;

  @override
  final double minPixels;

  @override
  final double maxPixels;

  @override
  final Size contentDimensions;

  @override
  final ViewportDimensions viewportDimensions;

  @override
  bool get hasPixels => true;

  SheetMetricsSnapshot copyWith({
    double? pixels,
    double? minPixels,
    double? maxPixels,
    Size? contentDimensions,
    ViewportDimensions? viewportDimensions,
  }) {
    return SheetMetricsSnapshot(
      pixels: pixels ?? this.pixels,
      minPixels: minPixels ?? this.minPixels,
      maxPixels: maxPixels ?? this.maxPixels,
      contentDimensions: contentDimensions ?? this.contentDimensions,
      viewportDimensions: viewportDimensions ?? this.viewportDimensions,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SheetMetricsSnapshot &&
        other.runtimeType == runtimeType &&
        other.pixels == pixels &&
        other.minPixels == minPixels &&
        other.maxPixels == maxPixels &&
        other.contentDimensions == contentDimensions &&
        other.viewportDimensions == viewportDimensions;
  }

  @override
  int get hashCode => Object.hash(
        runtimeType,
        pixels,
        minPixels,
        maxPixels,
        contentDimensions,
        viewportDimensions,
      );

  @override
  String toString() => (
        pixels: pixels,
        minPixels: minPixels,
        maxPixels: maxPixels,
        contentDimensions: contentDimensions,
        viewportDimensions: viewportDimensions,
      ).toString();
}

class _SheetMetricsRef with MaybeSheetMetrics, SheetMetrics {
  _SheetMetricsRef(this._source);

  final MaybeSheetMetrics _source;

  @override
  double get pixels => _source.pixels!;

  @override
  double get minPixels => _source.minPixels!;

  @override
  double get maxPixels => _source.maxPixels!;

  @override
  Size get contentDimensions => _source.contentDimensions!;

  @override
  ViewportDimensions get viewportDimensions => _source.viewportDimensions!;
}

abstract class SheetContext {
  TickerProvider get vsync;
  BuildContext? get notificationContext;
}

abstract class SheetExtentFactory {
  const SheetExtentFactory();
  SheetExtent create({required SheetContext context});
}

class SheetExtentScope extends StatefulWidget {
  const SheetExtentScope({
    super.key,
    required this.factory,
    this.controller,
    this.onExtentChanged,
    required this.child,
  });

  final SheetController? controller;
  final SheetExtentFactory factory;
  final ValueChanged<SheetExtent?>? onExtentChanged;
  final Widget child;

  @override
  State<SheetExtentScope> createState() => _SheetExtentScopeState();

  // TODO: Add 'useRoot' option
  static SheetExtent? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedSheetExtent>()
        ?.extent;
  }

  static SheetExtent of(BuildContext context) {
    return maybeOf(context)!;
  }
}

class _SheetExtentScopeState extends State<SheetExtentScope>
    with TickerProviderStateMixin
    implements SheetContext {
  late SheetExtent _extent;

  @override
  TickerProvider get vsync => this;

  @override
  BuildContext? get notificationContext => mounted ? context : null;

  @override
  void initState() {
    super.initState();
    _extent = widget.factory.create(context: this);
    widget.controller?.attach(_extent);
    widget.onExtentChanged?.call(_extent);
  }

  @override
  void dispose() {
    widget.onExtentChanged?.call(null);
    widget.controller?.detach(_extent);
    _extent.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SheetExtentScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldExtent = _extent;
    if (widget.factory != oldWidget.factory) {
      _extent = widget.factory.create(context: this)..takeOver(_extent);
      widget.onExtentChanged?.call(_extent);
    }

    if (widget.controller != oldWidget.controller || _extent != oldExtent) {
      oldWidget.controller?.detach(oldExtent);
      widget.controller?.attach(_extent);
    }

    if (oldExtent != _extent) {
      oldExtent.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedSheetExtent(
      extent: _extent,
      child: widget.child,
    );
  }
}

class _InheritedSheetExtent extends InheritedWidget {
  const _InheritedSheetExtent({
    required this.extent,
    required super.child,
  });

  final SheetExtent extent;

  @override
  bool updateShouldNotify(_InheritedSheetExtent oldWidget) =>
      extent != oldWidget.extent;
}
