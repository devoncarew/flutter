// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../base/os.dart';
import '../globals.dart';

// Android SDK layout:
//
// $ANDROID_HOME/platform-tools/adb
// $ANDROID_HOME/build-tools/19.1.0/aapt, dx, zipalign
// $ANDROID_HOME/build-tools/22.0.1/aapt
// $ANDROID_HOME/build-tools/23.0.2/aapt
// $ANDROID_HOME/platforms/android-22/android.jar
// $ANDROID_HOME/platforms/android-23/android.jar

// TODO(devoncarew): We need a way to locate the Android SDK w/o using an environment variable.
// Perhaps something like `flutter config --android-home=foo/bar`.

/// Locate ADB. Prefer to use one from an Android SDK, if we can locate that.
String getAdbPath([AndroidSdk existingSdk]) {
  if (existingSdk?.adbPath != null)
    return existingSdk.adbPath;

  AndroidSdk sdk = AndroidSdk.locateAndroidSdk();

  if (sdk?.latestVersion == null) {
    return os.which('adb')?.path;
  } else {
    return sdk.adbPath;
  }
}

class AndroidSdk {
  AndroidSdk(this.directory) {
    _init();
  }

  final String directory;

  List<AndroidSdkVersion> _sdkVersions;
  AndroidSdkVersion _latestVersion;

  static AndroidSdk locateAndroidSdk() {
    // TODO(devoncarew): Use explicit configuration information from a metadata file?

    String androidHomeDir;
    if (Platform.environment.containsKey('ANDROID_HOME')) {
      androidHomeDir = Platform.environment['ANDROID_HOME'];
    } else if (Platform.isLinux) {
      String homeDir = Platform.environment['HOME'];
      if (homeDir != null)
        androidHomeDir = '$homeDir/Android/Sdk';
    } else if (Platform.isMacOS) {
      String homeDir = Platform.environment['HOME'];
      if (homeDir != null)
        androidHomeDir = '$homeDir/Library/Android/sdk';
    }

    if (androidHomeDir != null) {
      if (validSdkDirectory(androidHomeDir))
        return new AndroidSdk(androidHomeDir);
      if (validSdkDirectory(path.join(androidHomeDir, 'sdk')))
        return new AndroidSdk(path.join(androidHomeDir, 'sdk'));
    }

    File aaptBin = os.which('aapt'); // in build-tools/$version/aapt
    if (aaptBin != null) {
      String dir = aaptBin.parent.parent.parent.path;
      if (validSdkDirectory(dir))
        return new AndroidSdk(dir);
    }

    File adbBin = os.which('adb'); // in platform-tools/adb
    if (adbBin != null) {
      String dir = adbBin.parent.parent.path;
      if (validSdkDirectory(dir))
        return new AndroidSdk(dir);
    }

    // No dice.
    printTrace('Unable to locate an Android SDK.');
    return null;
  }

  static bool validSdkDirectory(String dir) {
    return FileSystemEntity.isDirectorySync(path.join(dir, 'platform-tools'));
  }

  List<AndroidSdkVersion> get sdkVersions => _sdkVersions;

  AndroidSdkVersion get latestVersion => _latestVersion;

  String get adbPath => getPlatformToolsPath('adb');

  bool validateSdkWellFormed({ bool complain: false }) {
    if (!FileSystemEntity.isFileSync(adbPath)) {
      if (complain)
        printError('Android SDK file not found: $adbPath.');
      return false;
    }

    if (sdkVersions.isEmpty) {
      if (complain)
        printError('Android SDK does not have the proper build-tools.');
      return false;
    }

    return latestVersion.validateSdkWellFormed(complain: complain);
  }

  String getPlatformToolsPath(String binaryName) {
    return path.join(directory, 'platform-tools', binaryName);
  }

  void _init() {
    List<String> platforms = <String>[]; // android-22, ...

    Directory platformsDir = new Directory(path.join(directory, 'platforms'));
    if (platformsDir.existsSync()) {
      platforms = platformsDir
        .listSync()
        .map((FileSystemEntity entity) => path.basename(entity.path))
        .where((String name) => name.startsWith('android-'))
        .toList();
    }

    List<Version> buildToolsVersions = <Version>[]; // 19.1.0, 22.0.1, ...

    Directory buildToolsDir = new Directory(path.join(directory, 'build-tools'));
    if (buildToolsDir.existsSync()) {
      buildToolsVersions = buildToolsDir
        .listSync()
        .map((FileSystemEntity entity) {
          try {
            return new Version.parse(path.basename(entity.path));
          } catch (error) {
            return null;
          }
        })
        .where((Version version) => version != null)
        .toList();
    }

    // Here we match up platforms with cooresponding build-tools. If we don't
    // have a match, we don't return anything for that platform version. So if
    // the user only have 'android-22' and 'build-tools/19.0.0', we don't find
    // an Android sdk.
    _sdkVersions = platforms.map((String platform) {
      int sdkVersion;

      try {
        sdkVersion = int.parse(platform.substring('android-'.length));
      } catch (error) {
        return null;
      }

      Version buildToolsVersion = Version.primary(buildToolsVersions.where((Version version) {
        return version.major == sdkVersion;
      }).toList());

      if (buildToolsVersion == null)
        return null;

      return new AndroidSdkVersion(this, platform, buildToolsVersion.toString());
    }).where((AndroidSdkVersion version) => version != null).toList();

    _sdkVersions.sort();

    _latestVersion = _sdkVersions.isEmpty ? null : _sdkVersions.last;
  }

  String toString() => 'AndroidSdk: $directory';
}

class AndroidSdkVersion implements Comparable<AndroidSdkVersion> {
  AndroidSdkVersion(this.sdk, this.androidVersion, this.buildToolsVersion);

  final AndroidSdk sdk;
  final String androidVersion;
  final String buildToolsVersion;

  int get sdkLevel => int.parse(androidVersion.substring('android-'.length));

  String get androidJarPath => getPlatformsPath('android.jar');

  String get aaptPath => getBuildToolsPath('aapt');

  String get dxPath => getBuildToolsPath('dx');

  String get zipalignPath => getBuildToolsPath('zipalign');

  bool validateSdkWellFormed({ bool complain: false }) {
    return
      _exists(androidJarPath, complain: complain) &&
      _exists(aaptPath, complain: complain) &&
      _exists(dxPath, complain: complain) &&
      _exists(zipalignPath, complain: complain);
  }

  String getPlatformsPath(String itemName) {
    return path.join(sdk.directory, 'platforms', androidVersion, itemName);
  }

  String getBuildToolsPath(String binaryName) {
    return path.join(sdk.directory, 'build-tools', buildToolsVersion, binaryName);
  }

  int compareTo(AndroidSdkVersion other) {
    return sdkLevel - other.sdkLevel;
  }

  String toString() => '[${sdk.directory}, SDK version $sdkLevel, build-tools $buildToolsVersion]';

  bool _exists(String path, { bool complain: false }) {
    if (!FileSystemEntity.isFileSync(path)) {
      if (complain)
        printError('Android SDK file not found: $path.');
      return false;
    }

    return true;
  }
}
