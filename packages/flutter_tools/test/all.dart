// Copyright (c) 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// TODO(devoncarew): These `all.dart` test files are here to work around
// https://github.com/dart-lang/test/issues/327; the `test` package currently
// doesn't support running without symlinks. We can delete these files once that
// fix lands.

import 'adb_test.dart' as adb_test;
import 'analyze_duplicate_names_test.dart' as analyze_duplicate_names_test;
import 'analyze_test.dart' as analyze_test;
import 'android_device_test.dart' as android_device_test;
import 'android_sdk_test.dart' as android_sdk_test;
import 'base_utils_test.dart' as base_utils_test;
import 'context_test.dart' as context_test;
import 'create_test.dart' as create_test;
import 'daemon_test.dart' as daemon_test;
import 'device_test.dart' as device_test;
import 'drive_test.dart' as drive_test;
import 'install_test.dart' as install_test;
import 'listen_test.dart' as listen_test;
import 'logs_test.dart' as logs_test;
import 'os_utils_test.dart' as os_utils_test;
import 'run_test.dart' as run_test;
import 'service_protocol_test.dart' as service_protocol_test;
import 'stop_test.dart' as stop_test;
import 'trace_test.dart' as trace_test;
import 'upgrade_test.dart' as upgrade_test;

void main() {
  adb_test.main();
  analyze_duplicate_names_test.main();
  analyze_test.main();
  android_device_test.main();
  android_sdk_test.main();
  base_utils_test.main();
  context_test.main();
  create_test.main();
  daemon_test.main();
  device_test.main();
  drive_test.main();
  install_test.main();
  listen_test.main();
  logs_test.main();
  os_utils_test.main();
  run_test.main();
  service_protocol_test.main();
  stop_test.main();
  trace_test.main();
  upgrade_test.main();
}
