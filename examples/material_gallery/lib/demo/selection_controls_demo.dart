// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../gallery/demo.dart';

const String _checkboxText =
  "# Checkboxes\n"
  "Checkboxes allow the user to select multiple options from a set.";

const String _checkboxCode =
"""// Member variable holding the checkbox's value.
bool checkboxValue = false;

// Create a checkbox.
new Checkbox(
  value: checkboxValue,
  onChanged: (bool value) {
    setState(() {
      checkboxValue = value;
    }
  );
})

// Create a disabled checkbox.
// Checkboxes are disabled when onChanged isn't
// specified or null.
new Checkbox(value: false)""";

const String _radioText =
  "# Radio buttons\n"
  "Radio buttons allow the user to select one option from a set. Use radio "
  "buttons for exclusive selection if you think that the user needs to see "
  "all available options side-by-side.";

const String _radioCode =
"""// Member variable holding value.
int radioValue = 0;

// Method setting value.
void handleRadioValueChanged(int value) {
  setState(() {
    radioValue = value;
  });
}

// Creates a set of radio buttons.
new Row(
  children: <Widget>[
    new Radio<int>(
      value: 0,
      groupValue: radioValue,
      onChanged: handleRadioValueChanged
    ),
    new Radio<int>(
      value: 1,
      groupValue: radioValue,
      onChanged: handleRadioValueChanged
    ),
    new Radio<int>(
      value: 2,
      groupValue: radioValue,
      onChanged: handleRadioValueChanged
    )
  ]
);

// Creates a disabled radio button.
new Radio<int>(
  value: 0,
  groupValue: 0
);""";

const String _switchText =
  "# Switches\n"
  "On/off switches toggle the state of a single settings option. The option "
  "that the switch controls, as well as the state it’s in, should be made "
  "clear from the corresponding inline label.";

const String _switchCode =
"""// Member variable holding value.
bool switchValue = false;

// Create a switch.
new Switch(
  value: switchValue,
  onChanged: (bool value) {
    setState(() {
      switchValue = value;
    }
  );
})

// Create a disabled switch.
// Switches are disabled when onChanged isn't
// specified or null.
new Switch(value: false)""";

class SelectionControlsDemo extends StatefulWidget {
  @override
  _SelectionControlsDemoState createState() => new _SelectionControlsDemoState();
}

class _SelectionControlsDemoState extends State<SelectionControlsDemo> {
  @override
  Widget build(BuildContext context) {
    List<ComponentDemoTabData> demos = <ComponentDemoTabData>[
      new ComponentDemoTabData(
        tabName: "CHECKBOX",
        description: _checkboxText,
        widget: buildCheckbox(),
        exampleCode: _checkboxCode
      ),
      new ComponentDemoTabData(
        tabName: "RADIO",
        description: _radioText,
        widget: buildRadio(),
        exampleCode: _radioCode
      ),
      new ComponentDemoTabData(
        tabName: "SWITCH",
        description: _switchText,
        widget: buildSwitch(),
        exampleCode: _switchCode
      )
    ];

    return new TabbedComponentDemoScaffold(
      title: 'Selection Controls',
      demos: demos
    );
  }

  bool checkboxValueA = true;
  bool checkboxValueB = false;
  int radioValue = 0;
  bool switchValue = false;

  void handleRadioValueChanged(int value) {
    setState(() {
      radioValue = value;
    });
  }

  Widget buildCheckbox() {
    return new Align(
      alignment: new FractionalOffset(0.5, 0.4),
      child: new Column(
        mainAxisAlignment: MainAxisAlignment.collapse,
        children: <Widget>[
          new Row(
            mainAxisAlignment: MainAxisAlignment.collapse,
            children: <Widget>[
              new Checkbox(value: checkboxValueA, onChanged: (bool value) {
                setState(() {
                  checkboxValueA = value;
                });
              }),
              new Checkbox(value: checkboxValueB, onChanged: (bool value) {
                setState(() {
                  checkboxValueB = value;
                });
              })
            ]
          ),
          new Row(
            mainAxisAlignment: MainAxisAlignment.collapse,
            children: <Widget>[
              // Disabled checkboxes
              new Checkbox(value: true),
              new Checkbox(value: false)
            ]
          )
        ]
      )
    );
  }

  Widget buildRadio() {
    return new Align(
      alignment: new FractionalOffset(0.5, 0.4),
      child: new Column(
        mainAxisAlignment: MainAxisAlignment.collapse,
        children: <Widget>[
          new Row(
            mainAxisAlignment: MainAxisAlignment.collapse,
            children: <Widget>[
              new Radio<int>(
                value: 0,
                groupValue: radioValue,
                onChanged: handleRadioValueChanged
              ),
              new Radio<int>(
                value: 1,
                groupValue: radioValue,
                onChanged: handleRadioValueChanged
              ),
              new Radio<int>(
                value: 2,
                groupValue: radioValue,
                onChanged: handleRadioValueChanged
              )
            ]
          ),
          // Disabled radio buttons
          new Row(
            mainAxisAlignment: MainAxisAlignment.collapse,
            children: <Widget>[
              new Radio<int>(
                value: 0,
                groupValue: 0
              ),
              new Radio<int>(
                value: 1,
                groupValue: 0
              ),
              new Radio<int>(
                value: 2,
                groupValue: 0
              )
            ]
          )
        ]
      )
    );
  }

  Widget buildSwitch() {
    return new Align(
      alignment: new FractionalOffset(0.5, 0.4),
      child: new Row(
        mainAxisAlignment: MainAxisAlignment.collapse,
        children: <Widget>[
          new Switch(value: switchValue, onChanged: (bool value) {
            setState(() {
              switchValue = value;
            });
          }),
          // Disabled switches
          new Switch(value: true),
          new Switch(value: false)
        ]
      )
    );
  }
}
