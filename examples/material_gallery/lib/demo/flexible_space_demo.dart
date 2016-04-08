// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class _ContactCategory extends StatelessWidget {
  _ContactCategory({ Key key, this.icon, this.children }) : super(key: key);

  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return new Container(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      decoration: new BoxDecoration(
        border: new Border(bottom: new BorderSide(color: Theme.of(context).dividerColor))
      ),
      child: new DefaultTextStyle(
        style: Theme.of(context).textTheme.subhead,
        child: new Row(
          children: <Widget>[
            new SizedBox(
              width: 72.0,
              child: new Icon(icon: icon, color: Theme.of(context).primaryColor)
            ),
            new Flexible(child: new Column(children: children))
          ]
        )
      )
    );
  }
}

class _ContactItem extends StatelessWidget {
  _ContactItem({ Key key, this.icon, this.lines }) : super(key: key) {
    assert(lines.length > 1);
  }

  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    List<Widget> columnChildren = lines.sublist(0, lines.length - 1).map((String line) => new Text(line)).toList();
    columnChildren.add(new Text(lines.last, style: Theme.of(context).textTheme.caption));

    List<Widget> rowChildren = <Widget>[
      new Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columnChildren
      )
    ];
    if (icon != null) {
      rowChildren.add(new SizedBox(
        width: 72.0,
        child: new Icon(icon: icon, color: Theme.of(context).disabledColor)
      ));
    }
    return new Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: new Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: rowChildren
      )
    );
  }
}

class FlexibleSpaceDemo extends StatefulWidget {
  @override
  FlexibleSpaceDemoState createState() => new FlexibleSpaceDemoState();
}

class FlexibleSpaceDemoState extends State<FlexibleSpaceDemo> {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  final double _appBarHeight = 256.0;
  final Key _scrollableKey = new UniqueKey();
  AppBarBehavior _appBarBehavior = AppBarBehavior.scroll;

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return new Theme(
      data: new ThemeData(
        brightness: ThemeBrightness.light,
        primarySwatch: Colors.indigo
      ),
      child: new Scaffold(
        key: _scaffoldKey,
        scrollableKey: _scrollableKey,
        appBarBehavior: _appBarBehavior,
        appBar: new AppBar(
          expandedHeight: _appBarHeight,
          actions: <Widget>[
            new IconButton(
              icon: Icons.create,
              tooltip: 'Search',
              onPressed: () {
                _scaffoldKey.currentState.showSnackBar(new SnackBar(
                  content: new Text('Not supported.')
                ));
              }
            ),
            new PopupMenuButton<AppBarBehavior>(
              onSelected: (AppBarBehavior value) {
                setState(() {
                  _appBarBehavior = value;
                });
              },
              itemBuilder: (BuildContext context) => <PopupMenuItem<AppBarBehavior>>[
                new PopupMenuItem<AppBarBehavior>(
                  value: AppBarBehavior.scroll,
                  child: new Text('Toolbar scrolls away')
                ),
                new PopupMenuItem<AppBarBehavior>(
                  value: AppBarBehavior.under,
                  child: new Text('Toolbar stays put')
                )
              ]
            )
          ],
          flexibleSpace: new FlexibleSpaceBar(
            title : new Text('Ali Connors'),
            image: new AssetImage(
              name: 'packages/flutter_gallery_assets/ali_connors.png',
              fit: ImageFit.cover,
              height: _appBarHeight
            )
          )
        ),
        body: new Block(
          scrollableKey: _scrollableKey,
          padding: new EdgeInsets.only(top: _appBarHeight + statusBarHeight),
          children: <Widget>[
            new _ContactCategory(
              icon: Icons.call,
              children: <Widget>[
                new _ContactItem(
                  icon: Icons.message,
                  lines: <String>[
                    '(650) 555-1234',
                    'Mobile'
                  ]
                ),
                new _ContactItem(
                  icon: Icons.message,
                  lines: <String>[
                    '(323) 555-6789',
                    'Work'
                  ]
                )
              ]
            ),
            new _ContactCategory(
              icon: Icons.email,
              children: <Widget>[
                new _ContactItem(
                  lines: <String>[
                    'ali_connors@example.com',
                    'Personal'
                  ]
                ),
                new _ContactItem(
                  lines: <String>[
                    'aliconnors@example.com',
                    'Work'
                  ]
                )
              ]
            ),
            new _ContactCategory(
              icon: Icons.location_on,
              children: <Widget>[
                new _ContactItem(
                  lines: <String>[
                    '2000 Main Street',
                    'San Francisco, CA',
                    'Home'
                  ]
                ),
                new _ContactItem(
                  lines: <String>[
                    '1600 Amphitheater Parkway',
                    'Mountain View, CA',
                    'Work'
                  ]
                ),
                new _ContactItem(
                  lines: <String>[
                    '126 Severyns Ave',
                    'Mountain View, CA',
                    'Jet Travel'
                  ]
                )
              ]
            )
          ]
        )
      )
    );
  }
}
