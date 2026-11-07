import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 안드로이드: 웹뷰로 지도 미리보기 페이지를 띄운다 (터치는 막고 보기 전용)
Widget mapView(String url) => _MapWebView(url);

class _MapWebView extends StatefulWidget {
  final String url;
  const _MapWebView(this.url);
  @override
  State<_MapWebView> createState() => _MapWebViewState();
}

class _MapWebViewState extends State<_MapWebView> {
  late final _c = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) => IgnorePointer(child: WebViewWidget(controller: _c));
}
