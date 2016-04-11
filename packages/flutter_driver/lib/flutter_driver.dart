// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Provides API to test Flutter applications that run on real
/// devices and emulators.
///
/// The application runs in a separate process from the test itself.
///
/// This is Flutter's version of Selenium WebDriver (generic web),
/// Protractor (Angular), Espresso (Android) or Earl Gray (iOS).
library flutter_driver;

export 'src/driver.dart' show
  FlutterDriver;

export 'src/error.dart' show
  DriverError,
  LogLevel,
  LogRecord,
  flutterDriverLog;

export 'src/find.dart' show
  ObjectRef,
  GetTextResult;

export 'src/health.dart' show
  Health,
  HealthStatus;

export 'src/message.dart' show
  Message,
  Command,
  ObjectRef,
  CommandWithTarget,
  Result;

export 'src/timeline_summary.dart' show
  summarizeTimeline,
  EventTrace,
  TimelineSummary;

export 'src/timeline.dart' show
  Timeline,
  TimelineEvent;
