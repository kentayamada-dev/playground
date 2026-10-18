import { createServer } from "node:http";

const apiUrl = process.env.API_URL;
if (!apiUrl) {
  throw new Error("API_URL が設定されていません");
}

const server = createServer(async (req, res) => {
  if (req.method !== "GET" || req.url !== "/") {
    res.writeHead(404).end();
    return;
  }

  try {
    const apiRes = await fetch(`${apiUrl}/hello`);
    if (!apiRes.ok) {
      throw new Error(`api が ${apiRes.status} を返しました`);
    }
    const { message } = await apiRes.json();
    res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" }).end(`api からの応答: ${message}\n`);
  } catch (error) {
    res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" }).end(`api を呼び出せません: ${error.message}\n`);
  }
});

server.listen(3000, () => {
  console.log("http://localhost:3000 で待ち受けています");
});
