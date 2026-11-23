/** An aroma as a reason: where it comes from, how it sat in the glass and what that did. */
import type { Cause } from "../evidence/evidence.ts";
import { aromaEffect } from "../facts/aroma_effects.ts";
import type { Section } from "../selection/selection.ts";
import { effectProse } from "./prose_effects.ts";
import { short } from "./words.ts";
import { giver, PLACES, what, word } from "./reason_causes.ts";
import { type Card, type Told } from "./reason_told.ts";

/**
 * Where an aroma comes from, before 향이에요, as the dictionary's row says it
 * comes: of the fruit (**말벡** 포도에서 오는), with age (**피노 누아** 와인이
 * 숙성되면서 생기는), from the cask (**셰리 캐스크**에서 밴). Never 특유의:
 * of the Burgundy reds the catalog holds, one in six carries the earth the
 * row lists, so the name is said as where it comes from and not as what every
 * bottle of it has (the user's review, 2026-11-23). Nothing when the name
 * says it (쌀에서 나는 쌀 향 says 쌀 twice: the user's review, 2026-11-21),
 * or when the row does not say where.
 */
export function aromaFrom(c: Cause, aroma: string, card: Card): string {
  if (short(aroma).includes(c.ko) || c.ko.includes(short(aroma))) return "";
  const from = aromaSource(c, card);
  // 오크통에서 밴 오크 향, 누룩에서 오는 누룩·코지 향 say the thing twice.
  return short(aroma).split("·").some((part) => from.includes(part))
    ? ""
    : from;
}

export function aromaSource(c: Cause, card: Card): string {
  if (c.factor === "cask") return `${word(c)}에서 밴`;
  if (["ingredient", "making", "label_word", "age"].includes(c.factor)) {
    return `${giver(c)}에서 오는`;
  }
  const place = c.factor === "region_style" && PLACES.has(c.ko);
  // The drink of the name: **부르고뉴** 레드 와인, **피노 누아** 와인, **준마이**.
  const drink = c.factor === "grape"
    ? `${word(c)} 와인`
    : place
    ? `${word(c)} ${card.kind}`
    : c.factor === "producer"
    ? `${what(c)}의 ${card.kind}`
    : word(c);
  switch (c.aroma_source) {
    case "material":
    case "ripeness":
      return c.factor === "grape"
        ? `${word(c)} 포도에서 오는`
        : c.factor === "producer"
        ? `${what(c)}{이} 쓰는 원료에서 오는`
        : `${what(c)}의 ${card.wine ? "포도" : "원료"}에서 오는`;
    case "nuruk":
      return `${drink}의 누룩에서 오는`;
    case "ageing":
      return `${drink}{이} 숙성되면서 생기는`;
    case "cask":
      return c.factor === "producer"
        ? `${what(c)}{이} 쓰는 오크통에서 밴`
        : `${drink}{을} 숙성하는 오크통에서 밴`;
    case "yeast":
      return `${drink}{이} 발효하면서 생기는`;
    case "process":
      return `${drink}{을} 만드는 과정에서 생기는`;
    case "soil":
      return `${what(c)}의 토양에서 온다고 알려진`;
    case "surroundings":
      return `${what(c)}의 주변 환경에서 오는`;
    default:
      return "";
  }
}

export const EFFECT: Readonly<Record<Section, ReturnType<typeof effectProse>>> =
  {
    liked: effectProse("liked"),
    burden: effectProse("burden"),
  };

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
    liked: ["새콤달콤하게 퍼지면서", "술이 한결 경쾌하게 느껴져요"],
    burden: ["강하게 앞서면서", "술이 시고 날카롭게 다가와요"],
  },
  effect_fresh_fruit: {
    liked: ["가볍고 상쾌하게 퍼지면서", "술이 한결 산뜻하게 느껴져요"],
    burden: ["가볍게만 스치면서", "전체적인 인상이 다소 허전하게 느껴져요"],
  },
  effect_floral: {
    liked: ["은은하게 피어오르면서", "술이 한결 화사하고 섬세하게 느껴져요"],
    burden: ["끝까지 강하게 남아", "맛과 어우러지지 않고 겉돌아요"],
  },
  effect_smoke: {
    liked: ["첫 향부터 깊게 깔리면서", "술의 중심을 잘 잡아 줘요"],
    burden: ["너무 강하게 앞서면서", "다른 향과 맛을 가려 버려요"],
  },
  effect_sweet_scent: {
    liked: ["달큰하게 감돌면서", "술을 한결 부드럽게 감싸 줘요"],
    burden: ["지나치게 진하게 올라와", "마실수록 금방 물리게 돼요"],
  },
  effect_grain_nut: {
    liked: ["구수하게 깔리면서", "술이 편안하고 든든하게 느껴져요"],
    burden: ["지나치게 앞서면서", "술이 무겁고 텁텁하게 느껴져요"],
  },
  effect_roast: {
    liked: ["쌉쌀하고 고소하게 깔리면서", "술이 진하고 묵직하게 느껴져요"],
    burden: ["강하게 앞서면서", "탄 듯한 쓴맛만 도드라져요"],
  },
  effect_wood: {
    liked: ["은은하게 올라와 머물면서", "술이 차분하고 안정감 있게 느껴져요"],
    burden: ["지나치게 강하게 남아", "입안이 답답하고 텁텁하게 느껴져요"],
  },
  effect_green: {
    liked: ["상쾌하게 퍼지면서", "술이 깔끔하고 또렷하게 느껴져요"],
    burden: ["거칠게 앞서면서", "풋내가 강해 거슬려요"],
  },
  effect_vegetal: {
    liked: ["풋풋하게 스치면서", "술이 담백하고 깔끔하게 느껴져요"],
    burden: ["강하게 앞서면서", "거친 풋내로 거슬려요"],
  },
  effect_spice: {
    liked: ["알싸하게 퍼지면서", "술에 기분 좋은 온기와 생기를 더해 줘요"],
    burden: ["강하게 앞서면서", "맵고 거친 자극만 남아요"],
  },
  effect_mineral: {
    liked: ["서늘하고 깔끔하게 남으면서", "술이 단단하고 정돈된 느낌을 줘요"],
    burden: ["강하게 앞서면서", "입안이 차갑고 딱딱하게 느껴져요"],
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
    liked: [
      "살짝 시큼하고 구수하게 올라오면서",
      "술이 생생하고 풍성하게 느껴져요",
    ],
    burden: ["강하게 앞서면서", "시큼하고 쿰쿰하게 거슬려요"],
  },
  effect_savory: {
    liked: ["감칠맛 나게 깔리면서", "술이 든든하고 깊게 느껴져요"],
    burden: ["지나치게 앞서면서", "무겁고 짭짤하게 느껴져요"],
  },
  effect_aged: {
    liked: ["차분하고 낮게 깔리면서", "술에 그윽한 깊이를 더해 줘요"],
    burden: ["강하게 앞서면서", "술이 퀴퀴하고 무겁게 느껴져요"],
  },
};

/** What an aroma does in the nose and mouth, liked or minded (writing/prose_effects.ts). */
export function aromaProse(
  key: string,
  section: Section,
): { name: string; body: string } {
  const row = aromaEffect(key);
  const said = row ? AROMA_SAID[row]?.[section] : undefined;
  if (row && said) {
    return {
      name: EFFECT[section][row].name,
      body: `{aroma}{이} ${said[0]}, ${said[1]}.`,
    };
  }
  if (row) return EFFECT[section][row];
  return section === "liked"
    ? {
      name: "{aroma}",
      body:
        "{aroma}{이} 기분 좋게 올라오면서, 첫인상부터 술을 풍성하게 느끼게 해 줘요.",
    }
    : {
      name: "{aroma}",
      body: "{aroma}{이} 강하게 앞서면서, 다른 향과 맛을 가려 거슬려요.",
    };
}

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

/** An aroma: where it comes from, how it sat in the glass and what that did. */
export function tellAroma(
  key: string,
  cause: Cause | null,
  section: Section,
  card: Card,
): Told {
  const prose = aromaProse(key, section);
  const aroma = `**${short(key)} 향**`;
  // 이 레드 와인은 레드 와인 특유의 … says the kind twice.
  const from = cause && cause.ko !== card.kind
    ? aromaFrom(cause, key, card)
    : "";
  // How it sat in the glass, and what that did.
  const said = prose.body.match(/^\{aroma\}\{이\} (.+?), (.+)\.$/);
  const base = {
    name: prose.name.replaceAll("{aroma}", `${short(key)} 향`),
    brief: `${short(key)} 향`,
    whole: true,
    causes: [],
    marks: [],
    lack: false,
    of: { aroma: aromaEffect(key) ?? undefined, side: "high" },
  };
  if (!said) {
    return {
      ...base,
      body: prose.body.replaceAll("{aroma}", aroma).replace(/\.$/, ""),
    };
  }
  return {
    ...base,
    body: "",
    point: cause && from
      // 자두 향은 말벡 포도에서 오는 향이에요. 새콤달콤하게 퍼지면서 술이 …
      ? {
        cause,
        open: { taste: aroma, from: `${from} 향이에요` },
        why: said[1],
        act: said[2],
        glue: " ",
      }
      : {
        cause: null,
        open: null,
        why: `${aroma}{이} ${said[1]}`,
        act: said[2],
      },
  };
}
