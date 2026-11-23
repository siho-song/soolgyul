/** What the writer passes between its parts: the card a section is written for, a point of a section, and a reason as told. */
import type { Cause, Evidence } from "../evidence/evidence.ts";
import { type GaugeAxis } from "../../record_reading/facts/facts.ts";
import type { WineSweetness } from "../../record_reading/facts/wine_sweetness.ts";

export type Card = {
  /** The drink as the sentence calls it: 레드 와인, 위스키, 막걸리. */
  kind: string;
  /** Whether the drink is brewed from grain (사케, 전통주): 쌀로 빚은, not 만든. */
  brewed: boolean;
  /** Whether the drink is a wine: what it is made of is a grape. */
  wine: boolean;
  /** The shelf the kind's bottles are counted on. */
  shelf: string | null;
  /** A still wine's sweetness read from the bottle's own traits; null for any other drink. */
  sweetness: WineSweetness | null;
  /** Whether the bottle's strength is one of its causes: its strength is then not said to be low. */
  strong: boolean;
  /** The side on which the bottle stands out among its kind on a gauge, given the causes that speak of it. */
  standsOut: (
    axis: GaugeAxis,
    causes: readonly Cause[],
  ) => "high" | "low" | null;
};

export type Gauge = Extract<Evidence["answer"], { kind: "gauge" }>;

/**
 * One point of a section (the user's standard, 2026-11-22): the taste and
 * what it comes from, then why and what it does in the mouth.
 *
 *   묵직한 바디감은 **말벡** 품종에서 나와요. 색소가 진하고 껍질이 두꺼워
 *   묵직한 질감이 우러나, 한 모금에도 입안이 든든하게 차요.
 *
 * With no cause to name, one sentence says it (이 와인에서는 단맛이 적당히
 * 감돌아, …).
 */
export type Point = {
  /** The cause it names, if any. */
  cause: Cause | null;
  /** The first sentence, without the particle after the taste; null when one sentence says it all. */
  open: { taste: string; from: string } | null;
  /** Why, before what it does: 색소가 진하고 껍질이 두꺼워 묵직한 질감이 우러나서. "" when the name says enough. */
  why: string;
  /** What the taste does in the mouth. */
  act: string;
  /** What stands between the two: ", " but for an aroma (퍼지면서 술이 …). */
  glue?: string;
};

export type Told = {
  /** The reason as the subtitle names it: 든든하게 채우는 무게감. */
  name: string;
  /** The reason in two words, as its point opens on it: 묵직한 바디감, 자두 향. */
  brief: string;
  /** What is said of the drink, after whatever opens the sentence, without its period. */
  body: string;
  /** A sentence that names its own subject (**말벡**은 보통 …, **자두 향**은 …) and takes no opening. */
  whole: boolean;
  /**
   * The cause a whole sentence opens on (**병내 2차 발효**는 …) and, for a
   * place, the word its climate is called by (서늘한 **샤블리**는 …).
   */
  subject?: { cause: Cause; climate?: string };
  /** The body without 같은 종류 가운데서도 유난히, for when the closing says it. */
  plain?: string;
  /** The causes the sentence stands on, the one it was told by first. */
  causes: readonly Cause[];
  /** The words of the sense the sentence is about, for the bold mark. */
  marks: readonly string[];
  /** Whether a burden is something the reader wanted more of (적은 단맛, 짧은 여운). */
  lack: boolean;
  /** 이번 잔에서 alone: the gauge it speaks of and the gauges it is explained by. */
  glass?: { of: GaugeAxis; by: readonly string[] };
  /** A point the section puts together: the taste, where it comes from, why and what it does. */
  point?: Point;
  /** What the sentence is about, for how two reasons stand to each other. */
  of?: { axis?: GaugeAxis; side?: string; aroma?: string };
};
