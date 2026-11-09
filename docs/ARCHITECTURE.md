# Soolgyul Architecture

## 목적과 경계

술결의 제품 정의는 **마신 술의 느낌에서 내 취향을 발견하고, 다음 한 잔을 더 잘 고르게 돕는 술 취향 가이드**다. 이 문서는 그 제품을 Flutter와 Supabase로 구현한 현재 구조를 설명한다. 제품 범위는 `PRD.md`, 결정은 `ADR.md`, 테이블과 migration 규칙은 `DATABASE.md`가 소유한다.

술결카드의 사용자 공개 문안과 품질 검수 기준은 [`TASTE_CARD_RECORD_SCENARIOS`](specs/TASTE_CARD_RECORD_SCENARIOS.md)다. 카드 생성 엔진의 실행 계약은 versioned code와 fixture가 소유한다.

술결 저장소가 제품 문서, 코드, DB 자산, 테스트를 모두 소유한다. 에이전트 작업 규칙은 루트 `AGENTS.md`가, 강제되는 git·비밀 파일 규칙은 `tools/hooks/`가 맡는다.

## 시스템 구성

```text
Flutter (mobile / mobile-width web)
  -> screen routes, flow coordinators, local draft states
  -> gateways (Supabase client, Edge Function invoke)
  -> Supabase Auth / Edge Functions / Postgres RPC and RLS / Storage
```

### 웹 표면

소개 사이트, 사용자 앱, 관리자 도구는 하나의 route tree로 섞지 않고 build와 deploy를 분리한다.

```text
soolgyul.com        -> site/        정적 소개 사이트
app.soolgyul.com    -> lib/main.dart        온보딩 체험용 Flutter Web
admin.soolgyul.com  -> lib/admin_main.dart  별도 관리자 Flutter Web
                              |
                              v
                  shared Supabase project
                  Auth + RLS + Postgres + Storage
```

`tools/deploy_web.sh site|app|admin`이 세 표면을 Vercel에 배포한다. 관리자 웹 주소를 아는 것만으로 권한을 얻을 수 없다. backend가 소유한 role, RLS와 role을 검사하는 RPC가 정보글 작성·수정·media 업로드·발행·철회를 허용한다.

### Flutter (`lib/`)

- `main.dart`, `admin_main.dart`: 실행 진입점만 소유한다.
- `src/app/`: `app.dart`는 `MaterialApp.router`와 초기 route를 소유한다. `app_flow.dart`는 route stack과 back 처리의 얇은 shell이고, route별 화면 생성은 `app_flow_pages.dart`, debug 진입은 `app_flow_debug.dart`가 맡는다. `app_header_policy.dart`는 route별 공통 헤더를 정한다.
- `src/app/flows/`: 흐름별 coordinator가 상태와 gateway 호출을 소유한다. 온보딩, 반복 기록, 술결카드, 로그인·프로필이 분리되어 있고 `app_gateways.dart`가 gateway 주입 경계를 한곳에서 묶는다.
- `src/app/state/`: 온보딩, 반복 기록, 술결카드 흐름의 local draft 상태 객체다. 온보딩과 반복 기록은 입력 화면을 공유하지만 draft는 공유하지 않는다.
- `src/navigation/`: 이름이 있는 `AppRoute`, URL 해석과 page stack을 소유한다. 하단 탭은 root route를 교체하고 상세 화면은 stack에 쌓이며, Android back과 web browser history가 같은 흐름을 쓴다.
- `src/core/catalog/`: 분류·원료·공정 키의 공통 계약에서 생성한 `CatalogAssignment`를 소유한다.
- `src/core/sensory/`: 온보딩·반복 기록이 묻고 술결카드가 제출하는 감각 질문의 규칙과 답의 의미(질문 순서, 주종별로 묻는 항목, 맛 반응, 마무리 선지, 다시 마실 마음)다.
- `src/core/` 나머지: 여러 기능이 쓰는 작은 공용 코드. `ids.dart`(UUID), `format/dates.dart`(`2026.06.18` 날짜 표기), `supabase/signed_in.dart`(로그인한 계정 확인)다. 상품 대표 사진은 `features/catalog/data/catalog_photos.dart`가 한곳에서 읽는다.
- `src/design/`, `src/widgets/`, `src/config/`: 디자인 토큰, 공통 위젯, 앱 환경 설정이다.
- `src/features/`: 기능 단위 화면과 gateway다. 기능마다 `data/`(gateway, 응답 해석, 모델)와 `presentation/`(화면과 `widgets/`)로 나눈다. 다른 기능은 그 기능의 `data/`와 `presentation/widgets/`만 쓰고 화면이나 내부 파일은 쓰지 않는다. `core/`, `design/`, `widgets/`는 기능을 가져다 쓰지 않는다. `test/architecture/import_rules_test.dart`가 이 규칙을 검사한다.
  - `auth/`: Kakao, Apple, Google 소셜 로그인 서비스와 플랫폼 adapter.
  - `catalog/`: 술 검색 gateway와 검색 결과 모델.
  - `editorial/`: 공개 정보글 domain, 조회·저장 gateway, media renderer. `explore`와 `profile`은 이 feature의 ID를 공유한다.
  - `explore/`: 탐색 탭의 정보글 목록과 상세 화면.
  - `home/`: 홈 탭. 취향 맞춤 검색 진입, 네 글자 카드와 상세, 다음 한 잔 가이드와 그 gateway.
  - `onboarding/`: 첫 경험, 향 고르기(`adaptive/`)와 질문 화면(`presentation/sensory/`), 질문지와 사전 보기 데이터, 소셜 로그인 뒤 첫 기록 복원.
  - `preferences/`: 취향 탭의 달력과 월별 기록 화면. `PreferenceHistoryGateway`로 읽고, Supabase 구현은 `soolgyul_my_drink_history` RPC를 쓴다.
  - `profile/`: 표시 이름·관심 주종, 가입 확인, 좋아요한 카드, 마케팅 동의, 문의, 탈퇴 gateway와 마이페이지 화면.
  - `recording/`: 온보딩과 반복 기록이 함께 쓰는 술 이름 검색과 사진 입력 화면. draft와 라우팅은 소유하지 않는다.
  - `records/`: 기록에 한 줄 메모를 붙이는 gateway.
  - `taste_fit/`: 홈의 매대 검색과 판정 화면. 라벨 사진은 앱 안의 카메라 화면(`camera` 플러그인, 틀 가이드와 어두움 감지)이나 앨범에서 받아 기기 안에서만 글자로 읽고(iOS Apple Vision, Android ML Kit 한국어 모델, 채널 `soolgyul/label-ocr`) 그 줄들을 catalog 검색에 넣어 후보를 합친다. 사진과 글자는 서버로 보내지 않는다. 검색한 상품이 내 술결과 맞는지 보여주는 뱃지와 상세 판정은 `taste-fit` gateway가 가져온다.
  - `taste_card/`: 술결카드 결과 모델, 렌더링, 공유·좋아요 액션, 카드 생성·전환·조회 gateway.
- `src/admin/`: 관리자 Flutter Web의 Auth gate, role-aware editorial gateway, 목록·편집·실시간 미리보기와 사진 관리, 그리고 소개 사이트의 공지사항·자주 묻는 질문(`site_posts`) 작성이다. 소개 사이트의 두 페이지는 발행된 글을 publishable key로 읽는다. 정보글 `editor`는 미발행 초안만 저장하고 `admin`만 발행·철회·초안 삭제를 수행한다.

Flutter는 repository 원천 자료나 Supabase table을 임의로 읽지 않고 gateway를 통해서만 backend에 접근한다. gateway는 주입 가능하므로 화면은 fixture gateway로도 실행된다.

### Supabase (`supabase/`)

- Auth: Kakao, Apple, Google만 사용한다. `auth.users` insert trigger가 같은 UUID의 제품 계정(`users`)과 빈 profile을 만든다. 받지 않은 약관·개인정보·만 19세 확인 시각은 만들지 않으며 해당 동의는 `complete-profile` 흐름이 저장한다.
- Postgres: 계정·동의 이력, 관심 주종, 즐겨찾기, 정보글과 사용자 bookmark, 술 catalog serving 자료, 기록과 답변, 술결카드 결과, 탈퇴 상태를 저장한다. 테이블 목록과 접근 규칙은 `DATABASE.md`, 논리 계약은 `specs/ALCOHOL_CATALOG_DATA_CONTRACT.md`가 정본이다.
- Storage: `soolgyul-private`(문의 첨부 사진, owner-only), `alcohol-product-images`(공개 상품 이미지), `soolgyul-editorial`(정보글 이미지), `soolgyul-catalog-public`, `soolgyul-catalog-private`, `soolgyul-catalog-snapshots`(카탈로그 수집 원문과 수집 메타데이터의 유일한 보관본, `catalog-archive/latest/`, service role로만 읽는다)이다. 보존 기간 처리는 bucket이 아니라 pg_cron job `soolgyul-account-retention`·`soolgyul-anonymous-retention`이 맡는다.
- Edge Functions (`functions/`): 서버 판정이 필요한 application boundary다.
  - `taste-card-generations`: 술결카드 생성(익명 첫 기록과 인증 반복 기록).
  - `taste-card-conversions`: 익명 첫 결과를 계정으로 한 번만 전환.
  - `taste-card-results`: 저장된 결과의 owner 조회.
  - `taste-fit`: 검색한 상품이 사용자의 저장된 술결과 맞는지 판정(뱃지·태그·한 문장·맛 수치).
  - `complete-profile`: 가입 확인(만 19세, 약관·개인정보·마케팅 동의)과 profile 상태 조회.
  - `account-deletion`, `account-retention-purge`: 탈퇴 요청과 만료 후 영구 삭제.
  - `_shared/`: 공통 HTTP·계약(`http.ts`, `soolgyul_contract.ts`, `soolgyul_edge.ts`), `profile/repository.ts`, `catalog/`(분류 키 계약과 `assignment.ts`), `taste_card/`(카드 엔진), `taste_fit/`(카드의 설명 행을 모은 취향 장부와 상품 판정).
- Postgres RPC: 마이페이지 표시 이름·관심 주종은 active owner 검증, 사용자별 lock, 1~5개 제한을 가진 `soolgyul_*_my_*` 함수가 유일한 변경 경로다. 로그인 직후 profile setup도 같은 RPC를 쓴다. 카탈로그 검색은 `soolgyul_search_alcohol_catalog`가 맡고, 정보글 저장은 admin 전용 RPC가 본문과 관련 주종을 한 transaction으로 처리한다.
- RLS: 활성 계정의 소유자만 개인 데이터와 private asset에 접근한다. 탈퇴 대기 계정은 즉시 일반 접근을 잃는다. anon·authenticated는 공개 시각이 지난 정보글·media와 published catalog serving 자료만 read-only로 읽는다. 좋아요한 술결카드는 본인의 카드만 추가·조회할 수 있고 공개 반응 수나 타인 관계를 제공하지 않는다.
- `migrations/`: timestamped migration이 물리 schema 이력을 소유한다. 질문지는 table이 아니라 코드(`_shared/taste_card/sensory_questionnaire_v1.ts`)다.
- Flutter Web OAuth redirect 직전에는 필수 술 식별만 tab-scoped `sessionStorage`에 두고 callback에서 한 번 복원한 뒤 삭제한다. 질문 답변과 메모는 이 값에 포함하지 않는다.

### Catalog 데이터 구조

```text
catalog/dictionary/terms.json (사전: 주종·종류·품종·산지·원료·공정·숙성·맛 축·향·질감·생산자, 한 줄 모양)
catalog/sensory/ (답 선지 정의, 향 선택 참고·빈도, 노트 용어 대응표, 맛 질문 은행)
manual-import/fill-work/rows.sqlite3 (수집·정규화 작업 DB)
  -> tools/catalog (수집 connector, 이름·상품 정규화, 중복 판정, 감각 채움, 검증)
  -> 검증된 변경분 sync (manual-import/fill-work/sync)
  -> Supabase catalog serving
       alcohol_categories -> alcohol_items <- producers
       alcohol_items -> catalog_media_assets (상품당 이미지 하나)
       alcohol_items -> alcohol_tasting_profiles (note, 태그, 1~5 수치, 수치별 출처)
       catalog_taxonomy (검색·검증이 쓰는 분류 뼈대)
  -> soolgyul_search_alcohol_catalog RPC (alcohol_items.search_fold_text 검색) / 카드 엔진 -> Flutter, Edge Function

auth.users
  -> users (제품 계정, profile) -> user_consents, user_drink_interests

drink_records -> drink_record_answers (질문 key, 고른 선지 key, 원문)
              -> taste_cards (기록당 하나의 결과 snapshot)
users -> taste_letters (계정당 네 글자와 기울기) -> taste_letter_changes (글자가 드러나거나 바뀐 순간)
```

- Supabase가 앱이 읽는 catalog의 현재 상태를 소유한다. 수집 원본과 처리 코드는 repository가 소유하고, 대용량 작업 산출물은 Git에 두지 않는다. 로컬 작업 DB는 `tools/catalog/backup_local_db.sh`로만 백업한다.
- 한 `alcohol_items` row는 판매 SKU나 병 용량이 아니라 하나의 상품 단위다. 빈티지, 도수, 숙성 연수가 다른 상품은 별도 row로 둔다. 기록, 이미지, 감각 프로필은 상품 ID 하나에 연결한다.
- 주종은 `alcohol_categories`가 정본이고, 사용자 관심 주종 표현은 `alcohol_categories.interest_key`로 연결한다.
- 생산자는 `producers` 표가 소유하고 상품이 `producer_id`로 가리킨다. 검색은 상품명과 생산자명을 모두 본다.
- 분류·원료·공정 키는 상품의 배열 column에 저장하고 `catalog_taxonomy`로 검증한다. 공통 계약(`supabase/functions/_shared/catalog/assignment_contract.json`)에서 Python(`tools/catalog/enrichment/`), Dart(`lib/src/core/catalog/`), 서버(`_shared/catalog/`)의 키와 규칙을 생성하고, DB migration의 trigger가 같은 규칙으로 검증한다.
- `alcohol_tasting_profiles`는 상품당 하나이며 향·맛·질감·마무리 note, 구간별 태그, 1~5 수치와 수치별 근거 등급(`level_sources`, 1~4)을 가진다. 병에서 읽은 값만 저장하고, 비어 있는 수치는 카드가 사전(`catalog/dictionary/terms.json`)의 종류 줄 값을 읽어 말한다. 도수는 같은 사전의 주종·종류 줄에 적힌 구간으로 읽는다.
- 사전 `catalog/dictionary/terms.json`이 독자가 만나는 모든 용어의 단일 정의다. 줄마다 이름·자리·한 줄 설명·맛 경향·향 경향·고르는 힌트·앱 표시·근거 칸을 같은 모양으로 가진다. 카드 함수, 앱, 도구는 `dictionary.ts` / `dictionary_views.dart` / `tools/catalog/dictionary/project.py`의 보기로 읽고, `catalog_taxonomy` 투영도 여기서 만든다.
- 가격, 판매처, 재고, 구매 링크는 저장하지 않는다. 모든 기록은 catalog 상품 하나를 가리킨다. Flutter는 published projection과 RPC만 사용한다.

### 수집·정규화 파이프라인 (`tools/catalog`, `manual-import/fill-work`)

수집기 → 출처가 연결된 작업 DB → 정규화·채움·검증 → 검수한 변경분 → Supabase 순서다. 수집기는 재시작 가능한 checkpoint를 쓰고 DB 반영과 분리한다.

- `dictionary/`: 사전 보기와 `catalog_taxonomy` 투영. `enrichment/`: 분류·원료·공정 배정과 `catalog_taxonomy` 생성. `sensory/`: 감각 note 추출, 수치 채움, 스타일 표 계산. `field_rules/`: 상품 필드 규칙 검사와 표기 정리. `normalization/`: 감각 사전 도구. `backup_local_db.sh`: 작업 DB 백업.
- 수집값은 확인된 기존 값을 덮어쓰지 않고 빈 값만 보완한다. 배열은 근거 있는 합집합을 쓰며 충돌은 따로 남긴다. 추정 보완은 출처와 낮은 확신을 남긴다.
- 수집한 자료와 그 근거는 보존한다. 한 작업은 `manual-import/fill-work/collect/YYYY-MM-DD_slug` 폴더 하나에 둔다.
- 로컬 작업 완료는 Supabase 반영을 뜻하지 않는다. 원격 반영은 별도 요청으로만 한다.

### 술결카드 엔진 (`supabase/functions/_shared/taste_card`)

익명 첫 기록과 인증 반복 기록은 같은 서버 orchestration(`orchestrator.ts`)과 순수 결정론 엔진을 쓴다. 전환과 owner 조회는 저장된 snapshot을 재계산하지 않는다.

```text
anonymous completion ─┐
                      ├─> orchestrator.ts (questionnaire 검증, catalog 한 번 읽기)
authenticated record ─┘
                              v
                   card_record.ts -> SensoryRecord (정규화한 답변 + 상품)
                              v
                   card_reading -> card_findings -> card_conclusions (CardFacts)
                              v
                   card_writing / card_prose* / card_summary / card_guide
                   -> card_text.ts (별명 · 핵심 요약 · 가이드 · 두 섹션의 문단)
                              v
                   repository.ts -> taste_cards (idempotent) / 익명 전환
                              v
                   Flutter TasteCard renderer

saved cards of one account -> taste_letters.ts (기록당 축별 한 표 -> 최근 가중 합산 -> 네 글자·기울기·바뀐 순간)
                           -> repository.ts -> taste_letters / taste_letter_changes -> Flutter 홈
```

- 입력은 설문 답변과 상품 하나뿐이다. 과거 기록과 메모는 카드에 쓰지 않는다. 엔진은 Supabase, Flutter, HTTP, clock, random, filesystem을 모르는 순수 함수다. Dart와 TypeScript에 규칙을 중복 구현하지 않는다. runtime에서 LLM을 호출하지 않으며 제품명별 분기도 두지 않는다.
- 카탈로그가 더 이상 내주지 않는 상품(검색 뒤 비공개된 경우)은 카드를 쓰지 않고 거절한다. timeout과 read failure는 근거가 아니며, 카탈로그가 이 상태이면 final 대신 재시도 가능한 상태로 남긴다.
- 카드 문장은 `card_facts.ts`와 `card_conclusions.ts`가 읽은 사실에서 `card_writing.ts`가 문단으로 쓴다. 문장 틀과 문안은 `card_prose*.ts`가 소유하고, 핵심 요약은 `card_summary.ts`, 다음 술 가이드는 `card_guide.ts`, 별명은 `nickname_*`이 쓴다. `card_text.ts`가 이들을 한 장으로 모은다.
- 공개 view는 `TasteCardResultEnvelope` 하나이며 `types.ts`와 `serialization.ts`가 wire를 소유한다. Flutter는 `lib/src/features/taste_card/data/taste_card_wire_parser.dart`로 parse한다. 기록과 카드 사실(private snapshot)은 Flutter에 노출하지 않는다.
- 기록 완료 시 당시 카드를 재현할 수 있는 snapshot(기록과 카드 사실)을 기록에 연결한다. 이후 기록·catalog·rule이 바뀌어도 과거 카드를 자동 재계산해 덮어쓰지 않는다.

## 핵심 흐름

### 공통 술결 완료와 술결카드

1. 비로그인 첫 사용자와 로그인 이후 반복 사용자는 각각의 local draft에서 하나의 `술결 남기기` 흐름을 시작한다.
2. 같은 흐름 안에서 catalog 검색으로 술을 필수 확정한다.
3. 이름 검색은 검수된 published catalog projection을 사용한다. 결과가 없으면 다른 이름으로 다시 찾는다.
4. 카드와 기록은 catalog 대표 이미지를, 없으면 주종별 기본 이미지를 쓴다.
5. 질문 답변(질문 key와 고른 선지 key)을 draft에 보존한다. 향은 검색으로 고른 것까지 최대 5개 고른다. 자동 상세 질문은 최대 한 개다.
6. 선택 개인 메모는 분석에 쓰일 수 있음을 입력 전에 고지한다. versioned deterministic rule이 하나의 의미로 명확하게 해석한 내용만 근거로 쓰고, 모호한 내용은 원문으로만 보존한다. 메모 원문이나 해석 결과를 다음 기록 입력 화면에 다시 보이지 않는다.
7. 서버가 답변을 정규화하고 catalog 상품과 함께 카드 사실을 읽은 뒤, 공개 view `product -> bite(별명·핵심 요약·가이드) -> positive -> burden -> balanced`를 쓴다. Flutter는 고정 chrome인 bridge와 actions를 더해 `product -> bite -> bridge -> 왜 잘 맞았을까요 -> 왜 부담이었을까요 -> 왜 편안했을까요 -> actions` 순서로 표시한다(빈 섹션은 생략).
8. 근거가 부족하면 일반 문구로 채우지 않고 해당 섹션을 비운다. 잘 맞은 답이 없으면 왜 잘 맞았을까요 섹션은 없다.
9. 카드는 이번 기록의 답변과 그 술의 확인된 정보만 사용한다. 기록 수 자체는 깊이나 확신도를 올리지 않는다.

### 술결카드 조회 경계

과거 카드 조회는 최신 rule로 재생성하지 않고 `taste_cards`에 저장된 rendered content를 읽는다. 카드 생성 시도는 `taste_card_generation_attempts`가 기록하고, 익명 결과는 30일 뒤 삭제된다.

### 저장 전환

1. 결과의 `내 술결 저장하기`가 save intent를 만든다.
2. Kakao, Apple, Google 중 하나로 인증한다.
3. 미완료 profile은 `닉네임 -> 관심 주종 -> 가입 확인`을 거친다.
4. `가입 확인`은 생년월일로 연령 기준을 검증해 비공개 저장하고, 만 19세 자가 확인과 문서 버전별 약관·개인정보·선택 마케팅 동의를 `complete-profile`에 멱등적으로 저장한다.
5. 검증된 Auth provider와 계정 상태는 서버가 판별하고 client 선언을 신뢰하지 않는다. 현재 문서 버전의 동의를 이미 완료한 계정은 status 조회 후 가입 확인을 건너뛴다.
6. 임시 `anonymousSessionId`, `resultId`, `conversionToken`으로 첫 결과를 계정에 한 번만 전환한다.
7. 결과 화면으로 돌아와 저장 완료 상태를 보여주고 내 술결과 내 취향으로 연결한다.

### 탈퇴와 삭제

탈퇴 요청 즉시 계정, 기록과 개인화 데이터의 일반 접근을 차단한다. 30일 안에는 복구할 수 있고, 만료 후 service-role purge(`account-retention-purge`)가 계정, 소셜 연결, 기록, 사진, 답변, 자유 입력, 결과와 snapshot을 영구 삭제한다. 클라이언트는 purge 권한을 갖지 않는다.

## 계약 우선순위

1. `docs/PRD.md`와 `docs/ADR.md`: 제품 정의, 범위와 결정
2. `docs/specs/TASTE_CARD_RECORD_SCENARIOS.md`: 술결카드 공개 문안과 인사이트 품질 기준
3. `docs/specs/FRONTEND_DATA_CONTRACT.md`: 화면 상태 계약
4. `docs/specs/SHARED_API_DTO_CONTRACT.md`와 Flutter/TypeScript DTO: 공유 request/response wire
5. `docs/specs/ALCOHOL_CATALOG_DATA_CONTRACT.md`, `docs/DATABASE.md`와 migration SQL: repository/serving 경계, 물리 schema, RLS와 보존 정책
6. 코드와 test fixture: 실행 가능한 계약

계층 사이에 충돌이 있으면 한쪽을 임의 정본으로 선언하지 않고 차이를 기록해 해당 결정을 다시 확인한다.

## 검증 계층

- Flutter model/widget tests (`test/`): entry, onboarding, profile setup, navigation, record draft, 공통 frontend 상태와 공통 컴포넌트
- Responsive widget matrix: 모든 `AppRoute`를 320px 휴대폰, Galaxy S26, iPhone 17과 1440px web viewport에서 렌더링하고 큰 글자·keyboard inset을 검증한다.
- Security tests: auth/profile gate, anonymous conversion redaction, RLS·Storage 접근 거부, retention purge, shared DTO 계약
- Deno tests (`supabase/functions/_tests`): Edge Function 계약, endpoint 동작, 카드 엔진, observability redaction
- Python tests (`tools/catalog/tests`, 공통 fixture는 `tests/fixtures/`): 수집·정규화·감각 사전·검증 도구
- Integration tests: Flutter와 backend 계약을 연결한 첫 경험, 저장 전환, 공유, 탈퇴 핵심 흐름
