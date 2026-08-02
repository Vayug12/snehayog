#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerDubbingTools } from "./tools/dubbing.js";
import { registerAnalysisTools } from "./tools/analysis.js";
import { registerEmbeddingTools } from "./tools/embeddings.js";
import { registerVideoTools } from "./tools/videos.js";
import { registerUserTools } from "./tools/users.js";
import { registerSearchTools } from "./tools/search.js";
import { registerAdTools } from "./tools/ads.js";
import { registerAdminTools } from "./tools/admin.js";

const BACKEND_URL = process.env.VAYU_BACKEND_URL || "http://localhost:3000";

const server = new McpServer({
  name: "vayu-ai-service",
  version: "1.0.0",
});

// Register all tool modules
registerDubbingTools(server, BACKEND_URL);
registerAnalysisTools(server, BACKEND_URL);
registerEmbeddingTools(server, BACKEND_URL);
registerVideoTools(server, BACKEND_URL);
registerUserTools(server, BACKEND_URL);
registerSearchTools(server, BACKEND_URL);
registerAdTools(server, BACKEND_URL);
registerAdminTools(server, BACKEND_URL);

// Resources - Provider Info
server.resource("ai-providers", "vayu://ai/providers", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(
        {
          gemini: {
            model: "gemini-2.0-flash",
            features: ["multimodal", "embeddings", "text-generation"],
            freeTier: { rpm: 2, daily: 1000 },
          },
          deepseek: {
            model: "deepseek-chat",
            features: ["text-generation", "json-structured"],
            freeTier: { rpm: 30, daily: "unlimited" },
          },
          openai: {
            model: "gpt-4o-mini",
            features: ["multimodal", "whisper", "text-generation"],
          },
          huggingface: {
            models: ["whisper", "mbart-50", "bart-cnn"],
            features: ["transcription", "translation", "summarization"],
          },
          openrouter: {
            features: ["free-models", "multi-provider-proxy"],
          },
          siliconflow: {
            features: ["free-models", "text-generation"],
          },
        },
        null,
        2
      ),
    },
  ],
}));

// Resource - App Architecture
server.resource("architecture", "vayu://app/architecture", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(
        {
          backend: "Node.js / Express",
          database: "MongoDB (Mongoose)",
          cache: "Redis (Upstash) + Cloudflare KV",
          storage: "Cloudinary + Cloudflare R2 + AWS S3",
          video: "HLS (FFmpeg adaptive bitrate)",
          payments: "Razorpay",
          notifications: "Firebase FCM + Brevo",
          auth: "Google Sign-In + JWT",
          ai: {
            dubbing: "HuggingFace (Whisper, MBART, BART) / Edge TTS (free)",
            analysis: "Gemini + DeepSeek + OpenAI",
            embeddings: "Gemini text-embedding-004 (384-dim)",
            videoGen: "VayugAI (FastAPI on HuggingFace Spaces)",
          },
          deployment: "Fly.io (Docker)",
        },
        null,
        2
      ),
    },
  ],
}));

// Resource - API Endpoints
server.resource("api-endpoints", "vayu://api/endpoints", async (uri) => ({
  contents: [
    {
      uri: uri.href,
      mimeType: "application/json",
      text: JSON.stringify(
        {
          auth: "/api/auth",
          users: "/api/users",
          videos: "/api/videos",
          ads: "/api/ads",
          dubbing: "/api/dubbing",
          search: "/api/search",
          admin: "/api/admin",
          notifications: "/api/notifications",
          billing: "/api/billing",
          "creator-payouts": "/api/creator-payouts",
          upload: "/api/upload",
          "video-gen": "/api/video-gen",
          e2ee: "/api/e2ee",
          agent: "/api/agent",
          referrals: "/api/referrals",
          feedback: "/api/feedback",
          report: "/api/report",
          "app-config": "/api/app-config",
        },
        null,
        2
      ),
    },
  ],
}));

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Vayu AI MCP Server running on stdio");
  console.error(`Backend URL: ${BACKEND_URL}`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
