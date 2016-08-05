// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'application_package.dart';
import 'base/logger.dart';
import 'base/utils.dart';
import 'build_info.dart';
import 'cache.dart';
import 'commands/build_apk.dart';
import 'commands/install.dart';
import 'commands/trace.dart';
import 'device.dart';
import 'globals.dart';
import 'observatory.dart';
import 'devfs.dart';

/// Given the value of the --target option, return the path of the Dart file
/// where the app's main function should be.
String findMainDartFile([String target]) {
  if (target == null)
    target = '';
  String targetPath = path.absolute(target);
  if (FileSystemEntity.isDirectorySync(targetPath))
    return path.join(targetPath, 'lib', 'main.dart');
  else
    return targetPath;
}

String getDevFSLoaderScript() {
  return path.absolute(path.join(Cache.flutterRoot,
                                 'packages',
                                 'flutter',
                                 'bin',
                                 'loader',
                                 'loader_app.dart'));
}

class RunAndStayResident {
  RunAndStayResident(
    this.device, {
    this.target,
    this.debuggingOptions,
    this.usesTerminalUI: true,
    this.hotMode: false
  });

  final Device device;
  final String target;
  final DebuggingOptions debuggingOptions;
  final bool usesTerminalUI;
  final bool hotMode;

  ApplicationPackage _package;
  String _mainPath;
  LaunchResult _result;

  final Completer<int> _exitCompleter = new Completer<int>();
  StreamSubscription<String> _loggingSubscription;

  Observatory observatory;

  /// Start the app and keep the process running during its lifetime.
  Future<int> run({
    bool traceStartup: false,
    bool benchmark: false,
    Completer<int> observatoryPortCompleter,
    String route,
    bool shouldBuild: true
  }) {
    // Don't let uncaught errors kill the process.
    return runZoned(() {
      return _run(
        traceStartup: traceStartup,
        benchmark: benchmark,
        observatoryPortCompleter: observatoryPortCompleter,
        route: route,
        shouldBuild: shouldBuild
      );
    }, onError: (dynamic error, StackTrace stackTrace) {
      printError('Exception from flutter run: $error', stackTrace);
    });
  }

  Future<bool> restart() async {
    if (observatory == null) {
      printError('Debugging is not enabled.');
      return false;
    } else {
      Status status = logger.startProgress('Re-starting application...');

      Future<Event> extensionAddedEvent;

      if (device.restartSendsFrameworkInitEvent) {
        extensionAddedEvent = observatory.onExtensionEvent
          .where((Event event) => event.extensionKind == 'Flutter.FrameworkInitialization')
          .first;
      }

      bool restartResult = await device.restartApp(
        _package,
        _result,
        mainPath: _mainPath,
        observatory: observatory
      );

      status.stop(showElapsedTime: true);

      if (restartResult && extensionAddedEvent != null) {
        // TODO(devoncarew): We should restore the route here.
        await extensionAddedEvent;
      }

      return restartResult;
    }
  }

  Future<Null> stop() {
    _stopLogger();
    return _stopApp();
  }

  Future<int> _run({
    bool traceStartup: false,
    bool benchmark: false,
    Completer<int> observatoryPortCompleter,
    String route,
    bool shouldBuild: true
  }) async {
    _mainPath = findMainDartFile(target);
    if (!FileSystemEntity.isFileSync(_mainPath)) {
      String message = 'Tried to run $_mainPath, but that file does not exist.';
      if (target == null)
        message += '\nConsider using the -t option to specify the Dart file to start.';
      printError(message);
      return 1;
    }

    // TODO: aapt dump badging build/app_prebuilt.apk
    // launchable-activity: name='org.domokit.sky.shell.SkyActivity'  label='' icon=''
    _package = getApplicationPackageForPlatform(device.platform, preBuiltApplicationBinary);

    if (_package == null) {
      String message = 'No application found for ${device.platform}.';
      String hint = getMissingPackageHintForPlatform(device.platform);
      if (hint != null)
        message += '\n$hint';
      printError(message);
      return 1;
    }

    Stopwatch startTime = new Stopwatch()..start();

    // TODO(devoncarew): We shouldn't have to do type checks here.
    if (shouldBuild && device is AndroidDevice) {
      printTrace('Running build command.');

      int result = await buildApk(
        device.platform,
        target: target,
        buildMode: debuggingOptions.buildMode
      );

      if (result != 0)
        return result;
    }

    // TODO(devoncarew): Move this into the device.startApp() impls.
    if (_package != null) {
      printTrace("Stopping app '${_package.name}' on ${device.name}.");
      // We don't wait for the stop command to complete.
      device.stopApp(_package);
    }

    // Allow any stop commands from above to start work.
    await new Future<Duration>.delayed(Duration.ZERO);

    // TODO(devoncarew): This fails for ios devices - we haven't built yet.
    if (device is AndroidDevice) {
      printTrace('Running install command.');
      if (!(installApp(device, _package, uninstall: false)))
        return 1;
    }

    Map<String, dynamic> platformArgs;
    if (traceStartup != null)
      platformArgs = <String, dynamic>{ 'trace-startup': traceStartup };

    if (!hotMode || (hotMode && !device.needsDevFS))
      printStatus('Running ${getDisplayPath(_mainPath)} on ${device.name}...');


    _loggingSubscription = device.logReader.logLines.listen((String line) {
      if (!line.contains('Observatory listening on http') && !line.contains('Diagnostic server listening on http'))
        printStatus(line);
    });

    _result = await device.startApp(
      _package,
      debuggingOptions.buildMode,
      mainPath: (hotMode && device.needsDevFS) ? getDevFSLoaderScript() : _mainPath,
      debuggingOptions: debuggingOptions,
      platformArgs: platformArgs,
      route: route
    );

    if (!_result.started) {
      printError('Error running application on ${device.name}.');
      await _loggingSubscription.cancel();
      return 2;
    }

    startTime.stop();

    if (observatoryPortCompleter != null && _result.hasObservatory)
      observatoryPortCompleter.complete(_result.observatoryPort);

    // Connect to observatory.
    if (debuggingOptions.debuggingEnabled) {
      observatory = await Observatory.connect(_result.observatoryPort);
      printTrace('Connected to observatory port: ${_result.observatoryPort}.');
      observatory.populateIsolateInfo();
      observatory.onExtensionEvent.listen((Event event) {
        printTrace(event.toString());
      });
      observatory.onIsolateEvent.listen((Event event) {
        printTrace(event.toString());
      });

      if (hotMode && device.needsDevFS) {
        _loaderShowMessage('Connecting...', progress: 0);
        bool result = await _updateDevFS(
          progressReporter: (int progress, int max) {
            _loaderShowMessage('Syncing files to device...', progress: progress, max: max);
          }
        );
        if (!result) {
          _loaderShowMessage('Failed.');
          printError('Could not perform initial file synchronization.');
          return 3;
        }
        printStatus('Running ${getDisplayPath(_mainPath)} on ${device.name}...');
        _loaderShowMessage('Launching...');
        await _launchFromDevFS(_package, _mainPath);
      }

      if (benchmark)
        await observatory.waitFirstIsolate;

      // Listen for observatory connection close.
      observatory.done.whenComplete(() {
        if (!_exitCompleter.isCompleted) {
          printStatus('Application finished.');
          _exitCompleter.complete(0);
        }
      });
    }

    printStatus('Application running.');

    if (observatory != null && traceStartup) {
      printStatus('Downloading startup trace info...');

      await downloadStartupTrace(observatory);

      if (!_exitCompleter.isCompleted)
        _exitCompleter.complete(0);
    } else {
      if (usesTerminalUI) {
        if (!logger.quiet)
          _printHelp();

        terminal.singleCharMode = true;
        terminal.onCharInput.listen((String code) {
          printStatus(''); // the key the user tapped might be on this line
          final String lower = code.toLowerCase();
          if (lower == 'h' || lower == '?' || code == AnsiTerminal.KEY_F1) {
            // F1, help
            _printHelp();
          } else if (lower == 'r' || code == AnsiTerminal.KEY_F5) {
            // F5, restart
            if (hotMode && code == 'r') {
              // lower-case 'r'
              _reloadSources();
            } else {
              // upper-case 'r', or hot restart disabled
              if (device.supportsRestart)
                restart();
            }
          } else if (lower == 'q' || code == AnsiTerminal.KEY_F10) {
            // F10, exit
            _stopApp();
          } else if (lower == 'w') {
            _debugDumpApp();
          } else if (lower == 't') {
            _debugDumpRenderTree();
          }
        });
      }

      ProcessSignal.SIGINT.watch().listen((ProcessSignal signal) async {
        _resetTerminal();
        await _cleanupDevFS();
        await _stopLogger();
        await _stopApp();
        exit(0);
      });
      ProcessSignal.SIGTERM.watch().listen((ProcessSignal signal) async {
        _resetTerminal();
        await _cleanupDevFS();
        await _stopLogger();
        await _stopApp();
        exit(0);
      });
    }

    if (benchmark) {
      await new Future<Null>.delayed(new Duration(seconds: 4));

      // Touch the file.
      File mainFile = new File(_mainPath);
      mainFile.writeAsBytesSync(mainFile.readAsBytesSync());

      Stopwatch restartTime = new Stopwatch()..start();
      bool restarted = await restart();
      restartTime.stop();
      writeRunBenchmarkFile(startTime, restarted ? restartTime : null);
      await new Future<Null>.delayed(new Duration(seconds: 2));
      stop();
    }

    return _exitCompleter.future.then((int exitCode) async {
      _resetTerminal();
      _stopLogger();
      return exitCode;
    });
  }

  void _debugDumpApp() {
    observatory.flutterDebugDumpApp(observatory.firstIsolateId);
  }

  void _debugDumpRenderTree() {
    observatory.flutterDebugDumpRenderTree(observatory.firstIsolateId);
  }

  void _loaderShowMessage(String message, { int progress, int max }) {
    observatory.flutterLoaderShowMessage(observatory.firstIsolateId, message);
    if (progress != null) {
      observatory.flutterLoaderSetProgress(observatory.firstIsolateId, progress.toDouble());
      observatory.flutterLoaderSetProgressMax(observatory.firstIsolateId, max?.toDouble() ?? 0.0);
    } else {
      observatory.flutterLoaderSetProgress(observatory.firstIsolateId, 0.0);
      observatory.flutterLoaderSetProgressMax(observatory.firstIsolateId, -1.0);
    }
  }

  DevFS _devFS;
  String _devFSProjectRootPath;
  Future<bool> _updateDevFS({ DevFSProgressReporter progressReporter }) async {
    if (_devFS == null) {
      Directory directory = Directory.current;
      _devFSProjectRootPath = directory.path;
      String fsName = path.basename(directory.path);
      _devFS = new DevFS(observatory, fsName, directory);

      try {
        await _devFS.create();
      } catch (error) {
        _devFS = null;
        printError('Error initializing DevFS: $error');
        return false;
      }

      _exitCompleter.future.then((_) async {
        await _cleanupDevFS();
      });
    }

    Status devFSStatus = logger.startProgress('Syncing files on device...');
    await _devFS.update(progressReporter: progressReporter);
    devFSStatus.stop(showElapsedTime: true);
    printStatus('Synced ${getSizeAsMB(_devFS.bytes)} MB');
    return true;
  }

  Future<Null> _cleanupDevFS() async {
    if (_devFS != null) {
      // Cleanup the devFS.
      await _devFS.destroy();
    }
    _devFS = null;
  }

  Future<Null> _launchFromDevFS(ApplicationPackage package,
                                String mainScript) async {
    String entryPath = path.relative(mainScript, from: _devFSProjectRootPath);
    String deviceEntryPath =
        _devFS.baseUri.resolve(entryPath).toFilePath();
    String devicePackagesPath =
        _devFS.baseUri.resolve('.packages').toFilePath();
    await device.runFromFile(package,
                             deviceEntryPath,
                             devicePackagesPath);
  }

  Future<bool> _reloadSources() async {
    if (observatory.firstIsolateId == null)
      throw 'Application isolate not found';
    if (_devFS != null)
      await _updateDevFS();
    Status reloadStatus = logger.startProgress('Performing hot reload');
    try {
      await observatory.reloadSources(observatory.firstIsolateId);
    } catch (errorMessage) {
      reloadStatus.stop(showElapsedTime: true);
      printError('Hot reload was rejected:\n$errorMessage');
      return false;
    }
    reloadStatus.stop(showElapsedTime: true);
    Status reassembleStatus =
        logger.startProgress('Reassembling application');
    try {
      await observatory.flutterReassemble(observatory.firstIsolateId);
    } catch (_) {
      reassembleStatus.stop(showElapsedTime: true);
      printError('Reassembling application failed.');
      return false;
    }
    reassembleStatus.stop(showElapsedTime: true);
    return true;
  }

  void _printHelp() {
    printStatus('Type "h" or F1 for this help message. Type "q", F10, or ctrl-c to quit.', emphasis: true);
    String hot = '';
    String cold = '';
    if (hotMode)
      hot = 'Type "r" or F5 to perform a hot reload of the app';
    if (device.supportsRestart) {
      if (hotMode) {
        cold = ', and "R" to cold restart the app';
      } else {
        cold = 'Type "r" or F5 to restart the app';
      }
    }
    if (hot != '' || cold != '')
      printStatus('$hot$cold.', emphasis: true);
    printStatus('Type "w" to print the widget hierarchy of the app, and "t" for the render tree.', emphasis: true);
  }

  Future<dynamic> _stopLogger() {
    return _loggingSubscription?.cancel();
  }

  void _resetTerminal() {
    if (usesTerminalUI)
      terminal.singleCharMode = false;
  }

  Future<Null> _stopApp() {
    if (observatory != null && !observatory.isClosed) {
      if (observatory.isolates.isNotEmpty) {
        observatory.flutterExit(observatory.firstIsolateId);
        return new Future<Null>.delayed(new Duration(milliseconds: 100));
      }
    }

    if (!_exitCompleter.isCompleted)
      _exitCompleter.complete(0);

    return new Future<Null>.value();
  }
}

String getMissingPackageHintForPlatform(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android_arm:
    case TargetPlatform.android_x64:
      return 'Is your project missing an android/AndroidManifest.xml?\nConsider running "flutter create ." to create one.';
    case TargetPlatform.ios:
      return 'Is your project missing an ios/Runner/Info.plist?\nConsider running "flutter create ." to create one.';
    default:
      return null;
  }
}

void writeRunBenchmarkFile(Stopwatch startTime, [Stopwatch restartTime]) {
  final String benchmarkOut = 'refresh_benchmark.json';
  Map<String, dynamic> data = <String, dynamic>{
    'start': startTime.elapsedMilliseconds,
    'time': (restartTime ?? startTime).elapsedMilliseconds // time and restart are the same
  };
  if (restartTime != null)
    data['restart'] = restartTime.elapsedMilliseconds;

  new File(benchmarkOut).writeAsStringSync(toPrettyJson(data));
  printStatus('Run benchmark written to $benchmarkOut ($data).');
}
