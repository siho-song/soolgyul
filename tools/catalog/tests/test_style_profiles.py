from tools.catalog.sensory.style_profiles import (
    StyleProfileResolver,
    explicit_dimensions,
    load_style_profiles,
    product_levels,
    sensory_descriptor_keys,
    taxonomy_process_keys,
    taxonomy_style_keys,
    validate_style_profiles,
)

TABLE = {
    "styles": [
        {
            "key": "red_wine", "name_ko": "레드 와인", "intro_ko": "껍질째 발효해요",
            "traits": {
                "astringency": {"level": "mid", "basis": "production", "reason_ko": "껍질"},
                "carbonation": {"level": "none", "basis": "production", "reason_ko": "비발포"},
            },
            "aromas": [{"key": "cherry", "basis": "typical", "reason_ko": "대표 향"}],
        },
        {"key": "ipa", "name_ko": "IPA", "intro_ko": "홉이 많아요", "traits": {
            "bitterness": {"level": "high", "basis": "production", "reason_ko": "홉"}}},
    ],
    "wine_grapes": [
        {"key": "cabernet_sauvignon", "name_ko": "까베르네 소비뇽", "intro_ko": "x",
         "colors": ["red"], "match": {"patterns": ["cabernet sauvignon", "까베르네 소비뇽"]},
         "traits": {"astringency": {"level": "high", "basis": "production", "reason_ko": "두꺼운 껍질"}},
         "aromas": [{"key": "blackcurrant", "basis": "typical", "reason_ko": "품종 향"}]},
        {"key": "gamay", "name_ko": "가메", "intro_ko": "x", "colors": ["red"],
         "match": {"patterns": ["gamay", "가메"]},
         "traits": {"astringency": {"level": "low", "basis": "production", "reason_ko": "얇은 껍질"}}},
    ],
    "wine_regions": [
        {"key": "douro_port_fortified", "name_ko": "포트", "intro_ko": "x", "color": "any",
         "match": {"region_labels": ["도루(Douro)"], "style_keys": ["fortified_wine", "port_wine"]},
         "traits": {"sweetness": {"level": "high", "basis": "production", "reason_ko": "주정 강화"}}},
        {"key": "burgundy_red", "name_ko": "부르고뉴", "intro_ko": "x", "color": "red",
         "match": {"region_labels": ["부르고뉴(Bourgogne)", "부르고뉴(Bourgogne) > 꼬뜨 샬로네즈(Côte Chalonnaise)"],
                   "name_patterns": []},
         "traits": {"body": {"level": "mid", "basis": "typical", "reason_ko": "피노 누아"}}},
        {"key": "beaujolais_red", "name_ko": "보졸레", "intro_ko": "x", "color": "red",
         "match": {"region_labels": ["부르고뉴(Bourgogne) > 보졸레(Beaujolais)"], "name_patterns": ["beaujolais", "보졸레"]},
         "traits": {"body": {"level": "low", "basis": "production", "reason_ko": "가메"}}},
    ],
}


def test_grape_overrides_style_and_region_adds():
    resolver = StyleProfileResolver(TABLE)
    result = resolver.resolve("red_wine", "Some Cabernet Sauvignon 2020", "")
    assert result["traits"]["astringency"]["level"] == "high"
    assert result["traits"]["astringency"]["source_key"] == "cabernet_sauvignon"
    assert result["traits"]["carbonation"]["level"] == "none"
    assert [a["key"] for a in result["aromas"]] == ["blackcurrant", "cherry"]

    result = resolver.resolve("red_wine", "도멘 X 보졸레 빌라주", "부르고뉴(Bourgogne) > 보졸레(Beaujolais) > 빌라주")
    assert result["traits"]["body"]["source_key"] == "beaujolais_red"


def test_deeper_region_match_wins_over_broad_entry_with_long_labels():
    resolver = StyleProfileResolver(TABLE)
    by_label = resolver.resolve("red_wine", "도멘 X", "부르고뉴(Bourgogne) > 보졸레(Beaujolais)")
    assert by_label["traits"]["body"]["source_key"] == "beaujolais_red"
    by_name = resolver.resolve("red_wine", "Beaujolais Villages", "부르고뉴(Bourgogne)")
    assert by_name["traits"]["body"]["source_key"] == "beaujolais_red"


def test_region_entry_with_style_keys_skips_other_styles():
    resolver = StyleProfileResolver(TABLE)
    assert "sweetness" in resolver.resolve("fortified_wine", "포트", "도루(Douro)")["traits"]
    assert "sweetness" not in resolver.resolve("red_wine", "도루 레드", "도루(Douro)")["traits"]


def test_disagreeing_grapes_cancel_the_dimension():
    resolver = StyleProfileResolver(TABLE)
    result = resolver.resolve("red_wine", "까베르네 소비뇽 가메 블렌드", "")
    assert "astringency" not in result["traits"]


def test_non_wine_styles_skip_grape_matching():
    resolver = StyleProfileResolver(TABLE)
    result = resolver.resolve("ipa", "cabernet sauvignon ipa", "")
    assert result["entries"] == [("style", "ipa")]


def test_validation_reports_problems():
    broken = {
        "styles": [{"key": "ipa", "name_ko": "IPA", "intro_ko": "x",
                    "traits": {"bitterness": {"level": "huge", "basis": "production", "reason_ko": "홉"}}}],
        "wine_grapes": [], "wine_regions": [],
    }
    errors = validate_style_profiles(broken, {"ipa", "lager"}, {"cherry"}, set())
    assert any("bad level" in e for e in errors)
    assert any("lager has no entry" in e for e in errors)


def test_committed_table_is_valid():
    table = load_style_profiles()
    assert validate_style_profiles(
        table, taxonomy_style_keys(), sensory_descriptor_keys(), taxonomy_process_keys()
    ) == []


def test_producer_and_stated_process_override_broader_layers():
    table = {
        **TABLE,
        "producers": [{"key": "laphroaig", "kind": "distillery", "name_ko": "라프로익", "intro_ko": "x",
                       "traits": {"astringency": {"level": "low", "basis": "typical", "reason_ko": "x"}},
                       "aromas": [{"key": "seaweed", "basis": "typical", "reason_ko": "x"}]}],
        "processes": [{"key": "ex_sherry_cask", "name_ko": "셰리 캐스크", "intro_ko": "x",
                       "traits": {"astringency": {"level": "mid", "basis": "typical", "reason_ko": "x"}},
                       "aromas": [{"key": "dried_fruit", "basis": "production", "reason_ko": "x"}]}],
    }
    resolver = StyleProfileResolver(table)
    result = resolver.resolve("red_wine", "Cabernet Sauvignon", "", "laphroaig")
    assert result["traits"]["astringency"]["source_key"] == "laphroaig"
    result = resolver.resolve("red_wine", "Cabernet Sauvignon", "", "laphroaig", ["ex_sherry_cask"])
    assert result["traits"]["astringency"]["source_key"] == "ex_sherry_cask"
    assert [a["key"] for a in result["aromas"]] == ["dried_fruit", "seaweed", "blackcurrant", "cherry"]


def test_house_peat_and_casks_apply_as_processes():
    table = {
        **TABLE,
        "producers": [{"key": "lagavulin", "kind": "distillery", "name_ko": "라가불린", "intro_ko": "x",
                       "peat": "heavy", "house_casks": [], "traits": {}, "aromas": []},
                      {"key": "glenkinchie", "kind": "distillery", "name_ko": "글렌킨치", "intro_ko": "x",
                       "peat": "light", "house_casks": [], "traits": {}, "aromas": []}],
        "processes": [{"key": "peated_malt", "name_ko": "피트", "intro_ko": "x", "traits": {},
                       "aromas": [{"key": "peat", "basis": "production", "reason_ko": "x"}]}],
    }
    resolver = StyleProfileResolver(table)
    assert [a["key"] for a in resolver.resolve("ipa", "", "", "lagavulin")["aromas"]] == ["peat"]
    assert resolver.resolve("ipa", "", "", "glenkinchie", ["peated_malt"])["entries"][-1] == ("process", "peated_malt")
    assert resolver.resolve("ipa", "", "", "glenkinchie")["aromas"] == []


def test_stated_grapes_replace_name_matching():
    resolver = StyleProfileResolver(TABLE)
    result = resolver.resolve("red_wine", "Cabernet Sauvignon", "", grape_keys=["gamay"])
    assert result["traits"]["astringency"]["source_key"] == "gamay"


def test_spirit_abv_sets_alcohol_presence():
    table = {**TABLE, "styles": [*TABLE["styles"], {"key": "distilled_soju", "name_ko": "증류식 소주", "intro_ko": "x",
             "traits": {"alcohol_presence": {"level": "mid", "basis": "typical", "reason_ko": "x"}}}]}
    resolver = StyleProfileResolver(table)
    assert resolver.resolve("distilled_soju", "x", "", abv_percent=58)["traits"]["alcohol_presence"]["level"] == "high"
    assert resolver.resolve("distilled_soju", "x", "", abv_percent=25)["traits"]["alcohol_presence"]["level"] == "mid"
    assert resolver.resolve("distilled_soju", "x", "", abv_percent=12)["traits"]["alcohol_presence"]["source_key"] == "distilled_soju"


def test_product_stated_levels_win_over_table():
    row = {"astringency": 2, "carbonation": 3, "body": 5,
           "level_sources": {"astringency": "note", "carbonation": "catalog", "body": "note_modifier"}}
    assert product_levels(row) == {"astringency": "low", "body": "high"}
    result = StyleProfileResolver(TABLE).resolve(
        "red_wine", "cabernet sauvignon", "", stated_levels=product_levels(row))
    # The cabernet's high tannin moves one step down, not straight to low.
    assert result["traits"]["astringency"]["level"] == "mid"
    assert result["traits"]["astringency"]["source_kind"] == "product"


def test_sparkling_name_adds_carbonation_only_to_still_styles():
    result = StyleProfileResolver(TABLE).resolve("red_wine", "스파클링 레드", "")
    assert result["traits"]["carbonation"]["level"] == "mid"


def test_grape_name_does_not_match_region_pattern():
    table = {**TABLE, "wine_grapes": [*TABLE["wine_grapes"], {
        "key": "melon_de_bourgogne", "name_ko": "믈롱", "intro_ko": "x", "colors": ["white"],
        "match": {"patterns": ["melon de bourgogne"]}}],
        "wine_regions": [*TABLE["wine_regions"], {
            "key": "burgundy_white", "name_ko": "부르고뉴", "intro_ko": "x", "color": "white",
            "match": {"region_labels": [], "name_patterns": ["bourgogne"]}}]}
    entries = StyleProfileResolver(table).resolve("white_wine", "domaine x melon de bourgogne", "")["entries"]
    assert ("region", "burgundy_white") not in entries


def test_specific_entry_replaces_broad_aroma():
    table = {**TABLE, "wine_grapes": [{**TABLE["wine_grapes"][1], "replaces_aromas": ["cherry"],
                                        "aromas": [{"key": "raspberry", "basis": "typical", "reason_ko": "x"}]}]}
    aromas = [a["key"] for a in StyleProfileResolver(table).resolve("red_wine", "gamay", "")["aromas"]]
    assert aromas == ["raspberry"]


def test_blend_aromas_come_from_main_grape_only():
    aromas = StyleProfileResolver(TABLE).resolve(
        "red_wine", "x", "", grape_keys=["gamay", "cabernet_sauvignon"])["aromas"]
    assert "blackcurrant" not in [a["key"] for a in aromas]


def test_region_name_pattern_skipped_when_region_is_elsewhere():
    table = {**TABLE, "wine_regions": [*TABLE["wine_regions"], {
        "key": "burgundy_white", "name_ko": "부르고뉴", "intro_ko": "x", "color": "white",
        "match": {"region_labels": ["부르고뉴(Bourgogne)"], "name_patterns": ["부르고뉴"]}}]}
    resolver = StyleProfileResolver(table)
    assert ("region", "burgundy_white") not in resolver.resolve("white_wine", "므롱 드 부르고뉴", "루아르(Loire)")["entries"]
    assert ("region", "burgundy_white") in resolver.resolve("white_wine", "부르고뉴 블랑", "")["entries"]


def test_notes_do_not_talk_down_style_bubbles():
    table = {**TABLE, "styles": [*TABLE["styles"], {"key": "sparkling_wine", "name_ko": "스파클링", "intro_ko": "x",
             "traits": {"carbonation": {"level": "high", "basis": "production", "reason_ko": "x"}}}]}
    result = StyleProfileResolver(table).resolve("sparkling_wine", "cava", "", stated_levels={"carbonation": "low"})
    assert result["traits"]["carbonation"]["level"] == "high"


def test_explicit_scale_levels_are_not_anchored_to_the_table():
    row = {"astringency": 1, "sweetness": 5, "body": 5,
           "level_sources": {"astringency": "wine21_scale", "sweetness": "wine21_scale",
                             "body": "wine21_note"}}
    assert explicit_dimensions(row) == {"astringency", "sweetness"}
    result = StyleProfileResolver(TABLE).resolve(
        "red_wine", "cabernet sauvignon", "", stated_levels=product_levels(row),
        explicit_dimensions=explicit_dimensions(row))
    # A retailer's 1/5 tannin scale is taken as it is; prose still moves one step.
    assert result["traits"]["astringency"]["level"] == "low"
    assert result["traits"]["sweetness"]["level"] == "high"
    assert result["traits"]["body"]["level"] == "high"
