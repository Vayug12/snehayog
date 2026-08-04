/**
 * Store product → ad credits. **This map is the only place credits are decided.**
 *
 * Never derive credits from a price the client (or even the webhook payload)
 * reports. A client that can name its own price can name its own credit
 * balance; and a store price is a local-currency number that changes with
 * region, promotions, and tax treatment, none of which should move the amount
 * of inventory a purchase buys.
 *
 * Because this lives server-side only, a change to the fee tier, to GST
 * treatment, or to pricing is one edit here plus a Play Console change — no
 * client release.
 *
 * ---
 *
 * Pricing note (see AD_CREDITS_PLAN.md §3.2): the store takes its cut off the
 * top, so every price must be grossed up — `price = credits / (1 − storeFee)`.
 * Both rows below are priced to clear even at Google's **30%** tier
 * (credits ≤ 0.70 × price), so the unresolved 15%-vs-30% question cannot make
 * either one sell at a loss. At the 15% tier they carry ₹11.65 and ₹26.65 of
 * margin respectively. GST treatment is still a question for a CA, and it
 * changes the formula — but not enough to invert either row.
 *
 * **Why the packs are this small.** The binding constraint is not what an
 * advertiser will pay, it is how much inventory exists to deliver against.
 * Billable impressions run ~320/day at a ₹20 banner CPM, so the platform can
 * absorb roughly ₹6.40/day of ad spend in total. A 1,000-credit pack — the old
 * entry tier — is five months of that, and the old 25,000-credit pack was over
 * a decade. Selling a pack that cannot be delivered is a refund and a one-star
 * review with extra steps. Sized against real throughput, 30 credits clears in
 * ~5 days and 100 in ~16.
 *
 * Add larger tiers back when billable impressions clear ~1,500/day. Re-measure
 * before doing so — this note is a snapshot of a number that has been roughly
 * 2.5x'ing month over month, not a ceiling.
 */

/**
 * Consumables, not subscriptions, and deliberately no entitlements —
 * an entitlement models "does the user have access", which is not what a
 * spendable balance is.
 */
export const AD_CREDIT_PRODUCTS = Object.freeze({
  ad_credits_30: Object.freeze({
    credits: 30,
    label: '30 credits',
    suggestedPriceINR: 49
  }),
  ad_credits_100: Object.freeze({
    credits: 100,
    label: '100 credits',
    suggestedPriceINR: 149
  })
});

/** RevenueCat Offering that carries the packages above. */
export const AD_CREDITS_OFFERING_ID = 'ad_credits';

/**
 * Credits for a store product id, or `null` if we do not sell it.
 *
 * `null` is meaningful: the webhook answers 200 to an unknown product (so
 * RevenueCat stops retrying something that can never succeed) but credits
 * nothing and logs loudly. Guessing a credit amount here would be inventing
 * money for a product we never priced.
 */
export const creditsForProduct = (productId) => {
  if (!productId || typeof productId !== 'string') return null;

  // Play appends the base plan / offer to some ids ("sku:base-plan"); the
  // product is the part before the colon.
  const normalised = productId.split(':')[0].trim();
  return AD_CREDIT_PRODUCTS[normalised]?.credits ?? null;
};

export const isKnownProduct = (productId) => creditsForProduct(productId) !== null;

export default { AD_CREDIT_PRODUCTS, AD_CREDITS_OFFERING_ID, creditsForProduct, isKnownProduct };
