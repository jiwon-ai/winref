import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';
import 'theme.dart';
import 'venue_map_stub.dart' if (dart.library.js_interop) 'venue_map_web.dart';

/// 대회 장소 지도 미리보기 + 네이버 지도 열기
class VenueMap extends StatelessWidget {
  final String? venue;
  final String? address;
  const VenueMap({super.key, this.venue, this.address});

  String get _query => (address ?? '').trim().isNotEmpty ? address!.trim() : (venue ?? '').trim();

  Future<void> _openNaver() async {
    final q = Uri.encodeComponent(_query);
    final app = Uri.parse('nmap://search?query=$q&appname=kr.co.winref.app');
    final webUrl = Uri.parse('https://map.naver.com/p/search/$q');
    if (!kIsWeb && await canLaunchUrl(app)) {
      await launchUrl(app);
    } else {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_query.isEmpty) return const SizedBox.shrink();
    final base = kIsWeb ? '' : appUrl; // 웹은 같은 사이트, 앱은 배포된 사이트의 map.html
    final url = '${base}map.html?address=${Uri.encodeComponent(address ?? '')}&venue=${Uri.encodeComponent(venue ?? '')}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 190,
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDCE5F0)), color: Brand.ivoryDeep),
          child: Semantics(label: '대회 장소 지도', child: mapView(url)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _openNaver,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: const Text('네이버 지도에서 크게 보기'),
        ),
      ),
    ]);
  }
}
