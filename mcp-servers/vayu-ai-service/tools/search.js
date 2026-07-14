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

export function registerSearchTools(server, backendUrl) {
  server.tool(
    "search-videos",
    "Search videos by title, description, or tags.",
    {
      query: z.string().describe("Search query"),
      limit: z.number().optional().describe("Number of results (default: 20)"),
    },
    async ({ query, limit }) => {
      try {
        const result = await apiCall(
          backendUrl,
          `/api/search/videos?q=${encodeURIComponent(query)}&limit=${limit || 20}`
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Search failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-feedback-stats",
    "Get user feedback statistics.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/feedback/stats");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-referral-stats",
    "Get referral system statistics.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/referrals/stats");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );
}
