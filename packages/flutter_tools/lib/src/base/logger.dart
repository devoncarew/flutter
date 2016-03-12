// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

final _terminal = new _AnsiTerminal();

abstract class Logger {
  bool get isVerbose => false;

  /// Display an error level message to the user. Commands should use this if they
  /// fail in some way.
  void printError(String message, [StackTrace stackTrace]);

  /// Display normal output of the command. This should be used for things like
  /// progress messages, success messages, or just normal command output.
  void printStatus(String message);

  /// Use this for verbose tracing output. Users can turn this output on in order
  /// to help diagnose issues with the toolchain or with their setup.
  void printTrace(String message);

  /// Flush any buffered output.
  void flush() { }
}

class StdoutLogger implements Logger {
  bool get isVerbose => false;

  void printError(String message, [StackTrace stackTrace]) {
    stderr.writeln(message);
    if (stackTrace != null)
      stderr.writeln(stackTrace);
  }

  void printStatus(String message) => print(message);

  void printTrace(String message) { }

  void flush() { }
}

class BufferLogger implements Logger {
  bool get isVerbose => false;

  StringBuffer _error = new StringBuffer();
  StringBuffer _status = new StringBuffer();
  StringBuffer _trace = new StringBuffer();

  String get errorText => _error.toString();
  String get statusText => _status.toString();
  String get traceText => _trace.toString();

  void printError(String message, [StackTrace stackTrace]) => _error.writeln(message);
  void printStatus(String message) => _status.writeln(message);
  void printTrace(String message) => _trace.writeln(message);

  void flush() { }
}

class VerboseLogger implements Logger {
  _LogMessage lastMessage;

  bool get isVerbose => true;

  void printError(String message, [StackTrace stackTrace]) {
    _emit();
    lastMessage = new _LogMessage(_LogType.error, message, stackTrace);
    flush();
  }

  void printStatus(String message) {
    _emit();
    lastMessage = new _LogMessage(_LogType.status, message);
  }

  void printTrace(String message) {
    _emit();
    lastMessage = new _LogMessage(_LogType.trace, message);
  }

  void flush() => _emit();

  void _emit() {
    lastMessage?.emit();
    lastMessage = null;
  }
}

enum _LogType {
  error,
  status,
  trace
}

class _LogMessage {
  _LogMessage(this.type, this.message, [this.stackTrace]) {
    stopwatch.start();
  }

  final _LogType type;
  final String message;
  final StackTrace stackTrace;

  Stopwatch stopwatch = new Stopwatch();

  void emit() {
    stopwatch.stop();

    int millis = stopwatch.elapsedMilliseconds;
    String prefix = '${millis.toString().padLeft(4)} ms • ';
    String indent = ''.padLeft(prefix.length);
    if (millis >= 100)
      prefix = _terminal.writeBold(prefix.substring(0, prefix.length - 3)) + ' • ';
    String indentMessage = message.replaceAll('\n', '\n$indent');

    if (type == _LogType.error) {
      stderr.writeln(prefix + _terminal.writeBold(indentMessage));
      if (stackTrace != null)
        stderr.writeln(indent + stackTrace.toString().replaceAll('\n', '\n$indent'));
    } else if (type == _LogType.status) {
      print(prefix + _terminal.writeBold(indentMessage));
    } else {
      print(prefix + indentMessage);
    }
  }
}

class _AnsiTerminal {
  _AnsiTerminal() {
    String term = Platform.environment['TERM'];
    _supportsColor = term != null && term != 'dumb';
  }

  static const String _bold = '\u001B[1m';
  static const String _reset = '\u001B[0m';

  bool _supportsColor;
  bool get supportsColor => _supportsColor;

  String writeBold(String str) => supportsColor ? '$_bold$str$_reset' : str;
}
