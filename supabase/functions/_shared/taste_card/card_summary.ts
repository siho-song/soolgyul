/**
 * 핵심 요약: the tags and the one line at the top of the card (the user's
 * wordings, 2026-11-03). The paragraphs below carry the reasons; the summary
 * only says, in the reader's own words, what was liked, what weighed, and
 * what was missing.
 *
 *   tags  흙향 (liked) · 떫은맛 (less) · 단맛 (more) — one per sensation the
 *         reader answered, liked first, then burdens, then lacks, at most
 *         three. A burden the reader called too strong, or that stayed in the
 *         finish, is "less"; one that did not fit is "burden". The app draws
 *         each kind as its icon.
 *   line  one sentence by shape: only liked, only burdens, or liked against
 *         what weighed (with or without a lack). Each sensation is dressed
 *         with a short phrase (입안을 꽉 조이는 떫은맛, 침샘을 자극하는 깔끔한
 *         산미); an aroma takes the adjective of its family (향긋한, 달콤한,
 *         고소한), never a reaction the reader did not give.
 *
 * Everything comes from the reader's answers (the reactions), so a sensation
 * the reader named is in the summary even when no paragraph explains it.
 */
import type { CardFacts, ReactionFact, Subject } from "./card_facts.ts";
import {
  emphasize,
  josa,
  subjectPhrases,
  type WriteOptions,
  type WrittenSection,
} from "./card_writing.ts";
import { serviceVocabulary } from "./dictionary.ts";
import type { TasteCardTag } from "./types.ts";

export type Summary = {
  shape: "호감만" | "부담만" | "엇갈림" | "밸런스";
  tags: readonly TasteCardTag[];
  line: string;
  /** The line's sentence with the dressing left off (체리 향과 산미는
   * 반갑지만, 떫은맛은 아직 조금 버거워요), for a record card's one line. */
  brief: string;
};

type Side = "liked" | "burden" | "lack";

/** One sensation as the summary names it; aromas gather into one item. */
type Item = {
  domain: Subject["domain"];
  key: string;
  /** Every aroma gathered into the item; one key otherwise. */
  keys: readonly string[];
  /** 흙 향, 떫은 맛, 긴 여운 */
  name: string;
  /** A burden the reader wanted less of (너무 셌어요, 끝에 오래 남았어요). */
  less?: boolean;
};

export function writeSummary(
  facts: CardFacts,
  _positive: WrittenSection,
  _burden: WrittenSection,
  options: WriteOptions = {},
): Summary | null {
  const name = options.productName ?? facts.record.product_name;
  const { liked, burdens, lacks } = sides(facts);
  if (!liked.length && !burdens.length && !lacks.length) return null;
  const tags = pickTags(
    liked.map((i) => tag(i, "liked")),
    burdens.map((i) => tag(i, "burden")),
    lacks.map((i) => tag(i, "lack")),
  );
  const seed = `${name}|${[...liked, ...burdens, ...lacks].map((i) => i.key)}`;
  const likedPhrase = listed(dressed(liked, "liked"));
  const burdenPhrase = listed(dressed(burdens, "burden"));
  // The sensations in bold: 체리 향, 산미, 떫은맛 (the noun of each phrase).
  const nouns = [
    ...liked.map((i) => noun(i, "liked")),
    ...burdens.map((i) => noun(i, "burden")),
    ...lacks.map(lackName),
  ];
  const line = (text: string) => emphasize(josa(text), nouns);
  const likedNames = liked.map((i) => briefName(i, "liked"));
  const burdenNames = listed(burdens.map((i) => briefName(i, "burden")));
  const lackNames = listed(lacks.map(lackName));

  if (!burdens.length && !lacks.length) {
    const words = dressed(liked, "liked");
    return {
      shape: "호감만",
      tags,
      brief: josa(
        likedNames.length === 1
          ? `${likedNames[0]}{이} 거슬리는 데 없이 마음에 쏙 들었어요.`
          : likedNames.length === 2
          ? `${likedNames[0]}부터 ${likedNames[1]}까지 입맛에 찰떡이었어요.`
          : `${likedNames[0]}{과} ${likedNames.slice(1, -1).join(", ")}, ${
            likedNames[likedNames.length - 1]
          }까지 빈틈없이 마음에 쏙 들었어요.`,
      ),
      line: line(
        words.length === 1
          ? `${words[0]}{이} 거슬리는 데 없이 마음에 쏙 들었어요.`
          : words.length === 2
          ? `${words[0]}부터 ${
            words[1]
          }까지, 처음부터 끝까지 내 입맛에 찰떡인 술이에요.`
          : `${words[0]}{과} ${words.slice(1, -1).join(", ")}, ${
            words[words.length - 1]
          }까지 빈틈없이 마음에 쏙 들었어요.`,
      ),
    };
  }

  if (!liked.length) {
    const softer = listed(burdens.map((i) => i.name));
    const more = listed(lacks.map(lackName));
    return {
      shape: "부담만",
      tags,
      brief: josa(
        burdens.length && lacks.length
          ? `${burdenNames}{이} 너무 강렬하고 ${lackNames}{은} 살짝 아쉬웠어요.`
          : burdens.length
          ? `${burdenNames}{이} 너무 강렬했어요.`
          : `${lackNames}{이} 살짝 아쉬웠어요.`,
      ),
      line: line(
        burdens.length && lacks.length
          ? `${burdenPhrase}{이} 너무 강렬했어요. 다음엔 ${softer}{은} 한 톤 부드럽고 ${more}{은} 조금 더 있는 술로 가볼까요?`
          : burdens.length
          ? `${burdenPhrase}{이} 너무 강렬했어요. 다음엔 ${
            nextSofter(burdens)
          } 술로 가볼까요?`
          : `${more}{이} 살짝 아쉬웠어요. 다음엔 ${more}{이} 조금 더 있는 술로 가볼까요?`,
      ),
    };
  }

  const wanted = lacks.map(lackWant).join(", ");
  const likedList = listed(likedNames);
  return {
    shape: "엇갈림",
    tags,
    brief: josa(
      burdens.length && lacks.length
        ? `${likedList}{은} 반갑지만, ${burdenNames}{은} 조금 버겁고 ${lackNames}{은} 아쉬웠어요.`
        : burdens.length
        ? `${likedList}{은} 반갑지만, ${burdenNames}{은} 아직 조금 버거워요.`
        : `${likedList}{은} 딱 좋은데, ${lackNames}{이} 조금 아쉬웠어요.`,
    ),
    line: line(
      burdens.length && lacks.length
        ? `${likedPhrase}{은} 반갑지만, ${burdenPhrase}{은} 조금 버겁고 ${wanted} 했어요.`
        : burdens.length
        ? pick(seed, CONTRAST_LINES)
          .replaceAll("{liked}", likedPhrase)
          .replaceAll("{burden}", burdenPhrase)
        : `${likedPhrase}{은} 딱 좋은데, ${wanted} 더 완벽했을 거예요.`,
    ),
  };
}

/* ------------------------------------------------------------- wordings */

/** Liked against a burden: the user's three sentences. */
const CONTRAST_LINES = [
  "{liked}{은} 반갑지만, {burden}{은} 아직 조금 버거워요.",
  "{liked}{은} 매력적이지만, {burden}{은} 조금 덜어내고 싶어요.",
  "{liked}{은} 설렜지만, {burden}{은} 조금 과하게 느껴졌어요.",
] as const;

/** The sensation itself inside its dressed phrase: 산미 of 침샘을 자극하는 깔끔한 산미. */
function noun(item: Item, side: "liked" | "burden"): string {
  if (item.domain === "aroma") return item.name;
  return (WORDS[side][item.key] ?? item.name).split(" ").pop()!;
}

/** The sensation as the brief names it: the bare noun, or the one word
 * that keeps it meaningful (매끄러운 질감, not 질감). */
function briefName(item: Item, side: "liked" | "burden"): string {
  if (item.domain === "aroma") return item.name;
  return BRIEF_WORDS[side][item.key] ?? noun(item, side);
}

const BRIEF_WORDS: Readonly<
  Record<"liked" | "burden", Record<string, string>>
> = {
  liked: {
    sweetness: "달콤함",
    light: "가벼운 질감",
    smooth: "매끄러운 질감",
    clean: "깔끔한 마무리",
  },
  burden: {
    light: "가벼운 질감",
    smooth: "밋밋한 질감",
    warmth: "열감",
  },
};

/** How the line dresses each sensation on each side. */
const WORDS: Readonly<Record<"liked" | "burden", Record<string, string>>> = {
  liked: {
    sweetness: "달콤한 풍미",
    acidity: "침샘을 자극하는 깔끔한 산미",
    bitterness: "은은하게 깔리는 쌉쌀함",
    light: "가볍게 넘어가는 질감",
    heavy: "입안을 채우는 묵직함",
    smooth: "매끄럽게 감기는 질감",
    drying: "입안을 잡아 주는 떫은맛",
    bubbles: "톡 쏘는 탄산",
    warmth: "은은하게 퍼지는 열감",
    persistence: "은은하게 맴도는 여운",
    clean: "깔끔하게 떨어지는 마무리",
    lingering: "은은하게 맴도는 여운",
  },
  burden: {
    sweetness: "묵직하게 다가오는 단맛",
    acidity: "혀끝을 찌르는 새콤함",
    bitterness: "혀에 오래 남는 쓴맛",
    light: "허전할 만큼 가벼운 질감",
    heavy: "입안을 꽉 채우는 묵직함",
    smooth: "밋밋하게 느껴지는 질감",
    drying: "입안을 꽉 조이는 떫은맛",
    bubbles: "거칠게 쏘는 탄산",
    warmth: "확 올라오는 알코올 열감",
    persistence: "길게 남는 여운",
    clean: "깔끔한 마무리",
    lingering: "입안에 오래 남는 여운",
  },
};

/** The adjective an aroma takes, by what the dictionary says it is. */
const AROMA_ADJECTIVE: Readonly<Record<string, string>> = {
  fruit: "싱그러운",
  botanical: "향긋한",
  bakery_sweets_nuts: "달콤한",
  earthy_spices_savory: "기분 좋은",
};
const AROMA_ADJECTIVE_BY_KEY: Readonly<Record<string, string>> = {
  jammy: "달콤한",
  fruit_syrup: "달콤한",
  dried_fruit: "달콤한",
  raisin: "달콤한",
  banana: "달콤한",
  coconut: "달콤한",
  bell_pepper: "풋풋한",
  jalapeno: "풋풋한",
  tomato: "풋풋한",
  cucumber: "풋풋한",
  celery: "풋풋한",
  leaf: "풋풋한",
  vegetal: "풋풋한",
  potato: "구수한",
  sweet_potato: "구수한",
  bread: "고소한",
  cereal: "고소한",
  nutty: "고소한",
  roasted: "고소한",
  toast: "고소한",
  corn: "고소한",
  rice: "고소한",
  barley: "고소한",
  malt: "고소한",
  wheat: "고소한",
  almond: "고소한",
  walnut: "고소한",
  hazelnut: "고소한",
  macadamia: "고소한",
  cashew: "고소한",
  coffee: "고소한",
  mocha: "고소한",
  dairy: "부드러운",
  butter: "부드러운",
  cream: "부드러운",
  cheese: "부드러운",
  pepper: "코끝을 스치는",
  spice: "코끝을 스치는",
  cinnamon: "코끝을 스치는",
  ginger: "코끝을 스치는",
  clove: "코끝을 스치는",
  coriander_seed: "코끝을 스치는",
  juniper: "코끝을 스치는",
  wood: "은은하게 깔리는",
  smoke: "은은하게 깔리는",
  oak: "은은하게 깔리는",
  peat: "은은하게 깔리는",
  tobacco: "은은하게 깔리는",
  leather: "은은하게 깔리는",
  incense: "은은하게 깔리는",
  musk: "은은하게 깔리는",
  cherry_wood: "은은하게 깔리는",
  aged_aromatic: "은은하게 깔리는",
  fermentation: "은은한",
  yeast: "은은한",
  nuruk: "은은한",
  ginjo_aroma: "은은한",
};
const AROMA_FAMILY = new Map<string, string>(
  (serviceVocabulary as { groups: { key: string; category_key?: string }[] })
    .groups.map((g) => [g.key, g.category_key ?? ""]),
);

/**
 * Each item dressed for its side. An aroma's adjective gives way (향긋한) when
 * a taste in the same list already opens with it: 향긋한 바닐라 향과 달콤한
 * 풍미, not 달콤한 바닐라 향과 달콤한 풍미.
 */
function dressed(items: readonly Item[], side: "liked" | "burden"): string[] {
  const taken = new Set(
    items.filter((i) => i.domain !== "aroma").map((i) =>
      (WORDS[side][i.key] ?? i.name).split(" ")[0]
    ),
  );
  return items.map((item) => {
    if (item.domain !== "aroma") return WORDS[side][item.key] ?? item.name;
    let adjective = side === "liked"
      ? aromaAdjective(item.keys)
      : "너무 진하게 올라오는";
    if (taken.has(adjective)) adjective = "향긋한";
    return `${adjective} ${item.name}`;
  });
}

/** The family's adjective when every aroma named shares it, else a plain one. */
function aromaAdjective(keys: readonly string[]): string {
  const each = keys.map((key) =>
    AROMA_ADJECTIVE_BY_KEY[key] ??
      AROMA_ADJECTIVE[AROMA_FAMILY.get(key) ?? ""] ?? "기분 좋은"
  );
  return each.every((a) => a === each[0]) ? each[0] : "기분 좋은";
}

/** 단맛, 여운: what was missing, by its plain name. */
function lackName(item: Item): string {
  return item.key === "persistence" || item.key === "lingering"
    ? "여운"
    : item.name;
}

/** "{단맛}{이} 살짝 받쳐줬으면", "여운이 조금 더 이어졌으면". */
function lackWant(item: Item): string {
  const name = lackName(item);
  if (item.key === "persistence" || item.key === "lingering") {
    return `${name}{이} 조금 더 이어졌으면`;
  }
  if (item.domain === "aroma") return `${name}{이} 조금 더 피어올랐으면`;
  return `${name}{이} 살짝 받쳐줬으면`;
}

/** The softer bottle the 부담만 line points to. */
function nextSofter(burdens: readonly Item[]): string {
  if (burdens.length === 1 && burdens[0].key === "light") {
    return "조금 더 묵직한";
  }
  if (
    burdens.length === 1 &&
    (burdens[0].key === "persistence" || burdens[0].key === "lingering")
  ) {
    return "여운이 짧게 끊기는";
  }
  return `${listed(burdens.map((i) => i.name))}{이} 한 톤 부드러운`;
}

/** Two joined by 과/와, more as a comma list. */
function listed(words: readonly string[]): string {
  if (words.length < 2) return words[0] ?? "";
  if (words.length === 2) return josa(`${words[0]}{과} ${words[1]}`);
  return words.join(", ");
}

/* ----------------------------------------------------------------- tags */

/** 흙향 liked, 떫은맛 less, 단맛 more. */
function tag(item: Item, side: Side): TasteCardTag {
  const label = (side === "lack" ? lackName(item) : item.name).replaceAll(
    " ",
    "",
  );
  const kind = side === "liked"
    ? "liked"
    : side === "lack"
    ? "more"
    : item.less
    ? "less"
    : "burden";
  return { label, kind };
}

/** At most three tags, every side the reader answered keeping one. */
function pickTags(
  liked: readonly TasteCardTag[],
  burdens: readonly TasteCardTag[],
  lacks: readonly TasteCardTag[],
): TasteCardTag[] {
  const sides = [liked, burdens, lacks].filter((s) => s.length);
  const out = sides.map((s) => s[0]);
  const rest = sides.flatMap((s) => s.slice(1));
  const chosen = [...out, ...rest.slice(0, Math.max(0, 3 - out.length))];
  // Keep the liked → burden → lack order after filling.
  return [...liked, ...burdens, ...lacks].filter((t) => chosen.includes(t));
}

/* ---------------------------------------------------------------- sides */

/**
 * The sensations of each side, as the reader answered them. A sensation
 * answered on both sides (단맛 liked while drinking, 달게 남는 여운 a burden)
 * is named once, on the side of the answer given while drinking; the other
 * side keeps the finish as "여운". A burden the reader wanted more of (너무
 * 약했어요, 너무 짧았어요) is a lack, not a burden.
 */
function sides(
  facts: CardFacts,
): { liked: Item[]; burdens: Item[]; lacks: Item[] } {
  const reacted = facts.reactions.filter((r) =>
    r.reaction === "liked" || r.reaction === "burden"
  );
  const same = (a: Subject, b: Subject) =>
    a.domain === b.domain && a.key === b.key;
  const subjects = reacted
    .map((r) => r.subject)
    .filter((s, i, all) => all.findIndex((t) => same(t, s)) === i);
  const on = (s: Subject, reaction: ReactionFact["reaction"]) =>
    reacted.filter((r) => r.reaction === reaction && same(r.subject, s));
  const liked: Subject[] = [];
  const burdens: Subject[] = [];
  const lacks: Subject[] = [];
  const lessOf = new Set<Subject>();
  let likedFinish = false;
  let burdenFinish = false;
  for (const s of subjects) {
    const l = on(s, "liked");
    const b = on(s, "burden");
    const isLack = b.some((r) =>
      r.qualifier === "too_weak" || r.qualifier === "too_brief"
    );
    // Too strong, or still there in the finish, is "less"; a mouthfeel burden
    // is asked no reason and always means too much of it (떫음, 열감, 무게감).
    const less = s.domain === "mouthfeel" ||
      b.some((r) => r.qualifier === "excessive" || r.qualifier === "lingering");
    if (l.length && b.length) {
      // The drinking answer wins; the finish answer of the other side stays.
      const likedDrinking = l.some((r) => r.phase === "drinking");
      const burdenDrinking = b.some((r) => r.phase === "drinking");
      if (likedDrinking && !burdenDrinking) {
        liked.push(s);
        burdenFinish = true;
      } else if (burdenDrinking && !likedDrinking) {
        if (isLack) lacks.push(s);
        else {
          burdens.push(s);
          if (less) lessOf.add(s);
        }
        likedFinish = true;
      } else {
        liked.push(s);
      }
    } else if (l.length) {
      liked.push(s);
    } else if (isLack) {
      lacks.push(s);
    } else {
      burdens.push(s);
      if (less) lessOf.add(s);
    }
  }
  const finish = (items: Item[], add: boolean, less: boolean) =>
    add && !items.some((i) => i.name.endsWith("여운"))
      ? [...items, {
        domain: "finish" as const,
        key: "lingering",
        keys: ["lingering"],
        name: "여운",
        less,
      }]
      : items;
  const burdenItems = items(burdens).map((item) => ({
    ...item,
    less: burdens.some((s) =>
      lessOf.has(s) && (item.keys.includes(s.key) || item.key === s.key)
    ),
  }));
  return {
    liked: finish(items(liked), likedFinish, false),
    burdens: finish(burdenItems, burdenFinish, true),
    lacks: items(lacks),
  };
}

/** Aromas gathered into one item, the rest one each, in answer order. */
function items(subjects: readonly Subject[]): Item[] {
  const aromas = subjects.filter((s) => s.domain === "aroma");
  const out: Item[] = [];
  if (aromas.length) {
    out.push({
      domain: "aroma",
      key: aromas[0].key,
      keys: aromas.map((s) => s.key),
      name: subjectPhrases(aromas)[0],
    });
  }
  for (const s of subjects) {
    if (s.domain === "aroma") continue;
    const name = subjectPhrases([s])[0];
    if (name) out.push({ domain: s.domain, key: s.key, keys: [s.key], name });
  }
  return out;
}

/** One of the wordings, always the same one for the same seed. */
function pick<T>(seed: string, options: readonly T[]): T {
  let hash = 0;
  for (const char of seed) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return options[hash % options.length];
}
