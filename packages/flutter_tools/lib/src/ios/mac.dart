// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import '../base/context.dart';
import '../base/process.dart';

class XCode {
  static void initGlobal() {
    context[XCode] = new XCode();
  }

  bool get isInstalled => exitsHappy(<String>['xcode-select', '--print-path']);

  /// Has the EULA been signed?
  bool get eulaSigned {
    try {
      ProcessResult result = Process.runSync('usr/bin/xcrun', <String>['clang']);
      if (result.stdout != null && result.stdout.contains('license'))
        return false;
      if (result.stderr != null && result.stderr.contains('license'))
        return false;
      return true;
    } catch (error) {
      return false;
    }
  }
}
