# Shared API·DTO 계약

정확한 request·response 형태와 검증은 `supabase/functions/_shared/contract.ts`가
소유하고 `supabase/functions/_tests/`의 endpoint 테스트가 검증한다. 술결카드 결과
envelope와 공개 view의 형태는 `supabase/functions/_shared/taste_card/service/types.ts`가 소유한다.
이 문서는 둘이 따르는 원칙과 endpoint 책임만 적는다. DTO 필드는 여기에 옮기지 않는다.

## 정본 우선순위

1. TypeScript contract와 Edge Function validation
2. Dart wire DTO와 parser
3. QA fixture

endpoint, field, enum을 바꾸면 TypeScript, Dart, fixture를 한 변경으로 맞춘다.

## Edge Function

| 함수 | 책임 |
|---|---|
| `taste-card-generations` | 술결카드 생성과 저장. 결과는 `final` 또는 `retryable`뿐이다. |
| `taste-card-results` | 저장된 술결카드 한 건 조회 |
| `taste-card-conversions` | 익명 final 결과를 로그인한 계정으로 전환 |
| `complete-profile` | 필수 프로필과 약관 동의 제출 |
| `account-deletion` | 탈퇴 상태 조회, 탈퇴 요청, 유예 기간 내 복구 |
| `account-retention-purge` | 예약 작업 전용. 유예 기간이 끝난 탈퇴 계정의 보존·삭제 처리 |
| `taste-fit` | 검색 결과 상품마다 사용자의 저장된 카드로 취향 적합도 판정 |

## 공통 원칙

- JSON key는 `snake_case`, Dart field는 `lowerCamelCase`다.
- ID는 opaque string이며 client가 의미를 추정하지 않는다.
- request는 allowlist field만 받고 unknown field를 거부한다.
- response를 읽는 app은 모르는 field를 무시하고, 읽어야 할 field가 빠졌을 때만 실패한다. 이미 설치된 app이 있으므로 server는 field를 더할 수 있지만 빼거나 뜻을 바꾸지 않는다.
- null과 누락을 구분하고 빈 문자열을 null 대신 쓰지 않는다.
- secret, signed URL, conversion token, 내부 trace는 응답하지 않는다.
- timestamp는 UTC ISO-8601이고 순서가 있는 목록은 명시적 sort key를 가진다.
- 빈 카드나 placeholder를 `final`로 반환하지 않는다.
- 같은 생성·전환 요청은 idempotent하다. 전환 token은 log와 analytics에 남기지 않는다.
- 익명 생성과 로그인 생성은 같은 engine을 쓴다.
- 저장된 final 결과는 불변이며 조회·전환은 저장된 그대로 반환한다.

## Error code

- 응답은 안정적인 `error_code`와 사람이 읽는 message를 분리한다.
- client는 message 문구가 아니라 code로 분기한다.
- code는 소문자 snake_case이며 인증, 입력, catalog, 결과, 계정 범주로 나뉜다.

## 검증

```bash
deno test --allow-read --allow-env supabase/functions/_tests/endpoints/complete_profile_endpoint_test.ts
flutter test test/features/taste_card_gateway_test.dart
```
