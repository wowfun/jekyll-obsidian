import { describe, expect, it } from "vitest";
import {
  parseCatalogPayload,
  parseGraphPayload,
  parseSearchPayload
} from "../../src/frontend/data";

describe("versioned data contracts", () => {
  it("accepts the three schema version 1 payloads", () => {
    expect(
      parseCatalogPayload({
        schema_version: 1,
        notes: [
          {
            id: "index.md",
            title: "Index",
            url: "/",
            aliases: [],
            tags: ["home"],
            description: null,
            preview: "Begin here.",
            updated: "2026-07-31",
            content_type: "page",
            published_at: null
          }
        ]
      }).notes[0]?.id
    ).toBe("index.md");

    expect(
      parseSearchPayload({
        schema_version: 1,
        documents: [
          {
            id: "index.md",
            title: "Index",
            url: "/",
            aliases: [],
            tags: [],
            text: "Begin here."
          }
        ]
      }).documents
    ).toHaveLength(1);

    expect(
      parseGraphPayload({
        schema_version: 1,
        nodes: [{ id: "index.md", title: "Index", url: "/" }],
        edges: [{ source: "index.md", target: "note.md", kind: "link", count: 2 }]
      }).edges[0]?.kind
    ).toBe("link");
  });

  it("fails closed on unknown schema versions and malformed records", () => {
    expect(() => parseCatalogPayload({ schema_version: 2, notes: [] })).toThrow(/schema/);
    expect(() =>
      parseSearchPayload({
        schema_version: 1,
        documents: [{ id: "private.md", title: "Leaked" }]
      })
    ).toThrow(/schema/);
    expect(() =>
      parseGraphPayload({
        schema_version: 1,
        nodes: [],
        edges: [{ source: "a", target: "b", kind: "other", count: 1 }]
      })
    ).toThrow(/schema/);
  });
});
