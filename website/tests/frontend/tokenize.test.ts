import { describe, expect, it } from "vitest";
import { websiteTokenizer } from "../../src/frontend/tokenize";

describe("websiteTokenizer", () => {
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
