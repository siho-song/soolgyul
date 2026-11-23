/**
 * One entry of the card's wording tables: what an aroma does in the glass
 * (writing/prose_effects.ts) and how strong or lasting a taste was
 * (writing/prose_tastes.ts). writing/reasons.ts fills the placeholders and
 * joins the entry to the cause it tells; particles follow the word before
 * them: {은} {이} {을} {과} {예요} {이라} {이나} {으로}.
 */
export type Prose = {
  /** 짧은 이름: 수식어 하나 + 감각 명사, 4–12자, 조사 없이 명사로 끝. */
  name: string;
  /** 이 술의 특징과 그래서 입에서 어떻게 느껴지는지, 한 문장 (해요체). */
  body: string;
};
