// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/rendering.dart';

import 'basic.dart';
import 'framework.dart';
import 'scrollable.dart';
import 'scroll_behavior.dart';

/// Provides children for [LazyBlock] or [LazyBlockViewport].
///
/// See also [LazyBlockBuilder] for an implementation of LazyBlockDelegate based
/// on an [IndexedBuilder] closure.
abstract class LazyBlockDelegate {
  /// Abstract const constructor. This constructor enables subclasses to provide
  /// const constructors so that they can be used in const expressions.
  const LazyBlockDelegate();

  /// Returns a widget representing the item with the given index.
  ///
  /// This function might be called with index parameters in any order. This
  /// function should return null for indices that exceed the number of children
  /// provided by this delegate. If this function must not return a null value
  /// for an index if it previously returned a non-null value for that index or
  /// a larger index.
  ///
  /// This function might be called during the build or layout phases of the
  /// pipeline.
  ///
  /// The returned widget might or might not be cached by [LazyBlock]. See
  /// [shouldRebuild] for details about how to evict the cache.
  Widget buildItem(BuildContext context, int index);

  /// Whether [LazyBlock] should evict its cache of widgets returned by [buildItem].
  ///
  /// When a [LazyBlock] receives a new configuration with a new delegate, it
  /// evicts its cache of widgets if (1) the new configuration has a delegate
  /// with a different runtimeType than the old delegate, or (2) the
  /// [shouldRebuild] method of the new delegate returns true when passed the
  /// old delgate.
  ///
  /// When calling this function, [LazyBlock] will always pass an argument that
  /// matches the runtimeType of the receiver.
  bool shouldRebuild(LazyBlockDelegate oldDelegate);
}

/// Uses an [IndexedBuilder] to provide children for [LazyBlock].
///
/// A LazyBlockBuilder rebuilds the children whenever the [LazyBlock] is
/// rebuilt, similar to the behavior of [Builder].
///
/// See also [LazyBlockViewport].
class LazyBlockBuilder extends LazyBlockDelegate {
  /// Creates a LazyBlockBuilder based on the given builder.
  LazyBlockBuilder({ this.builder }) {
    assert(builder != null);
  }

  /// Returns a widget representing the item with the given index.
  ///
  /// This function might be called with index parameters in any order. This
  /// function should return null for indices that exceed the number of children
  /// provided by this delegate. If this function must not return a null value
  /// for an index if it previously returned a non-null value for that index or
  /// a larger index.
  ///
  /// This function might be called during the build or layout phases of the
  /// pipeline.
  final IndexedBuilder builder;

  @override
  Widget buildItem(BuildContext context, int index) => builder(context, index);

  @override
  bool shouldRebuild(LazyBlockDelegate oldDelegate) => true;
}

/// An infinite scrolling list of variable height children.
///
/// [LazyBlock] is a general-purpose scrollable list for a large (or infinite)
/// number of children that might not all have the same height. Rather than
/// materializing all of its children, [LazyBlock] asks its [delegate] to build
/// child widgets lazily to fill its viewport. [LazyBlock] caches the widgets
/// it obtains from the delegate as long as they're visible. (See
/// [LazyBlockDelegate.shouldRebuild] for details about how to evict the cache.)
///
/// [LazyBlock] works by dead reckoning changes to its [scrollOffset] from the
/// top of the first child that is visible in its viewport. If the children
/// above the first visible child change size, the [scrollOffset] might not
/// return to zero when the [LazyBlock] is scrolled all the way back to the
/// start because the height of each child will be subtracted incrementally from
/// the current scroll position. For this reason, making large changes to the
/// [scrollOffset] is expensive because [LazyBlock] computes the size of every
/// child between the old scroll offset and the new scroll offset.
///
/// Prefer [ScrollableList] when all the children have the same height because
/// it can use that property to be more efficient. Prefer [ScrollableViewport]
/// when there is only one child.
class LazyBlock extends Scrollable {
  LazyBlock({
    Key key,
    double initialScrollOffset,
    Axis scrollDirection: Axis.vertical,
    ScrollListener onScroll,
    SnapOffsetCallback snapOffsetCallback,
    this.delegate
  }) : super(
    key: key,
    initialScrollOffset: initialScrollOffset,
    scrollDirection: scrollDirection,
    onScroll: onScroll,
    snapOffsetCallback: snapOffsetCallback
  );

  /// Provides children for this widget.
  ///
  /// See [LazyBlockDelegate] for details.
  final LazyBlockDelegate delegate;

  @override
  ScrollableState<LazyBlock> createState() => new _LazyBlockState();
}

class _LazyBlockState extends ScrollableState<LazyBlock> {
  @override
  BoundedBehavior createScrollBehavior() => new OverscrollWhenScrollableBehavior();

  @override
  BoundedBehavior get scrollBehavior => super.scrollBehavior;

  void _handleExtentsChanged(double contentExtent, double containerExtent, double minScrollOffset) {
    setState(() {
      didUpdateScrollBehavior(scrollBehavior.updateExtents(
        contentExtent: contentExtent,
        containerExtent: containerExtent,
        minScrollOffset: minScrollOffset,
        scrollOffset: scrollOffset
      ));
    });
  }

  @override
  Widget buildContent(BuildContext context) {
    return new LazyBlockViewport(
      startOffset: scrollOffset,
      mainAxis: config.scrollDirection,
      onExtentsChanged: _handleExtentsChanged,
      delegate: config.delegate
    );
  }
}

/// Signature used by [LazyBlockViewport] to report its interior and exterior dimensions.
typedef void LazyBlockExtentsChangedCallback(double contentExtent, double containerExtent, double minScrollOffset);

/// A viewport on an infinite list of variable height children.
///
/// [LazyBlockViewport] is a a general-purpose viewport for a large (or
/// infinite) number of children that might not all have the same height. Rather
/// than materializing all of its children, [LazyBlockViewport] asks its
/// [delegate] to build child widgets lazily to fill itself. [LazyBlockViewport]
/// caches the widgets it obtains from the delegate as long as they're visible.
/// (See [LazyBlockDelegate.shouldRebuild] for details about how to evict the
/// cache.)
///
/// [LazyBlockViewport] works by dead reckoning changes to its [startOffset]
/// from the top of the first child that is visible in itself. For this reason,
/// making large changes to the [startOffset] is expensive because
/// [LazyBlockViewport] computes the size of every child between the old offset
/// and the new offset.
///
/// Prefer [ListViewport] when all the children have the same height because
/// it can use that property to be more efficient. Prefer [Viewport] when there
/// is only one child.
///
/// For a scrollable version of this widget, see [LazyBlock].
class LazyBlockViewport extends RenderObjectWidget {
  LazyBlockViewport({
    Key key,
    this.startOffset: 0.0,
    this.mainAxis: Axis.vertical,
    this.onExtentsChanged,
    this.delegate
  }) : super(key: key) {
    assert(delegate != null);
  }

  /// The offset of the start of the viewport.
  ///
  /// As the start offset increases, children with larger indices are visible
  /// in the viewport.
  ///
  /// For vertical viewports, the offset is from the top of the viewport. For
  /// horizontal viewports, the offset is from the left of the viewport.
  final double startOffset;

  /// The direction in which the children are permitted to be larger than the viewport
  ///
  /// The children are given layout constraints that are fully unconstrainted
  /// along the main axis (e.g., children can be as tall as it wants if the main
  /// axis is vertical).
  final Axis mainAxis;

  /// Called when the interior or exterior dimensions of the viewport change.
  final LazyBlockExtentsChangedCallback onExtentsChanged;

  /// Provides children for this widget.
  ///
  /// See [LazyBlockDelegate] for details.
  final LazyBlockDelegate delegate;

  @override
  _LazyBlockElement createElement() => new _LazyBlockElement(this);

  @override
  _RenderLazyBlock createRenderObject(BuildContext context) => new _RenderLazyBlock();
}

class _LazyBlockParentData extends ContainerBoxParentDataMixin<RenderBox> { }

class _RenderLazyBlock extends RenderVirtualViewport<_LazyBlockParentData> {
  _RenderLazyBlock({
    Offset paintOffset: Offset.zero,
    Axis mainAxis: Axis.vertical,
    LayoutCallback callback
  }) : super(
    paintOffset: paintOffset,
    mainAxis: mainAxis,
    callback: callback
  );

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LazyBlockParentData)
      child.parentData = new _LazyBlockParentData();
  }

  bool _debugThrowIfNotCheckingIntrinsics() {
    assert(() {
      if (!RenderObject.debugCheckingIntrinsics) {
        throw new FlutterError(
          'LazyBlockViewport does not support returning intrinsic dimensions.\n'
          'Calculating the intrinsic dimensions would require walking the entire '
          'child list, which defeats the entire point of having a lazily-built '
          'list of children.'
        );
      }
      return true;
    });
    return true;
  }

  double getIntrinsicWidth(BoxConstraints constraints) {
    switch (mainAxis) {
      case Axis.horizontal:
        return constraints.constrainWidth(0.0);
      case Axis.vertical:
        assert(_debugThrowIfNotCheckingIntrinsics());
        return constraints.constrainWidth(0.0);
    }
  }

  @override
  double getMinIntrinsicWidth(BoxConstraints constraints) {
    assert(constraints.debugAssertIsNormalized);
    return getIntrinsicWidth(constraints);
  }

  @override
  double getMaxIntrinsicWidth(BoxConstraints constraints) {
    assert(constraints.debugAssertIsNormalized);
    return getIntrinsicWidth(constraints);
  }

  double getIntrinsicHeight(BoxConstraints constraints) {
    switch (mainAxis) {
      case Axis.horizontal:
        return constraints.constrainHeight(0.0);
      case Axis.vertical:
        assert(_debugThrowIfNotCheckingIntrinsics());
        return constraints.constrainHeight(0.0);
    }
  }

  @override
  double getMinIntrinsicHeight(BoxConstraints constraints) {
    assert(constraints.debugAssertIsNormalized);
    return getIntrinsicHeight(constraints);
  }

  @override
  double getMaxIntrinsicHeight(BoxConstraints constraints) {
    assert(constraints.debugAssertIsNormalized);
    return getIntrinsicHeight(constraints);
  }

  @override
  bool get sizedByParent => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performResize() {
    size = constraints.biggest;
  }

  @override
  void performLayout() {
    if (callback != null)
      invokeLayoutCallback(callback);
  }
}

class _LazyBlockElement extends RenderObjectElement {
  _LazyBlockElement(LazyBlockViewport widget) : super(widget);

  @override
  LazyBlockViewport get widget => super.widget;

  @override
  _RenderLazyBlock get renderObject => super.renderObject;

  /// The offset of the top of the first item represented in _children from the top of the item with logical index zero.
  double _firstChildLogicalOffset = 0.0;

  /// The logical index of the first item represented in _children.
  int _firstChildLogicalIndex = 0;

  /// The explicitly represented items.
  List<Element> _children = <Element>[];

  /// The minimum scroll offset used by the scroll behavior.
  ///
  /// Not all the items between the minimum and maximum scroll offsets are
  /// reprsented explicitly in _children.
  double _minScrollOffset = 0.0;

  /// The maximum scroll offset used by the scroll behavior.
  ///
  /// Not all the items between the minimum and maximum scroll offsets are
  /// reprsented explicitly in _children.
  double _maxScrollOffset = 0.0;

  /// The smallest start offset (inclusive) that can be displayed properly with the items currently represented in [_children].
  double _startOffsetLowerLimit = 0.0;

  /// The largest start offset (exclusive) that can be displayed properly with the items currently represented in [_children].
  double _startOffsetUpperLimit = 0.0;

  double _lastReportedContentExtent;
  double _lastReportedContainerExtent;
  double _lastReportedMinScrollOffset;

  @override
  void visitChildren(ElementVisitor visitor) {
    for (Element child in _children)
      visitor(child);
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    renderObject
      ..callback = _layout
      ..mainAxis = widget.mainAxis;
    // Children will get built during layout.
    // Paint offset will get updated during layout.
  }

  @override
  void update(LazyBlockViewport newWidget) {
    LazyBlockViewport oldWidget = widget;
    super.update(newWidget);
    renderObject.mainAxis = widget.mainAxis;
    LazyBlockDelegate newDelegate = newWidget.delegate;
    LazyBlockDelegate oldDelegate = oldWidget.delegate;
    if (newDelegate != oldDelegate && (newDelegate.runtimeType != oldDelegate.runtimeType || newDelegate.shouldRebuild(oldDelegate)))
      performRebuild();
    // If the new start offset can be displayed properly with the items
    // currently represented in _children, we just need to update the paint
    // offset. Otherwise, we need to trigger a layout in order to change the
    // set of explicitly represented children.
    if (widget.startOffset >= _startOffsetLowerLimit && widget.startOffset < _startOffsetUpperLimit)
      _updatePaintOffset();
    else
      renderObject.markNeedsLayout();
  }

  @override
  void unmount() {
    renderObject.callback = null;
    super.unmount();
  }

  @override
  void performRebuild() {
    IndexedBuilder builder = widget.delegate.buildItem;
    List<Widget> widgets = <Widget>[];
    for (int i = 0; i < _children.length; ++i) {
      int logicalIndex = _firstChildLogicalIndex + i;
      Widget childWidget = builder(this, logicalIndex);
      if (childWidget == null)
        break;
      widgets.add(new RepaintBoundary.wrap(childWidget, logicalIndex));
    }
    _children = new List<Element>.from(updateChildren(_children, widgets));
    super.performRebuild();
  }

  void _layout(BoxConstraints constraints) {
    final double blockExtent = _getMainAxisExtent(renderObject.size);

    owner.lockState(() {
      final IndexedBuilder builder = widget.delegate.buildItem;
      final double startLogicalOffset = widget.startOffset;
      final double endLogicalOffset = startLogicalOffset + blockExtent;
      final _RenderLazyBlock block = renderObject;
      final BoxConstraints innerConstraints = _getInnerConstraints(constraints);

      // A high watermark for which children have been through layout this pass.
      int firstLogicalIndexNeedingLayout = _firstChildLogicalIndex;

      // The index of the current child we're examining. The index is the same one
      // used for the builder (as opposed to the physical index in the _children
      // list).
      int currentLogicalIndex = _firstChildLogicalIndex;

      // The offset of the current child we're examining from the start of the
      // entire block (in the direction of the main axis). As we compute layout
      // information, we use dead reckoning to keep track of where all the
      // children are based on this quantity.
      double currentLogicalOffset = _firstChildLogicalOffset;

      // First, we check if we need to inflate any children before the start of
      // the viewport. Because we're dead reckoning from the current viewport, we
      // inflate the children in reverse tree order.

      if (currentLogicalIndex > 0 && currentLogicalOffset > startLogicalOffset) {
        final List<Element> newChildren = <Element>[];

        while (currentLogicalIndex > 0 && currentLogicalOffset > startLogicalOffset) {
          currentLogicalIndex -= 1;
          Widget newWidget = builder(this, currentLogicalIndex);
          assert(newWidget != null);
          newWidget = new RepaintBoundary.wrap(newWidget, currentLogicalIndex);
          newChildren.add(inflateWidget(newWidget, null));
          RenderBox child = block.firstChild;
          assert(child == newChildren.last.renderObject);
          child.layout(innerConstraints, parentUsesSize: true);
          currentLogicalOffset -= _getMainAxisExtent(child.size);
        }

        final int numberOfNewChildren = newChildren.length;
        _children.insertAll(0, newChildren.reversed);
        _firstChildLogicalIndex = currentLogicalIndex;
        _firstChildLogicalOffset = currentLogicalOffset;
        firstLogicalIndexNeedingLayout = currentLogicalIndex + numberOfNewChildren;
      } else if (currentLogicalOffset < startLogicalOffset) {
        // If we didn't need to inflate more children before the viewport, we
        // might need to deactivate children that have left the viewport from the
        // top. We repeatedly check whether the first child overlaps the viewport
        // and deactivate it if it's outside the viewport.
        int currentPhysicalIndex = 0;
        while (block.firstChild != null) {
          RenderBox child = block.firstChild;
          child.layout(innerConstraints, parentUsesSize: true);
          firstLogicalIndexNeedingLayout += 1;
          double childExtent = _getMainAxisExtent(child.size);
          if (currentLogicalOffset + childExtent >= startLogicalOffset)
            break;
          deactivateChild(_children[currentPhysicalIndex]);
          _children[currentPhysicalIndex] = null;
          currentPhysicalIndex += 1;
          currentLogicalIndex += 1;
          currentLogicalOffset += childExtent;
        }

        if (currentPhysicalIndex > 0) {
          _children.removeRange(0, currentPhysicalIndex);
          _firstChildLogicalIndex = currentLogicalIndex;
          _firstChildLogicalOffset = currentLogicalOffset;
        }
      }

      // We've now established the invariant that the first physical child in the
      // block is the first child that ought to be visible in the viewport. Now we
      // need to walk forward until we've filled up the viewport. We might have
      // already called layout for some of the children we encounter in this phase
      // of the algorithm, we we'll need to be careful not to call layout on them again.

      if (currentLogicalOffset >= startLogicalOffset) {
        // The first element is visible. We need to update our reckoning of where
        // the min scroll offset is.
        _minScrollOffset = currentLogicalOffset;
        _startOffsetLowerLimit = double.NEGATIVE_INFINITY;
      } else {
        // The first element is not visible. Ensure that we have one blockExtent
        // of headroom so we don't hit the min scroll offset prematurely.
        _minScrollOffset = currentLogicalOffset - blockExtent;
        _startOffsetLowerLimit = currentLogicalOffset;
      }

      // Materialize new children until we fill the viewport (or run out of
      // children to materialize).

      RenderBox child;
      while (currentLogicalOffset < endLogicalOffset) {
        int physicalIndex = currentLogicalIndex - _firstChildLogicalIndex;
        if (physicalIndex >= _children.length) {
          assert(physicalIndex == _children.length);
          Widget newWidget = builder(this, currentLogicalIndex);
          if (newWidget == null)
            break;
          newWidget = new RepaintBoundary.wrap(newWidget, currentLogicalIndex);
          Element previousChild = _children.isEmpty ? null : _children.last;
          _children.add(inflateWidget(newWidget, previousChild));
        }
        child = _getNextWithin(block, child);
        assert(child != null);
        if (currentLogicalIndex >= firstLogicalIndexNeedingLayout) {
          assert(currentLogicalIndex == firstLogicalIndexNeedingLayout);
          child.layout(innerConstraints, parentUsesSize: true);
          firstLogicalIndexNeedingLayout += 1;
        }
        currentLogicalOffset += _getMainAxisExtent(child.size);
        currentLogicalIndex += 1;
      }

      // We now have all the physical children we ought to have to fill the
      // viewport. The currentLogicalIndex is the index of the first child that
      // we don't need.

      if (currentLogicalOffset < endLogicalOffset) {
        // The last element is visible. We need to update our reckoning of where
        // the max scroll offset is.
        _maxScrollOffset = currentLogicalOffset - blockExtent;
        _startOffsetUpperLimit = double.INFINITY;
      } else {
        // The last element is not visible. Ensure that we have one blockExtent
        // of headroom so we don't hit the max scroll offset prematurely.
        _maxScrollOffset = currentLogicalOffset;
        _startOffsetUpperLimit = currentLogicalOffset - blockExtent;
      }

      // Remove any unneeded children.

      int currentPhysicalIndex = currentLogicalIndex - _firstChildLogicalIndex;
      final int numberOfRequiredPhysicalChildren = currentPhysicalIndex;
      while (currentPhysicalIndex < _children.length) {
        deactivateChild(_children[currentPhysicalIndex]);
        _children[currentPhysicalIndex] = null;
        currentPhysicalIndex += 1;
      }
      _children.length = numberOfRequiredPhysicalChildren;

      // We now have the correct physical children, each of which has gone through
      // layout exactly once. We still need to position them correctly. We
      // position the first physical child at Offset.zero and use the paintOffset
      // on the render object to adjust the final paint location of the children.

      Offset currentChildOffset = Offset.zero;
      child = block.firstChild;
      while (child != null) {
        final _LazyBlockParentData childParentData = child.parentData;
        childParentData.offset = currentChildOffset;
        currentChildOffset += _getMainAxisOffsetForSize(child.size);
        child = childParentData.nextSibling;
      }

      _updatePaintOffset();
    }, building: true, context: 'during $runtimeType layout');

    LazyBlockExtentsChangedCallback onExtentsChanged = widget.onExtentsChanged;
    if (onExtentsChanged != null) {
      double contentExtent = _maxScrollOffset - _minScrollOffset + blockExtent;
      if (_lastReportedContentExtent != contentExtent ||
          _lastReportedContainerExtent != blockExtent ||
          _lastReportedMinScrollOffset != _minScrollOffset) {
        _lastReportedContentExtent = contentExtent;
        _lastReportedContainerExtent = blockExtent;
        _lastReportedMinScrollOffset = _minScrollOffset;
        onExtentsChanged(_lastReportedContentExtent, _lastReportedContainerExtent, _lastReportedMinScrollOffset);
      }
    }
  }

  BoxConstraints _getInnerConstraints(BoxConstraints constraints) {
    switch (widget.mainAxis) {
      case Axis.horizontal:
        return new BoxConstraints.tightFor(height: constraints.maxHeight);
      case Axis.vertical:
        return new BoxConstraints.tightFor(width: constraints.maxWidth);
    }
  }

  double _getMainAxisExtent(Size size) {
    switch (widget.mainAxis) {
      case Axis.horizontal:
        return size.width;
      case Axis.vertical:
        return size.height;
    }
  }

  Offset _getMainAxisOffsetForSize(Size size) {
    switch (widget.mainAxis) {
      case Axis.horizontal:
        return new Offset(size.width, 0.0);
      case Axis.vertical:
        return new Offset(0.0, size.height);
    }
  }

  static RenderBox _getNextWithin(_RenderLazyBlock block, RenderBox child) {
    if (child == null)
      return block.firstChild;
    final _LazyBlockParentData childParentData = child.parentData;
    return childParentData.nextSibling;
  }

  void _updatePaintOffset() {
    double physicalStartOffset = widget.startOffset - _firstChildLogicalOffset;
    switch (widget.mainAxis) {
      case Axis.horizontal:
        renderObject.paintOffset = new Offset(-physicalStartOffset, 0.0);
        break;
      case Axis.vertical:
        renderObject.paintOffset = new Offset(0.0, -physicalStartOffset);
        break;
    }
  }

  @override
  void insertChildRenderObject(RenderObject child, Element slot) {
    renderObject.insert(child, after: slot?.renderObject);
  }

  @override
  void moveChildRenderObject(RenderObject child, dynamic slot) {
    assert(child.parent == renderObject);
    renderObject.move(child, after: slot?.renderObject);
  }

  @override
  void removeChildRenderObject(RenderObject child) {
    assert(child.parent == renderObject);
    renderObject.remove(child);
  }
}
