// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

import 'build_configuration.dart';
import 'ios/plist_utils.dart';

abstract class ApplicationPackage {
  /// Path to the actual apk or bundle.
  final String localPath;

  /// Package ID from the Android Manifest or equivalent.
  final String id;

  /// File name of the apk or bundle.
  final String name;

  ApplicationPackage({
    String localPath,
    this.id
  }) : localPath = localPath, name = path.basename(localPath) {
    assert(localPath != null);
    assert(id != null);
  }

  String get displayName => name;

  @override
  String toString() => displayName;
}

class AndroidApk extends ApplicationPackage {
  /// The path to the activity that should be launched.
  final String launchActivity;

  AndroidApk({
    String localPath,
    String id,
    this.launchActivity
  }) : super(localPath: localPath, id: id) {
    assert(launchActivity != null);
  }

  /// Creates a new AndroidApk based on the information in the Android manifest.
  factory AndroidApk.fromBuildConfiguration(BuildConfiguration config) {
    String manifestPath = path.join('android', 'AndroidManifest.xml');
    if (!FileSystemEntity.isFileSync(manifestPath))
      return null;
    String manifestString = new File(manifestPath).readAsStringSync();
    xml.XmlDocument document = xml.parse(manifestString);

    Iterable<xml.XmlElement> manifests = document.findElements('manifest');
    if (manifests.isEmpty)
      return null;
    String id = manifests.first.getAttribute('package');

    String launchActivity;
    for (xml.XmlElement category in document.findAllElements('category')) {
      if (category.getAttribute('android:name') == 'android.intent.category.LAUNCHER') {
        xml.XmlElement activity = category.parent.parent;
        String activityName = activity.getAttribute('android:name');
        launchActivity = "$id/$activityName";
        break;
      }
    }
    if (id == null || launchActivity == null)
      return null;

    String localPath = path.join('build', 'app.apk');
    return new AndroidApk(localPath: localPath, id: id, launchActivity: launchActivity);
  }
}

class IOSApp extends ApplicationPackage {
  IOSApp({
    String iosProjectDir,
    String iosProjectBundleId
  }) : super(localPath: iosProjectDir, id: iosProjectBundleId);

  factory IOSApp.fromBuildConfiguration(BuildConfiguration config) {
    if (getCurrentHostPlatform() != HostPlatform.mac)
      return null;

    String plistPath = path.join('ios', 'Info.plist');
    String value = getValueFromFile(plistPath, kCFBundleIdentifierKey);
    if (value == null)
      return null;

    String projectDir = path.join('ios', '.generated');
    return new IOSApp(iosProjectDir: projectDir, iosProjectBundleId: value);
  }

  @override
  String get displayName => id;
}

class ApplicationPackageStore {
  final AndroidApk android;
  final IOSApp iOS;

  ApplicationPackageStore({ this.android, this.iOS });

  ApplicationPackage getPackageForPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android_arm:
      case TargetPlatform.android_x64:
        return android;
      case TargetPlatform.ios:
        return iOS;
      case TargetPlatform.darwin_x64:
      case TargetPlatform.linux_x64:
        return null;
    }
  }

  static ApplicationPackageStore forConfigs(List<BuildConfiguration> configs) {
    AndroidApk android;
    IOSApp iOS;

    for (BuildConfiguration config in configs) {
      switch (config.targetPlatform) {
        case TargetPlatform.android_arm:
        case TargetPlatform.android_x64:
          android ??= new AndroidApk.fromBuildConfiguration(config);
          break;

        case TargetPlatform.ios:
          iOS ??= new IOSApp.fromBuildConfiguration(config);
          break;

        case TargetPlatform.darwin_x64:
        case TargetPlatform.linux_x64:
          break;
      }
    }

    return new ApplicationPackageStore(android: android, iOS: iOS);
  }
}
