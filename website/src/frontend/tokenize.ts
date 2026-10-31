const WORD_RUN = /[\p{L}\p{N}\p{M}]+/gu;
const CJK_CHARACTER = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u;

function isCjk(value: string): boolean {
  return CJK_CHARACTER.test(value);
}

/**
 * Stable tokenizer used for both indexing and queries. CJK runs always emit
 * individual code points and adjacent bigrams, so indexing and queries use the
 * same terms in every browser.
 */
export function websiteTokenizer(input: string): string[] {
  return boundedWebsiteTokenizer(input, Infinity);
}

export function boundedWebsiteTokenizer(input: string, maximum: number): string[] {
  const normalized = input.normalize("NFKC").toLocaleLowerCase("und");
  const output = new Set<string>();
  const add = (term: string) => { if (output.size < maximum) output.add(term); };

  for (const match of normalized.matchAll(WORD_RUN)) {
    const run = match[0];
    let latin = "";
    let cjk = "";

    const flushLatin = () => {
      if (latin) add(latin);
      latin = "";
    };
    const flushCjk = () => {
      if (cjk.length === 0) return;
      for (const character of cjk) { add(character); if (output.size >= maximum) break; }
      let previous = '';
      for (const character of cjk) {
        if (previous) add(previous + character);
        previous = character;
        if (output.size >= maximum) break;
      }
      cjk = '';
    };

    for (const character of run) {
      if (isCjk(character)) {
        flushLatin();
        cjk += character;
      } else {
        flushCjk();
        latin += character;
      }
    }
    flushLatin();
    flushCjk();
    if (output.size >= maximum) break;
  }

  return [...output];
}
