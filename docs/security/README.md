# 보안 계약

사용자 데이터와 계정에 관해 절대 일어나면 안 되는 일을 한곳에 모았다.
수치와 허용 목록은 각 규칙의 담당 코드가 정하고, 여기서는 규칙과 그것을 검증하는 테스트만 적는다.

## 로그인과 프로필

- 저장된 계정 기록은 소셜 로그인(카카오·애플·구글), 완성된 프로필, 성인 확인, 약관·개인정보 동의, 활성 계정이 모두 있을 때만 만들어진다.
- 이메일·비밀번호 로그인은 없다. 허용 목록 밖의 제공자는 프로필 완성이나 결과 전환 전에 거절된다.
- 프로필이 덜 찼거나 삭제 예정인 계정의 저장 요청은 `complete_profile_required`로 거절되고 아무것도 저장되지 않는다.
- 로그인 리다이렉트 주소는 설정에 적힌 값과 정확히 일치할 때만 받는다. 미리보기용 주소는 운영 목록에 넣지 않는다.
- 로그인 전 첫 결과는 인증 없이 만들어지고 볼 수 있다. 계정 저장만 위 조건으로 막는다.

## 비로그인 결과의 계정 전환

토큰 모델은 `supabase/functions/_shared/taste_card/service/conversion_token.ts`가 정한다.

- 원문 전환 토큰은 어떤 저장소, 감사 기록, 로그, 분석, 공유 응답에도 남지 않는다.
- 토큰이 틀리면 `anonymous_result_token_rejected`, 세션이 다르면 `anonymous_result_mismatch`로 거절된다.
- 다른 계정이 이미 가져간 결과는 `anonymous_result_already_claimed`로 거절된다.
- 같은 사용자의 재시도는 거절이 아니다. 저장은 한 번만 일어나고 응답은 계속 저장됨을 알린다.
- 토큰은 전환 엔드포인트로만 보낸다. 경로, 분석 이벤트, 로그, 공개 에셋 주소에 넣지 않는다.
- 거절 응답에는 저장된 해시, 원문 토큰, 제공자 응답, 답변 글, 저장소 경로가 들어가지 않는다.
- 요청 크기 제한은 토큰 비교나 저장보다 앞서, 제품 검증과 별개로 전송 계층에서 건다.

## 본인만 보는 데이터

- 사용자 소유 표는 모두 `auth.uid()`와 활성 계정 조건으로 본인 행만 읽고 쓴다. 답변·결과 요약은 본인 기록의 하위로만 보인다.
- 삭제 상태 표는 클라이언트가 읽지 못한다. 상태는 서버 응답으로만 전달된다.
- 비공개 버킷은 첫 경로 조각이 본인 아이디이고 계정이 활성일 때만 읽기·쓰기·수정·삭제를 허용한다. 익명 접근 정책은 없다.
- 버킷의 크기와 형식 제한은 `supabase/migrations/`가 정한다.
- 공유 응답에는 결과 식별자, 공유 문구, 안전 영역, 저장 유도 문구만 있다. 원문 답변, 사진, 저장소 경로, 서명 주소는 없다.

## 로그와 분석

로그, 분석, 감사 기록에는 답변 원문, 자유 글, 선택지 이름, 사진, 저장소 경로, 서명 주소, 로그인 토큰, 전환 토큰, 제공자 프로필 원문을 남기지 않는다.
남기는 것은 횟수, 상태 이름, 거절 코드, 해시된 주체 식별자뿐이다.
삭제 예약 작업은 식별자나 상위 응답을 기록하지 않는다.

## 계정 삭제

- 삭제를 요청하면 계정은 즉시 삭제 예정이 되고, 본인 프로필·기록·비공개 사진·삭제 상태를 바로 읽지 못한다.
- 복구 기한은 서버가 계산한다. 재시도해도 기한은 늘지 않고, 기한 이후 복구는 `restore_window_closed`로 거절된다.
- 영구 삭제는 제공자 연동 해제, 비공개 저장소 삭제, 기록 보존, 인증 계정 삭제 순서로 진행한다. 앞 단계가 실패하면 뒤 단계로 가지 않는다.
- 활성 계정, 기한 미설정, 기한 전 계정은 영구 삭제되지 않는다.
- 인증 계정 삭제가 실패해 다시 시도해도 이미 끝난 보존 단계는 건너뛴다.
- 보존 대상과 기간은 `supabase/migrations/`와 `supabase/functions/account-retention-purge/`가 정한다.
- 예약 작업은 전용 비밀값으로 인증한다. 사용자 토큰으로는 호출되지 않는다.

## 검증

| 규칙 | 테스트 |
| --- | --- |
| 허용되지 않은 제공자 거절 | `supabase/functions/_tests/endpoints/complete_profile_endpoint_test.ts`, `supabase/functions/_tests/endpoints/edge_functions_test.ts` |
| 프로필 완성 계약과 인증·충돌 응답 | `supabase/functions/_tests/endpoints/complete_profile_endpoint_test.ts` |
| 전환 토큰 변조 거절과 재시도 | `supabase/functions/_tests/taste_card/taste_card_generation_test.ts` |
| 표 권한·정책, 행 수준 보안, 본인 격리, 비공개 버킷, 익명 정리 | `supabase/functions/_tests/db/schema_privileges_test.ts` |
| 삭제 확인·예약·제공자 연동 해제, 로그 비노출, 저장소 삭제 범위 | `supabase/functions/_tests/endpoints/account_deletion_endpoint_test.ts` |
| 영구 삭제 순서·재시도·기한 | `supabase/functions/_tests/endpoints/edge_functions_test.ts` |
| 복구 안내 화면 | `test/features/account_restore_dialog_test.dart` |
