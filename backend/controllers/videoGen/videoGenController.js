import VideoGenJob from '../../models/VideoGenJob.js';
import { triggerVideoGeneration, isAgentHealthy, AGENT_BASE_URL } from '../../services/videoGen/aiAgentService.js';
import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import eventBus from '../../utils/eventBus.js';

/** Event name used to push job status to connected SSE clients. */
const VIDEOGEN_EVENT = 'videogen-status';

/** Build the payload shape shared by SSE snapshots and status responses. */
const toStatusPayload = (job) => ({
  jobId: job._id ? job._id.toString() : job.jobId,
  status: job.status,
  videoUrl: job.videoUrl ?? null,
  downloadUrl: job.downloadUrl ?? null,
  error: job.errorMessage ?? null,
});

/**
 * POST /api/video-gen/generate
 *
 * Accepts a user prompt, creates a VideoGenJob in DB, then fires off
 * an async request to the VayugAI FastAPI agent. The agent handles the
 * full pipeline (research → script → clips → voice → edit → publish).
 *
 * The client receives a `jobId` immediately, then polls `/status/:jobId`
 * to track progress.
 */
export const generateVideo = async (req, res) => {
  const { prompt, category, audience } = req.body;

  // 1. Validate prompt
  if (!prompt || typeof prompt !== 'string' || prompt.trim().length < 5) {
    return res.status(400).json({
      error: 'A valid prompt is required (minimum 5 characters).'
    });
  }

  if (prompt.trim().length > 1000) {
    return res.status(400).json({
      error: 'Prompt is too long. Maximum 1000 characters.'
    });
  }

  // 2. Check if the AI agent is reachable before creating the job
  console.log(`🔍 [VideoGen] Checking AI Agent health status...`);
  const agentOnline = await isAgentHealthy();
  if (!agentOnline) {
    console.warn(`⚠️ [VideoGen] AI Agent at ${AGENT_BASE_URL} is offline. Rejecting request.`);
    return res.status(503).json({
      error: `AI video generation service is currently offline (Target: ${AGENT_BASE_URL}). Please try again later.`
    });
  }
  console.log(`✅ [VideoGen] AI Agent is online. Proceeding with job creation.`);

  // 3. Create a job record in MongoDB
  let job;
  try {
    job = await VideoGenJob.create({
      userId: req.user._id,
      prompt: prompt.trim(),
      category: category?.trim() || null,
      audience: audience?.trim() || null,
      status: 'processing',
    });
    console.log(`📝 [VideoGen] Created job ${job._id} for user ${req.user._id}`);
  } catch (err) {
    console.error('❌ [VideoGen] Failed to create job in MongoDB:', err.message);
    return res.status(500).json({ error: 'Failed to initiate video generation.' });
  }

  // 4. Respond immediately to client with jobId
  res.status(202).json({
    success: true,
    message: 'Video generation started. Use jobId to track progress.',
    jobId: job._id.toString(),
  });

  // 5. Fire-and-forget: trigger agent in background.
  //    IMPORTANT: the agent's response here is only an ACK that it accepted the
  //    job — the video does NOT exist yet. The real completion arrives later via
  //    the webhook (POST /api/video-gen/webhook/:jobId). So on a successful ACK
  //    we leave the job in `processing`; we only mark it `failed` if the agent
  //    could not even accept the request.
  console.log(`🚀 [VideoGen] Triggering background video generation for job ${job._id}...`);
  triggerVideoGeneration({
    jobId: job._id.toString(),
    prompt: prompt.trim(),
    category: category?.trim() || null,
    audience: audience?.trim() || null,
  })
    .then((result) => {
      if (result?.success === false) {
        // Agent explicitly rejected the job at ACK time.
        const errorMsg = result?.error || 'Agent rejected the generation request.';
        return VideoGenJob.findByIdAndUpdate(job._id, {
          status: 'failed',
          errorMessage: errorMsg,
        }).then(() => {
          console.error(`❌ [VideoGen] Job ${job._id} rejected by agent: ${errorMsg}`);
        });
      }
      console.log(`✅ [VideoGen] Job ${job._id} accepted by agent. Awaiting webhook.`);
    })
    .catch(async (err) => {
      let errMsg = err.message || 'Agent communication error.';
      if (err.response) {
        errMsg += ` (Status: ${err.response.status}, Data: ${typeof err.response.data === 'object' ? JSON.stringify(err.response.data) : err.response.data})`;
      }
      await VideoGenJob.findByIdAndUpdate(job._id, {
        status: 'failed',
        errorMessage: errMsg,
      });
      console.error(`❌ [VideoGen] Job ${job._id} communication error:`, err.message);
      if (err.response) {
        console.error(`   Agent Response Status: ${err.response.status}`);
        console.error(`   Agent Response Data:`, err.response.data);
      }
    });
};

/**
 * POST /api/video-gen/webhook/:jobId
 *
 * Called by the VayugAI agent when the pipeline finishes (or fails).
 * Authenticated by a shared secret (see verifyWebhookSecret middleware), NOT
 * a user token — the agent is a server.
 *
 * Expected body:
 *   {
 *     status: 'completed' | 'failed',
 *     video_url?: string,   // required when completed
 *     video_id?: string,    // optional Vayug Video document id
 *     error?: string,       // when failed
 *     metadata?: object     // title, tags, duration, etc.
 *   }
 */
export const handleAgentWebhook = async (req, res) => {
  const { jobId } = req.params;
  const { status, video_url, download_url, download_key, video_id, error, metadata } = req.body || {};

  if (!jobId || jobId.length !== 24) {
    return res.status(400).json({ error: 'Invalid jobId.' });
  }

  if (status !== 'completed' && status !== 'failed') {
    return res.status(400).json({ error: "status must be 'completed' or 'failed'." });
  }

  try {
    const job = await VideoGenJob.findById(jobId);
    if (!job) {
      return res.status(404).json({ error: 'Job not found.' });
    }

    // Idempotency: if the job already reached a terminal state, don't overwrite.
    // The agent may retry the webhook; treat repeats as success.
    if (job.status === 'completed' || job.status === 'failed') {
      console.log(`ℹ️ [VideoGen] Webhook for already-${job.status} job ${jobId} ignored.`);
      return res.status(200).json({ success: true, message: 'Job already finalized.' });
    }

    if (status === 'failed') {
      job.status = 'failed';
      job.errorMessage = (typeof error === 'string' && error.trim()) || 'Generation failed on agent.';
      await job.save();
      eventBus.emit(VIDEOGEN_EVENT, toStatusPayload(job));
      console.error(`❌ [VideoGen] Job ${jobId} marked failed via webhook: ${job.errorMessage}`);
      return res.status(200).json({ success: true });
    }

    // status === 'completed' — a video URL is mandatory, otherwise it's not
    // actually usable. Guard against the exact "completed but no URL" bug.
    const url = typeof video_url === 'string' ? video_url.trim() : '';
    if (!url) {
      job.status = 'failed';
      job.errorMessage = 'Agent reported completion without a video URL.';
      await job.save();
      eventBus.emit(VIDEOGEN_EVENT, toStatusPayload(job));
      console.error(`❌ [VideoGen] Job ${jobId} completed without video_url. Marked failed.`);
      return res.status(400).json({ error: 'video_url is required when status is completed.' });
    }

    job.status = 'completed';
    job.videoUrl = url;
    // Direct MP4 for gallery download; fall back to the stream URL if absent.
    job.downloadUrl = (typeof download_url === 'string' && download_url.trim()) || url;
    job.downloadKey = (typeof download_key === 'string' && download_key.trim()) || null;
    job.videoId = video_id || null;
    job.agentMetadata = metadata || null;
    job.errorMessage = null;
    await job.save();
    eventBus.emit(VIDEOGEN_EVENT, toStatusPayload(job));

    console.log(`✅ [VideoGen] Job ${jobId} completed via webhook. URL: ${url}`);
    return res.status(200).json({ success: true });
  } catch (err) {
    if (err.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid jobId format.' });
    }
    console.error(`❌ [VideoGen] Webhook handling error for job ${jobId}:`, err.message);
    return res.status(500).json({ error: 'Failed to process webhook.' });
  }
};

/**
 * GET /api/video-gen/status/:jobId
 *
 * Returns the current status of a video generation job.
 * Only the owner of the job can poll its status.
 */
export const getJobStatus = async (req, res) => {
  const { jobId } = req.params;

  if (!jobId || jobId.length !== 24) {
    return res.status(400).json({ error: 'Invalid jobId.' });
  }

  try {
    const job = await VideoGenJob.findById(jobId).select(
      'userId status prompt videoId videoUrl downloadUrl errorMessage agentMetadata createdAt updatedAt'
    );

    if (!job) {
      return res.status(404).json({ error: 'Job not found.' });
    }

    // Only the job owner can check status
    if (job.userId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Access denied.' });
    }

    return res.json({
      jobId: job._id,
      status: job.status,
      prompt: job.prompt,
      videoId: job.videoId,
      videoUrl: job.videoUrl,
      downloadUrl: job.downloadUrl,
      error: job.errorMessage,
      metadata: job.agentMetadata,
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
    });
  } catch (err) {
    if (err.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid jobId format.' });
    }
    console.error('❌ [VideoGen] Status check error:', err.message);
    return res.status(500).json({ error: 'Failed to retrieve job status.' });
  }
};

/**
 * GET /api/video-gen/stream/:jobId
 *
 * Server-Sent Events stream of a job's status. Replaces client polling: the
 * client opens one connection and receives a push when the webhook finalizes
 * the job. Only the job owner may subscribe.
 *
 * Emits an immediate snapshot, then `videogen-status` events, then closes the
 * connection once the job reaches a terminal state. The client should fall back
 * to polling if this connection cannot be established or drops early.
 */
export const streamJobStatus = async (req, res) => {
  const { jobId } = req.params;

  if (!jobId || jobId.length !== 24) {
    return res.status(400).json({ error: 'Invalid jobId.' });
  }

  // Auth + existence check before upgrading to a stream.
  let job;
  try {
    job = await VideoGenJob.findById(jobId).select('userId status videoUrl downloadUrl errorMessage');
  } catch (err) {
    if (err.name === 'CastError') return res.status(400).json({ error: 'Invalid jobId format.' });
    console.error('❌ [VideoGen] SSE open error:', err.message);
    return res.status(500).json({ error: 'Failed to open status stream.' });
  }

  if (!job) return res.status(404).json({ error: 'Job not found.' });
  if (job.userId.toString() !== req.user._id.toString()) {
    return res.status(403).json({ error: 'Access denied.' });
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.write('retry: 5000\n\n');

  let closed = false;
  const send = (payload) => {
    if (closed) return;
    res.write(`data: ${JSON.stringify(payload)}\n\n`);
    if (typeof res.flush === 'function') res.flush();
  };

  const onUpdate = (update) => {
    if (!update || update.jobId !== jobId) return;
    send(update);
    if (update.status === 'completed' || update.status === 'failed') {
      finish();
    }
  };

  // Keep-alive comment so proxies (Fly.io) don't drop the idle connection.
  const keepAlive = setInterval(() => {
    if (closed) return;
    res.write(': keep-alive\n\n');
    if (typeof res.flush === 'function') res.flush();
  }, 25000);

  const finish = () => {
    if (closed) return;
    closed = true;
    clearInterval(keepAlive);
    eventBus.removeListener(VIDEOGEN_EVENT, onUpdate);
    res.end();
  };

  // Subscribe FIRST, then re-read fresh state. This closes the race where the
  // webhook finalizes the job between our initial read and subscription.
  eventBus.on(VIDEOGEN_EVENT, onUpdate);
  req.on('close', finish);

  try {
    const fresh = await VideoGenJob.findById(jobId).select('status videoUrl downloadUrl errorMessage');
    if (!fresh) return finish();
    send(toStatusPayload({ ...fresh.toObject(), jobId }));
    if (fresh.status === 'completed' || fresh.status === 'failed') {
      // Already terminal — nothing more will come, so close now.
      finish();
    }
  } catch (err) {
    console.error('❌ [VideoGen] SSE snapshot error:', err.message);
    finish();
  }
};

/**
 * POST /api/video-gen/downloaded/:jobId
 *
 * Called by the app once the user has successfully saved the MP4 to their
 * gallery. Deletes the durable download copy from R2 and clears the download
 * fields so the storage isn't kept forever. Only the job owner may call this.
 *
 * Idempotent: if there is nothing to delete, it still returns success.
 */
export const confirmDownloaded = async (req, res) => {
  const { jobId } = req.params;

  if (!jobId || jobId.length !== 24) {
    return res.status(400).json({ error: 'Invalid jobId.' });
  }

  try {
    const job = await VideoGenJob.findById(jobId).select('userId downloadKey downloadUrl');
    if (!job) {
      return res.status(404).json({ error: 'Job not found.' });
    }

    if (job.userId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Access denied.' });
    }

    // Nothing to clean up — already deleted or no download copy existed.
    if (!job.downloadKey) {
      return res.status(200).json({ success: true, message: 'Nothing to clean up.' });
    }

    try {
      await cloudflareR2Service.deleteFile(job.downloadKey);
      console.log(`🧹 [VideoGen] Deleted download copy from R2: ${job.downloadKey}`);
    } catch (delErr) {
      // Don't fail the request if the object is already gone; just log it.
      console.warn(`⚠️ [VideoGen] Failed to delete R2 object ${job.downloadKey}: ${delErr.message}`);
    }

    // Clear fields regardless — the URL is no longer valid once we've tried to delete.
    await VideoGenJob.findByIdAndUpdate(jobId, {
      downloadUrl: null,
      downloadKey: null,
    });

    return res.status(200).json({ success: true });
  } catch (err) {
    if (err.name === 'CastError') {
      return res.status(400).json({ error: 'Invalid jobId format.' });
    }
    console.error('❌ [VideoGen] Download cleanup error:', err.message);
    return res.status(500).json({ error: 'Failed to clean up download.' });
  }
};
