/**
 * A mark said as a shop says it, 1 to 5. A wine shelf uses the trade's own
 * words (드라이, 미디엄 바디); a traditional drink's graph is read in plain
 * Korean. A draft for the owner to edit.
 */
export const WINE_LEVEL_WORDS: Readonly<Record<string, readonly string[]>> = {
  sweetness: ["드라이", "세미 드라이", "미디엄", "세미 스위트", "스위트"],
  acidity: [
    "낮은 산도",
    "조금 낮은 산도",
    "중간 산도",
    "조금 높은 산도",
    "높은 산도",
  ],
  astringency: [
    "아주 부드러운 타닌",
    "부드러운 타닌",
    "중간 타닌",
    "탄탄한 타닌",
    "강한 타닌",
  ],
  body: [
    "라이트 바디",
    "라이트-미디엄 바디",
    "미디엄 바디",
    "미디엄-풀 바디",
    "풀 바디",
  ],
  carbonation: [
    "잔잔한 탄산",
    "조금 잔잔한 탄산",
    "중간 탄산",
    "조금 강한 탄산",
    "강한 탄산",
  ],
};

export const TRADITIONAL_LEVEL_WORDS: Readonly<
  Record<string, readonly string[]>
> = {
  sweetness: [
    "달지 않은 편",
    "살짝 단 편",
    "적당히 단 편",
    "단 편",
    "아주 단 편",
  ],
  acidity: [
    "산미가 거의 없는 편",
    "산미가 은은한 편",
    "산미가 적당한 편",
    "산미가 또렷한 편",
    "산미가 강한 편",
  ],
  carbonation: [
    "탄산이 거의 없는 편",
    "탄산이 잔잔한 편",
    "탄산이 적당한 편",
    "탄산이 톡 쏘는 편",
    "탄산이 강한 편",
  ],
  body: [
    "가벼운 편",
    "조금 가벼운 편",
    "중간 무게",
    "조금 묵직한 편",
    "묵직한 편",
  ],
};
