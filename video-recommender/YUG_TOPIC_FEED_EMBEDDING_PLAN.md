# Yug Topic Feed via Existing-Video Embeddings

## Status

**Deferred design note.** This document records the agreed idea; it is not an
approved implementation plan yet.

## Goal

In the **Yug tab**, a user should be able to ask for a topic, for example:

> "Mujhe coding wali videos dikhao"  
> "Cricket ki videos chahiye"

The feed should then show only relevant existing Yug videos. Clearing the topic
returns the user to the normal Yug feed.

## Explicit scope and non-goals

- Process **existing completed videos only** in a one-time/manual batch.
- Do **not** add embedding generation to the upload pipeline.
- Do **not** add, require, or generate a video-description feature.
- Do not rely on a user’s personal computer being online after the batch is
  complete.
- Pinecone is the vector retrieval store; MongoDB remains the source of truth
  for the actual video record and access checks.

Consequently, videos uploaded after the batch will not be eligible for topic
feed results until a later manual re-index batch is run.

## Intended data flow

```text
One-time/manual batch
Existing Yug video -> sample frames locally -> video embedding -> Pinecone

At feed time
User topic -> query vector -> Pinecone matching IDs -> MongoDB validation
-> Yug topic-only feed
```

The batch must store the actual MongoDB `Video._id` as the Pinecone vector ID.
It must not generate a separate random ID, otherwise Pinecone results cannot be
mapped reliably back to Yug feed videos.

## Video embedding input

The primary input is sampled video frames. The proposed model family is CLIP,
which creates a shared image/text vector space.

- Sample a small, fixed number of representative frames per video.
- Encode frames locally and average/normalise them into one video vector.
- No `description` field is required.
- Existing `videoName`, `category`, or `tags` may be used later as an optional
  quality improvement, but this design does not depend on them.

For Hindi and multilingual user topics, the compatible query encoder considered
is `sentence-transformers/clip-ViT-B-32-multilingual-v1`. It maps text from
50+ languages into the same space as original CLIP image vectors. Model
reference: https://huggingface.co/sentence-transformers/clip-ViT-B-32-multilingual-v1

## Important blocker: user-query embedding

> **A user query can only be semantically searched after it is converted to a
> vector. A one-time video embedding batch does not solve this runtime step.**

The video vectors can be calculated once and stored forever, but a previously
unseen query such as "mujhe coding wali videos dikhao" still needs a query
vector at the time of search. There is no production-grade, unlimited, and
completely free hosted service that removes this compute requirement.

The query embedding itself is tiny (a 512-number vector, roughly 2 KB). The
heavy part is loading and running the encoder model.

### Option A — fixed topic catalogue (recommended for zero runtime cost)

Support a controlled set of topics, such as `coding`, `cricket`, `comedy`,
`news`, and `cooking`.

1. Generate and save a vector once per canonical topic, offline, using the
   same model used for retrieval.
2. Maintain Hindi, Hinglish, and English aliases in the backend.
3. At runtime, normalise the query and map it to a canonical topic.
4. Look up its saved vector and query Pinecone. No model runs for the user.

Examples:

```text
coding  <- coding, code, programming, developer, python, java, javascript,
           app banana, web development
cricket <- cricket, IPL, match, batting, bowling, wicket
```

Unknown topics should show an honest empty/unsupported-topic state and suggested
supported topics. They must not silently fall back to unrelated normal-feed
videos.

**Trade-off:** this is reliable, fast, and zero query-time model cost, but it
does not understand every arbitrary topic.

### Option B — local model on the backend

Host the compatible text encoder next to the backend and create a vector for
every new query. Cache normalised query vectors in Redis to avoid repeat work.

**Trade-off:** supports open-ended queries, but consumes backend RAM/CPU. It is
not an embedding API cost, but it is still infrastructure cost and needs an
always-available process.

### Option C — Hugging Face hosted inference

The backend can send the query to Hugging Face Inference Providers and receive
an embedding. The Hugging Face token must remain a backend secret; it must never
be shipped in the Flutter app.

This is suitable for a prototype, but not a "free forever" production design.
At the time of writing, a free Hugging Face account receives $0.10 monthly
Inference Provider credits; requests become pay-as-you-go after that. Reference:
https://huggingface.co/docs/inference-providers/pricing

Caching repeated queries helps, but every new unique query can still consume
credits.

### Option D — on-device query embedding (not recommended now)

The model needed to remain compatible with the selected CLIP video vectors is
large: the full multilingual CLIP text model is approximately 539 MB on disk.

- A 4 GB or 6 GB Android phone may technically run a quantised native model.
- In Vayu, Flutter, HLS/video playback, image caches, and the OS already use
  significant memory.
- The model download, cold-start latency, battery use, and out-of-memory risk
  make this a poor production choice for low-memory devices.

A smaller unrelated text model cannot be used directly: it produces vectors in
a different space and would require every video to be re-embedded with a new,
compatible design.

## Decision required before implementation

Choose one of these product commitments:

1. **Zero added runtime cost:** ship Option A, a fixed catalogue of popular
   topics and aliases.
2. **Open-ended natural-language topics:** accept either backend compute
   (Option B) or paid/credit-limited hosted inference (Option C).

Do not claim arbitrary-topic semantic search is permanently free without making
one of those trade-offs.

## Pinecone and production behaviour

Pinecone can be used on its Starter/free plan while usage stays within its
current quotas. It is the simplest index choice because this repository already
contains Pinecone connection/upsert/search code. Current pricing/limits must be
rechecked before launch:

- https://www.pinecone.io/pricing/
- https://docs.pinecone.io/guides/organizations/manage-billing/downgrade-billing-plan

For a topic search:

1. Query Pinecone for a sufficiently large candidate set with the topic vector.
2. Apply a calibrated minimum similarity threshold.
3. Fetch returned IDs from MongoDB, preserving Pinecone rank.
4. Re-check `processingStatus`, `videoType: 'yug'`, visibility, and subscriber
   permissions in MongoDB before returning a video.
5. Do not use Pinecone metadata as the only authorization decision.

If the threshold leaves too few results, return fewer videos or an empty state;
never fill the strict topic feed with unrelated videos.

## Yug feed integration

Topic mode must be separate from the standard Yug feed queue. The normal queue
can contain unrelated content, so filtering it after it has been popped is not
reliable.

Suggested API shape:

```http
POST /api/feed/topic-sessions
{ "topic": "coding", "videoType": "yug" }

GET /api/feed/topic-sessions/:sessionId?cursor=...

DELETE /api/feed/topic-sessions/:sessionId
```

The backend can cache ordered candidate IDs in Redis under a key such as:

```text
feed:topic:{userId}:{videoType}:{topicHash}
```

The Flutter Yug UI needs a visible active-topic chip and a clear action. On
clear, it switches back to the unchanged standard Yug feed.

## Current repository findings to address later

The codebase contains a Python `video-recommender` proof of concept and existing
backend semantic fields, but it is not wired into the production Yug flow.

- `video-recommender/src/storage/vector_db.py` has Pinecone connection/upsert/
  search code, but it currently needs fixes before use.
- The Python processing route generates a new video ID instead of receiving the
  MongoDB ID.
- Its fusion code attempts to add a 512-length visual array and 64-length
  metadata array, which is invalid.
- The Python vector database file uses `np.ndarray` without importing NumPy.
- Its configuration says 576 dimensions, while the Node `Video` model documents
  a different embedding dimension/version. Vector dimension and model version
  must be unified before indexing.
- The existing Node video pipeline contains only download, HLS transcode, and
  cleanup steps. This is acceptable because embeddings are deliberately kept
  outside the upload pipeline.
- The current Yug feed/recommendation path uses its own MongoDB vector fields
  and general queue; topic mode should be added as a parallel read path.

Create a new Pinecone index for the final selected dimension/model version (for
example, `video-topic-v2`). Do not mix vectors created by different models in
one index.

## Deferred implementation phases

1. Select Option A or Option B/C above.
2. Repair and simplify the batch embedding code for the final model/vector
   dimension.
3. Create a resumable, rate-limited manual batch job for all completed Yug
   videos. Download/process sequentially and delete temporary video/frame files.
4. Create the Pinecone index and upsert vectors using MongoDB video IDs.
5. Add topic-session backend endpoints and MongoDB revalidation.
6. Add Yug-tab topic input, active-topic UI, pagination, and clear action.
7. Test with labelled videos and Hindi/Hinglish queries; tune the similarity
   threshold before release.

## Acceptance criteria

- Existing completed Yug videos can be indexed without changing the upload flow.
- `coding` and `cricket` topic requests return only matching, authorised Yug
  videos.
- Clearing topic mode restores normal Yug feed behaviour.
- Deleted, incomplete, private, or subscriber-restricted videos never leak via
  Pinecone results.
- The selected query-vector strategy remains available whenever users can use
  the feature.
- The UI gives a clear empty state for unsupported topics or insufficient
  matches.
