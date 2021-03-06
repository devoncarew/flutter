// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

List<int> items = <int>[0, 1, 2, 3, 4, 5];

Widget buildCard(BuildContext context, int index) {
  if (index >= items.length)
    return null;
  return new Container(
    key: new ValueKey<int>(items[index]),
    height: 100.0,
    child: new DefaultTextStyle(
      style: new TextStyle(fontSize: 2.0 + items.length.toDouble()),
      child: new Text('${items[index]}')
    )
  );
}

Widget buildFrame() {
  return new LazyBlock(
    delegate: new LazyBlockBuilder(builder: buildCard)
  );
}

void main() {
  test('LazyBlock is a build function (smoketest)', () {
    testWidgets((WidgetTester tester) {
      tester.pumpWidget(buildFrame());
      expect(tester.findText('0'), isNotNull);
      expect(tester.findText('1'), isNotNull);
      expect(tester.findText('2'), isNotNull);
      expect(tester.findText('3'), isNotNull);
      items.removeAt(2);
      tester.pumpWidget(buildFrame());
      expect(tester.findText('0'), isNotNull);
      expect(tester.findText('1'), isNotNull);
      expect(tester.findText('2'), isNull);
      expect(tester.findText('3'), isNotNull);
    });
  });
}
