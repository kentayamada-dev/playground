import { createServer } from "node:http";

const golangUrl = process.env.GOLANG_URL;
if (!golangUrl) {
  throw new Error("GOLANG_URL が設定されていません");
}

const server = createServer(async (req, res) => {
  if (req.method !== "GET" || req.url !== "/") {
    res.writeHead(404).end();
    return;
  }

  try {
    const golangRes = await fetch(`${golangUrl}/hello`);
    if (!golangRes.ok) {
      throw new Error(`golang が ${golangRes.status} を返しました`);
    }
    const { message } = await golangRes.json();
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" }).end(`golang からの応答: ${message}\n`);
  } catch (error) {
    res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" }).end(`golang を呼び出せません: ${error.message}\n`);
  }
});

server.listen(3000, () => {
  console.log("http://localhost:3000 で待ち受けています");
});
