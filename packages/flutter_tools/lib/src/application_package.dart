// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

import 'artifacts.dart';
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

  String toString() => displayName;
}

class AndroidApk extends ApplicationPackage {
  static const String _defaultName = 'SkyShell.apk';
  static const String _defaultId = 'org.domokit.sky.shell';
  static const String _defaultLaunchActivity = '$_defaultId/$_defaultId.SkyActivity';
  static const String _defaultManifestPath = 'android/AndroidManifest.xml';
  static const String _defaultOutputPath = 'build/app.apk';

  /// The path to the activity that should be launched.
  /// Defaults to 'org.domokit.sky.shell/org.domokit.sky.shell.SkyActivity'
  final String launchActivity;

  AndroidApk({
    String localPath,
    String id: _defaultId,
    this.launchActivity: _defaultLaunchActivity
  }) : super(localPath: localPath, id: id) {
    assert(launchActivity != null);
  }

  /// Creates a new AndroidApk based on the information in the Android manifest.
  static AndroidApk getCustomApk({
    String localPath: _defaultOutputPath,
    String manifest: _defaultManifestPath
  }) {
    if (!FileSystemEntity.isFileSync(manifest))
      return null;
    String manifestString = new File(manifest).readAsStringSync();
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

    String plistPath = path.join("ios", "Info.plist");
    String value = getValueFromFile(plistPath, kCFBundleIdentifierKey);
    if (value == null)
      return null;

    String projectDir = path.join("ios", ".generated");
    return new IOSApp(iosProjectDir: projectDir, iosProjectBundleId: value);
  }

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
      case TargetPlatform.ios_arm:
      case TargetPlatform.ios_x64:
        return iOS;
      case TargetPlatform.darwin_x64:
      case TargetPlatform.linux_x64:
        return null;
    }
  }

  static Future<ApplicationPackageStore> forConfigs(List<BuildConfiguration> configs) async {
    AndroidApk android;
    IOSApp iOS;

    for (BuildConfiguration config in configs) {
      switch (config.targetPlatform) {
        case TargetPlatform.android_arm:
        case TargetPlatform.android_x64:
          // TODO: ???
          // assert(android == null);
          // TODO: This is totally wrong.
          // android ??= AndroidApk.getCustomApk();
          android = AndroidApk.getCustomApk();
          // Fall back to the prebuilt or engine-provided apk if we can't build
          // a custom one.
          // TODO(mpcomplete): we should remove both these fallbacks.
          if (android != null) {
            break;
          } else if (config.type != BuildType.prebuilt) {
            String localPath = path.join(config.buildDir, 'apks', AndroidApk._defaultName);
            android = new AndroidApk(localPath: localPath);
          } else {
            Artifact artifact = ArtifactStore.getArtifact(
              type: ArtifactType.shell, targetPlatform: config.targetPlatform);
            android = new AndroidApk(localPath: await ArtifactStore.getPath(artifact));
          }
          break;

        case TargetPlatform.ios_arm:
        case TargetPlatform.ios_x64:
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
