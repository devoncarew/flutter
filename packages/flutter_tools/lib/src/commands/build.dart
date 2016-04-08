// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import '../globals.dart';
import '../runner/flutter_command.dart';
import 'build_apk.dart';
import 'build_flx.dart';
import 'build_ios.dart';

class BuildCommand extends FlutterCommand {
  BuildCommand() {
    addSubcommand(new BuildApkCommand());
    addSubcommand(new BuildCleanCommand());
    addSubcommand(new BuildIOSCommand());
    addSubcommand(new BuildFlxCommand());
  }

  @override
  final String name = 'build';

  @override
  final String description = 'Flutter build commands.';

  @override
  Future<int> runInProject() => new Future<int>.value(0);
}

class BuildCleanCommand extends FlutterCommand {
  @override
  final String name = 'clean';

  @override
  final String description = 'Delete the build/ directory.';

  @override
  Future<int> runInProject() async {
    Directory buildDir = new Directory('build');
    printStatus("Deleting '${buildDir.path}${Platform.pathSeparator}'.");

    if (!buildDir.existsSync())
      return 0;

    try {
      buildDir.deleteSync(recursive: true);
      return 0;
    } catch (error) {
      printError(error.toString());
      return 1;
    }
  }
}
