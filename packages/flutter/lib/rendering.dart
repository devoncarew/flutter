// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// The Flutter rendering tree.
///
/// The [RenderObject] hierarchy is used by the Flutter Widgets
/// library to implement its layout and painting back-end. Generally,
/// while you may use custom [RenderBox] classes for specific effects
/// in your applications, most of the time your only interaction with
/// the [RenderObject] hierarchy will be in debugging layout issues.
///
/// If you are developing your own library or application directly on
/// top of the rendering library, then you will want to have a binding
/// (see [BindingBase]). You can use [RenderingFlutterBinding], or you
/// can create your own binding. If you create your own binding, it
/// needs to import at least [Scheduler], [Gesturer], [Services], and
/// [Renderer]. The rendering library does not automatically create a
/// binding, but relies on one being initialized with those features.
library rendering;

export 'src/rendering/auto_layout.dart';
export 'src/rendering/basic_types.dart';
export 'src/rendering/binding.dart';
export 'src/rendering/block.dart';
export 'src/rendering/box.dart';
export 'src/rendering/child_view.dart';
export 'src/rendering/custom_layout.dart';
export 'src/rendering/debug.dart';
export 'src/rendering/editable_line.dart';
export 'src/rendering/error.dart';
export 'src/rendering/flex.dart';
export 'src/rendering/grid.dart';
export 'src/rendering/image.dart';
export 'src/rendering/layer.dart';
export 'src/rendering/list.dart';
export 'src/rendering/node.dart';
export 'src/rendering/object.dart';
export 'src/rendering/overflow.dart';
export 'src/rendering/paragraph.dart';
export 'src/rendering/performance_overlay.dart';
export 'src/rendering/proxy_box.dart';
export 'src/rendering/rotated_box.dart';
export 'src/rendering/semantics.dart';
export 'src/rendering/shifted_box.dart';
export 'src/rendering/stack.dart';
export 'src/rendering/table.dart';
export 'src/rendering/view.dart';
export 'src/rendering/viewport.dart';

export 'package:vector_math/vector_math_64.dart' show Matrix4;
