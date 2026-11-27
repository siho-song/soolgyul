/** An aroma as a reason: where it comes from, how it sat in the glass and what that did. */
import type { Cause } from "../evidence/evidence.ts";
import { aromaEffect } from "../../record_reading/facts/aroma_effects.ts";
import type { Section } from "../selection/selection.ts";
import { short } from "./words.ts";
import { giver, namedByPlace, placed, what, word } from "./reason_causes.ts";
import { grapeByKey } from "../../record_reading/dictionary/dictionary.ts";
import { type Card, type Told } from "./reason_told.ts";
import { aromaLabel } from "./reason_words.ts";

/**
 * Where an aroma comes from, before 향이에요, as the dictionary's row says it
 * comes: in the row's own words where it has them (빵 발효에 쓰는 효모와 함께
 * 병에서 오래 숙성돼 구수해진), else by the origin it lists the aroma under
 * (**말벡** 품종에서 자주 나타나는, **피노 누아** 와인이 오래 숙성되며 깊어져
 * 생기는). The wording is the user's (res/code_artifact.md, 2026-11-26): a
 * sentence must show why the aroma follows to one who has never studied
 * drinks. The row's own words are said even when they name the aroma again
 * (피트 향은 피트를 태운 연기로 말린 보리를 써서 생기는), for they explain
 * it; a short form that only says the thing twice (오크통에서 우러난 오크 향,
 * 쌀에서 나는 쌀 향: the user's review, 2026-11-21) is not said.
 */
export function aromaFrom(c: Cause, aroma: string, card: Card): string {
  // The row lists the aroma and tells nothing of it: 귀부's sweetness does
  // not explain a 시트러스 (the returned review, res/2 (1).md, 2026-11-27).
  if (c.aroma_how === "") return "";
  if (c.aroma_how) return aromaSource(c, card);
  if (short(aroma).includes(c.ko) || c.ko.includes(short(aroma))) return "";
  // 위스키의 주원료인 곡물에서 우러나는 곡물 향 and 곰팡이와 효모가 함께
  // 발효하며 만들어 내는 발효 향 tell what the drink is made of and how: the
  // user's own sentences, kept.
  const twice = (from: string) =>
    !TELLS.some((end) => from.endsWith(end)) &&
    short(aroma).split("·").some((part) => from.includes(part));
  const from = aromaSource(c, card);
  if (!twice(from)) return from;
  // 나무 향은 … 나무 내음이 만든 향 says the wood twice: the short words.
  const shortly = aromaSource(c, card, true);
  return twice(shortly) ? "" : shortly;
}

const GRAIN = "주원료인 곡물에서 우러나는";
const NURUK =
  "빚을 때 곡물에 띄운 곰팡이와 효모가 함께 발효하며 만들어 내는 구수하고 시큼한";
const TELLS = [GRAIN, NURUK];

/** A cask, a way of making, an ingredient, a label word: the cause is the thing itself. */
const THINGS = ["cask", "ingredient", "making", "label_word", "age"];

/**
 * A grape in the climate its row names the aroma in (the returned review,
 * res/3_1_109 (1).md, 2026-11-27): what the climate does to the grape.
 */
const GROWN: Readonly<
  Record<"cool" | "warm" | "hot", (grape: string) => string>
> = {
  cool: (grape) =>
    `서늘한 곳에서 천천히 익으며 풋풋하고 상큼한 기운을 간직한 ${grape} 품종에서 오는`,
  warm: (grape) =>
    `따뜻한 햇볕을 듬뿍 받고 푹 익으며 달큰하고 진한 기운이 오른 ${grape} 품종에서 오는`,
  hot: (grape) =>
    `더운 햇살 아래 당분이 꽉 차고 농익은 ${grape} 품종을 발효할 때 짙게 피어나는`,
};

/**
 * Whether a grape's row says its own aroma is faint (샤르도네, 트레비아노):
 * such a grape is not said to be rich in aroma.
 */
const faintGrape = (key: string): boolean =>
  grapeByKey(key)?.taste?.aroma_intensity?.level === "low";

/** Casks that held a wine before the whisky. */
const HELD_WINE = ["셰리 캐스크", "포트 캐스크", "와인 캐스크"];
const MIZUNARA = "미즈나라 오크";
const NEW_OAK = "새 오크통";

/**
 * The casks a house mostly ages in, with what is true of the cask itself:
 * a sherry or port cask held a rich wine, a mizunara cask is of Japanese
 * oak. Of any other cask only that the house uses it.
 */
function houseCasks(c: Cause, names: readonly string[], shortly: boolean) {
  const casks = names.map((name) => `**${name}**`).join("{과} ");
  const house = what(c);
  if (shortly) return `${house}{이} 숙성에 주로 쓰는 ${casks}에서 우러난`;
  // A new cask is charred or toasted inside before it is filled.
  if (names.length === 1 && names[0] === NEW_OAK) {
    return `${house}에서 안쪽을 불에 구운 새 오크통에 숙성하며 나무 결에서 배어 나온`;
  }
  if (names.length === 1 && names[0] === MIZUNARA) {
    return `${house}{이} 숙성에 주로 쓰는 일본산 물참나무 통(${casks})에서 우러난 그윽한`;
  }
  if (
    names.length === 1 && names[0] !== "와인 캐스크" &&
    HELD_WINE.includes(names[0])
  ) {
    return `${house}{이} 숙성에 쓰는 진한 와인을 담았던 ${casks}에서 깊게 배어 나온`;
  }
  if (names.length > 1 && names.every((name) => HELD_WINE.includes(name))) {
    return `${house}{이} 숙성에 쓰는 진한 와인을 담았던 ${casks}의 나무 결에서 배어 나온`;
  }
  return `${house}{이} 숙성에 주로 쓰는 ${casks}에서 우러난`;
}

/** The drink of the name: **부르고뉴** 레드 와인, **피노 누아** 와인, **준마이**. */
const drinkOf = (c: Cause, card: Card): string =>
  c.factor === "grape"
    ? `${word(c)} 와인`
    : namedByPlace(c)
    ? `${word(c)} ${card.kind}`
    : c.factor === "producer"
    ? `${what(c)}의 ${card.kind}`
    : word(c);

/**
 * Where the aroma comes from with what the dictionary says more of it: how,
 * in the row's own words (**샤르도네** 와인이 유산균 발효를 거치면서 우유나
 * 버터처럼 고소해진); the casks a house mostly ages in; the climate the
 * grape's row names the aroma in (서늘한 곳에서 자란 **샤르도네** 품종에서
 * 자주 나타나는). Only what leads to the aroma: no rock, hill or person.
 * `shortly` gives the short words of a cask (오크통에서 우러난) for an aroma
 * the long ones would name twice.
 */
export function aromaSource(c: Cause, card: Card, shortly = false): string {
  if (THINGS.includes(c.factor)) {
    return c.aroma_how ?? plainSource(c, card, shortly);
  }
  // The row's own words before the casks of the house: they say more.
  if (c.aroma_how) return named(c.aroma_how, drinkOf(c, card), what(c));
  if (c.aroma_casks?.length) return houseCasks(c, c.aroma_casks, shortly);
  if (c.factor === "grape" && c.aroma_climate) {
    return GROWN[c.aroma_climate](word(c));
  }
  return plainSource(c, card, shortly);
}

/**
 * The row's words after the drink's name (**샤르도네** 와인이 유산균 발효를
 * …), or around it where they say where it stands: … 포도로 빚은 {술}의,
 * {술}에 버번 통의 … 내음이 함께 밴; {곳} is the place or the house itself
 * (**포 로지스** 증류소에서 …). Words with a subject of their own read as two
 * subjects after 와인이.
 */
const named = (how: string, drink: string, house: string): string =>
  how.includes("{술}") || how.includes("{곳}")
    ? how.replace("{술}", drink).replace("{곳}", house)
    : `${drink}{이} ${how}`;

/** Where the aroma comes from by the origin the row lists it under alone. */
function plainSource(c: Cause, card: Card, shortly: boolean): string {
  if (c.factor === "cask") return `${word(c)}에서 숙성하는 동안 우러난`;
  // 꿀 향은 '무알뢰'에서 오는 read the quotes as part of the cause.
  if (c.factor === "label_word") return `${word(c)}에서 오는`;
  if (THINGS.includes(c.factor)) return `${giver(c)}에서 오는`;
  const drink = drinkOf(c, card);
  const landless = c.factor === "grape" || c.factor === "kind";
  switch (c.aroma_source) {
    case "material":
    case "ripeness":
      return c.factor === "grape"
        // The grape's own aromas, kept in its skin and flesh and set free as
        // it ferments (res/3_1_109 (1).md); not said of a grape whose row
        // says it has little aroma of its own.
        ? faintGrape(c.key)
          ? `${word(c)} 품종에서 자주 나타나는`
          : `껍질과 과육에 향긋한 기운이 풍부한 ${
            word(c)
          } 품종을 발효할 때 피어나는`
        : c.factor === "producer"
        // 위스키 증류소의 양조 과정 is not said: a spirit is distilled.
        ? `${what(c)}의 원료와 ${
          card.wine || card.brewed ? "양조" : "발효·증류"
        } 과정에서 비롯된`
        : card.wine
        // A style with a place of its own that is not named as the place
        // (샴페인, 토카이 아수): what its grapes ripened in.
        ? placed(c) && what(c) === word(c)
          ? `${what(c)}의 기후와 흙을 머금고 익은 포도를 발효할 때 피어나는`
          : `${what(c)}의 포도에서 자주 나타나는`
        // 위스키의 주원료인 곡물. Of a brewed drink only 주원료에서 우러나는
        // could be said, which names nothing (the returned review,
        // 2026-11-27): nothing is said.
        : card.brewed
        ? ""
        : `${what(c)}의 ${GRAIN}`;
    case "nuruk":
      return `${drink}{을} ${NURUK}`;
    case "ageing":
      // A whisky ages in oak, whatever else is true of its house.
      return c.factor === "producer" && !card.wine && !card.brewed
        ? `${drink}{이} 오크통에서 오래 숙성되며 농축된 당분과 과일 기운이 어우러진`
        : `${drink}{이} 오래 숙성되며 깊어져 생기는`;
    case "cask":
      if (c.factor === "producer") {
        // Every cask is toasted or charred inside; a house the dictionary
        // names as a distillery keeps the short words.
        return shortly || what(c) !== word(c)
          ? `${what(c)}{이} 숙성에 쓰는 오크통에서 우러난`
          : `${
            what(c)
          }{이} 숙성에 쓰는 불에 구운 오크통에서 나무 당분이 녹아나와 배어든`;
      }
      if (shortly) return `${drink}{을} 숙성하는 오크통에서 우러난`;
      return c.factor === "grape"
        ? `${drink}{을} 안쪽이 구워진 오크통에서 오래 숙성하며 그을린 나무 내음이 배어든`
        : `${drink}{을} 안쪽이 구워진 오크통에 숙성하며 배어든 달큰하고 고소한 나무 내음이 만든`;
    case "yeast":
      return `${drink}{이} 발효할 때 자연스럽게 생기는`;
    // ○○를 빚는 과정에서 생기는 names no step of the making (the returned
    // review, 2026-11-27): nothing is said where the row has no words.
    case "process":
      return "";
    // A grape or a kind of drink has no ground of its own (리슬링 품종의
    // 토양, 셰리 와인의 주변 환경): nothing is said of where it comes from.
    case "soil":
      return landless ? "" : `${what(c)}의 토양 특성에서 비롯된`;
    case "surroundings":
      return landless
        ? ""
        : `${what(c)}의 기후와 주변 환경의 영향으로 나타나는`;
    default:
      return "";
  }
}

/**
 * How an aroma sat in this glass and what that did, liked or minded
 * (달큰하게 감돌아, 술을 한결 부드럽게 감싸 줘요). What kind of smell it is
 * in general (단맛과 늘 함께 오던 냄새라서) is not said: the user's review,
 * 2026-11-21, read it as a remark beside the point.
 */
export const AROMA_SAID: Readonly<
  Record<string, Readonly<Record<Section, readonly [string, string]>>>
> = {
  effect_ripe_fruit: {
    liked: ["달큰하게 피어오르면서", "술이 한결 포근하게 느껴져요"],
    burden: ["지나치게 앞서 나오면서", "마실수록 금방 물리게 돼요"],
  },
  effect_sour_fruit: {
    liked: ["새콤달콤하게 퍼지면서", "술에 생기를 더해 줘요"],
    burden: ["지나치게 풋풋하고 새콤하게 앞서면서", "다른 향을 가려 버려요"],
  },
  effect_fresh_fruit: {
    liked: ["싱그럽게 퍼지면서", "술이 한결 산뜻하게 느껴져요"],
    burden: ["가볍게만 스치면서", "전체적인 인상이 다소 허전하게 느껴져요"],
  },
  effect_floral: {
    liked: ["기분 좋게 피어오르면서", "술이 한결 우아하고 섬세하게 느껴져요"],
    burden: ["끝까지 강하게 남아", "맛과 어우러지지 않고 겉돌아요"],
  },
  effect_smoke: {
    liked: ["첫 향부터 깊게 깔리면서", "술의 중심을 잘 잡아 줘요"],
    burden: ["너무 강하게 앞서면서", "다른 향과 맛을 가려 버려요"],
  },
  effect_sweet_scent: {
    liked: ["포근하게 감돌면서", "술을 한결 부드럽게 만들어 줘요"],
    burden: ["너무 강하게 올라와", "마실수록 금방 물리게 돼요"],
  },
  effect_grain_nut: {
    liked: ["따뜻하고 차분하게 깔리면서", "술이 편안하고 든든하게 느껴져요"],
    burden: ["지나치게 앞서면서", "술이 무겁고 텁텁하게 느껴져요"],
  },
  effect_roast: {
    liked: ["쌉쌀하고 그윽하게 깔리면서", "술에 깊은 여운을 더해 줘요"],
    burden: ["강하게 앞서면서", "탄 듯한 쓴맛만 도드라져요"],
  },
  effect_wood: {
    liked: ["은은하게 감돌면서", "술이 차분하고 안정감 있게 느껴져요"],
    burden: ["지나치게 강하게 남아", "다른 향을 가려 버려요"],
  },
  effect_green: {
    liked: ["상쾌하게 퍼지면서", "술이 깔끔하고 또렷하게 느껴져요"],
    burden: ["거칠게 앞서면서", "풋내가 강해 거슬려요"],
  },
  effect_vegetal: {
    liked: ["풋풋하게 스치면서", "술이 담백하고 깔끔하게 느껴져요"],
    burden: ["강하게 앞서면서", "거친 풋내가 거슬려요"],
  },
  effect_spice: {
    liked: ["은은하게 퍼지면서", "술에 기분 좋은 온기와 생기를 더해 줘요"],
    burden: ["지나치게 강하게 앞서면서", "다른 향을 가려 버려요"],
  },
  effect_mineral: {
    liked: [
      "서늘하고 깔끔하게 남으면서",
      "술맛이 군더더기 없이 정돈된 느낌을 줘요",
    ],
    burden: ["지나치게 강하게 올라와", "쇳내나 돌 내음처럼 거슬리게 느껴져요"],
  },
  effect_earth: {
    liked: ["차분하게 깔리면서", "술에 그윽한 깊이를 더해 줘요"],
    burden: ["강하게 앞서면서", "술이 눅눅하고 퀴퀴하게 느껴져요"],
  },
  effect_dairy: {
    liked: ["매끄럽게 감돌면서", "술이 날카롭지 않고 부드럽게 느껴져요"],
    burden: ["진하게 남으면서", "술이 무겁고 느끼하게 느껴져요"],
  },
  effect_ferment: {
    liked: ["깊고 그윽하게 올라오면서", "술이 한층 생생하고 풍성하게 느껴져요"],
    burden: ["지나치게 강하게 올라와", "시큼하고 쿰쿰한 냄새로 거슬려요"],
  },
  effect_savory: {
    liked: ["진하고 구수하게 깔리면서", "술이 든든하고 깊게 느껴져요"],
    burden: ["지나치게 앞서면서", "무겁고 짭짤하게 느껴져요"],
  },
  effect_aged: {
    liked: ["차분하고 낮게 깔리면서", "술에 묵직한 여운을 더해 줘요"],
    burden: ["강하게 앞서면서", "술이 퀴퀴하고 무겁게 느껴져요"],
  },
};

/**
 * The aromas a minded answer is told of as too faint (가볍게만 스치면서 …
 * 허전하게 느껴져요), where every other is told of as too much. The tags, the
 * one line under them and 다음 방향 read it here, so that a card does not
 * call faint in one place what it calls a burden, or offers less of, in
 * another.
 */
const FAINT_WHEN_MINDED: ReadonlySet<string> = new Set(["effect_fresh_fruit"]);

export const mindedAsFaint = (aroma: string): boolean =>
  FAINT_WHEN_MINDED.has(aromaEffect(aroma) ?? "");

/** An aroma of no group: how it sat in the glass and what that did. */
const UNGROUPED: Readonly<Record<Section, readonly [string, string]>> = {
  liked: ["기분 좋게 올라오면서", "첫인상부터 술을 풍성하게 느끼게 해 줘요"],
  burden: ["강하게 앞서면서", "다른 향과 맛을 가려 거슬려요"],
};

/** How an aroma sat in the glass and what that did, liked or minded. */
export const aromaSaid = (
  key: string,
  section: Section,
): readonly [string, string] =>
  AROMA_SAID[aromaEffect(key) ?? ""]?.[section] ?? UNGROUPED[section];

/**
 * The cause an aroma is told by. A place that carries it gives way to the
 * bottle's grape when the grape carries it too: the earth of a Burgundy is
 * as common in a Pinot Noir from elsewhere, so it is the grape's.
 */
export const aromaCause = (
  told: Cause | null,
  causes: readonly Cause[],
): Cause | null =>
  told?.factor === "region_style"
    ? causes.find((c) => c.factor === "grape") ?? told
    : told;

/**
 * How an aroma sat and what that did, after where it comes from. A fruit
 * told of as fresh does not follow a reason of thickened sweetness (단맛과
 * 향이 짙어진 …. 가볍고 상쾌하게 read as two drinks), and a minded wood
 * names what stayed (the returned review, 2026-11-27).
 */
function saidAfter(
  key: string,
  section: Section,
  from: string,
): readonly [string, string] {
  const [how, did] = aromaSaid(key, section);
  if (!from) return [how, did];
  const effect = aromaEffect(key);
  if (
    effect === "effect_fresh_fruit" && section === "liked" && /단맛/.test(from)
  ) {
    return ["화사하게 퍼지면서", "술이 한결 생동감 있게 느껴져요"];
  }
  return effect === "effect_wood" && section === "burden"
    ? [`나무 내음이 ${how}`, did]
    : [how, did];
}

/** An aroma: where it comes from, how it sat in the glass and what that did. */
export function tellAroma(
  key: string,
  cause: Cause | null,
  section: Section,
  card: Card,
): Told {
  const aroma = `**${short(key)} 향**`;
  // 이 레드 와인은 레드 와인 특유의 … says the kind twice.
  const from = cause && cause.ko !== card.kind
    ? aromaFrom(cause, key, card)
    : "";
  const [how, did] = saidAfter(key, section, from);
  const base = {
    name: aromaLabel(key),
    brief: `${short(key)} 향`,
    whole: true,
    causes: [],
    marks: [],
    lack: false,
    of: { aroma: aromaEffect(key) ?? undefined, side: "high" },
  };
  return {
    ...base,
    body: "",
    point: cause && from
      // 자두 향은 말벡 포도에서 오는 향이에요. 새콤달콤하게 퍼지면서 술이 …
      ? {
        cause,
        open: { taste: aroma, from: `${from} 향이에요` },
        why: how,
        act: did,
        glue: " ",
      }
      : {
        cause: null,
        open: null,
        why: `${aroma}{이} ${how}`,
        act: did,
      },
  };
}
