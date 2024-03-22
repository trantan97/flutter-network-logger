import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'enumerate_items.dart';
import 'network_event.dart';
import 'network_logger.dart';

/// Overlay for [NetworkLoggerButton].
class NetworkLoggerOverlay extends StatefulWidget {
  static const double _defaultPadding = 30;

  const NetworkLoggerOverlay._({
    required this.right,
    required this.bottom,
    required this.draggable,
    Key? key,
  }) : super(key: key);

  final double bottom;
  final double right;
  final bool draggable;

  /// Attach overlay to specified [context]. The FAB will be draggable unless
  /// [draggable] set to `false`. Initial distance from the button to the screen
  /// edge can be configured using [bottom] and [right] parameters.
  static OverlayEntry attachTo(
    BuildContext context, {
    bool rootOverlay = true,
    double bottom = _defaultPadding,
    double right = _defaultPadding,
    bool draggable = true,
  }) {
    // create overlay entry
    final entry = OverlayEntry(
      builder: (context) => NetworkLoggerOverlay._(
        bottom: bottom,
        right: right,
        draggable: draggable,
      ),
    );
    // insert on next frame
    Future.delayed(Duration.zero, () {
      final overlay = Overlay.maybeOf(context, rootOverlay: rootOverlay);

      if (overlay == null) {
        throw FlutterError(
          'FlutterNetworkLogger:  No Overlay widget found. '
          '                       The most common way to add an Overlay to an application is to include a MaterialApp or Navigator above widget that calls NetworkLoggerOverlay.attachTo()',
        );
      }

      overlay.insert(entry);
    });
    // return
    return entry;
  }

  @override
  State<NetworkLoggerOverlay> createState() => _NetworkLoggerOverlayState();
}

class _NetworkLoggerOverlayState extends State<NetworkLoggerOverlay> {
  static const Size buttonSize = Size(57, 57);

  late double bottom = widget.bottom;
  late double right = widget.right;

  late MediaQueryData screen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screen = MediaQuery.of(context);
  }

  Offset? lastPosition;

  void onPanUpdate(LongPressMoveUpdateDetails details) {
    final delta = lastPosition! - details.localPosition;

    bottom += delta.dy;
    right += delta.dx;

    lastPosition = details.localPosition;

    /// Checks if the button went of screen
    if (bottom < 0) {
      bottom = 0;
    }

    if (right < 0) {
      right = 0;
    }

    if (bottom + buttonSize.height > screen.size.height) {
      bottom = screen.size.height - buttonSize.height;
    }

    if (right + buttonSize.width > screen.size.width) {
      right = screen.size.width - buttonSize.width;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.draggable) {
      return Positioned(
        right: right,
        bottom: bottom,
        child: GestureDetector(
          onLongPressMoveUpdate: onPanUpdate,
          onLongPressUp: () {
            setState(() => lastPosition = null);
          },
          onLongPressDown: (details) {
            setState(() => lastPosition = details.localPosition);
          },
          child: Material(
            elevation: lastPosition == null ? 0 : 30,
            borderRadius: BorderRadius.all(Radius.circular(buttonSize.width)),
            child: NetworkLoggerButton(),
          ),
        ),
      );
    }

    return Positioned(
      right: widget.right + screen.padding.right,
      bottom: widget.bottom + screen.padding.bottom,
      child: NetworkLoggerButton(),
    );
  }
}

/// [FloatingActionButton] that opens [NetworkLoggerScreen] when pressed.
class NetworkLoggerButton extends StatefulWidget {
  /// Source event list (default: [NetworkLogger.instance])
  final NetworkEventList eventList;

  /// Blink animation period
  final Duration blinkPeriod;

  // Button background color
  final Color color;

  /// If set to true this button will be hidden on non-debug builds.
  final bool showOnlyOnDebug;

  NetworkLoggerButton({
    Key? key,
    this.color = Colors.deepPurple,
    this.blinkPeriod = const Duration(seconds: 1, microseconds: 500),
    this.showOnlyOnDebug = false,
    NetworkEventList? eventList,
  })  : this.eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  @override
  _NetworkLoggerButtonState createState() => _NetworkLoggerButtonState();
}

class _NetworkLoggerButtonState extends State<NetworkLoggerButton> {
  StreamSubscription? _subscription;
  Timer? _blinkTimer;
  bool _visible = true;
  int _blink = 0;

  Future<void> _press() async {
    setState(() {
      _visible = false;
    });
    try {
      await NetworkLoggerScreen.open(context, eventList: widget.eventList);
    } finally {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant NetworkLoggerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventList != widget.eventList) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.eventList.stream.listen((event) {
      if (mounted) {
        setState(() {
          _blink = _blink % 2 == 0 ? 6 : 5;
        });
      }
    });
  }

  @override
  void initState() {
    _subscribe();
    _blinkTimer = Timer.periodic(widget.blinkPeriod, (timer) {
      if (_blink > 0 && mounted) {
        setState(() {
          _blink--;
        });
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox();
    }

    return _DebugOnly(
      enabled: widget.showOnlyOnDebug,
      child: FloatingActionButton(
        child: Icon(
          (_blink % 2 == 0) ? Icons.cloud : Icons.cloud_queue,
          color: Colors.white,
        ),
        onPressed: _press,
        backgroundColor: widget.color,
      ),
    );
  }
}

/// Screen that displays log entries list.
class NetworkLoggerScreen extends StatelessWidget {
  NetworkLoggerScreen({Key? key, NetworkEventList? eventList})
      : this.eventList = eventList ?? NetworkLogger.instance,
        super(key: key);

  /// Event list to listen for event changes.
  final NetworkEventList eventList;

  /// Opens screen.
  static Future<void> open(
    BuildContext context, {
    NetworkEventList? eventList,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NetworkLoggerScreen(eventList: eventList),
      ),
    );
  }

  final TextEditingController searchController = TextEditingController(text: null);

  /// filte events with search keyword
  List<NetworkEvent> getEvents() {
    if (searchController.text.isEmpty) return eventList.events;

    final query = searchController.text.toLowerCase();
    return eventList.events
        .where((it) => it.request?.uri.toLowerCase().contains(query) ?? false)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Network Logs'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: () => eventList.clear(),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: eventList.stream,
        builder: (context, snapshot) {
          // filter events with search keyword
          final events = getEvents();

          return Column(
            children: [
              TextField(
                controller: searchController,
                onChanged: (text) {
                  eventList.updated(NetworkEvent());
                },
                autocorrect: false,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, color: Colors.black26),
                  suffix: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchController,
                    builder: (context, value, child) => value.text.isNotEmpty
                        ? Text(getEvents().length.toString() + ' results')
                        : const SizedBox(),
                  ),
                  hintText: "enter keyword to search",
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: events.length,
                  itemBuilder: enumerateItems<NetworkEvent>(
                    events,
                    (context, item) => ListTile(
                      key: ValueKey(item.request),
                      title: Text(
                        item.request!.method,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        item.request!.uri.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: Icon(
                        item.error == null
                            ? (item.response == null ? Icons.hourglass_empty : Icons.done)
                            : Icons.error,
                      ),
                      trailing: _AutoUpdate(
                        duration: Duration(seconds: 1),
                        builder: (context) => Text(_timeDifference(item.timestamp!)),
                      ),
                      onTap: () => NetworkLoggerEventScreen.open(
                        context,
                        item,
                        eventList,
                      ),
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

String _timeDifference(DateTime time, [DateTime? origin]) {
  origin ??= DateTime.now();
  var delta = origin.difference(time);
  if (delta.inSeconds < 90) {
    return '${delta.inSeconds} s';
  } else if (delta.inMinutes < 90) {
    return '${delta.inMinutes} m';
  } else {
    return '${delta.inHours} h';
  }
}

final _jsonEncoder = JsonEncoder.withIndent('  ');

/// Screen that displays log entry details.
class NetworkLoggerEventScreen extends StatelessWidget {
  const NetworkLoggerEventScreen({Key? key, required this.event}) : super(key: key);

  static Route<void> route({
    required NetworkEvent event,
    required NetworkEventList eventList,
  }) {
    return MaterialPageRoute(
      builder: (context) => StreamBuilder(
        stream: eventList.stream.where((item) => item.event == event),
        builder: (context, snapshot) => NetworkLoggerEventScreen(event: event),
      ),
    );
  }

  /// Opens screen.
  static Future<void> open(
    BuildContext context,
    NetworkEvent event,
    NetworkEventList eventList,
  ) {
    return Navigator.of(context).push(route(
      event: event,
      eventList: eventList,
    ));
  }

  /// Which event to display details for.
  final NetworkEvent event;

  Widget buildBodyViewer(BuildContext context, dynamic body) {
    String text;
    if (body == null) {
      text = '';
    } else if (body is String) {
      text = body;
    } else if (body is List || body is Map) {
      text = _jsonEncoder.convert(body);
    } else {
      text = body.toString();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Copied to clipboard'),
            behavior: SnackBarBehavior.floating,
          ));
        },
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['sans-serif'],
          ),
        ),
      ),
    );
  }

  Widget buildHeadersViewer(
    BuildContext context,
    List<MapEntry<String, String>> headers,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: headers.map((e) => SelectableText(e.key)).toList(),
          ),
          SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: headers.map((e) => SelectableText(e.value)).toList(),
          ),
        ],
      ),
    );
  }

  Widget buildRequestView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 15),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 5),
          child: Text('URL', style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.request!.method,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              SizedBox(width: 15),
              Expanded(child: SelectableText(event.request!.uri.toString())),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('TIMESTAMP', style: Theme.of(context).textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Text(event.timestamp.toString()),
        ),
        if (event.request!.headers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('HEADERS', style: Theme.of(context).textTheme.bodySmall),
          ),
          buildHeadersViewer(context, event.request!.headers.entries),
        ],
        if (event.error != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('ERROR', style: Theme.of(context).textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
              event.error.toString(),
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('BODY', style: Theme.of(context).textTheme.bodySmall),
        ),
        buildBodyViewer(context, event.request!.data),
      ],
    );
  }

  Widget buildResponseView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 15),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 5),
          child: Text('RESULT', style: Theme.of(context).textTheme.bodySmall),
        ),
        SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.response!.statusCode.toString(),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              SizedBox(width: 15),
              Expanded(child: Text(event.response!.statusMessage)),
            ],
          ),
        ),
        if (event.response?.headers.isNotEmpty ?? false) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
            child: Text('HEADERS', style: Theme.of(context).textTheme.bodySmall),
          ),
          buildHeadersViewer(
            context,
            event.response?.headers.entries ?? [],
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Text('BODY', style: Theme.of(context).textTheme.bodySmall),
        ),
        buildBodyViewer(context, event.response?.data),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResponse = event.response != null;

    Widget? bottom;
    if (showResponse) {
      bottom = TabBar(
        isScrollable: true,
        tabs: [
          Tab(text: 'Request'),
          Tab(text: 'Response'),
        ],
      );
    }

    return DefaultTabController(
      initialIndex: 0,
      length: showResponse ? 2 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Log Entry'),
          bottom: (bottom as PreferredSizeWidget?),
        ),
        body: Builder(
          builder: (context) => TabBarView(
            children: <Widget>[
              buildRequestView(context),
              if (showResponse) buildResponseView(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget builder that re-builds widget repeatedly with [duration] interval.
class _AutoUpdate extends StatefulWidget {
  const _AutoUpdate({Key? key, required this.duration, required this.builder}) : super(key: key);

  /// Re-build interval.
  final Duration duration;

  /// Widget builder to build widget.
  final WidgetBuilder builder;

  @override
  _AutoUpdateState createState() => _AutoUpdateState();
}

class _AutoUpdateState extends State<_AutoUpdate> {
  Timer? _timer;

  void _setTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.duration, (timer) {
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_AutoUpdate old) {
    if (old.duration != widget.duration) {
      _setTimer();
    }
    super.didUpdateWidget(old);
  }

  @override
  void initState() {
    _setTimer();
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context);
  }
}

class _DebugOnly extends StatelessWidget {
  const _DebugOnly({Key? key, required this.enabled, required this.child}) : super(key: key);

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      if (!kDebugMode) {
        return const SizedBox();
      }
    }
    return child;
  }
}
