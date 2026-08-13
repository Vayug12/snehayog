/**
 * Progress Heartbeat
 *
 * Sirf ek sawaal ka jawab deta hai: "pichhli baar kaam AAGE kab badha tha?"
 *
 * Ye "job chal raha hai" se alag cheez hai, aur yehi farak zaroori hai. Hung
 * FFmpeg ke liye BullMQ job hamesha 'active' rehta hai — process zinda hai, lock
 * renew ho raha hai, bas progress ruk gaya hai. Job ki maujoodgi dekhne wala koi
 * bhi check use healthy batayega.
 *
 * Isliye worker ka stall watchdog wall-clock ya BullMQ events ke bajaye is
 * timestamp ko dekhta hai: dheema encode bhi tick karta rehta hai, hang nahi
 * karta. Ghanton lamba genuine job isse kabhi nahi marta.
 *
 * Worker machine ke bahar (API process) ye sirf ek timestamp likhta hai —
 * watchdog wahan chalta hi nahi, to koi asar nahi.
 */

let lastBeatAt = Date.now();

/** Kaam aage badha. Progress ke har source se call hona chahiye. */
export const beat = () => {
  lastBeatAt = Date.now();
};

/** Pichhle progress signal ko kitna time ho gaya. */
export const msSinceBeat = () => Date.now() - lastBeatAt;
