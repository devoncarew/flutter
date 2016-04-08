// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'android/android_device.dart';
import 'application_package.dart';
import 'artifacts.dart';
import 'base/common.dart';
import 'base/utils.dart';
import 'build_configuration.dart';
import 'globals.dart';
import 'ios/devices.dart';
import 'ios/simulators.dart';
import 'toolchain.dart';

/// A class to get all available devices.
class DeviceManager {
  /// Constructing DeviceManagers is cheap; they only do expensive work if some
  /// of their methods are invoked.
  DeviceManager() {
    // Register the known discoverers.
    _deviceDiscoverers.add(new AndroidDevices());
    _deviceDiscoverers.add(new IOSDevices());
    _deviceDiscoverers.add(new IOSSimulators());
  }

  List<DeviceDiscovery> _deviceDiscoverers = <DeviceDiscovery>[];

  /// A user-specified device ID.
  String specifiedDeviceId;

  bool get hasSpecifiedDeviceId => specifiedDeviceId != null;

  /// Return the device with the matching ID; else, complete the Future with
  /// `null`.
  ///
  /// This does a case insentitive compare with `deviceId`.
  Future<Device> getDeviceById(String deviceId) async {
    deviceId = deviceId.toLowerCase();
    List<Device> devices = await getAllConnectedDevices();
    Device device = devices.firstWhere(
      (Device device) => device.id.toLowerCase() == deviceId,
      orElse: () => null
    );

    if (device != null)
      return device;

    // Match on a close id / name.
    devices = devices.where((Device device) {
      return (device.id.toLowerCase().startsWith(deviceId) ||
        device.name.toLowerCase().startsWith(deviceId));
    });

    return devices.length == 1 ? devices.first : null;
  }

  /// Return the list of connected devices, filtered by any user-specified device id.
  Future<List<Device>> getDevices() async {
    if (specifiedDeviceId == null) {
      return getAllConnectedDevices();
    } else {
      Device device = await getDeviceById(specifiedDeviceId);
      return device == null ? <Device>[] : <Device>[device];
    }
  }

  /// Return the list of all connected devices.
  Future<List<Device>> getAllConnectedDevices() async {
    return _deviceDiscoverers
      .where((DeviceDiscovery discoverer) => discoverer.supportsPlatform)
      .expand((DeviceDiscovery discoverer) => discoverer.devices)
      .toList();
  }
}

/// An abstract class to discover and enumerate a specific type of devices.
abstract class DeviceDiscovery {
  bool get supportsPlatform;
  List<Device> get devices;
}

/// A [DeviceDiscovery] implementation that uses polling to discover device adds
/// and removals.
abstract class PollingDeviceDiscovery extends DeviceDiscovery {
  PollingDeviceDiscovery(this.name);

  static const Duration _pollingDuration = const Duration(seconds: 4);

  final String name;
  ItemListNotifier<Device> _items;
  Timer _timer;

  List<Device> pollingGetDevices();

  void startPolling() {
    if (_timer == null) {
      if (_items == null)
        _items = new ItemListNotifier<Device>();
      _timer = new Timer.periodic(_pollingDuration, (Timer timer) {
        _items.updateWithNewList(pollingGetDevices());
      });
    }
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  List<Device> get devices {
    if (_items == null)
      _items = new ItemListNotifier<Device>.from(pollingGetDevices());
    return _items.items;
  }

  Stream<Device> get onAdded {
    if (_items == null)
      _items = new ItemListNotifier<Device>();
    return _items.onAdded;
  }

  Stream<Device> get onRemoved {
    if (_items == null)
      _items = new ItemListNotifier<Device>();
    return _items.onRemoved;
  }

  void dispose() => stopPolling();

  @override
  String toString() => '$name device discovery';
}

abstract class Device {
  Device(this.id);

  final String id;

  String get name;

  bool get supportsStartPaused => true;

  /// Whether it is an emulated device running on localhost.
  bool get isLocalEmulator;

  /// Install an app package on the current device
  bool installApp(ApplicationPackage app);

  /// Check if the device is supported by Flutter
  bool isSupported();

  // String meant to be displayed to the user indicating if the device is
  // supported by Flutter, and, if not, why.
  String supportMessage() => isSupported() ? "Supported" : "Unsupported";

  /// Check if the current version of the given app is already installed
  bool isAppInstalled(ApplicationPackage app);

  TargetPlatform get platform;

  /// Get the log reader for this device.
  DeviceLogReader get logReader;

  /// Get the port forwarder for this device.
  DevicePortForwarder get portForwarder;

  /// Clear the device's logs.
  void clearLogs();

  /// Start an app package on the current device.
  ///
  /// [platformArgs] allows callers to pass platform-specific arguments to the
  /// start call.
  Future<bool> startApp(
    ApplicationPackage package,
    Toolchain toolchain, {
    String mainPath,
    String route,
    bool checked: true,
    bool clearLogs: false,
    bool startPaused: false,
    int observatoryPort: observatoryDefaultPort,
    int diagnosticPort: diagnosticDefaultPort,
    Map<String, dynamic> platformArgs
  });

  /// Stop an app package on the current device.
  Future<bool> stopApp(ApplicationPackage app);

  bool get supportsScreenshot => false;

  Future<bool> takeScreenshot(File outputFile) => new Future<bool>.error('unimplemented');

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other))
      return true;
    if (other is! Device)
      return false;
    return id == other.id;
  }

  @override
  String toString() => name;

  static void printDevices(List<Device> devices) {
    int nameWidth = 0;
    int idWidth = 0;

    for (Device device in devices) {
      nameWidth = math.max(nameWidth, device.name.length);
      idWidth = math.max(idWidth, device.id.length);
    }

    for (Device device in devices) {
      String supportIndicator = device.isSupported() ? '' : ' (unsupported)';
      printStatus('${device.name.padRight(nameWidth)} • '
        '${device.id.padRight(idWidth)} • '
        '${getNameForTargetPlatform(device.platform)}$supportIndicator');
    }
  }
}

class ForwardedPort {
  ForwardedPort(this.hostPort, this.devicePort);

  final int hostPort;
  final int devicePort;

  @override
  String toString() => 'ForwardedPort HOST:$hostPort to DEVICE:$devicePort';
}

/// Forward ports from the host machine to the device.
abstract class DevicePortForwarder {
  /// Returns a Future that completes with the current list of forwarded
  /// ports for this device.
  List<ForwardedPort> get forwardedPorts;

  /// Forward [hostPort] on the host to [devicePort] on the device.
  /// If [hostPort] is null, will auto select a host port.
  /// Returns a Future that completes with the host port.
  Future<int> forward(int devicePort, {int hostPort: null});

  /// Stops forwarding [forwardedPort].
  Future<Null> unforward(ForwardedPort forwardedPort);
}

/// Read the log for a particular device. Subclasses must implement `hashCode`
/// and `operator ==` so that log readers that read from the same location can be
/// de-duped. For example, two Android devices will both try and log using
/// `adb logcat`; we don't want to display two identical log streams.
abstract class DeviceLogReader {
  String get name;

  /// A broadcast stream where each element in the string is a line of log
  /// output.
  Stream<String> get lines;

  /// Start reading logs from the device.
  Future<Null> start();

  /// Actively reading lines from the log?
  bool get isReading;

  /// Actively stop reading logs from the device.
  Future<Null> stop();

  /// Completes when the log is finished.
  Future<int> get finished;

  @override
  int get hashCode;

  @override
  bool operator ==(dynamic other);

  @override
  String toString() => name;
}
