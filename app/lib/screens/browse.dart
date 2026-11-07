import 'package:flutter/material.dart';

import '../theme.dart';

/// 검색창 + 가로 스크롤 필터칩
class SearchFilterBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onQuery;
  final List<Widget> chips;
  final Widget? trailing;
  const SearchFilterBar({super.key, required this.hint, required this.onQuery, this.chips = const [], this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              onChanged: onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search, color: Brand.muted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                fillColor: Brand.ivory,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        if (chips.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 8),
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => chips[i],
            ),
          ),
      ]),
    );
  }
}

/// 선택형 필터칩 (선택 시 남색 배경)
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const FilterPill(this.label, {super.key, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: Brand.navy,
      backgroundColor: Brand.ivory,
      side: BorderSide(color: selected ? Brand.navy : const Color(0xFFC3D0E0)),
      labelStyle: TextStyle(color: selected ? Brand.ivory : Brand.navy, fontWeight: FontWeight.w600, fontSize: 13),
    );
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 월간 캘린더: 일정이 있는 날에 골드 점, 날짜 선택 콜백
class MonthCalendar extends StatefulWidget {
  final Map<DateTime, int> counts; // dateOnly → 일정 수
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  const MonthCalendar({super.key, required this.counts, required this.selected, required this.onSelect});
  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  static const _week = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    final first = _month;
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final lead = first.weekday % 7; // 일요일 시작
    final today = dateOnly(DateTime.now());
    final cells = lead + days;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: '이전 달',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
          ),
          Expanded(
            child: Text('${first.year}년 ${first.month}월',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(
            tooltip: '다음 달',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
          ),
        ]),
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(_week[i],
                    style: TextStyle(
                        fontSize: 12,
                        color: i == 0 ? const Color(0xFF9B2C2C) : (i == 6 ? Brand.navyLight : Brand.muted))),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: (cells / 7).ceil() * 7,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.1),
          itemBuilder: (_, i) {
            final day = i - lead + 1;
            if (day < 1 || day > days) return const SizedBox.shrink();
            final d = DateTime(first.year, first.month, day);
            final n = widget.counts[d] ?? 0;
            final sel = widget.selected != null && dateOnly(widget.selected!) == d;
            final isToday = d == today;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => widget.onSelect(d),
              child: Semantics(
                label: '${first.month}월 $day일${n > 0 ? ' 일정 $n건' : ''}',
                button: true,
                excludeSemantics: true,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: sel ? Brand.navy : null,
                    borderRadius: BorderRadius.circular(6),
                    border: isToday && !sel ? Border.all(color: Brand.gold) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$day',
                        style: TextStyle(
                          color: sel ? Brand.ivory : Brand.ink,
                          fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w400,
                        )),
                    const SizedBox(height: 3),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: n > 0 ? Brand.gold : Colors.transparent, shape: BoxShape.circle),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// 마감까지 남은 기간 배지 텍스트 (마감 지남 → null)
String? deadlineBadge(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return null;
  final diff = d.toLocal().difference(DateTime.now());
  if (diff.isNegative) return null;
  if (diff.inHours < 24) return '오늘 마감';
  return '마감 D-${diff.inDays}';
}
