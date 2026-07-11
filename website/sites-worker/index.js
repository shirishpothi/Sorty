const MIME_TYPES = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp",
  ".xml": "application/xml; charset=utf-8",
};

function assetPath(pathname) {
  if (pathname === "/") return "/index.html";
  if (pathname.endsWith("/")) return `${pathname}index.html`;
  if (!pathname.includes(".")) return `${pathname}.html`;
  return pathname;
}

function contentType(pathname) {
  const dotIndex = pathname.lastIndexOf(".");
  const extension = dotIndex === -1 ? "" : pathname.slice(dotIndex).toLowerCase();
  return MIME_TYPES[extension] || "application/octet-stream";
}

const worker = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const primaryPath = assetPath(url.pathname);
    const primary = await env.ASSETS.fetch(new Request(new URL(primaryPath, url), request));

    if (primary.status !== 404) {
      return primary;
    }

    const notFound = await env.ASSETS.fetch(new Request(new URL("/404.html", url), request));
    if (notFound.status !== 404) {
      return new Response(notFound.body, {
        status: 404,
        headers: {
          "content-type": contentType("/404.html"),
        },
      });
    }

    return new Response("Not found", { status: 404 });
  },
};

export default worker;
