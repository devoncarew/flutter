import 'dart:async';
import 'dart:convert' show JSON;
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' hide TextStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

// TODO: calling the APIs to measure memory usage sometimes triggers GC. We should
// have a way to query for memory usage that minimizes changes to the system.
// The JSON API and parsing for communicating over the service protocol (using
// the current APIs) shows up as a significant creator of GC garbage when this
// widget is active.

// TODO: pass click event through

// TODO: show errors in-line

// TODO: add tests

const Duration kMaxGraphTime = const Duration(minutes: 1);
const Duration kUpdateDelay = const Duration(seconds: 5);

// TODO: doc
class MemoryUsageOverlay extends StatelessWidget {
  const MemoryUsageOverlay({Key key, @required this.child}) : super(key: key);

  /// The widget to show behind the memory usage overlay.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = child;
    profile(() {
      result = new Stack(
        children: <Widget>[
          result,
          new MemoryUsage(),
        ],
      );
    });
    return result;
  }
}

class MemoryUsage extends StatefulWidget {
  @override
  MemoryUsageState createState() {
    return new MemoryUsageState();
  }
}

class MemoryUsageState extends State<MemoryUsage> {
  static const double kWidgetHeight = 96.0;
  static const TextStyle _textStyle = const TextStyle(
      fontSize: 16.0,
      decoration: TextDecoration.none,
      color: const Color(0xFFCDCDCD),
      fontWeight: FontWeight.normal);

  final HeapData data = new HeapData();

  ServiceConnection _service;

  @override
  void initState() {
    super.initState();

    () async {
      final developer.ServiceProtocolInfo info =
          await developer.Service.getInfo();
      final Uri uri = info.serverUri.resolve('ws').replace(scheme: 'ws');
      final ServiceConnection service =
          await ServiceConnection.connect(uri.toString());

      _service = service;

      // Gather memory usage info.
      _update(service);

      // Poll for updated usage info every kUpdateDelay.
      final Timer timer = new Timer.periodic(kUpdateDelay, (Timer t) {
        if (mounted) {
          _update(service);
        } else {
          t.cancel();
        }
      });

      service.onGCEvent.listen(_handleGCEvent);
      service.onDone.whenComplete(timer.cancel);
    }().catchError((dynamic error) {
      // TODO:
      print(error);
    });
  }

  @override
  void dispose() {
    super.dispose();

    _service?.dispose();
  }

  // TODO: handle errors
  Future<dynamic> _update(ServiceConnection service) async {
    final VM vm = await service.getVM();
    final List<Isolate> isolates = await Future
        .wait(vm.isolates.map((IsolateRef ref) => service.getIsolate(ref.id)));
    if (mounted) {
      setState(() {
        data.update(vm, isolates);
      });
    }
  }

  void _handleGCEvent(Event event) {
    final bool ignore = event.reason == 'compact';

    // Normally this state update would happen in a setState call, but we try
    // and avoid doing work for some frequent types of GC events, like compaction
    // events. We still record the heap data for the event, but don't trigger
    // a screen update.
    final List<HeapSpace> heaps = <HeapSpace>[
      new HeapSpace(event.json['new']),
      new HeapSpace(event.json['old'])
    ];
    data.updateGCEvent(event.isolate.id, heaps);

    if (!ignore && mounted) {
      setState(() {
        // trigger an update
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String used;
    String rss;

    if (data.samples.isNotEmpty) {
      used =
          '${_printMb(data.currentHeap, 1)} of ${_printMb(data.heapMax, 1)} MB';
      rss = '${_printMb(data.processRss, 0)} MB RSS';
    }

    return new Container(
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.bottomCenter,
      child: new Container(
        color: const Color(0xF0393939),
        alignment: Alignment.bottomCenter,
        height: kWidgetHeight,
        child: new CustomPaint(
          painter: new MemoryGraphPainter(data),
          child: new Padding(
            padding: const EdgeInsets.all(6.0),
            child: new Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Expanded(child: const Padding(padding: EdgeInsets.zero)),
                new Row(
                  children: <Widget>[
                    new Text(rss ?? '', style: _textStyle),
                    const Expanded(
                        child: const Padding(padding: EdgeInsets.zero)),
                    new Text(used ?? '', style: _textStyle),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HeapData {
  final List<HeapSample> samples = <HeapSample>[];
  final Map<String, List<HeapSpace>> isolateHeaps = <String, List<HeapSpace>>{};
  int heapMax;
  int processRss;

  int get currentHeap => samples.last.bytes;

  int get maxHeapData {
    return samples.fold<int>(heapMax,
        (int value, HeapSample sample) => math.max(value, sample.bytes));
  }

  void update(VM vm, List<Isolate> isolates) {
    processRss = vm.currentRSS;

    isolateHeaps.clear();
    for (Isolate isolate in isolates) {
      isolateHeaps[isolate.id] = isolate.heaps.toList();
    }

    _recalculate();
  }

  void updateGCEvent(String id, List<HeapSpace> heaps) {
    isolateHeaps[id] = heaps;
    _recalculate(true);
  }

  void _recalculate([bool fromGC = false]) {
    int current = 0;
    int total = 0;

    for (List<HeapSpace> heaps in isolateHeaps.values) {
      current += heaps.fold<int>(
          0, (int i, HeapSpace heap) => i + heap.used + heap.external);
      total += heaps.fold<int>(
          0, (int i, HeapSpace heap) => i + heap.capacity + heap.external);
    }

    heapMax = total;

    int time = new DateTime.now().millisecondsSinceEpoch;
    if (samples.isNotEmpty) {
      time = math.max(time, samples.last.time);
    }

    addSample(new HeapSample(current, time, fromGC));
  }

  void addSample(HeapSample sample) {
    if (samples.isEmpty) {
      // Add an initial synthetic sample so the first version of the graph draws some data.
      samples.add(new HeapSample(
          sample.bytes, sample.time - kUpdateDelay.inMilliseconds ~/ 4, false));
    }

    samples.add(sample);

    // delete old samples
    // TODO: Interpolate the left-most point if we remove a sample.
    final int oldestTime =
        (new DateTime.now().subtract(kMaxGraphTime).subtract(kUpdateDelay))
            .millisecondsSinceEpoch;
    samples.retainWhere((HeapSample sample) => sample.time >= oldestTime);
  }
}

class HeapSample {
  final int bytes;
  final int time;
  final bool isGC;

  HeapSample(this.bytes, this.time, this.isGC);
}

class MemoryGraphPainter extends CustomPainter {
  final HeapData data;

  MemoryGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.samples.isEmpty) {
      return;
    }

    final Rect rect = Offset.zero & size;

    // Make the y height large enough for the largest sample,
    const int tenMB = 1024 * 1024 * 10;
    final int maxDataSize = (data.maxHeapData ~/ tenMB) * tenMB + tenMB;

    final double width = rect.width;
    final double height = rect.height;

    // Use the last sample at the right most edge, instead of new DateTime.now(),
    // to prevent a gap between the graph and the right edge.
    final int latestTime = data.samples.last.time;
    final double pixelsPerMs = width / kMaxGraphTime.inMilliseconds;

    Offset _convertToSize(HeapSample sample) {
      final double x = width - (latestTime - sample.time) * pixelsPerMs;
      final double y = height - height * (sample.bytes / maxDataSize);
      return new Offset(x, y);
    }

    // Make sure we don't over-paint.
    canvas.clipRect(rect);

    // draw lines
    final Paint linePaint = new Paint()
      ..color = const Color(0xFFFED5A9)
      ..strokeWidth = 2.50
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(
      PointMode.polygon,
      data.samples.map(_convertToSize).toList(),
      linePaint,
    );

    // draw dots
    final Paint pointPaint = new Paint()
      ..color = const Color(0xFFFED5A9)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(
      PointMode.points,
      data.samples.where((HeapSample sample) => sample.isGC).map(_convertToSize).toList(),
      pointPaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class ServiceConnection {
  ServiceConnection._(this.ws) {
    ws.listen((dynamic message) {
      if (message is String) {
        _handleWsMessage(message);
      }
    }).onDone(() {
      _doneCompleter.complete();
    });

    // Begin listening for garbage collection events.
    streamListen('GC');
  }

  static Future<ServiceConnection> connect(String url) {
    return WebSocket.connect(url).then((WebSocket ws) {
      return new ServiceConnection._(ws);
    });
  }

  final WebSocket ws;
  final Completer<Null> _doneCompleter = new Completer<Null>();

  int _id = 0;
  final Map<String, Completer<ServiceObject>> _completers =
      <String, Completer<ServiceObject>>{};
  final StreamController<Event> _gcEventController =
      new StreamController<Event>();

  Future<ServiceObject> streamListen(String streamId) {
    return _call('streamListen', <String, dynamic>{'streamId': streamId});
  }

  Stream<Event> get onGCEvent => _gcEventController.stream;

  Future<Null> get onDone => _doneCompleter.future;

  Future<VM> getVM() => _call('getVM');

  Future<Isolate> getIsolate(String isolateId) {
    return _call('getIsolate', <String, dynamic>{'isolateId': isolateId});
  }

  Future<T> _call<T extends ServiceObject>(String method,
      [Map<String, dynamic> args]) {
    final String id = '${++_id}';
    final Completer<T> completer = new Completer<T>();
    _completers[id] = completer;
    final Map<String, dynamic> map = <String, dynamic>{
      'id': id,
      'method': method
    };
    if (args != null) {
      map['params'] = args;
    }
    ws.add(JSON.encode(map));
    return completer.future;
  }

  void _handleWsMessage(String message) {
    Map<String, dynamic> json;

    try {
      json = JSON.decode(message);
    } catch (error) {
      return;
    }

    if (json.containsKey('method')) {
      // a notification; ignore for now
      _processNotification(json);
    } else if (json.containsKey('id')) {
      _processResponse(json);
    }
  }

  void _processResponse(Map<String, dynamic> json) {
    final Completer<ServiceObject> completer = _completers.remove(json['id']);
    if (completer == null) {
      return;
    }

    if (json['error'] != null) {
      completer.completeError(ServiceError.parse(json['error']));
    } else {
      final Map<String, dynamic> result = json['result'];
      final String type = result['type'];

      if (type == 'VM') {
        completer.complete(new VM(result));
      } else if (type == 'Isolate') {
        completer.complete(new Isolate(result));
      } else {
        completer.complete(new UnkownResponse(result));
      }
    }
  }

  Future<dynamic> _processNotification(Map<String, dynamic> json) async {
    final String method = json['method'];
    final Map<String, dynamic> params = json['params'];
    if (method == 'streamNotify') {
      final Event event = new Event(params['event']);
      if (event.kind == 'GC') {
        _gcEventController.add(event);
      }
    }
  }

  void dispose() {
    ws.close().catchError((dynamic error) => null);
  }
}

abstract class ServiceObject {
  final dynamic json;

  ServiceObject(this.json);

  String get type => json['type'];

  String get name => json['name'];
}

class VM extends ServiceObject {
  VM(dynamic json) : super(json);

  String get version => json['version'];

  int get currentRSS => json['_currentRSS'];

  int get maxRSS => json['_maxRSS'];

  Iterable<IsolateRef> get isolates {
    return json['isolates'].map((dynamic json) => new IsolateRef(json));
  }
}

class Event extends ServiceObject {
  Event(dynamic json) : super(json);

  String get kind => json['kind'];

  String get reason => json['reason'];

  int get timestamp => json['timestamp'];

  IsolateRef get isolate => new IsolateRef(json['isolate']);
}

String _printMb(int bytes, int fractionDigits) =>
    (bytes / (1024 * 1024)).toStringAsFixed(fractionDigits);

class IsolateRef extends ServiceObject {
  IsolateRef(dynamic json) : super(json);

  String get id => json['id'];
}

class Isolate extends ServiceObject {
  Isolate(dynamic json) : super(json);

  String get id => json['id'];

  Iterable<HeapSpace> get heaps {
    final Map<String, dynamic> heaps = json['_heaps'];
    return heaps.values.map((dynamic json) => new HeapSpace(json));
  }
}

class HeapSpace extends ServiceObject {
  HeapSpace(dynamic json) : super(json);

  int get used => json['used'];

  int get capacity => json['capacity'];

  int get external => json['external'];

  int get collectTimeMillis => (json['time'] * 1000.0).toInt();
}

class UnkownResponse extends ServiceObject {
  UnkownResponse(dynamic json) : super(json);
}

class ServiceError {
  ServiceError(this.code, this.message, this.data);

  static ServiceError parse(dynamic json) {
    return new ServiceError(json['code'], json['message'], json['data']);
  }

  final int code;
  final String message;
  final Map<String, dynamic> data;

  String get details => data == null ? null : data['details'];

  @override
  String toString() {
    if (details == null) {
      return '$message ($code)';
    } else {
      return '$message ($code):\n$details';
    }
  }
}
