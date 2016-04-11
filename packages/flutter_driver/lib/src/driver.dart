// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'package:vm_service_client/vm_service_client.dart';
import 'package:matcher/matcher.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;

import 'error.dart';
import 'find.dart';
import 'gesture.dart';
import 'health.dart';
import 'matcher_util.dart';
import 'message.dart';
import 'retry.dart';
import 'timeline.dart';

final Logger _log = new Logger('FlutterDriver');

/// Computes a value.
///
/// If computation is asynchronous, the function may return a [Future].
///
/// See also [FlutterDriver.waitFor].
typedef dynamic EvaluatorFunction();

/// Drives a Flutter Application running in another process.
class FlutterDriver {
  FlutterDriver.connectedTo(this._serviceClient, this._peer, this._appIsolate);

  static const String _kFlutterExtensionMethod = 'ext.flutter_driver';
  static const String _kSetVMTimelineFlagsMethod = '_setVMTimelineFlags';
  static const String _kGetVMTimelineMethod = '_getVMTimeline';
  static const Duration _kDefaultTimeout = const Duration(seconds: 5);
  static const Duration _kDefaultPauseBetweenRetries = const Duration(milliseconds: 160);

  /// Connects to a Flutter application.
  ///
  /// Resumes the application if it is currently paused (e.g. at a breakpoint).
  ///
  /// [dartVmServiceUrl] is the URL to Dart observatory (a.k.a. VM service). By
  /// default it connects to `http://localhost:8182`.
  static Future<FlutterDriver> connect({String dartVmServiceUrl: 'http://localhost:8182'}) async {
    // Connect to Dart VM servcies
    _log.info('Connecting to Flutter application at $dartVmServiceUrl');
    VMServiceClientConnection connection = await vmServiceConnectFunction(dartVmServiceUrl);
    VMServiceClient client = connection.client;
    VM vm = await client.getVM();
    _log.trace('Looking for the isolate');
    VMIsolate isolate = await vm.isolates.first.loadRunnable();

    // TODO(yjbanov): vm_service_client does not support "None" pause event yet.
    // It is currently reported as `null`, but we cannot rely on it because
    // eventually the event will be reported as a non-`null` object. For now,
    // list all the events we know about. Later we'll check for "None" event
    // explicitly.
    //
    // See: https://github.com/dart-lang/vm_service_client/issues/4
    if (isolate.pauseEvent is! VMPauseStartEvent &&
        isolate.pauseEvent is! VMPauseExitEvent &&
        isolate.pauseEvent is! VMPauseBreakpointEvent &&
        isolate.pauseEvent is! VMPauseExceptionEvent &&
        isolate.pauseEvent is! VMPauseInterruptedEvent &&
        isolate.pauseEvent is! VMResumeEvent) {
      await new Future<Null>.delayed(new Duration(milliseconds: 300));
      isolate = await vm.isolates.first.loadRunnable();
    }

    FlutterDriver driver = new FlutterDriver.connectedTo(client, connection.peer, isolate);

    // Attempts to resume the isolate, but does not crash if it fails because
    // the isolate is already resumed. There could be a race with other tools,
    // such as a debugger, any of which could have resumed the isolate.
    Future<dynamic> resumeLeniently() {
      _log.trace('Attempting to resume isolate');
      return isolate.resume().catchError((dynamic e) {
        const int vmMustBePausedCode = 101;
        if (e is rpc.RpcException && e.code == vmMustBePausedCode) {
          // No biggie; something else must have resumed the isolate
          _log.warning(
            'Attempted to resume an already resumed isolate. This may happen '
            'when we lose a race with another tool (usually a debugger) that '
            'is connected to the same isolate.'
          );
        } else {
          // Failed to resume due to another reason. Fail hard.
          throw e;
        }
      });
    }

    // Attempt to resume isolate if it was paused
    if (isolate.pauseEvent is VMPauseStartEvent) {
      _log.trace('Isolate is paused at start.');

      // Waits for a signal from the VM service that the extension is registered
      Future<String> waitForServiceExtension() {
        return isolate.onExtensionAdded.firstWhere((String extension) {
          return extension == _kFlutterExtensionMethod;
        });
      }

      // If the isolate is paused at the start, e.g. via the --start-paused
      // option, then the VM service extension is not registered yet. Wait for
      // it to be registered.
      Future<dynamic> whenResumed = resumeLeniently();
      Future<dynamic> whenServiceExtensionReady = Future.any/*<dynamic>*/(<Future<dynamic>>[
        waitForServiceExtension(),
        // We will never receive the extension event if the user does not
        // register it. If that happens time out.
        new Future<String>.delayed(const Duration(seconds: 10), () => 'timeout')
      ]);
      await whenResumed;
      _log.trace('Waiting for service extension');
      dynamic signal = await whenServiceExtensionReady;
      if (signal == 'timeout') {
        throw new DriverError(
          'Timed out waiting for Flutter Driver extension to become available. '
          'Ensure your test app (often: lib/main.dart) imports '
          '"package:flutter_driver/driver_extension.dart" and '
          'calls enableFlutterDriverExtension() as the first call in main().'
        );
      }
    } else if (isolate.pauseEvent is VMPauseExitEvent ||
               isolate.pauseEvent is VMPauseBreakpointEvent ||
               isolate.pauseEvent is VMPauseExceptionEvent ||
               isolate.pauseEvent is VMPauseInterruptedEvent) {
      // If the isolate is paused for any other reason, assume the extension is
      // already there.
      _log.trace('Isolate is paused mid-flight.');
      await resumeLeniently();
    } else if (isolate.pauseEvent is VMResumeEvent) {
      _log.trace('Isolate is not paused. Assuming application is ready.');
    } else {
      _log.warning(
        'Unknown pause event type ${isolate.pauseEvent.runtimeType}. '
        'Assuming application is ready.'
      );
    }

    // At this point the service extension must be installed. Verify it.
    Health health = await driver.checkHealth();
    if (health.status != HealthStatus.ok) {
      client.close();
      throw new DriverError('Flutter application health check failed.');
    }

    _log.info('Connected to Flutter application.');
    return driver;
  }

  /// Client connected to the Dart VM running the Flutter application
  final VMServiceClient _serviceClient;
  /// JSON-RPC client useful for sending raw JSON requests.
  final rpc.Peer _peer;
  /// The main isolate hosting the Flutter application
  final VMIsolateRef _appIsolate;

  Future<Map<String, dynamic>> _sendCommand(Command command) async {
    Map<String, String> parameters = <String, String>{'command': command.kind}
      ..addAll(command.serialize());
    return _appIsolate.invokeExtension(_kFlutterExtensionMethod, parameters)
      .then((Map<String, dynamic> result) => result, onError: (dynamic error, dynamic stackTrace) {
        throw new DriverError(
          'Failed to fulfill ${command.runtimeType} due to remote error',
          error,
          stackTrace
        );
      });
  }

  /// Checks the status of the Flutter Driver extension.
  Future<Health> checkHealth() async {
    return Health.fromJson(await _sendCommand(new GetHealth()));
  }

  /// Finds the UI element with the given [key].
  Future<ObjectRef> findByValueKey(dynamic key) async {
    return ObjectRef.fromJson(await _sendCommand(new Find(new ByValueKey(key))));
  }

  /// Finds the UI element for the tooltip with the given [message].
  Future<ObjectRef> findByTooltipMessage(String message) async {
    return ObjectRef.fromJson(await _sendCommand(new Find(new ByTooltipMessage(message))));
  }

  /// Finds the text element with the given [text].
  Future<ObjectRef> findByText(String text) async {
    return ObjectRef.fromJson(await _sendCommand(new Find(new ByText(text))));
  }

  Future<Null> tap(ObjectRef ref) async {
    return await _sendCommand(new Tap(ref)).then((Map<String, dynamic> _) => null);
  }

  /// Tell the driver to perform a scrolling action.
  ///
  /// A scrolling action begins with a "pointer down" event, which commonly maps
  /// to finger press on the touch screen or mouse button press. A series of
  /// "pointer move" events follow. The action is completed by a "pointer up"
  /// event.
  ///
  /// [dx] and [dy] specify the total offset for the entire scrolling action.
  ///
  /// [duration] specifies the lenght of the action.
  ///
  /// The move events are generated at a given [frequency] in Hz (or events per
  /// second). It defaults to 60Hz.
  Future<Null> scroll(ObjectRef ref, double dx, double dy, Duration duration, {int frequency: 60}) async {
    return await _sendCommand(new Scroll(ref, dx, dy, duration, frequency)).then((Map<String, dynamic> _) => null);
  }

  Future<String> getText(ObjectRef ref) async {
    GetTextResult result = GetTextResult.fromJson(await _sendCommand(new GetText(ref)));
    return result.text;
  }

  /// Starts recording performance traces.
  Future<Null> startTracing() async {
    try {
      await _peer.sendRequest(_kSetVMTimelineFlagsMethod, {'recordedStreams': '[all]'});
      return null;
    } catch(error, stackTrace) {
      throw new DriverError(
        'Failed to start tracing due to remote error',
        error,
        stackTrace
      );
    }
  }

  /// Stops recording performance traces and downloads the timeline.
  Future<Timeline> stopTracingAndDownloadTimeline() async {
    try {
      await _peer.sendRequest(_kSetVMTimelineFlagsMethod, {'recordedStreams': '[]'});
      return new Timeline.fromJson(await _peer.sendRequest(_kGetVMTimelineMethod));
    } catch(error, stackTrace) {
      throw new DriverError(
        'Failed to stop tracing due to remote error',
        error,
        stackTrace
      );
    }
  }

  /// Runs [action] and outputs a performance trace for it.
  ///
  /// Waits for the `Future` returned by [action] to complete prior to stopping
  /// the trace.
  ///
  /// This is merely a convenience wrapper on top of [startTracing] and
  /// [stopTracingAndDownloadTimeline].
  Future<Timeline> traceAction(Future<dynamic> action()) async {
    await startTracing();
    await action();
    return stopTracingAndDownloadTimeline();
  }

  /// Calls the [evaluator] repeatedly until the result of the evaluation
  /// satisfies the [matcher].
  ///
  /// Returns the result of the evaluation.
  Future<String> waitFor(EvaluatorFunction evaluator, Matcher matcher, {
    Duration timeout: _kDefaultTimeout,
    Duration pauseBetweenRetries: _kDefaultPauseBetweenRetries
  }) async {
    return retry(() async {
      dynamic value = await evaluator();
      MatchResult matchResult = match(value, matcher);
      if (!matchResult.hasMatched) {
        return new Future<Null>.error(matchResult.mismatchDescription);
      }
      return value;
    }, timeout, pauseBetweenRetries);
  }

  /// Closes the underlying connection to the VM service.
  ///
  /// Returns a [Future] that fires once the connection has been closed.
  // TODO(yjbanov): cleanup object references
  Future<Null> close() => _serviceClient.close().then((_) {
    // Don't leak vm_service_client-specific objects, if any
    return null;
  });
}

/// Encapsulates connection information to an instance of a Flutter application.
class VMServiceClientConnection {
  /// Use this for structured access to the VM service's public APIs.
  final VMServiceClient client;

  /// Use this to make arbitrary raw JSON-RPC calls.
  ///
  /// This object allows reaching into private VM service APIs. Use with
  /// caution.
  final rpc.Peer peer;

  VMServiceClientConnection(this.client, this.peer);
}

/// A function that connects to a Dart VM service given the [url].
typedef Future<VMServiceClientConnection> VMServiceConnectFunction(String url);

/// The connection function used by [FlutterDriver.connect].
///
/// Overwrite this function if you require a custom method for connecting to
/// the VM service.
VMServiceConnectFunction vmServiceConnectFunction = _waitAndConnect;

/// Restores [vmServiceConnectFunction] to its default value.
void restoreVmServiceConnectFunction() {
  vmServiceConnectFunction = _waitAndConnect;
}

/// Waits for a real Dart VM service to become available, then connects using
/// the [VMServiceClient].
///
/// Times out after 30 seconds.
Future<VMServiceClientConnection> _waitAndConnect(String url) async {
  Stopwatch timer = new Stopwatch()..start();

  Future<VMServiceClientConnection> attemptConnection() async {
    Uri uri = Uri.parse(url);
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'ws', path: '/ws');

    WebSocket ws1;
    WebSocket ws2;
    try {
      ws1 = await WebSocket.connect(uri.toString());
      ws2 = await WebSocket.connect(uri.toString());
      return new VMServiceClientConnection(
        new VMServiceClient(ws1),
        new rpc.Peer(ws2, ws2)..listen()
      );
    } catch(e) {
      if (ws1 != null)
        ws1.close();

      if (ws2 != null)
        ws2.close();

      if (timer.elapsed < const Duration(seconds: 30)) {
        _log.info('Waiting for application to start');
        await new Future<Null>.delayed(const Duration(seconds: 1));
        return attemptConnection();
      } else {
        _log.critical(
          'Application has not started in 30 seconds. '
          'Giving up.'
        );
        throw e;
      }
    }
  }

  return attemptConnection();
}
