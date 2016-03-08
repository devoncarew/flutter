// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

Process daemon;

// To use, start from the console and enter:
//   version: print version
//   shutdown: terminate the server
//   start: start an app
//   stopAll: stop any running app
//   devices: list devices

main() async {
  daemon = await Process.start('flutter', ['daemon']);
  print('daemon process started, pid: ${daemon.pid}');

  daemon.stdout
    .transform(UTF8.decoder)
    .transform(const LineSplitter())
    .listen((String line) => print('<== $line'));
  daemon.stderr.listen((data) => stderr.add(data));

  stdout.write('> ');
  stdin.transform(UTF8.decoder).transform(const LineSplitter()).listen((String line) {
    if (line == 'version' || line == 'v') {
      _send({'method': 'daemon.version'});
    } else if (line == 'shutdown' || line == 'q') {
      _send({'method': 'daemon.shutdown'});
    } else if (line == 'start') {
      _send({'method': 'app.start'});
    } else if (line == 'stopAll') {
      _send({'method': 'app.stopAll'});
    } else if (line == 'devices') {
      _send({'method': 'device.getDevices'});
    } else {
      print('command not understood: $line');
    }
    stdout.write('> ');
  });

  daemon.exitCode.then((int code) {
    print('daemon exiting ($code)');
    exit(code);
  });
}

int id = 0;

void _send(Map map) {
  map['id'] = id++;
  String str = '[${JSON.encode(map)}]';
  daemon.stdin.writeln(str);
  print('==> $str');
}
