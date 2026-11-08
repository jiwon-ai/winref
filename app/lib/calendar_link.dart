import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// 구글 캘린더 일정 추가 화면을 연다 (휴대폰은 캘린더 앱/브라우저, 웹은 새 탭)
Future<void> addToCalendar({
  required String title,
  required DateTime start,
  DateTime? end,
  bool allDay = false,
  String? location,
  String? details,
}) async {
  String dates;
  if (allDay) {
    final f = DateFormat('yyyyMMdd');
    final last = end ?? start;
    dates = '${f.format(start)}/${f.format(last.add(const Duration(days: 1)))}'; // 종일: 끝 날짜는 다음 날
  } else {
    final f = DateFormat("yyyyMMdd'T'HHmmss'Z'");
    final e = end ?? start.add(const Duration(hours: 2));
    dates = '${f.format(start.toUtc())}/${f.format(e.toUtc())}';
  }
  final uri = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': dates,
    if (location != null && location.isNotEmpty) 'location': location,
    if (details != null && details.isNotEmpty) 'details': details,
  });
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
