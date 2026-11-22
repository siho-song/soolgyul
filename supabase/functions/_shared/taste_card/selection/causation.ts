/**
 * Whether a cause of the bottle can be said to make a taste.
 *
 * A grape, a place, a maker, a word of the label, the strength and the age
 * are what the drink is: their level on a gauge is the drink's own (a grape
 * is sharp). A way of making, a cask and an ingredient are different: the
 * dictionary's level for them is what drinks made so tend to be, which is
 * not what the making does. Wines fermented a second time in the bottle are
 * mostly sharp, because they are made from grapes picked early; the second
 * fermentation gives the bubbles, not the acidity (the user's review,
 * 2026-11-21: "제법이 담당하는 맛 축과 산지·품종이 담당하는 맛 축을
 * 엇갈리지 않게"). So such a cause is named for a taste only when the
 * dictionary's own sentence about it speaks of that taste.
 */
import researched from "../../../../../catalog/dictionary/causes.json" with {
  type: "json",
};
import { terms } from "../dictionary/dictionary.ts";
import type { Cause } from "../evidence/evidence.ts";
import type { GaugeAxis } from "../facts/facts.ts";
import { short } from "../writing/words.ts";

/** The words a dictionary sentence names each gauge's taste by. */
const SPOKEN: Readonly<Record<GaugeAxis, RegExp>> = {
  sweetness: /단맛|달콤|달큰|당분|당이|드라이/,
  acidity: /산미|산도|새콤|신맛|시큼/,
  umami: /감칠/,
  body:
    /바디|묵직|무게|가볍|걸쭉|농밀|농도|질감|크리미|부드럽|매끄|둥글|진득|두터/,
  tannin: /타닌|탄닌|떫/,
  spice: /알싸|스파이시|타격|자극|화끈|열감|알코올|도수/,
  sparkling: /탄산|기포|버블/,
  peat: /피트|스모키|훈연|연기/,
  finish_length: /여운|피니시|뒷맛/,
  finish_character: /끝맛|뒷맛|마무리|깔끔|목넘김/,
};

/** The factors whose level is a tendency of drinks made so, not the drink's own. */
const MADE_SO: ReadonlySet<string> = new Set(["making", "cask", "ingredient"]);

type Row = { key: string; summary?: string | null; why?: string | null };

/** What the dictionary says of each way of making, cask and ingredient. */
const SAID: ReadonlyMap<string, string> = new Map(
  ["process", "maturation", "ingredient"].flatMap((type) =>
    (terms(type) as readonly Row[]).map((row) =>
      [row.key, [row.summary, row.why].filter(Boolean).join(" ")] as const
    )
  ),
);

/**
 * Whether the cause may be named as where an aroma comes from: a way of
 * making, a cask or an ingredient only when its dictionary sentence names
 * the aroma (셰리 캐스크의 건포도 향), since the aromas listed for it are
 * otherwise those of drinks made so.
 */
export function givesAroma(cause: Cause, aroma: string): boolean {
  if (!MADE_SO.has(cause.factor)) return true;
  const name = short(aroma);
  return name !== aroma &&
    (`${SAID.get(cause.key) ?? ""} ${cause.why ?? ""}`.includes(name) ||
      cause.ko.includes(name) || name.includes(cause.ko));
}

type Made = Readonly<
  Record<
    string,
    Record<string, {
      how: string;
      process?: string;
      why?: string;
      reason?: string;
      side?: "high" | "low";
    }>
  >
>;
type Denied = Readonly<Record<string, Record<string, string>>>;
const MADE = researched.made as unknown as Readonly<Record<string, Made>>;
const DENIED = researched.denied as unknown as Readonly<Record<string, Denied>>;

/** The tables of catalog/dictionary/causes.json a cause's factor is looked up in. */
const TABLES: Readonly<Record<string, readonly string[]>> = {
  making: ["process", "maturation"],
  cask: ["maturation", "process"],
  ingredient: ["ingredient"],
  label_word: ["label_word"],
  abv: ["abv"],
  kind: ["kind"],
  grape: ["grape"],
  region_style: ["regional_style"],
  producer: ["producer"],
};

/** The research's row for a cause and a taste, on the side it was written for. */
function rowOf(cause: Cause, axis: GaugeAxis, side?: "high" | "low") {
  for (const table of TABLES[cause.factor] ?? []) {
    const row = MADE[table]?.[cause.key]?.[axis];
    if (row?.how && (!row.side || !side || row.side === side)) return row;
  }
  return null;
}

/**
 * How the cause makes the taste (병 안에서 한 번 더 발효해 탄산을 가둬서),
 * where the dictionary's research says it does. It is the record that the
 * pair was found to make the taste; the card says the process alone
 * (processOf). A clause written for one side of a taste (껍질이 얇아 떫은맛이
 * 순해서) holds only for an answer on that side.
 */
export function howOf(
  cause: Cause,
  axis: GaugeAxis,
  side?: "high" | "low",
): string | null {
  return rowOf(cause, axis, side)?.how ?? null;
}

/**
 * What was done, or what the cause is, as a clause that goes before 덕분에 /
 * 탓에 (병 속에서 한 번 더 발효하며 기포를 가둔). It stops at the process:
 * how that tastes is the sentence's own second half. Nothing where the
 * research holds only the result for the pair.
 */
export function processOf(
  cause: Cause,
  axis: GaugeAxis,
  side?: "high" | "low",
): string | null {
  return rowOf(cause, axis, side)?.process ?? null;
}

/**
 * Whether the cause may be named as what gives the bottle this taste. What
 * the research settled goes first: a pair it found to make the taste, or
 * found not to. A pair it did not look at falls back on whether the
 * dictionary's sentence about the cause speaks of the taste.
 */
export function makes(cause: Cause, axis: GaugeAxis): boolean {
  if (howOf(cause, axis)) return true;
  if (!MADE_SO.has(cause.factor)) return true;
  const denied = (TABLES[cause.factor] ?? []).some((table) =>
    DENIED[table]?.[cause.key]?.[axis] !== undefined
  );
  if (denied) return false;
  return SPOKEN[axis].test(`${SAID.get(cause.key) ?? ""} ${cause.why ?? ""}`);
}

type ClimateRow = Readonly<Record<string, string>>;
const CLIMATE = researched.climate_process as unknown as Readonly<
  Record<string, ClimateRow>
>;

/** The side a climate pushes a taste to, where the principle is plain. */
const PUSHES: Readonly<
  Record<string, Partial<Record<GaugeAxis, "high" | "low">>>
> = {
  cool: { acidity: "high", body: "low" },
  warm: { acidity: "low", body: "high" },
  hot: { acidity: "low", body: "high" },
};

/** The climate as a place is called by it: 서늘한 산지. */
export const CLIMATE_WORD: Readonly<Record<string, string>> = {
  cool: "서늘한",
  warm: "따뜻한",
  hot: "더운",
};

/**
 * What a place's climate does to its grapes, as a clause that goes before
 * 덕분에 / 탓에 (서늘한 기후에서 포도가 천천히 익은), when the climate pushes
 * the taste to the side the reader set (a cool place and a sharp wine).
 * Nothing for a moderate place, or a taste climate alone does not settle
 * (sweetness is how the wine was made, not how ripe the grape).
 */
export function climateProcess(
  climate: string | undefined,
  axis: GaugeAxis,
  side: "high" | "low",
): string | null {
  if (!climate || PUSHES[climate]?.[axis] !== side) return null;
  return CLIMATE[climate]?.[axis] ?? null;
}

const REASONS = researched.reasons as unknown as Readonly<
  Record<string, Readonly<Record<string, string>>>
>;

/**
 * Why the cause makes the taste, as one plain clause that goes between the
 * cause and how it felt (두꺼운 껍질에서 진하고 떫은 성분이 많이 우러나서): the
 * pair's own, or the one of the kind of reason its clauses give. Null where
 * the kind has no clause for this taste and side.
 */
export function reasonOf(
  cause: Cause,
  axis: GaugeAxis,
  side: "high" | "low",
): string | null {
  const row = rowOf(cause, axis, side);
  if (!row) return null;
  return row.reason ?? REASONS[row.why ?? ""]?.[`${axis}:${side}`] ?? null;
}

/**
 * Whether a clause has reached the taste (… 질감을 묵직하게 채워서, … 입안에
 * 오래 남아서): the sentence then does not name the taste after it.
 */
export function reaches(axis: GaugeAxis, clause: string): boolean {
  return REACHED[axis].test(clause);
}

/** The words a clause ends on a taste by, beyond the taste's own names. */
const REACHED: Readonly<Record<GaugeAxis, RegExp>> = {
  sweetness: /단맛|달콤|달큰|달게|당분|당이|드라이/,
  acidity: /산미|산도|새콤|상큼|신맛|시큼/,
  umami: /감칠|담백/,
  body: /바디|묵직|무게|가볍|가벼|걸쭉|농밀|질감|진득|두터|두텁|경쾌/,
  tannin: /타닌|탄닌|떫/,
  spice: /알싸|스파이|타격|자극|화끈|열감|목넘김|순하|순해/,
  sparkling: /탄산|기포|거품/,
  peat: /피트|스모키|훈연|연기/,
  finish_length: /여운|오래 남|길게|끊|금방|빨리 사라/,
  finish_character: /끝맛|뒷맛|마무리|끝까지|끝이|깔끔|개운/,
};

/** The kind of reason the pair's clauses give (variety_skin, oak, …), or null. */
export function reasonKindOf(
  cause: Cause,
  axis: GaugeAxis,
  side: "high" | "low",
): string | null {
  return rowOf(cause, axis, side)?.why ?? null;
}

/** The same for what a place's climate does, where the place has no pair of its own. */
export function climateReason(
  climate: string | undefined,
  axis: GaugeAxis,
  side: "high" | "low",
): string | null {
  if (!climate || PUSHES[climate]?.[axis] !== side) return null;
  const kind = climate === "cool" ? "cool_ripening" : "warm_ripening";
  return REASONS[kind]?.[`${axis}:${side}`] ?? null;
}
