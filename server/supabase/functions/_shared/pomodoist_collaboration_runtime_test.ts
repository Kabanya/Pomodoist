import { assertEquals, assert } from "jsr:@std/assert@1";
import { collaborationRuntime } from "./pomodoist_collaboration_runtime.ts";
Deno.test("Storage signing keeps internal service traffic but returns public capability URLs", async () => {
  const calls: string[] = [];
  const runtime = collaborationRuntime({ url: "http://gateway:8000", publicUrl: "https://api.example.com",
    key: "fake-service-key", webUrl: "https://app.example.com", env: { get: () => undefined },
    fetcher: async (input) => {
      const url = String(input); calls.push(url);
      return Response.json(url.includes("/upload/sign/") ? { url: "/object/upload/sign/pomodoist-shared/path?token=fake" } :
        { signedURL: "/object/sign/pomodoist-shared/path?token=fake" });
    },
  });
  const upload = await runtime.upload("path");
  const download = await runtime.download("path", "notes.txt");
  assert(upload.signedUrl.startsWith("https://api.example.com/storage/v1/"));
  assert(download.startsWith("https://api.example.com/storage/v1/"));
  assertEquals(calls.every(url => url.startsWith("http://gateway:8000/")), true);
});
