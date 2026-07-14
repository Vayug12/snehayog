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

export function registerAdTools(server, backendUrl) {
  server.tool(
    "get-ad-campaigns",
    "Get all ad campaigns.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/ads/campaigns");
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
    "create-ad-campaign",
    "Create a new ad campaign.",
    {
      name: z.string().describe("Campaign name"),
      budget: z.number().describe("Campaign budget in INR"),
      targeting: z
        .object({})
        .passthrough()
        .optional()
        .describe("Targeting configuration (interests, demographics)"),
    },
    async ({ name, budget, targeting }) => {
      try {
        const result = await apiCall(backendUrl, "/api/ads/campaigns", "POST", {
          name,
          budget,
          targeting,
        });
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
    "get-ad-analytics",
    "Get analytics for a specific ad (impressions, clicks, CTR).",
    {
      adId: z.string().describe("Ad ID"),
    },
    async ({ adId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/ads/analytics/${adId}`);
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
    "get-ad-categories",
    "Get available video categories for ad targeting.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/ads/available-categories");
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
    "get-targeting-insights",
    "Get AI-powered targeting insights for ad campaigns.",
    {
      campaignId: z.string().optional().describe("Campaign ID (optional)"),
    },
    async ({ campaignId }) => {
      try {
        const result = await apiCall(backendUrl, "/api/ads/targeting/insights", "POST", {
          campaignId,
        });
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
