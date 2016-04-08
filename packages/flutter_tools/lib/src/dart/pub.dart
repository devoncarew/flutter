// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../base/logger.dart';
import '../base/process.dart';
import '../cache.dart';
import '../globals.dart';

bool _shouldRunPubGet({ File pubSpecYaml, File dotPackages }) {
  if (!dotPackages.existsSync())
    return true;
  DateTime dotPackagesLastModified = dotPackages.lastModifiedSync();
  if (pubSpecYaml.lastModifiedSync().isAfter(dotPackagesLastModified))
    return true;
  File flutterToolsStamp = Cache.instance.getStampFileFor('flutter_tools');
  if (flutterToolsStamp.lastModifiedSync().isAfter(dotPackagesLastModified))
    return true;
  return false;
}

Future<int> pubGet({
  String directory,
  bool skipIfAbsent: false,
  bool upgrade: false,
  bool checkLastModified: true
}) async {
  if (directory == null)
    directory = Directory.current.path;

  File pubSpecYaml = new File(path.join(directory, 'pubspec.yaml'));
  File dotPackages = new File(path.join(directory, '.packages'));

  if (!pubSpecYaml.existsSync()) {
    if (skipIfAbsent)
      return 0;
    printError('$directory: no pubspec.yaml found');
    return 1;
  }

  if (!checkLastModified || _shouldRunPubGet(pubSpecYaml: pubSpecYaml, dotPackages: dotPackages)) {
    String command = upgrade ? 'upgrade' : 'get';
    Status status = logger.startProgress("Running 'pub $command' in ${path.basename(directory)}...");
    int code = await runCommandAndStreamOutput(
      <String>[sdkBinaryName('pub'), '--verbosity=warning', command, '--no-package-symlinks', '--no-precompile'],
      workingDirectory: directory
    );
    status.stop(showElapsedTime: true);
    if (code != 0)
      return code;
  }

  if (dotPackages.existsSync() && dotPackages.lastModifiedSync().isAfter(pubSpecYaml.lastModifiedSync()))
    return 0;

  printError('$directory: pubspec.yaml and .packages are in an inconsistent state');
  return 1;
}
