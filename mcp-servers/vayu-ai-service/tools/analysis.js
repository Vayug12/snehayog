import { z } from "zod";

async function apiCall(backendUrl, endpoint, method = "GET", body = null) {
  const options = {
    method,
    headers: { "Content-Type": "application/json" },
  };
  if (body) options.body = JSON.stringify(body);

  const res = await fetch(`${backendUrl}${endpoint}`, options);
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`API Error (${res.status}): ${err}`);
  }
  return res.json();
}

export function registerAnalysisTools(server, backendUrl) {
  server.tool(
    "analyze-video",
    "Analyze video content using AI. Returns tags, summary, language, category, sentiment.",
    {
      videoId: z.string().describe("Video ID to analyze"),
      provider: z
        .enum(["gemini", "deepseek", "openai"])
        .optional()
        .describe("AI provider to use for analysis"),
    },
    async ({ videoId, provider }) => {
      try {
        const result = await apiCall(backendUrl, `/api/videos/${videoId}`);
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  videoId,
                  title: result.title,
                  description: result.description,
                  tags: result.tags,
                  language: result.language,
                  region: result.region,
                  aiContext: result.aiContext,
                  summary: result.summary,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Analysis failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "check-ai-context-status",
    "Check which videos have AI-generated context/analysis and which are pending.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/videos/ai-context-status");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to check status: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "check-embedding-status",
    "Check which videos have semantic embeddings and which are pending.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/videos/embedding-status");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to check status: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "recalculate-scores",
    "Trigger recommendation score recalculation for all videos (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/recalculate-scores", "POST");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to recalculate: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-creator-analytics",
    "Get detailed analytics for a creator (views, likes, revenue, engagement).",
    {
      userId: z.string().describe("Creator's user ID or googleId"),
    },
    async ({ userId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/videos/creator/analytics/${userId}`);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to get analytics: ${error.message}` }],
          isError: true,
        };
      }
    }
  );
}
