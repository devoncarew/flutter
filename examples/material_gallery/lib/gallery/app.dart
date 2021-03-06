// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

import 'home.dart';

class GalleryApp extends StatefulWidget {
  GalleryApp({ Key key }) : super(key: key);

  @override
  GalleryAppState createState() => new GalleryAppState();
}

class GalleryAppState extends State<GalleryApp> {
  bool _useLightTheme = true;

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Flutter Material Gallery',
      theme: _useLightTheme ? _kGalleryLightTheme : _kGalleryDarkTheme,
      routes: {
        '/': (BuildContext context) => new GalleryHome(
          theme: _useLightTheme,
          onThemeChanged: (bool value) { setState(() { _useLightTheme = value; }); },
          timeDilation: timeDilation,
          onTimeDilationChanged: (double value) { setState(() { timeDilation = value; }); }
        )
      }
    );
  }
}

ThemeData _kGalleryLightTheme = new ThemeData(
  brightness: ThemeBrightness.light,
  primarySwatch: Colors.purple
);

ThemeData _kGalleryDarkTheme = new ThemeData(
  brightness: ThemeBrightness.dark,
  primarySwatch: Colors.purple
);
