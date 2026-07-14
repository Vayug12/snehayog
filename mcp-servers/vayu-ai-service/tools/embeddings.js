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

export function registerEmbeddingTools(server, backendUrl) {
  server.tool(
    "generate-embedding",
    "Generate a 384-dimensional semantic embedding vector for text using Gemini.",
    {
      text: z.string().describe("Text to generate embedding for"),
    },
    async ({ text }) => {
      try {
        const result = await apiCall(backendUrl, "/api/search/embedding", "POST", { text });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  text,
                  dimensions: result.embedding?.length || 0,
                  embedding: result.embedding,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Embedding generation failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "semantic-search",
    "Search videos semantically using AI embeddings. Finds conceptually similar content.",
    {
      query: z.string().describe("Natural language search query"),
      limit: z.number().optional().describe("Number of results to return (default: 10)"),
    },
    async ({ query, limit }) => {
      try {
        const result = await apiCall(backendUrl, "/api/search/videos", "GET");
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  query,
                  resultsCount: result.length || result.videos?.length || 0,
                  results: result,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Semantic search failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "search-creators",
    "Search for creators/users by name or username.",
    {
      query: z.string().describe("Search query (name or username)"),
      limit: z.number().optional().describe("Number of results (default: 20)"),
    },
    async ({ query, limit }) => {
      try {
        const result = await apiCall(
          backendUrl,
          `/api/search/creators?q=${encodeURIComponent(query)}&limit=${limit || 20}`
        );
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Creator search failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );
}
