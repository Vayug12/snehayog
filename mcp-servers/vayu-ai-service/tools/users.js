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

export function registerUserTools(server, backendUrl) {
  server.tool(
    "get-user-profile",
    "Get user profile details by user ID.",
    {
      userId: z.string().describe("User ID or Google ID"),
    },
    async ({ userId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/users/${userId}`);
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
    "get-leaderboard",
    "Get global creator leaderboard (top earners).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/users/leaderboard/global");
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
    "get-subscribers",
    "Get list of a creator's subscribers.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/users/subscribers");
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
    "get-following",
    "Get list of users that the current user is following.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/users/following/list");
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
    "get-payout-stats",
    "Get creator payout statistics (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/creator-payouts/stats");
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
    "get-creator-revenue",
    "Get ad revenue summary for a creator.",
    {
      userId: z.string().describe("Creator's user ID"),
    },
    async ({ userId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/ads/creator/revenue/${userId}`);
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
