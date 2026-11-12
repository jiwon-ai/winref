// 이름 규칙: 한글만, 띄어쓰기 없이 2~10자
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winref/common.dart';

String typed(String input) {
  var v = TextEditingValue.empty;
  for (final f in koreanNameInput) {
    v = f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input, selection: TextSelection.collapsed(offset: input.length)));
    input = v.text;
  }
  return v.text;
}

void main() {
  test('입력 단계: 영문·숫자·공백·특수문자·이모지는 들어가지 않음, 조합 중 자모는 허용', () {
    expect(typed('Kim 김심판1!😀'), '김심판');
    expect(typed('ㄱ'), 'ㄱ'); // 한글 조합 중
    expect(typed('ㅅㆍ'), 'ㅅㆍ'); // 천지인
    expect(typed('가나다라마바사아자차카'), '가나다라마바사아자차'); // 10자 제한
  });

  test('저장 단계 검사', () {
    expect(koreanNameError('김심판'), isNull);
    expect(koreanNameError('남궁민수'), isNull);
    expect(koreanNameError(''), '필수 입력');
    for (final bad in ['김', 'Kim', '김 심판', '김심판😀', '김ㅅ', '김-심판']) {
      expect(koreanNameError(bad), isNotNull, reason: bad);
    }
  });
}
