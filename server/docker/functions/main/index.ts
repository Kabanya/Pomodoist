// Adapted from Supabase self-hosting templates; modified for Pomodoist.
// Copyright 2024 Supabase. See docker/NOTICE and docker/LICENSE.supabase.
console.log("Pomodoist function router started");

const mcpMetadataPath =
  "/.well-known/oauth-protected-resource/functions/v1/pomodoist-mcp";

Deno.serve(async (request: Request) => {
  const pathname = new URL(request.url).pathname;
  const serviceName = pathname === mcpMetadataPath
    ? "pomodoist-mcp"
    : pathname.split("/")[1];

  if (!serviceName) {
    return Response.json({ msg: "missing function name in request" }, {
      status: 400,
    });
  }

  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath: `/home/deno/functions/${serviceName}`,
      memoryLimitMb: 150,
      workerTimeoutMs: 150_000,
      noModuleCache: false,
      importMapPath: null,
      envVars: Object.entries(Deno.env.toObject()),
    });
    return await worker.fetch(request);
  } catch (error) {
    console.error(error);
    return Response.json({ msg: String(error) }, { status: 500 });
  }
});
