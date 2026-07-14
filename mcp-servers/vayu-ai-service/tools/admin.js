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

export function registerAdminTools(server, backendUrl) {
  server.tool(
    "get-platform-stats",
    "Get overall platform statistics (total users, videos, revenue, etc.).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/stats");
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
    "get-daily-videos",
    "Get count of videos uploaded per day (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/videos/daily");
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
    "get-all-creators",
    "Get summary of all creators (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/creators");
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
    "get-monthly-earnings",
    "Get monthly earnings for all creators (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/creators/monthly-earnings");
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
    "get-all-feedback",
    "Get all user feedback submissions (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/feedback");
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
    "get-report-stats",
    "Get content report statistics (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/report-stats");
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
    "get-recommender-stats",
    "Get recommendation engine statistics (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/recommender/stats");
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
    "get-user-behavior",
    "Get user behavior metrics (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/user-behavior/stats");
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
    "broadcast-email",
    "Send broadcast email to all users (admin). Use with caution!",
    {
      subject: z.string().describe("Email subject"),
      content: z.string().describe("Email HTML content"),
    },
    async ({ subject, content }) => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/email/blast", "POST", {
          subject,
          content,
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
    "get-app-config",
    "Get current app configuration (feature flags, kill switch, etc.).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/app-config");
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
    "check-kill-switch",
    "Check if the app kill switch is active.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/app-config/kill-switch");
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
    "health-check",
    "Check if the Vayu backend is running and healthy.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/health");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Backend is DOWN: ${error.message}` }],
          isError: true,
        };
      }
    }
  );
}
