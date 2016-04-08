// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:stack_trace/stack_trace.dart';

import 'src/base/context.dart';
import 'src/base/logger.dart';
import 'src/base/process.dart';
import 'src/base/utils.dart';
import 'src/commands/analyze.dart';
import 'src/commands/build.dart';
import 'src/commands/create.dart';
import 'src/commands/daemon.dart';
import 'src/commands/devices.dart';
import 'src/commands/doctor.dart';
import 'src/commands/drive.dart';
import 'src/commands/install.dart';
import 'src/commands/listen.dart';
import 'src/commands/logs.dart';
import 'src/commands/precache.dart';
import 'src/commands/refresh.dart';
import 'src/commands/run.dart';
import 'src/commands/run_mojo.dart';
import 'src/commands/screenshot.dart';
import 'src/commands/skia.dart';
import 'src/commands/stop.dart';
import 'src/commands/test.dart';
import 'src/commands/trace.dart';
import 'src/commands/update_packages.dart';
import 'src/commands/upgrade.dart';
import 'src/device.dart';
import 'src/doctor.dart';
import 'src/globals.dart';
import 'src/runner/flutter_command_runner.dart';

/// Main entry point for commands.
///
/// This function is intended to be used from the [flutter] command line tool.
Future<Null> main(List<String> args) async {
  bool help = args.contains('-h') || args.contains('--help');
  bool verbose = args.contains('-v') || args.contains('--verbose');
  bool verboseHelp = help && verbose;

  if (verboseHelp) {
    // Remove the verbose option; for help, users don't need to see verbose logs.
    args = new List<String>.from(args);
    args.removeWhere((String option) => option == '-v' || option == '--verbose');
  }

  FlutterCommandRunner runner = new FlutterCommandRunner(verboseHelp: verboseHelp)
    ..addCommand(new AnalyzeCommand())
    ..addCommand(new BuildCommand())
    ..addCommand(new CreateCommand())
    ..addCommand(new DaemonCommand(hidden: !verboseHelp))
    ..addCommand(new DevicesCommand())
    ..addCommand(new DoctorCommand())
    ..addCommand(new DriveCommand())
    ..addCommand(new InstallCommand())
    ..addCommand(new ListenCommand())
    ..addCommand(new LogsCommand())
    ..addCommand(new PrecacheCommand())
    ..addCommand(new RefreshCommand())
    ..addCommand(new RunCommand())
    ..addCommand(new RunMojoCommand(hidden: !verboseHelp))
    ..addCommand(new ScreenshotCommand())
    ..addCommand(new SkiaCommand())
    ..addCommand(new StopCommand())
    ..addCommand(new TestCommand())
    ..addCommand(new TraceCommand())
    ..addCommand(new UpdatePackagesCommand(hidden: !verboseHelp))
    ..addCommand(new UpgradeCommand());

  return Chain.capture(() async {
    // Initialize globals.
    context[Logger] = new StdoutLogger();
    context[DeviceManager] = new DeviceManager();
    Doctor.initGlobal();

    dynamic result = await runner.run(args);

    if (result is int)
      exit(result);
  }, onError: (dynamic error, Chain chain) {
    if (error is UsageException) {
      stderr.writeln(error.message);
      stderr.writeln();
      stderr.writeln("Run 'flutter -h' (or 'flutter <command> -h') for available "
        "flutter commands and options.");
      // Argument error exit code.
      exit(64);
    } else if (error is ProcessExit) {
      // We've caught an exit code.
      exit(error.exitCode);
    } else {
      // We've crashed; emit a log report.
      stderr.writeln();
      if (error is String)
        stderr.writeln('Oops; flutter has exited unexpectedly: "$error".');
      else
        stderr.writeln('Oops; flutter has exited unexpectedly.');

      if (Platform.environment.containsKey('FLUTTER_DEV')) {
        // If we're working in the tools themselves, just print the stack trace.
        stderr.writeln(chain.terse.toString());
      } else {
        File file = _createCrashReport(args, error, chain);

        stderr.writeln(
          'Crash report written to ${path.relative(file.path)}; '
          'please let us know at https://github.com/flutter/flutter/issues.');
      }

      exit(1);
    }
  });
}

File _createCrashReport(List<String> args, dynamic error, Chain chain) {
  File crashFile = getUniqueFile(Directory.current, 'flutter', 'log');

  StringBuffer buf = new StringBuffer();

  buf.writeln('Flutter crash report; please file at https://github.com/flutter/flutter/issues.\n');

  buf.writeln('## command\n');
  buf.writeln('flutter ${args.join(' ')}\n');

  buf.writeln('## exception\n');
  buf.writeln('$error\n');
  buf.writeln('```\n${chain.terse}```\n');

  buf.writeln('## flutter doctor\n');
  buf.writeln('```\n${_doctorText()}```');

  crashFile.writeAsStringSync(buf.toString());

  return crashFile;
}

String _doctorText() {
  try {
    BufferLogger logger = new BufferLogger();
    AppContext appContext = new AppContext();

    appContext[Logger] = logger;

    appContext.runInZone(() => doctor.diagnose());

    return logger.statusText;
  } catch (error, trace) {
    return 'encountered exception: $error\n\n${trace.toString().trim()}\n';
  }
}
