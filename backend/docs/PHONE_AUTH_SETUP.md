# Vayu phone authentication setup

Phone authentication is delivered by 2Factor from the backend. The Flutter app
never receives the provider API key. Vayu continues to issue its own access and
refresh tokens after OTP verification.

## Local development

Add these values to `backend/.env`:

```env
PHONE_OTP_PROVIDER=mock
OTP_HASH_SECRET=replace-with-a-long-random-secret
```

The API returns `debugOtp` only when the mock provider is used outside
production. The Flutter OTP sheet displays it for local testing.

## 2Factor production setup

1. Create a 2Factor account and complete the required India DLT sender/template
   onboarding.
2. Purchase a small OTP balance and test Jio, Airtel and Vi numbers before
   enabling the UI for all users.
3. Set the production environment variables:

```env
NODE_ENV=production
PHONE_OTP_PROVIDER=2factor
TWO_FACTOR_API_KEY=your-server-side-api-key
TWO_FACTOR_OTP_TEMPLATE=your-approved-template-name
OTP_HASH_SECRET=another-long-random-production-secret
```

4. Restart the backend. Never put these values in Flutter assets, Dart defines,
   Remote Config, source control or client logs.

## API flow

```text
POST /api/auth/phone/request  { phoneNumber }
POST /api/auth/phone/verify   { challengeId, otp, deviceId, deviceName, platform }
```

Verification returns the same `accessToken`, `refreshToken` and `user` shape as
Google authentication. If `/phone/verify` receives a valid existing Vayu bearer
token, the phone is linked to that account instead of creating another account.

## Production checks

- Confirm the approved DLT template exactly matches the configured OTP message.
- Confirm OTP delivery on Jio, Airtel and Vi before broad rollout.
- Keep Google sign-in visible as a fallback.
- Monitor HTTP 429, provider 5xx, delivery time and verification conversion.
- Keep `PHONE_OTP_PROVIDER=mock` blocked in production (the backend enforces it).
