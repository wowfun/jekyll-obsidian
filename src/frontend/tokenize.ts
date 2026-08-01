const WORD_RUN = /[\p{L}\p{N}\p{M}]+/gu;
const CJK_CHARACTER = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

function isCjk(value: string): boolean {
  return CJK_CHARACTER.test(value);
}

/**
 * Stable tokenizer used for both indexing and queries. CJK runs always emit
 * individual code points and adjacent bigrams. Intl.Segmenter may improve the
 * ranking elsewhere, but never changes this baseline index.
 */
export function obsidianTokenizer(input: string): string[] {
  const normalized = input.normalize("NFKC").toLocaleLowerCase("und");
  const output: string[] = [];

  for (const match of normalized.matchAll(WORD_RUN)) {
    const run = match[0];
    let latin = "";
    let cjk: string[] = [];

    const flushLatin = () => {
      if (latin) output.push(latin);
      latin = "";
    };
    const flushCjk = () => {
      if (cjk.length === 0) return;
      output.push(...cjk);
      for (let index = 0; index + 1 < cjk.length; index += 1) {
        output.push(`${cjk[index]}${cjk[index + 1]}`);
      }
      cjk = [];
    };

    for (const character of Array.from(run)) {
      if (isCjk(character)) {
        flushLatin();
        cjk.push(character);
      } else {
        flushCjk();
        latin += character;
      }
    }
    flushLatin();
    flushCjk();
  }

  return [...new Set(output)];
}

export function cjkSegmentBoost(input: string): string[] {
  if (!("Segmenter" in Intl)) return [];
  const segmenter = new Intl.Segmenter(undefined, { granularity: "word" });
  return Array.from(segmenter.segment(input.normalize("NFKC")))
    .filter((segment) => segment.isWordLike)
    .map((segment) => segment.segment.toLocaleLowerCase("und"));
}
