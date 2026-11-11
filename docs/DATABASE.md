# Soolgyul Database

이 문서는 현재 schema의 역할만 적는다. 이력은 `supabase/migrations/`가, 원격 적용 여부는 Supabase migration list가 답한다.

## 정본

- 물리 schema와 그 이력은 `supabase/migrations/`의 timestamped migration이 소유한다.
- 앱이 읽는 catalog는 Supabase serving table이 소유한다.
- catalog 로컬 작업본은 `manual-import/fill-work/rows.sqlite3`다.
- Supabase는 production 프로젝트와 그 안의 persistent branch `develop` 두 환경이다. migration과 함수는 `develop`에서 먼저 검증한 뒤 production에 적용한다.
- Alcohol Catalog의 repository/serving 경계와 최소 serving 논리 계약은 [`specs/ALCOHOL_CATALOG_DATA_CONTRACT.md`](specs/ALCOHOL_CATALOG_DATA_CONTRACT.md)가 소유한다.
- 술결카드의 의미와 lifecycle은 versioned engine code가 소유한다. [`TASTE_CARD_RECORD_SCENARIOS`](specs/TASTE_CARD_RECORD_SCENARIOS.md)는 카드 문안과 품질을 검수할 뿐 migration을 승인하지 않는다.
- 이 문서를 고쳐도 migration, import, table drop, 원격 적용은 일어나지 않는다.

## 테이블 역할

| Table | 책임 | 보존·접근 핵심 |
|---|---|---|
| `users` | `auth.users`와 1:1인 제품 계정·프로필 | 닉네임·성인 확인·생년월일·계정 상태. 활성 owner 조회와 RPC-only 수정 |
| `user_consents` | 약관·개인정보·마케팅 정책 version별 동의/철회 이력 | 기존 동의를 덮어쓰지 않는 append-only 이력 |
| `user_drink_interests` | 사용자와 관심 주종(`alcohol_categories.interest_key`)의 다대다 관계 | FK, 사용자당 1~5개, owner read와 RPC-only mutation |
| `user_liked_drink_cards` | 본인에게 발급된 술결카드의 private 좋아요 보관함 | `(user_id, drink_record_id)` PK, 활성 owner만 select/insert/delete, 계정·카드 purge cascade |
| `user_saved_articles` | 사용자의 private 저장한 정보글 | `(user_id, article_id)` PK, 활성 owner만 select/insert/delete, 계정·글 삭제 cascade |
| `user_push_devices` | 알림을 켠 기기의 알림 주소(FCM token)와 기기 종류 | token PK, 기기 하나는 한 계정에만 속하고 회원당 최근 10대, client는 등록·삭제 RPC만 쓰고 table은 service-only, 계정 삭제 cascade |
| `catalog_search_signals` | 검색에서 같은 급의 결과 중 앞에 올 상품 | `known`은 손으로 고른 알려진 상품, `picks`는 최근 90일에 그 상품을 고르거나 궁합을 열거나 기록한 회원 수(밤마다 `soolgyul_refresh_catalog_search_picks`가 다시 센다). service-only, 상품 삭제 cascade |
| `catalog_unlisted_terms` | 카탈로그가 다루지 않는 술을 가리키는 낱말과 그 종류 | 공백·부호 없는 소문자 낱말 PK. service-only |
| `admin_user_roles` | 별도 관리자 웹의 backend-owned 권한 grant | 계정당 `editor` 또는 `admin` 하나, client는 본인 role만 읽고 grant 변경 불가 |
| `editorial_articles` | 탐색·보관함에서 쓰는 게시글(사진 갤러리 + 줄바꿈 있는 일반 글) | 본문, `instagram_url`(있으면 글 머리글의 인스타그램 버튼이 여는 주소), draft/published/withdrawn 상태. 피드는 공개 시각 최신순 |
| `editorial_article_media_assets` | 게시글 소유 사진 | `sort_order`가 갤러리 순서이고 맨 앞 사진이 표지, Storage 경로 |
| `editorial_article_interests` | 게시글이 다루는 관심 주종 | `(article_id, interest_key)` PK, `alcohol_categories.interest_key` FK. 줄이 없는 글은 특정 주종과 무관한 글 |
| `site_posts` | soolgyul.com 공지사항·자주 묻는 질문 글(관리자 웹에서 작성) | `kind` notice/faq, 제목·줄바꿈 있는 본문, FAQ 순서 `sort_order`, draft/published/withdrawn. 발행본은 public read, editor는 초안만 쓰고 admin이 발행·삭제 |
| `app_gates` | 플랫폼별(ios·android·web) 앱 출입 조건 | 이 버전 미만이면 업데이트 안내(`minimum_version`), 값이 있으면 점검 안내(`maintenance_message`). 누구나 읽고, 바꾸는 것은 SQL로만 |
| `alcohol_categories` | primary 주종 정본 | 활성 row는 public read, service-managed write. `interest_key`는 그 주종을 사용자 관심 주종으로 내보이는 unique 키이며 모든 주종이 가진다 |
| `producers` | 생산자(와이너리·증류소·양조장·브랜드) | `producer_key` unique, 한글·영문 이름, 라벨에 찍힌 원어 이름 `name_native`(사케는 일본어), 셋을 접은 검색 generated column |
| `catalog_taxonomy` | 검색·검증이 쓰는 분류 뼈대(산지 트리, 종류·원료·공정·숙성 키, 감각 태그 키) | `(term_type, term_key)` 정본. 아래 "분류 어휘" 절 참조 |
| `alcohol_items` | 기록·검색의 단일 상품 단위. 빈티지·도수·연산 버전도 개별 행 | 이름, category FK, `producer_id`, style, 재료·공정 key 배열, 와인 품종 배열(`grape_variety_keys`), 국가 코드, 산지 `region_key`(`catalog_taxonomy` region 행), ABV, vintage_year, age_statement_years, 공개 여부 `publish_status`, 검색 접기 generated column |
| `catalog_media_assets` | 상품당 하나의 이미지 | `alcohol_item_id` unique, `media_path`로 Storage 파일 연결 |
| `alcohol_tasting_profiles` | 상품별 하나의 선택적 운영 감각 프로필 | 아래 "감각 프로필" 절 참조 |
| `drink_records` | 비로그인/회원 술 기록. 답한 질문지 버전 이름, 카탈로그 상품 ID, 한 줄 메모 | owner는 읽기만, 쓰기는 service RPC. 예외는 owner가 메모만 바꾸는 RPC 하나. 회원이 지우면 익명 보존 후 원본 삭제, 계정 purge 대상 |
| `drink_record_answers` | 질문(`sensory_<구간>`)별로 고른 선지 key | record owner만 접근, parent 삭제 시 cascade |
| `taste_cards` | 술결카드 결과와 내부 해석 근거 | 기록당 하나. 공개 rendered snapshot과 private semantic snapshot을 한 행에 둔다 |
| `taste_card_generation_attempts` | 카드 생성 시도와 재시도 | principal별 idempotency key, 익명 세션당 24시간 10회 상한 trigger |
| `taste_letters` | 계정당 하나의 취향 조각 네 글자(향 F/R · 단맛 D/S · 무게 L/H · 여운 C/P)와 축별 기울기·표 수 | 저장된 카드 전체를 다시 돌린 결과. 카드가 만들어지거나 익명 카드가 계정에 붙을 때 service RPC가 통째로 바꾼다. owner read |
| `taste_letter_changes` | 글자가 처음 드러나거나 넘어간 순간 | 축·이전 글자·새 글자·기울기·넘긴 기록(병 이름). `taste_letters`와 함께 통째로 바뀌고 기록 삭제 시 cascade. owner read |
| `support_inquiries` | 비공개 문의 내용·이메일·첨부 경로·답변 완료 시각 | 접수 UUID로 재시도 처리. 관리자 웹은 `admin` role만 `soolgyul_admin_*_support_inquir*` RPC로 읽고 답변 완료를 표시한다. 답변 6개월 뒤 `account-retention-purge`가 첨부 파일을 지우고 행을 `closed_support_inquiries`로 옮기며, 어느 문의에도 없는 첨부 파일은 올린 지 24시간 뒤 지운다 |
| `closed_support_inquiries` | 답변 6개월이 지난 문의의 유형과 내용 | 주인·이메일·첨부·날짜 없이 보존하는 익명 기록. client 읽기 없음 |
| `admin_access_logs` | 관리자가 문의를 읽거나 답변 상태를 바꾼 기록 (누가·언제·어느 문의) | 문의 RPC만 쓰고 client 읽기 없음. 1년 이상 보관 |
| `sign_in_records` | 로그인한 시각·IP 주소·기기 정보 | `auth.sessions` trigger만 쓰고 client 읽기 없음. 3개월 뒤 삭제하며 탈퇴 계정의 행도 그 기간 동안 남는다 |
| `withdrawn_drink_records` | 회원이 지운 카드와 탈퇴 회원의 카드를 주인 없이 보존하는 익명 기록 | 아래 "탈퇴와 30일 보존" 절 참조 |
| `drink_discovery_events` | 검색 선택·빈 검색·라벨 일치/불일치·취향 핏 열람 이벤트 | 쓰기는 `soolgyul_record_discovery_event` RPC만, client 읽기 없음. 회원 행은 13개월 뒤나 계정 purge 때 계정 연결을 끊고 KST 날짜·출생연도 5년 구간·동의한 성별만 남긴다. 비회원 행은 처음부터 계정이 없다 |

### 감각 프로필

`alcohol_tasting_profiles`는 `alcohol_item_id` unique다.

- 네 구간 note(aroma·palate·texture·finish)와 세 구간 태그(`aroma_tags`, `palate_tags`, `finish_tags`)를 가진다.
- 1~5 수치 아홉 개는 `sweetness`, `acidity`, `bitterness`, `astringency`, `body`, `carbonation`, `aroma_intensity`, `finish_length`, `finish_cleanliness`다.
- 수치는 nullable이며 병에서 읽은 값만 저장한다. 수치별 근거 등급은 `level_sources`에 1~4 숫자로 적고(1 제조사 공식, 2 외부 평가, 3 사용자 평가 모음, 4 종류 추정), 등급 없는 수치는 미상이다.
- 빈 수치는 카드가 사전(`catalog/dictionary/terms.json`)의 종류 줄 값으로 말한다. 알코올감은 column 없이 `abv_percent`를 사전의 주종·종류 줄에 적힌 다섯 단계에 놓아 읽는다.
- 공개 여부는 상품의 `publish_status` 하나로 본다.

### 상품 모델

- 주종은 `alcohol_category_id`, 세부 분류는 `style_key`, 생산자는 `producer_id`로 가리킨다. 표시명은 `name_ko`/`name_en`이다.
- 서비스 공개 판정은 상품의 `publish_status` 하나다.
- 릴리스 table은 없다. 빈티지·연산·edition·batch는 개별 `alcohol_items` 행이다.
- 중복 상품은 참조를 canonical 상품으로 옮기고 행을 삭제하므로 redirect table은 없다.
- 용량·판촉 포장 차이는 같은 상품으로 정리하고 용량은 저장하지 않는다.
- 도수가 실제 판매 라인을 구분하면 도수별 상품을 유지하고 표시명에도 도수 숫자를 남긴다(`화요 17`).
- 생산자 이름 검색은 `producer_id` 연결을 통해 한다.

## 감각 사전과 연결

- [감각 계약](specs/SENSORY_CATALOG.md): 향·향미·질감·피니시의 의미와 상품 경계.
- `catalog/dictionary/terms.json`: 향·질감·여운 용어의 트리, 별칭, 원문 표현 규칙, 앱에 보이는 대표 표현, 한 줄 설명과 특성.
- DB `catalog_taxonomy`: 활성 어휘와 적용 영역. 사용자 표시에는 `metadata.user_visible=true`도 확인한다.
- 감각 설명과 해석 특성은 사전 파일에만 있고, 카드 함수는 함께 배포된 사전 사본을 읽는다.
- 상품 연결은 `alcohol_tasting_profiles`의 구간별 태그가 담당한다. 연결이 없는 값은 감각 부재나 0이 아니다.
- 감각 프로필 통합은 같은 상품 안에서만 한다. 구간 없는 태그를 aroma·finish 양쪽에 복제하지 않는다.
- 별도 감각 관리자 table은 만들지 않는다.

## 분류 어휘와 스토리 계약

`catalog_taxonomy`는 DB가 검색과 검증에 쓰는 분류 뼈대만 투영한다. 설명문, 전체 후보, 주종 적용 범위, 배타 규칙, 검수 evidence는 하나의 사전 `catalog/dictionary/terms.json`이 소유한다.

| Column | 계약 |
|---|---|
| `term_type`, `term_key` | composite primary key. type은 `sensory_descriptor`, `ingredient`, `process`, `maturation`, `style`, `region` |
| `label_ko`, `label_en` | 한국어 필수 표시명과 nullable 영문 표시명 |
| `synonyms` | null·빈 값·중복 없는 최대 64개 text 배열 |
| `parent_term_key` | nullable same-type parent. self-parent와 orphan 금지 |
| `applicable_sections` | 해당 term이 허용되는 비어 있지 않은 최대 9개 section 집합 |
| `metadata` | 서비스 표시에 필요한 제한된 확장. raw evidence 저장 금지 |
| `taxonomy_version`, `sort_order`, `is_active` | seed version, 정렬, lifecycle |
| `created_at`, `updated_at` | 생성·수정 시각 |

- `term_key`는 snake_case다.
- table은 RLS를 켜고 anon/authenticated 직접 권한을 주지 않는다.
- trigger가 key 변경을 거부한다. rename은 새 key를 추가하고 기존 key를 지운다. 사전에서 빠진 term은 seed가 지운다.
- 감각 태그 배열은 구간별 최대 64개, GIN index를 가지며 활성 `sensory_descriptor`이면서 해당 `applicable_sections`에 허용된 값만 받는다. 검색용 태그는 이 배열들을 합쳐 조회하며 `flavor_tags`는 없다.
- `ingredient_keys`는 `ingredient`, `production_process_keys`는 `process|maturation`, style key는 `style`, `region_key`는 `region` term을 검증한다.
- `region`은 산지 표다. 나라 행(ISO 두 글자 소문자 key)이 뿌리이고 `parent_term_key`로 위 산지를 잇는다. 단계 수는 주종마다 다르다(와인 나라>광역>세부, 위스키 나라>스코틀랜드>지역, 사케 일본>도도부현, 전통주 한국>시도>시군구). 상품은 가장 세부 행 하나를 가리키고, 카드 서버는 사전에서 같은 트리를 읽어 산지 줄을 만든다. 배열은 최대 원소 수와 중복 금지를 DB constraint로 강제한다.
- term 검증 trigger는 신규 row나 해당 배열이 바뀌는 update만 활성 term에 대조한다.
- seed 전체를 운영 DB에 재실행하지 않는다. 최신 상태를 대조한 변경분만 반영한다.
- 상품 이야기 table·view·함수와 `story_topic`은 없다.
- 향·맛·피니시·질감·원료·공정별 table과 generic term-link table은 만들지 않는다. assignment별 강도·순서·출처가 서비스 요구로 승인될 때만 관계 모델을 다시 정한다.

## 모델링 불변조건

- 안정적인 ID, FK, 소유권, 상태, 생성/변경 시각은 typed column이다.
- 질문과 선지, 결과·취향의 변경 가능한 구조는 질문지 버전 이름(`questionnaire_version`)과 `canonical_schema_version`이 붙은 snapshot으로 보존한다. JSON snapshot은 owner ID, FK, 상태, timestamp를 대신하지 않는다.
- 술 정본 단위는 판매 SKU나 병 용량이 아니라 `alcohol_items` 상품이다.
- 병·캔·페트와 용량·판촉 포장만 다른 중복 행은 media·tasting과 사용자 FK를 canonical 상품으로 옮긴 뒤 삭제한다.
- legacy category text는 두지 않고 `alcohol_category_id` FK만 쓴다.
- "어떻게 만들었나"는 `production_process_keys` 한 칸이다. 정규화한 style/ingredient/process table이나 generic link table은 만들지 않고 생산자만 `producers` table로 둔다. 산지는 `catalog_taxonomy`의 `region` 행이 부모 연결로 맡는다.
- 사용자 관심 주종은 `alcohol_categories.interest_key`를 참조하고 선택은 최대 5개다.
- Kakao·Apple·Google `auth.users` insert는 security-definer trigger가 같은 UUID의 `users` row 하나를 provision한다. `display_name`과 `age_confirmed_at`은 완료 전 null이며 확인·동의 시각을 꾸며 넣지 않는다. `provider_user_id`는 변경 가능한 user metadata가 아니라 Auth UUID를 쓴다. client는 계정·프로필 row를 직접 insert/update할 수 없다.
- 마이페이지는 `soolgyul_get_my_profile_preferences`, `soolgyul_update_my_display_name`, `soolgyul_replace_my_drink_interests` RPC만 쓴다. mutation RPC는 UUID idempotency key, 활성 계정, owner lock, 입력 검증을 강제한다. 표시 이름은 2~12자, 관심 주종은 활성 key 1~5개다.
- 가입은 `soolgyul_complete_my_profile` 하나다. 표시 이름, 연령 확인, 생년월일, 성별, 문서 버전별 필수 동의와 선택 마케팅 동의를 한 transaction에 저장하고, 수락 이력은 `user_consents`에 남긴다. 생년월일은 공개 응답에 넣지 않는다. RPC는 `users.auth_provider`가 Kakao·Apple·Google인지 확인한다.
- 완료 상태는 `soolgyul_get_my_profile_status`이 현재 문서 버전 기준으로 조회한다.
- 성인 프로필 완료 판정은 `soolgyul_adult_profile_complete` 하나가 정의한다. 연령 확인 시각과 현재 버전의 성인·약관·개인정보 동의가 모두 유효해야 하며 상태 RPC, 비회원 카드 귀속, 카드 생성 확정, Edge 프로필 게이트가 이 함수를 쓴다.
- tasting note는 `aroma`, `palate`, `finish`, `texture` 구간별로 보존하고, 구간별 태그 배열은 구간 위치를 보존한다.
- 15번째 축 `tannin` column은 없다. `astringency`를 tannin 근거로 쓰지 않는다.
- 개인 table은 owner RLS를 적용한다. 검수된 published catalog projection만 anon/authenticated read-only로 공개한다.
- 가격, 판매처, 재고, 구매 링크는 catalog 범위에서 제외한다. 이미지는 `catalog_media_assets`로 관리하며 권리·검수 상태 필드는 없다.

## 질문지와 답변 재현

질문과 선지는 DB에 두지 않는다. 서버 코드의 버전 붙은 질문지(`record/questionnaire.ts`)가 정본이고, 기록은 답한 질문지의 버전 이름(`drink_records.questionnaire_version`)을 글자로 남긴다. 답변은 구간별 `question_key`와 `selected_option_keys`만 저장하고 문구는 그 버전의 질문지에서 찾는다. 구조화된 답변은 `free_text`를 받지 않는다. 선지 수 제한은 질문지 코드가 검증한다.

질문지가 바뀐 뒤에도 사용자가 실제로 본 질문과 선택을 복원할 수 있다. 한 줄 메모는 답변이 아니라 `drink_records.one_line_note`에 둔다.

## 술 식별

`drink_records`는 항상 `alcohol_item_id`를 갖는다. 이름을 직접 적은 기록은 없으며, 상품 이름과 주종은 카탈로그에서 읽는다.

이름 검색은 화면이 부르는 `soolgyul_search_catalog(text, integer, integer)`와 그 안의 `soolgyul_search_alcohol_catalog(text, integer, integer)` RPC만 쓴다. 앞의 것은 결과(`results`)와, 낱말이 카탈로그가 다루지 않는 술을 가리킬 때 그 종류(`not_carried`)를 함께 준다.

- active·published 상품을 한글명, 영문명, 생산자 이름으로 찾고 최대 20개를 반환한다.
- 질의와 이름을 `soolgyul_fold_korean_sound`로 접어서 비교한다. 된소리→예사소리, ㅐ=ㅔ, ㅛ=ㅗ 같은 모음 짝, 끼어든 르·이 제거, 공백·부호 제거, 라틴 악센트 접기가 포함된다. 일본어 가나·한자는 그대로 남긴다.
- 질의는 낱말 단위로 나뉘며 모든 낱말이 상품 이름이나 생산자 이름에 있으면 찾는다. 낱말이 이름에 있다는 것은 이름의 한 낱말 안에 들어 있거나, 이름의 어느 낱말 첫머리부터 붙여 쓴 대로 이어진다는 뜻이다. 앞 낱말의 끝과 뒤 낱말의 처음을 이어 붙인 것은 치지 않는다. 한두 글자 낱말과 혼자 친 한 음절은 이름 낱말의 첫머리여야 한다. 맨 앞의 "더"·"the"는 찾지 않는다.
- 그런 상품이 없으면 같은 말을 달리 적어 다시 찾는다. 숫자 뒤의 "도"·"년산"을 떼고, 글자와 숫자를 띄우고, 한글로 읽은 알파벳("엠")을 글자로 바꾼다.
- 그래도 없을 때만 비슷한 상품을 돌려준다. 비슷하다는 것은 질의의 낱말마다 첫 글자가 같고, trigram 유사도가 0.45 이상이거나 한 글자만 다른 이름·생산자 낱말이 있다는 뜻이다. 비슷한 상품도 없고 질의가 붙여 쓴 한글 한 낱말이면, 둘로 갈라 각 토막이 이름 낱말의 첫머리인 상품("조니블랙")을 준다.
- 주종을 가리키는 낱말(위스키, 와인, 사케, 전통주)과 나라 이름은 이름에서 찾지 않고 그 주종·나라로 좁힌다. 좁힌 결과가 없거나 질의 전체가 어떤 상품의 이름이면 모든 낱말을 이름에서 찾는다. 주종·나라 낱말만 있으면 그 안의 알려진 상품을 준다.
- style을 가리키는 낱말(막걸리, 싱글몰트, 레드 등)을 다른 낱말과 함께 치면, 나머지 낱말이 이름 낱말의 첫머리인 그 style 상품도 찾는다.
- 각 행의 `match_kind`는 `exact`(친 그대로의 철자가 이름에 있음), `sound`(소리만 같음), `near`(비슷함)이다.
- 접은 글은 `alcohol_items.search_fold_text`와 `producers.search_fold_text` generated column에 두고 trigram index로 찾는다.
- 같은 접기 규칙이 `tools/catalog/field_rules/check.py`의 `search_fold`에 있고 fixture `korean_sound_fold.json`이 둘을 맞춘다.
- 정렬은 친 그대로의 철자(친 대로 시작하는 이름이 없으면, 소리대로 시작하는 알려진 상품도 같은 자리에 선다), 전체 이름 일치, 이름에서 찾은 것(생산자에서만 찾은 것보다 먼저), `catalog_search_signals`의 무게(알려진 상품 3 + ln(1 + 고른 회원 수)), 낱말이 이름에 놓인 자리(이름의 시작, 온전한 낱말, 낱말의 시작, 일부), 연도를 뗀 이름의 길이, 최근 빈티지 순이다.
- 친 철자는 `alcohol_items.search_typed_text` generated column(두 이름에서 공백·부호·악센트를 빼고 소문자로)에 둔다.
- `catalog_unlisted_terms`의 낱말이 질의 전체이거나 첫 낱말이고, 그 낱말로 시작하는 상품 이름이 카탈로그에 없으면 다루지 않는 술로 본다. 이때는 `exact` 행만 준다.
- Flutter는 이 RPC가 돌려주는 공개 column만 기록 선택 계약으로 받는다.

## 술결카드 저장 구조

- 카드는 `taste_cards` 한 행에 공개 rendered snapshot과 private semantic snapshot을 함께 둔다.
- 카드 lifecycle은 `final` 하나다. 카드는 한 번에 통째로 쓰이고 trigger가 이후 내용 변경을 막는다.
- 일시 실패와 재시도는 `taste_card_generation_attempts`가 principal별 idempotency key로 관리한다.
- client는 연결에 필요한 카드 ID만 직접 조회한다. 카드 내용은 owner를 검증하는 Edge 경로가 service-role RPC로 읽는다.
- 첫 기록과 반복 기록 모두 기록에 묶인 snapshot을 만들고, 히스토리는 해당 snapshot을 열어 당시 카드를 재현한다. 이후 기록, catalog, rule이 바뀌어도 과거 snapshot을 덮어쓰지 않는다.
- 카드의 `clues`, `combination`, 선택 방향, rendered copy마다 별도 table을 만들지 않는다. ID, owner, 상태, 시각은 typed column이고 함께 versioning되는 semantic·presentation은 bounded JSON envelope다.
- 기록 수나 최근 목록처럼 원본에서 손실 없이 구할 수 있는 값은 조회 시 계산한다. 시점별로 다시 보여줘야 하는 해석은 snapshot row로 보존한다.

## RLS와 Storage

- 모든 개인 table은 RLS를 쓴다. `soolgyul_account_active(user_id)`가 활성 계정인지 확인한다.
- 권한은 명시적 grant만 쓴다. `postgres`의 기본 권한에서 `anon`·`authenticated`를 제거했고, client가 호출하는 RPC와 정책·제약에서 실행되는 검증 함수만 허용한다. 새 함수와 table은 필요한 역할에 직접 grant해야 노출된다.
- 회원 record, answer, 공개 result는 활성 owner만 읽는다. private semantic snapshot은 client가 직접 읽지 않는다.
- `user_liked_drink_cards`는 본인의 삭제되지 않은 record만 추가·조회한다. update, anon 접근, 공개 반응 수, 타인 카드 관계는 허용하지 않는다.
- 검수된 published catalog projection만 비로그인 공개 읽기를 허용한다. 미공개 상품·media·tasting은 service-only다.
- 검색 RPC `soolgyul_search_catalog`와 `soolgyul_search_alcohol_catalog`는 `search_path`를 고정한 `SECURITY DEFINER` 함수다. active·published 상품만 고정 SQL로 골라 공개 column(ID, 이름, 주종, style과 그 한글 이름, ABV, 사진 경로, 국가, 산지 한글 이름)만 반환한다. `PUBLIC` execute는 회수하고 `anon`·`authenticated`·`service_role`에만 허용한다.
- 서비스 이미지는 공개 버킷 `alcohol-product-images`의 `{category_key}/{상품ID}.webp`에 둔다. 버킷은 코드에 고정하고 `catalog_media_assets.media_path`가 파일 경로를 연결한다. 상품당 하나이며 원본·썸네일을 따로 만들지 않는다. 전용 이미지가 없는 상품은 앱의 주종 기본 이미지를 쓴다.
- `soolgyul-private` Storage bucket은 비공개이며 문의 첨부 사진을 둔다. object path 첫 segment가 owner UUID이며 활성 owner의 read/insert/update/delete만 허용한다.
- 게시글 사진은 공개 버킷 `soolgyul-editorial`에 두고, 쓰기는 관리자 role(admin·editor)만 할 수 있다.
- 카탈로그 수집 원문, 출처, 추정 여부와 DB에서 걷어낸 행·컬럼은 serving DB가 아니라 비공개 버킷 `soolgyul-catalog-snapshots`의 `catalog-archive/latest/`에만 보관한다. 다시 수집할 수 없는 자료이므로 지우지 않고, client policy 없이 service role로만 읽는다.
- service-role 작업은 client policy와 분리하며 service key를 앱이나 evidence에 넣지 않는다.
- Security Advisor의 공개 view `security_definer_view` ERROR와 함수 mutable `search_path` WARN은 허용하지 않는다. service-only table의 `RLS enabled, no policy` WARN은 의도된 deny-by-default이므로 없애려고 client read policy나 raw column grant를 추가하지 않는다.

## 비회원 보관

- 첫 접수 후 30일이 지난 미귀속 비회원 기록·답변·카드·시도 행은 매시간 도는 pg_cron 작업 `soolgyul-anonymous-retention`이 삭제한다. 그 안에 앱에서 로그인한 계정이 전환 티켓으로 가져가면 회원 기록이 된다.
- 기록은 Storage object를 갖지 않으므로 Storage 정리는 없다. 집계 table은 만들지 않는다.

## 탈퇴와 30일 보존

1. 탈퇴 요청·복구는 소유자 RPC로 `users`의 현재 상태만 갱신하며 별도 탈퇴 이력 table은 없다.
2. 요청 즉시 앱 로그인/조회, 추천·개인화·분석 사용을 차단한다.
3. 30일 동안 삭제 대기 상태로 보관하고 그 안에 복구할 수 있다.
4. 기간이 끝나면 `withdrawn_drink_records`에 출생연도 5년 구간·동의한 성별·제품·고른 답·카드 해석만 별도 보존한다. 원본 회원/기록 ID, 세션 증명, 메모와 자유문장은 옮기지 않고 구조적인 이름·사진 연결도 제거한 익명정보다. 같은 단계에서 그 계정의 `drink_discovery_events`도 계정 연결을 끊는다. 회원이 카드를 직접 지울 때도 같은 방식으로 그 기록 하나를 바로 옮기고 원본을 삭제한다.
5. Storage 삭제 확인 후 보존과 서비스 기록 제거를 원자적으로 수행하고 계정을 `purged`로 잠근다. 이후 Auth Admin 삭제가 계정·연락처·관계를 최종 제거한다. 외부 삭제가 실패하면 재시도하며 보존 자료를 중복 생성하지 않는다.
6. `account-deletion`은 Auth 서버로 요청자를 확인하고 신선한 소셜 증명의 소유자를 검증한 뒤 연결을 해제한다. 토큰은 저장하지 않고 재로그인 시 해제 표시를 무효화한다. `account-retention-purge`는 전용 예약 비밀값으로만 호출되며, 기한이 지난 계정은 대기 중 재로그인으로 해제 표시가 무효화됐더라도 모두 처리한다.
7. 탈퇴 요청 전에 보존 범위와 복구 불가를 고지한다.

## 변경 규칙

- schema 변경은 새 timestamped migration으로 추가한다. 변경 이유는 migration 맨 위 짧은 주석에 쓴다.
- 테이블·인덱스·정책·함수를 바꾸는 migration은 주석 다음 줄에 `set local lock_timeout = '5s';`를 둔다. 긴 조회 뒤에서 잠금을 기다리는 동안 뒤따르는 요청이 모두 막히는 일을 없애고, 실패하면 다시 적용한다.
- RLS/Storage/권한/retention 변경은 `supabase/functions/_tests/db/schema_privileges_test.ts`에 마이그레이션 적용 후 동작 검증을 먼저 보강한다.
- API 필드 변경은 `docs/specs/SHARED_API_DTO_CONTRACT.md`, Dart contract, TypeScript contract, QA fixture를 한 변경으로 맞춘다.
- catalog seed와 projection은 가격, 판매처, 재고, 구매 링크, 병 용량, 판매 SKU를 추가하지 않는다.
- catalog 규칙 변경은 repository config와 도구를 고치고, 실제 데이터는 검증된 migration/import로 Supabase에 반영한다. 대용량 작업 파일은 Git에 넣지 않는다.
- MFDS `PRDUCT_KOREAN_NM`과 `PRDUCT_NM`은 source evidence에 원문으로 두고 `alcohol_items` 표시명이나 검색 projection으로 자동 승격하지 않는다.
- 서비스 제외 상품은 관계·전용 이미지까지 승인된 절차로 삭제하되 사용자 기록이 참조하면 자동 삭제를 중단한다.
- 공개 조건은 승인·게시된 상품이다. 사진은 게시 조건이 아니다.
