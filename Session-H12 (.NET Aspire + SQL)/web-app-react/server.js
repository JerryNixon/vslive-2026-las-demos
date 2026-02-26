const express = require("express");
const path = require("path");
const http = require("http");

const app = express();
const port = process.env.PORT || 3000;

// Debug: log all env vars related to data-api
const apiEnvVars = Object.entries(process.env)
  .filter(([k]) => /data.api/i.test(k))
  .map(([k, v]) => `  ${k}=${v}`);
console.log("Data-API env vars:\n" + (apiEnvVars.length ? apiEnvVars.join("\n") : "  (none found)"));

const dabUrl = process.env['services__data-api__http__0']
  || process.env['services__data-api__https__0']
  || process.env['DATA_API_HTTP']
  || "http://localhost:4567";

console.log("DAB URL:", dabUrl);

function httpGet(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error(`Invalid JSON from ${url}: ${data.slice(0, 200)}`)); }
      });
    }).on('error', reject);
  });
}

app.use(express.static(path.join(__dirname, "public")));

// Proxy API calls to DAB
app.get("/api/:entity", async (req, res) => {
  const url = new URL(`/api/${req.params.entity}`, dabUrl);
  for (const [key, value] of Object.entries(req.query)) {
    url.searchParams.set(key, value);
  }
  try {
    const data = await httpGet(url.toString());
    res.json(data);
  } catch (err) {
    console.error("Proxy error:", url.toString(), err.message);
    res.status(502).json({ error: err.message });
  }
});

app.listen(port, () => {
  console.log(`React app listening on http://localhost:${port}`);
});
