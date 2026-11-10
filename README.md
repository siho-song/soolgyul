# 술결

술결은 **마신 술의 느낌에서 내 취향을 발견하고, 다음 한 잔을 더 잘 고르게 돕는 술 취향 가이드**다.

Flutter 모바일 앱과 모바일 폭 중심 웹을 하나의 제품 저장소에서 개발한다. 제품 문서, 프론트엔드, Supabase 자산, 테스트, 검증 증거와 로컬 planning state도 이 저장소가 소유한다.

## MVP

- 로그인 없이 쉬운 첫 판단으로 술결 시작
- 필수 술 이름 검색과 선택적 사진 추가
- 국내 제조·수입 근거를 계속 보강하는 장기 주류 카탈로그
- 결과에 필요한 근거에서 역산한 적응형 질문과 룰 기반 술결카드
- 취향 단서, 다음 한 잔 방향, 부담스러운 방향
- 누적 기록 기반 취향 변화, 스펙트럼과 다음 탐험 방향
- Kakao, Apple, Google 소셜 로그인과 가입 단계의 만 19세 이상 확인
- 로그인 후 첫 술결 자동 저장, 내 술결과 취향 스냅샷
- 탈퇴 즉시 접근 차단, 30일 삭제 대기와 복구, 이후 영구 삭제

OCR, AI 문장 생성, 가격·판매처·재고·구매 기능, 상황별 개인화, 커뮤니티,
이메일/비밀번호 로그인은 MVP에 포함하지 않는다. 전체 문서의 역할과 읽는 순서는
[문서 안내](docs/README.md)를 따른다.

## 현재 Gate 상태

- 시각 구현 gate는 새 외부 디자인 이미지가 승인되고 Flutter 모바일 및 `360px` 웹 비교 캡처가 만들어질 때까지 차단돼 있다. 파일이 없는 과거 PNG 비교 기록은 통과 증거로 사용하지 않는다.
- shared API/DTO는 프런트엔드 시각 구현과 리팩터링 후 `frontend_data_contract_approved`가 기록될 때까지 초안이다.
- 저장소의 기존 Supabase 자산은 보존된 사전 구현 자산이며 라이브 배포 상태나 현재 승인된 production contract를 뜻하지 않는다.

## 저장소 구조

- `lib/`, `test/`: Flutter 제품 코드와 단위/위젯 테스트
- `supabase/`: 스키마, RLS, Storage 정책과 Edge Functions
- `docs/`: [문서 안내](docs/README.md), PRD, ADR, 아키텍처, DB와 기능 계약
- `tools/`: 카탈로그 도구, 로컬 DB 백업 스크립트, 에이전트 훅(`tools/hooks/`)

## 실행

```bash
flutter pub get
flutter run -d chrome
```

## 검증

```bash
flutter analyze
flutter test
pytest -q
deno test --allow-read --allow-env supabase/functions/_tests
```

## Icon System

- `assets/icons/soolgyeol/` contains the icons the app uses, in Regular and Strong weights.
- `AppIconAsset` is the typed catalog and `AppIcon` is the shared renderer.
- Small controls resolve to Strong by default. Large editorial/category artwork resolves to Regular, while interactive components can explicitly request Strong.
