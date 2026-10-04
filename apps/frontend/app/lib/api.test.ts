import { afterEach, describe, expect, it, vi } from "vitest";
import { api } from "./api";

afterEach(() => vi.unstubAllGlobals());

describe("API contract", () => {
  it("sends a message through the relative API path and validates the response", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ id: 7, text: "hello", createdAt: "2026-10-04T00:00:00Z" }), {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await expect(api.create("hello")).resolves.toMatchObject({ id: 7, text: "hello" });
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/messages",
      expect.objectContaining({ method: "POST", body: JSON.stringify({ text: "hello" }) }),
    );
  });

  it("rejects an invalid server response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify([{ id: "wrong", text: "hello" }]))));
    await expect(api.messages()).rejects.toThrow();
  });

  it("reports non-success HTTP responses", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(null, { status: 503 })));
    await expect(api.ready()).rejects.toThrow("API 503");
  });
});
