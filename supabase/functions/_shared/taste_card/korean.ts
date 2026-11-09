/**
 * Korean particles: 은/는, 이/가, 을/를 … chosen by the syllable before them,
 * and words joined by 과/와.
 */

/** Two words joined by 과/와 ("꽃과 배"); three or more as a plain list
 * ("꽃, 배, 바닐라"), which reads more naturally in Korean than "A, B와 C". */
export function andJoin(words: readonly string[]): string {
  if (words.length < 2) return words[0] ?? "";
  if (words.length > 2) return words.join(", ");
  return josa(`${words[0]}{과} ${words[1]}`);
}

/* ------------------------------------------------------------ particles */

export const PARTICLES: Readonly<Record<string, [string, string]>> = {
  "은": ["은", "는"],
  "이": ["이", "가"],
  "을": ["을", "를"],
  "과": ["과", "와"],
  "예요": ["이에요", "예요"],
  "이라": ["이라", "라"],
  "으로": ["으로", "로"],
  "이고": ["이고", "고"],
  "이나": ["이나", "나"],
  "이다": ["이다", "다"],
};

/** Resolves {은} {이} {을} {과} {예요} {이라} {으로} {이고} {이나} {이다} by the syllable before them. */
export function josa(text: string): string {
  return text.replace(
    /\{(은|이|을|과|예요|이라|으로|이고|이나|이다)\}/g,
    (_match, key: string, offset: number) => {
      const before = text.slice(0, offset).replace(/['’"”)\]]+$/, "");
      const last = before.charAt(before.length - 1);
      // 으로/로: a final ㄹ takes 로 (쌀로, 메를로로 is 메를로 + 로).
      const consonant = hasFinalConsonant(last) &&
        !(key === "으로" && finalIsRieul(last));
      return PARTICLES[key][consonant ? 0 : 1];
    },
  );
}

export function finalIsRieul(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return code >= 0xac00 && code <= 0xd7a3 && (code - 0xac00) % 28 === 8;
}

export function hasFinalConsonant(ch: string): boolean {
  if (!ch) return false;
  const code = ch.charCodeAt(0);
  if (code >= 0xac00 && code <= 0xd7a3) return (code - 0xac00) % 28 !== 0;
  if (/[0-9]/.test(ch)) return "013678".includes(ch);
  return /[lmn]/i.test(ch);
}
