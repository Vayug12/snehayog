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

export function registerVideoTools(server, backendUrl) {
  server.tool(
    "get-video",
    "Get complete details of a video by ID.",
    {
      videoId: z.string().describe("Video ID"),
    },
    async ({ videoId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/videos/${videoId}`);
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
    "get-user-videos",
    "Get all videos uploaded by a specific user.",
    {
      googleId: z.string().describe("User's Google ID"),
    },
    async ({ googleId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/videos/user/${googleId}`);
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
    "delete-video",
    "Delete a video by ID.",
    {
      videoId: z.string().describe("Video ID to delete"),
    },
    async ({ videoId }) => {
      try {
        await apiCall(backendUrl, `/api/videos/${videoId}`, "DELETE");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify({ success: true, message: "Video deleted", videoId }, null, 2),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Delete failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "bulk-delete-videos",
    "Delete multiple videos at once.",
    {
      videoIds: z.array(z.string()).describe("Array of video IDs to delete"),
    },
    async ({ videoIds }) => {
      try {
        const result = await apiCall(backendUrl, "/api/videos/bulk-delete", "POST", { videoIds });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Bulk delete failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-video-feed",
    "Get the main video feed (Yug Feed).",
    {
      page: z.number().optional().describe("Page number (default: 1)"),
      limit: z.number().optional().describe("Videos per page (default: 20)"),
    },
    async ({ page, limit }) => {
      try {
        const result = await apiCall(
          backendUrl,
          `/api/videos?page=${page || 1}&limit=${limit || 20}`
        );
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
    "get-saved-videos",
    "Get user's saved/bookmarked videos.",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/videos/saved");
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
    "get-video-status",
    "Check video processing status (HLS encoding, thumbnail, etc.).",
    {
      videoId: z.string().describe("Video ID"),
    },
    async ({ videoId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/upload/video/${videoId}/status`);
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to get status: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "retry-video-processing",
    "Retry processing for a failed video.",
    {
      videoId: z.string().describe("Video ID to retry"),
    },
    async ({ videoId }) => {
      try {
        const result = await apiCall(backendUrl, `/api/upload/video/${videoId}/retry`, "POST");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Retry failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-flagged-videos",
    "Get all flagged/NSFW videos pending review (admin).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/admin/videos/flagged");
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
