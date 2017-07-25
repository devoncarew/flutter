// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../application_package.dart';
import '../artifacts.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../build_info.dart';
import '../device.dart';
import '../globals.dart';
import '../protocol_discovery.dart';
import '../version.dart';

class FlutterTesterDevices extends PollingDeviceDiscovery {
  static bool showFlutterTesterDevice = false;
  static final String kTesterDeviceId = 'flutter-tester';

  FlutterTesterDevices() : super('Flutter tester');

  final FlutterTesterDevice _testerDevice = new FlutterTesterDevice(kTesterDeviceId);

  @override
  bool get canListAnything => true;

  @override
  Future<List<Device>> pollingGetDevices() async {
    return showFlutterTesterDevice ? <Device>[_testerDevice] : <Device>[];
  }

  @override
  bool get supportsPlatform => true;
}

// TODO(devoncarew): This device does not currently work with full restarts.

class FlutterTesterDevice extends Device {
  FlutterTesterDevice(String deviceId) : super(deviceId);

  final _FlutterTesterDeviceLogReader _logReader =
      new _FlutterTesterDeviceLogReader();

  Process _process;

  @override
  void clearLogs() {}

  @override
  DeviceLogReader getLogReader({ApplicationPackage app}) => _logReader;

  @override
  Future<bool> installApp(ApplicationPackage app) async => true;

  @override
  Future<bool> isAppInstalled(ApplicationPackage app) async => false;

  @override
  Future<bool> isLatestBuildInstalled(ApplicationPackage app) async => false;

  @override
  Future<bool> get isLocalEmulator async => false;

  @override
  bool isSupported() => true;

  @override
  String get name => "Flutter test device";

  @override
  DevicePortForwarder get portForwarder => null;

  @override
  Future<String> get sdkNameAndVersion async {
    final FlutterVersion flutterVersion = FlutterVersion.instance;
    return 'Flutter ${flutterVersion.frameworkRevisionShort}';
  }

  @override
  Future<LaunchResult> startApp(
    ApplicationPackage applicationPackage,
    BuildMode mode, {
    String mainPath,
    String route,
    DebuggingOptions debuggingOptions,
    Map<String, dynamic> platformArgs,
    String kernelPath,
    bool prebuiltApplication: false,
    bool applicationNeedsRebuild: false,
    bool usesTerminalUi: true,
  }) async {
    if (mode != BuildMode.debug) {
      printError('This device only supports debug mode.');
      return new LaunchResult.failed();
    }

    final String shellPath = artifacts.getArtifactPath(Artifact.flutterTester);
    if (!fs.isFileSync(shellPath))
      throwToolExit('Cannot find Flutter shell at $shellPath');

    final List<String> arguments = <String>[
      '--non-interactive',
      '--enable-dart-profiling',
    ];
    if (debuggingOptions.debuggingEnabled) {
      if (debuggingOptions.startPaused)
        arguments.add('--start-paused');
      if (debuggingOptions.hasObservatoryPort)
        arguments.add('--observatory-port=${debuggingOptions.hasObservatoryPort}');
    }
    if (mainPath != null)
      arguments.add(mainPath);

    try {
      printTrace('$shellPath ${arguments.join(' ')}');

      _process = await Process.start(shellPath, arguments);
      _process.stdout.transform(UTF8.decoder).transform(const LineSplitter()).listen((String line) { // transform<String>
        _logReader.addLine(line);
      });
      _process.stderr.transform(UTF8.decoder).transform(const LineSplitter()).listen((String line) {
        _logReader.addLine(line);
      });

      if (!debuggingOptions.debuggingEnabled)
        return new LaunchResult.succeeded();

      final ProtocolDiscovery observatoryDiscovery = new ProtocolDiscovery.observatory(
          getLogReader(), hostPort: debuggingOptions.observatoryPort);

      final Uri observatoryUri = await observatoryDiscovery.uri;
      return new LaunchResult.succeeded(observatoryUri: observatoryUri);
    } catch (error) {
      printError('Failed to launch $applicationPackage: $error');
      return new LaunchResult.failed();
    }
  }

  @override
  Future<bool> stopApp(ApplicationPackage app) async {
    _process?.kill();
    _process = null;

    return true;
  }

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.tester;

  @override
  Future<bool> uninstallApp(ApplicationPackage app) async => true;
}

class FlutterTesterApp extends ApplicationPackage {
  FlutterTesterApp._(this._dir);

  factory FlutterTesterApp.fromCurrentDirectory() {
    return new FlutterTesterApp._(fs.currentDirectory.path);
  }

  final String _dir;

  @override
  String get name => path.basename(_dir);

  @override
  String get packagePath => path.join(_dir, '.packages');
}

class _FlutterTesterDeviceLogReader extends DeviceLogReader {
  final StreamController<String> _logLinesController =
      new StreamController<String>.broadcast();

  @override
  String get name => 'flutter tester log reader';

  @override
  int get appPid => 0;

  @override
  Stream<String> get logLines => _logLinesController.stream;

  void addLine(String line) => _logLinesController.add(line);
}
