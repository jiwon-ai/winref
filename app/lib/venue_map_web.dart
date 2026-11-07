import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

/// 웹: 같은 사이트의 map.html 을 iframe 으로 띄운다
Widget mapView(String url) {
  final type = 'venue-map-${url.hashCode}';
  if (_registered.add(type)) {
    ui_web.platformViewRegistry.registerViewFactory(type, (int _) {
      return web.HTMLIFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none';
    });
  }
  return HtmlElementView(viewType: type);
}
