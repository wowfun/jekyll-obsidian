import { describe, expect, it } from "vitest";
import { boundedWebsiteTokenizer, websiteTokenizer } from "../../src/frontend/tokenize";

describe("websiteTokenizer", () => {
  it('bounds unique terms and handles long CJK runs without spreading a huge argument list', () => {
    expect(boundedWebsiteTokenizer(Array.from({ length: 20_000 }, (_, i) => `word${i}`).join(' '), 100)).toHaveLength(100);
    expect(websiteTokenizer('知'.repeat(200_000))).toEqual(['知', '知知']);
  });
  it("always emits deterministic CJK unigrams and bigrams", () => {
    expect(websiteTokenizer("知识花园")).toEqual([
      "知",
      "识",
      "花",
      "园",
      "知识",
      "识花",
      "花园"
    ]);
  });

  it("normalizes case, width, and duplicate terms", () => {
    expect(websiteTokenizer("ＦＯＯ foo 笔记")).toEqual(["foo", "笔", "记", "笔记"]);
  });

  it("keeps Latin words separate from adjacent CJK text", () => {
    expect(websiteTokenizer("OFM支持 CJK-search")).toEqual([
      "ofm",
      "支",
      "持",
      "支持",
      "cjk",
      "search"
    ]);
  });
});
