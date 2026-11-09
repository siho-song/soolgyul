# Frontend 데이터 계약

Frontend contract는 화면이 보존해야 할 입력과 상태의 경계를 정한다. Wire 형태는
`SHARED_API_DTO_CONTRACT.md`, 공개 문안의 품질은 `TASTE_CARD_RECORD_SCENARIOS.md`,
화면 상태 타입은 각 기능 폴더 `lib/src/features/`가 소유한다.

## 책임 경계

| 계층 | 책임 |
|---|---|
| 화면 draft | 제출 전 고른 술·답변·프로필 입력 |
| frontend domain | 화면 간 공유되는 조회·인증·저장 상태 |
| wire DTO | backend request·response 직렬화 |
| server | 권한, 검증, engine 실행, persistence |

## 접근과 draft

- Owner 데이터는 authenticated user ID 기준으로 읽고 쓴다.
- UI에서 숨기는 것만으로 권한을 보장하지 않는다. server와 RLS가 최종 검증한다.
- 세션 만료, OAuth 복귀, 화면 이동으로 고른 술·답변 draft를 잃지 않는다.
- `retryable` 응답이면 draft를 유지하고 같은 idempotency key로 재시도한다.
- Flutter는 사용자가 입력한 사실만 보내고 최종 인사이트를 만들지 않는다.
- 술은 카탈로그에서 고른 상품 하나가 필수이며 이름을 직접 적는 기록은 없다. 한 줄 메모는 저장된 기록에 카드 머리글에서 더하는 선택 입력이다.

## 술결카드 결과 불변조건

- `bite`는 별명, 핵심 요약(줄마다 한 문장), nullable 가이드(줄마다 한 행)를 각각 별도 필드로 받는다. frontend는 분석 문장을 합성하지 않는다.
- `positive`, `burden`, `balanced`는 문단 목록이고, 문단은 독자의 답(`answer`)과 설명(`text`)이다. 비어 있으면 그 섹션은 제목까지 표시하지 않는다. `balanced`(왜 편안했을까요)는 균형 기록에서만 차 있다.
- `product.category_label`은 nullable이다. 알 수 없는 주종은 만들지 않고 생략한다.
- 임의 Markdown 문자열을 화면에서 해석하지 않는다.
- 근거 없는 nullable 영역을 빈 문자열, placeholder, 범용 문구로 채우지 않는다.
- 섹션 제목, 전환 문구, 접기·펼치기, 저장·공유는 Flutter chrome이며 결과 payload에 들어가지 않는다.
- 분석은 서버가 결정론적으로 만든다. 제품명·BP ID별 하드코딩과 runtime LLM 호출을 쓰지 않으며 Flutter에 이 규칙을 복제하지 않는다.
- 내부 기록과 카드 사실(private snapshot)은 화면 상태에 넣지 않는다.

## 목록과 갱신

- stable item ID를 key로 쓰고 pagination 중복과 순서 변경을 안전하게 병합한다.
- refresh 중과 refresh 실패 시 기존 데이터를 유지한다. empty를 error나 loading으로 표현하지 않는다.
- 낙관적 UI가 server 실패하면 이전 상태로 복원하고 재시도 방법을 제공한다.

## 화면에 넣지 않는 데이터

- service-role key와 provider secret
- 내부 evidence trace 전체
- memo 원문과 불필요한 개인정보
- storage bucket 내부 경로와 장기 signed URL
- unpublished catalog row
- 권한 판정을 대신하는 client flag

## 검증

```bash
flutter test
flutter analyze
deno test --allow-read --allow-env supabase/functions/_tests/soolgyul_contract_test.ts
```
