import axios from 'axios';

/**
 * aiAgentService — communicates with the VayugAI FastAPI server.
 *
 * The VayugAI agent runs on a separate process (port 7860 by default).
 * It accepts a prompt, runs the full pipeline, and publishes the video
 * to Vayug automatically via its own publishing_agent.
 *
 * ENV variables required:
 *   AI_AGENT_BASE_URL — base URL of the VayugAI FastAPI server
 *                       e.g. http://localhost:7860
 */

export const AGENT_BASE_URL = process.env.AI_AGENT_BASE_URL || 'http://localhost:7860';

/**
 * Public base URL of THIS backend, reachable by the AI agent for webhook callbacks.
 * Falls back to BASE_URL (already used elsewhere) then localhost.
 */
export const BACKEND_PUBLIC_URL =
  process.env.VIDEO_GEN_CALLBACK_BASE_URL ||
  process.env.BASE_URL ||
  'http://localhost:5001';

/** Shared secret the agent must echo back on the webhook call. */
export const WEBHOOK_SECRET = process.env.VIDEO_GEN_WEBHOOK_SECRET || '';

/** Timeout for the async trigger call (5 seconds — agent just needs to ACK) */
const TRIGGER_TIMEOUT_MS = 10_000;

/** Timeout for a sync generate call (10 minutes — video generation is slow) */
const SYNC_TIMEOUT_MS = 10 * 60 * 1000;

/** Timeout for health check (45 seconds — Hugging Face Spaces can take up to 60s to cold-start) */
const HEALTH_TIMEOUT_MS = 45_000;

/**
 * Trigger async video generation on the AI agent.
 * The agent runs the pipeline in a background task and, when finished,
 * calls back to `callbackUrl` with the resulting video URL. This function
 * only awaits the agent's immediate ACK — NOT the full generation.
 *
 * @param {object} params
 * @param {string} params.jobId        — Our VideoGenJob id (agent echoes it back)
 * @param {string} params.prompt       — User prompt
 * @param {string} [params.category]   — Optional category hint
 * @param {string} [params.audience]   — Optional target audience hint
 * @returns {Promise<{ success: boolean, message: string }>} the agent's ACK
 */
export async function triggerVideoGeneration({ jobId, prompt, category = null, audience = null }) {
  const callbackUrl = `${BACKEND_PUBLIC_URL}/api/video-gen/webhook/${jobId}`;
  console.log(`📤 [VideoGen] Sending trigger request to: ${AGENT_BASE_URL}/generate`);
  console.log(`   Payload:`, { jobId, prompt, category, audience, callbackUrl });

  try {
    const response = await axios.post(
      `${AGENT_BASE_URL}/generate`,
      {
        job_id: jobId,
        prompt,
        category,
        audience,
        // Where and how the agent reports completion back to us.
        callback_url: callbackUrl,
        callback_secret: WEBHOOK_SECRET,
      },
      { timeout: TRIGGER_TIMEOUT_MS }
    );
    console.log(`📥 [VideoGen] Trigger ACK response:`, response.data);
    return response.data;
  } catch (err) {
    console.error(`❌ [VideoGen] triggerVideoGeneration request failed: ${err.message}`);
    if (err.response) {
      console.error(`   Response Status: ${err.response.status}`);
      console.error(`   Response Data:`, typeof err.response.data === 'object' ? JSON.stringify(err.response.data) : err.response.data);
    }
    throw err;
  }
}

/**
 * Trigger synchronous video generation (waits for full completion).
 * Use for testing only — production should use the async endpoint.
 *
 * @param {object} params
 * @param {string} params.prompt
 * @param {string} [params.category]
 * @param {string} [params.audience]
 * @returns {Promise<object>} Full pipeline result including video URL
 */
export async function triggerVideoGenerationSync({ prompt, category = null, audience = null }) {
  console.log(`📤 [VideoGen] Sending sync trigger request to: ${AGENT_BASE_URL}/generate-sync`);
  
  try {
    const response = await axios.post(
      `${AGENT_BASE_URL}/generate-sync`,
      { prompt, category, audience },
      { timeout: SYNC_TIMEOUT_MS }
    );
    console.log(`📥 [VideoGen] Sync trigger response success.`);
    return response.data;
  } catch (err) {
    console.error(`❌ [VideoGen] triggerVideoGenerationSync request failed: ${err.message}`);
    if (err.response) {
      console.error(`   Response Status: ${err.response.status}`);
      console.error(`   Response Data:`, typeof err.response.data === 'object' ? JSON.stringify(err.response.data) : err.response.data);
    }
    throw err;
  }
}

/**
 * Check if the AI agent server is reachable.
 * Retries up to 3 times to allow Hugging Face Spaces to cold-start.
 * @returns {Promise<boolean>}
 */
export async function isAgentHealthy() {
  const MAX_RETRIES = 3;
  console.log(`🔍 [VideoGen] Checking health of AI Agent at: ${AGENT_BASE_URL} (Timeout: ${HEALTH_TIMEOUT_MS}ms)`);
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      await axios.get(`${AGENT_BASE_URL}/`, { 
        timeout: HEALTH_TIMEOUT_MS,
        validateStatus: (status) => (status >= 200 && status < 300) || status === 404
      });
      console.log(`✅ [VideoGen] Health check passed on attempt ${attempt}`);
      return true;
    } catch (err) {
      console.warn(`⚠️ [VideoGen] Health check attempt ${attempt}/${MAX_RETRIES} failed: ${err.message}`);
      if (err.response) {
        console.warn(`   Response Status: ${err.response.status}`);
        console.warn(`   Response Headers:`, JSON.stringify(err.response.headers));
        console.warn(`   Response Data:`, typeof err.response.data === 'object' ? JSON.stringify(err.response.data) : err.response.data);
      } else if (err.request) {
        console.warn(`   No response received. The host might be unreachable or cold-starting.`);
      }
      
      if (attempt < MAX_RETRIES) {
        console.log(`   Waiting 5 seconds before next retry...`);
        await new Promise((r) => setTimeout(r, 5000));
      }
    }
  }
  console.error(`❌ [VideoGen] AI Agent health check failed after ${MAX_RETRIES} attempts. Agent is offline.`);
  return false;
}

export default { triggerVideoGeneration, triggerVideoGenerationSync, isAgentHealthy, AGENT_BASE_URL };
