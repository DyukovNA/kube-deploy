import { z } from "zod";

const messageSchema = z.object({
  id: z.number().int().positive(),
  text: z.string(),
  createdAt: z.iso.datetime({ offset: true }),
});

const versionSchema = z.object({
  version: z.string(),
  commit: z.string(),
});

const healthSchema = z.object({ status: z.string() });

export type Message = z.infer<typeof messageSchema>;
export type Version = z.infer<typeof versionSchema>;

async function request<T>(path: string, schema: z.ZodType<T>, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: { Accept: "application/json", ...init?.headers },
  });
  if (!response.ok) {
    throw new Error(`API ${response.status}`);
  }
  return schema.parse(await response.json());
}

export const api = {
  version: () => request("/api/version", versionSchema),
  ready: () => request("/api/health/ready", healthSchema),
  messages: () => request("/api/messages", z.array(messageSchema)),
  create: (text: string) =>
    request("/api/messages", messageSchema, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    }),
};
