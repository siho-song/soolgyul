/**
 * 준비: the first stage of the 술결카드 생성 파이프라인. It makes the two
 * things every later stage works from and judges nothing:
 *
 *   해석   the answers → 해석 결과 (answers.ts)
 *   조회   the bottle  → 술의 사실 (bottle.ts)
 *
 * The two do not know each other: the answers are read without the bottle,
 * and the bottle is looked up without the answers. 근거 찾기 is the first
 * stage that holds one against the other.
 */
import type { SensoryRecord } from "./record/sensory_record.ts";
import { type BottleFacts, bottleFacts } from "./bottle.ts";
import { type Answers, readAnswers } from "./answers.ts";

export type RecordReading = {
  answers: Answers;
  bottle: BottleFacts;
};

export function readRecord(record: SensoryRecord): RecordReading {
  return {
    answers: readAnswers(record),
    bottle: bottleFacts(record.product),
  };
}
