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

export function registerDubbingTools(server, backendUrl) {
  server.tool(
    "transcribe",
    "Transcribe audio from a video using AI (Whisper). Returns transcribed text.",
    {
      videoUrl: z.string().describe("URL of the video to transcribe"),
      language: z
        .string()
        .optional()
        .describe("Source language code (e.g., 'en', 'hi', 'es'). Auto-detect if not provided."),
    },
    async ({ videoUrl, language }) => {
      try {
        const result = await apiCall(backendUrl, "/api/dubbing/transcribe", "POST", {
          videoUrl,
          language: language || undefined,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Transcription failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "translate-text",
    "Translate text from one language to another using AI.",
    {
      text: z.string().describe("Text to translate"),
      sourceLang: z.string().describe("Source language code (e.g., 'en', 'hi')"),
      targetLang: z.string().describe("Target language code (e.g., 'en', 'hi', 'es', 'fr')"),
    },
    async ({ text, sourceLang, targetLang }) => {
      try {
        const result = await apiCall(backendUrl, "/api/dubbing/translate", "POST", {
          text,
          sourceLang,
          targetLang,
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Translation failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "synthesize-speech",
    "Convert text to speech (TTS) using Edge TTS (free). Returns audio data.",
    {
      text: z.string().describe("Text to convert to speech"),
      voice: z
        .string()
        .optional()
        .describe("Edge TTS voice name (e.g., 'hi-IN-SwaraNeural', 'en-US-AriaNeural')"),
      language: z.string().optional().describe("Language code (e.g., 'en', 'hi')"),
    },
    async ({ text, voice, language }) => {
      try {
        const result = await apiCall(backendUrl, "/api/dubbing/synthesize", "POST", {
          text,
          voice: voice || "alloy",
          language: language || "en",
        });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Speech synthesis failed: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get-dubbing-engine",
    "Get the currently active AI dubbing engine (huggingface or openai).",
    {},
    async () => {
      try {
        const result = await apiCall(backendUrl, "/api/dubbing/engine");
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to get engine: ${error.message}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "set-dubbing-engine",
    "Switch the active AI dubbing engine.",
    {
      engine: z.enum(["huggingface", "openai"]).describe("AI engine to use for dubbing"),
    },
    async ({ engine }) => {
      try {
        const result = await apiCall(backendUrl, "/api/dubbing/engine", "POST", { engine });
        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `Failed to set engine: ${error.message}` }],
          isError: true,
        };
      }
    }
  );
}
