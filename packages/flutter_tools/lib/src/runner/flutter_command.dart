// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../application_package.dart';
import '../build_configuration.dart';
import '../dart/pub.dart';
import '../device.dart';
import '../flx.dart' as flx;
import '../globals.dart';
import '../package_map.dart';
import '../toolchain.dart';
import 'flutter_command_runner.dart';

typedef bool Validator();

abstract class FlutterCommand extends Command {
  FlutterCommand() {
    commandValidator = _commandValidator;
  }

  @override
  FlutterCommandRunner get runner => super.runner;

  /// Whether this command needs to be run from the root of a project.
  bool get requiresProjectRoot => true;

  /// Whether this command requires a (single) Flutter target device to be connected.
  bool get requiresDevice => false;

  /// Whether this command only applies to Android devices.
  bool get androidOnly => false;

  /// Whether this command uses the 'target' option.
  bool _usesTargetOption = false;

  bool _usesPubOption = false;

  List<BuildConfiguration> get buildConfigurations => runner.buildConfigurations;

  void usesTargetOption() {
    argParser.addOption('target',
      abbr: 't',
      defaultsTo: flx.defaultMainPath,
      help: 'Target app path / main entry-point file.');
    _usesTargetOption = true;
  }

  void usesPubOption() {
    argParser.addFlag('pub',
      defaultsTo: true,
      help: 'Whether to run "pub get" before executing this command.');
    _usesPubOption = true;
  }

  void _setupToolchain() {
    toolchain ??= Toolchain.forConfigs(buildConfigurations);
  }

  void _setupApplicationPackages() {
    applicationPackages ??= ApplicationPackageStore.forConfigs(buildConfigurations);
  }

  @override
  Future<int> run() {
    Stopwatch stopwatch = new Stopwatch()..start();

    return _run().then((int exitCode) {
      int ms = stopwatch.elapsedMilliseconds;
      printTrace("'flutter $name' took ${ms}ms; exiting with code $exitCode.");
      return exitCode;
    });
  }

  Future<int> _run() async {
    if (requiresProjectRoot && !commandValidator())
      return 1;

    // Ensure at least one toolchain is installed.
    if (requiresDevice && !doctor.canLaunchAnything) {
      printError("Unable to locate a development device; please run 'flutter doctor' "
        "for information about installing additional components.");
      return 1;
    }

    // Validate devices.
    if (requiresDevice) {
      List<Device> devices = await deviceManager.getDevices();

      if (devices.isEmpty && deviceManager.hasSpecifiedDeviceId) {
        printError("No device found with id '${deviceManager.specifiedDeviceId}'.");
        return 1;
      } else if (devices.isEmpty) {
        printStatus('No connected devices.');
        return 1;
      }

      devices = devices.where((Device device) => device.isSupported()).toList();

      if (androidOnly)
        devices = devices.where((Device device) => device.platform == TargetPlatform.android_arm).toList();

      if (devices.isEmpty) {
        printStatus('No supported devices connected.');
        return 1;
      } else if (devices.length > 1) {
        printStatus("More than one device connected; please specify a device with "
          "the '-d <deviceId>' flag.");
        printStatus('');
        devices = await deviceManager.getAllConnectedDevices();
        Device.printDevices(devices);
        return 1;
      } else {
        _deviceForCommand = devices.single;
      }
    }

    if (_usesPubOption && argResults['pub']) {
      int exitCode = await pubGet();
      if (exitCode != 0)
        return exitCode;
    }

    // Populate the cache.
    await cache.updateAll();

    _setupToolchain();
    _setupApplicationPackages();

    return await runInProject();
  }

  // This is a field so that you can modify the value for testing.
  Validator commandValidator;

  bool _commandValidator() {
    if (!FileSystemEntity.isFileSync('pubspec.yaml')) {
      printError('Error: No pubspec.yaml file found.\n'
        'This command should be run from the root of your Flutter project.\n'
        'Do not run this command from the root of your git clone of Flutter.');
      return false;
    }

    if (_usesTargetOption) {
      String targetPath = argResults['target'];
      if (!FileSystemEntity.isFileSync(targetPath)) {
        printError('Target file "$targetPath" not found.');
        return false;
      }
    }

    // Validate the current package map only if we will not be running "pub get" later.
    if (!(_usesPubOption && argResults['pub'])) {
      String error = PackageMap.instance.checkValid();
      if (error != null) {
        printError(error);
        return false;
      }
    }

    return true;
  }

  Future<int> runInProject();

  // This is caculated in run() if the command has [requiresDevice] specified.
  Device _deviceForCommand;

  Device get deviceForCommand => _deviceForCommand;

  ApplicationPackageStore applicationPackages;
  Toolchain toolchain;
}
