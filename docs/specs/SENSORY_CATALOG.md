# 술결 감각 카탈로그

향, 맛·향미, 질감, 피니시를 나타내는 감각 사전의 정본과 변경 방법을 적는다.

## 1. 정본

- 향 계열과 감각어의 트리는 사전 `catalog/dictionary/terms.json` 한 곳에서만 정의한다. 계열, 감각어, 별칭, 상위 연결은 이 파일의 향·질감·여운 줄이 목록이다.
- 서비스에 쓰는 어휘와 맛 성향은 이 트리에서 `tools/catalog/sensory/style_profiles.py`가 만든다. 트리를 복사하거나 따로 고쳐 쓰지 않는다.
- 같은 감각어가 향, 맛·향미, 피니시에 모두 나올 수 있으므로 key와 관찰된 영역을 함께 보존한다.
- 주종별로 다른 분류표를 만들지 않는다. 같은 분류에서 상품의 실제 근거에 맞는 감각만 쓴다.
- 직접 근거가 없는 감각은 낮음이나 0이 아니라 `unknown`이다. 출처가 충돌하면 평균내지 않고 `conflict`로 둔다.

## 2. 레벨형 감각 지표

감각어는 무엇이 느껴지는지, 레벨 지표는 얼마나 강한지를 나타낸다. 서로 자동으로 바꾸지 않는다.
향 세기, 단맛, 산미, 쓴맛, 떫음, 바디, 탄산, 피니시 길이, 피니시 깔끔함은 각각 별개의 지표다.
지표의 key와 단계는 코드와 [질문지 명세](QUESTIONNAIRE.md)를 따른다.

## 3. 변경 절차

1. 수집 원문이나 검증된 근거를 확인한다.
2. 같은 뜻은 기존 별칭으로 합치고, 기존 key로 표현할 수 없는 독립 개념만 새 key로 만든다.
3. 사전 `catalog/dictionary/terms.json`을 고친다. 어휘 쪽 변경은 `style_profiles.py`와 그 입력 표에서 한다.
4. 아래 테스트를 실행한다.
5. 변경 이유와 diff를 Git에 남긴다.

```bash
python3 -m pytest -q tools/catalog/tests/test_dictionary_build.py tools/catalog/tests/test_sensory_hierarchy.py
```
