/// What a member is told once agreeing to advertising, or taking the
/// agreement back, was saved: who sends, what was asked, the day it was
/// asked and that it is done. The day is written out; "today" would not
/// say which day later.
String adConsentNotice({required bool accepted, required DateTime on}) =>
    '술결의 광고성 정보 수신 ${accepted ? '동의' : '동의 철회'}가 '
    '${on.year}년 ${on.month}월 ${on.day}일 처리되었어요.';
