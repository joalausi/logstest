const express = require("express");
const os = require("os");

const app = express();
const port = process.env.PORT || 3000;

let requestCount = 0;

function bytesToMb(bytes) {
  return Math.round(bytes / 1024 / 1024);
}

app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    service: "infrastructure-insight-backend",
    timestamp: new Date().toISOString()
  });
});

app.get("/metrics", (req, res) => {
  requestCount += 1;

  const cpus = os.cpus();

  res.json({
    backend_server: process.env.BACKEND_SERVER_NAME || "app-01",
    container_hostname: os.hostname(),
    platform: os.platform(),
    os_type: os.type(),
    os_release: os.release(),
    cpu_model: cpus.length > 0 ? cpus[0].model : "unknown",
    cpu_cores: cpus.length,
    memory_total_mb: bytesToMb(os.totalmem()),
    memory_free_mb: bytesToMb(os.freemem()),
    uptime_seconds: Math.round(os.uptime()),
    request_count: requestCount,
    timestamp: new Date().toISOString()
  });
});

app.listen(port, "0.0.0.0", () => {
  console.log(`Infrastructure Insight backend listening on port ${port}`);
});