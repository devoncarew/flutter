// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

import 'context.dart';
import 'process.dart';

/// Returns [OperatingSystemUtils] active in the current app context (i.e. zone).
OperatingSystemUtils get os {
  return context[OperatingSystemUtils] ?? (context[OperatingSystemUtils] = new OperatingSystemUtils._());
}

abstract class OperatingSystemUtils {
  factory OperatingSystemUtils._() {
    if (Platform.isWindows) {
      return new _WindowsUtils();
    } else {
      return new _PosixUtils();
    }
  }

  OperatingSystemUtils._private();

  String get operatingSystem => Platform.operatingSystem;

  bool get isMacOS => operatingSystem == 'macos';
  bool get isWindows => operatingSystem == 'windows';
  bool get isLinux => operatingSystem == 'linux';

  /// Make the given file executable. This may be a no-op on some platforms.
  ProcessResult makeExecutable(File file);

  /// Return the path (with symlinks resolved) to the given executable, or `null`
  /// if `which` was not able to locate the binary.
  File which(String execName);

  void unzip(File file, Directory targetDirectory);
}

class _PosixUtils extends OperatingSystemUtils {
  _PosixUtils() : super._private();

  @override
  ProcessResult makeExecutable(File file) {
    return Process.runSync('chmod', ['a+x', file.path]);
  }

  /// Return the path (with symlinks resolved) to the given executable, or `null`
  /// if `which` was not able to locate the binary.
  @override
  File which(String execName) {
    ProcessResult result = Process.runSync('which', <String>[execName]);
    if (result.exitCode != 0)
      return null;
    String path = result.stdout.trim().split('\n').first.trim();
    return new File(new File(path).resolveSymbolicLinksSync());
  }

  // unzip -o -q zipfile -d dest
  @override
  void unzip(File file, Directory targetDirectory) {
    runSync(<String>['unzip', '-o', '-q', file.path, '-d', targetDirectory.path]);
  }
}

class _WindowsUtils extends OperatingSystemUtils {
  _WindowsUtils() : super._private();

  // This is a no-op.
  @override
  ProcessResult makeExecutable(File file) {
    return new ProcessResult(0, 0, null, null);
  }

  @override
  File which(String execName) {
    ProcessResult result = Process.runSync('where', <String>[execName]);
    if (result.exitCode != 0)
      return null;
    return new File(result.stdout.trim().split('\n').first.trim());
  }

  @override
  void unzip(File file, Directory targetDirectory) {
    Archive archive = new ZipDecoder().decodeBytes(file.readAsBytesSync());

    for (ArchiveFile archiveFile in archive.files) {
      // The archive package doesn't correctly set isFile.
      if (!archiveFile.isFile || archiveFile.name.endsWith('/'))
        continue;

      File destFile = new File(path.join(targetDirectory.path, archiveFile.name));
      if (!destFile.parent.existsSync())
        destFile.parent.createSync(recursive: true);
      destFile.writeAsBytesSync(archiveFile.content);
    }
  }
}

Future<int> findAvailablePort() async {
  ServerSocket socket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);
  int port = socket.port;
  await socket.close();
  return port;
}
