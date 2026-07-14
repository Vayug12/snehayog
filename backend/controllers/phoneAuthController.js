import crypto from 'crypto';
import User from '../models/User.js';
import RefreshToken from '../models/RefreshToken.js';
import PhoneOtpChallenge from '../models/PhoneOtpChallenge.js';
import { generateJWT } from '../utils/verifytoken.js';
import { sendPhoneOtp, getPhoneOtpProvider } from '../services/auth/phoneVerificationService.js';

const OTP_TTL_MINUTES = 5;
const MAX_VERIFY_ATTEMPTS = 5;
const MAX_SENDS_PER_HOUR = 3;

const normalizeIndianPhone = (input) => {
  const digits = String(input || '').replace(/\D/g, '');
  const national = digits.startsWith('91') && digits.length === 12
    ? digits.substring(2)
    : digits;

  if (!/^[6-9]\d{9}$/.test(national)) {
    return null;
  }
  return `+91${national}`;
};

const otpSecret = () => process.env.OTP_HASH_SECRET || process.env.JWT_SECRET;

const hashOtp = (challengeId, otp) => {
  const secret = otpSecret();
  if (!secret) throw new Error('OTP_HASH_SECRET or JWT_SECRET must be configured');
  return crypto
    .createHmac('sha256', secret)
    .update(`${challengeId}:${otp}`)
    .digest('hex');
};

const safeHashEquals = (left, right) => {
  const leftBuffer = Buffer.from(String(left), 'hex');
  const rightBuffer = Buffer.from(String(right), 'hex');
  return leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer);
};

const phoneIdentity = (phoneNumber) => {
  const secret = otpSecret();
  const digest = crypto
    .createHmac('sha256', secret)
    .update(`phone-identity:${phoneNumber}`)
    .digest('hex');
  return {
    identityId: `phone:${digest}`,
    syntheticEmail: `phone-${digest}@auth.vayug.invalid`
  };
};

const maskPhone = (phoneNumber) => `${phoneNumber.substring(0, 3)}******${phoneNumber.slice(-4)}`;

export const requestPhoneOtp = async (req, res) => {
  try {
    const phoneNumber = normalizeIndianPhone(req.body?.phoneNumber);
    if (!phoneNumber) {
      return res.status(400).json({ error: 'Enter a valid Indian mobile number' });
    }

    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const resendCutoff = new Date(Date.now() - 45 * 1000);
    const recentlySent = await PhoneOtpChallenge.exists({
      phoneNumber,
      createdAt: { $gte: resendCutoff }
    });
    if (recentlySent) {
      return res.status(429).json({
        error: 'Please wait 45 seconds before requesting another OTP.'
      });
    }

    const recentSendCount = await PhoneOtpChallenge.countDocuments({
      phoneNumber,
      createdAt: { $gte: oneHourAgo }
    });
    if (recentSendCount >= MAX_SENDS_PER_HOUR) {
      return res.status(429).json({
        error: 'Too many OTP requests for this number. Please try again after one hour.'
      });
    }

    const challenge = new PhoneOtpChallenge({
      phoneNumber,
      otpHash: 'pending',
      provider: getPhoneOtpProvider(),
      expiresAt: new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000)
    });
    const otp = crypto.randomInt(100000, 1000000).toString();
    challenge.otpHash = hashOtp(challenge._id.toString(), otp);

    const providerResult = await sendPhoneOtp(phoneNumber, otp);
    challenge.provider = providerResult.provider;
    challenge.providerReference = providerResult.reference;
    await challenge.save();

    const response = {
      challengeId: challenge._id.toString(),
      maskedPhone: maskPhone(phoneNumber),
      expiresInSeconds: OTP_TTL_MINUTES * 60,
      resendAfterSeconds: 45
    };
    if (providerResult.provider === 'mock' && process.env.NODE_ENV !== 'production') {
      response.debugOtp = otp;
    }
    return res.status(201).json(response);
  } catch (error) {
    console.error('Phone OTP request failed:', error.message);
    const isConfigurationError = error.message.includes('configured') || error.message.includes('Unsupported');
    return res.status(isConfigurationError ? 503 : 502).json({
      error: isConfigurationError
        ? 'Phone sign-in is temporarily unavailable'
        : 'Could not send OTP. Please try Google sign-in or retry shortly.'
    });
  }
};

export const verifyPhoneOtp = async (req, res) => {
  try {
    const { challengeId, otp, deviceId, deviceName, platform } = req.body || {};
    if (!challengeId || !/^\d{6}$/.test(String(otp || ''))) {
      return res.status(400).json({ error: 'Challenge ID and a 6-digit OTP are required' });
    }

    const challenge = await PhoneOtpChallenge.findById(challengeId);
    if (!challenge || challenge.consumedAt || challenge.expiresAt <= new Date()) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new one.' });
    }
    if (challenge.attempts >= MAX_VERIFY_ATTEMPTS) {
      return res.status(429).json({ error: 'Too many incorrect attempts. Request a new OTP.' });
    }

    const submittedHash = hashOtp(challenge._id.toString(), String(otp));
    if (!safeHashEquals(challenge.otpHash, submittedHash)) {
      challenge.attempts += 1;
      await challenge.save();
      return res.status(400).json({
        error: 'Incorrect OTP',
        attemptsRemaining: Math.max(0, MAX_VERIFY_ATTEMPTS - challenge.attempts)
      });
    }

    // Consume before issuing a session so the same OTP cannot be replayed.
    challenge.consumedAt = new Date();
    await challenge.save();

    let user = null;
    if (req.user?._id) {
      user = await User.findById(req.user._id);
      const phoneOwner = await User.findOne({
        phoneNumber: challenge.phoneNumber,
        _id: { $ne: user?._id }
      }).select('_id');
      if (phoneOwner) {
        return res.status(409).json({ error: 'This phone number is already linked to another account.' });
      }
    }

    if (!user) {
      user = await User.findOne({ phoneNumber: challenge.phoneNumber });
    }

    let isNewUser = false;
    if (!user) {
      isNewUser = true;
      const identity = phoneIdentity(challenge.phoneNumber);
      user = await User.create({
        googleId: identity.identityId,
        authProvider: 'phone',
        authMethods: ['phone'],
        phoneNumber: challenge.phoneNumber,
        phoneVerifiedAt: new Date(),
        name: `Vayu User ${challenge.phoneNumber.slice(-4)}`,
        email: identity.syntheticEmail,
        isSyntheticEmail: true,
        videos: [],
        lastActive: new Date(),
        isAppUninstalled: false
      });
    } else {
      user.phoneNumber = challenge.phoneNumber;
      user.phoneVerifiedAt = new Date();
      user.authMethods = Array.from(new Set([
        ...(user.authMethods || []),
        ...(user.authProvider === 'google' ? ['google'] : []),
        'phone'
      ]));
      await user.save();
    }

    const accessToken = generateJWT(user.googleId, '30d');
    const refreshToken = await RefreshToken.createForDevice(
      user._id,
      deviceId,
      deviceName || 'Unknown Device',
      platform || 'unknown'
    );

    return res.json({
      accessToken,
      refreshToken,
      user: {
        id: user.googleId,
        _id: user._id,
        googleId: user.googleId,
        name: user.name,
        email: user.isSyntheticEmail ? '' : user.email,
        profilePic: user.profilePic,
        phoneNumber: maskPhone(user.phoneNumber),
        phoneVerified: true,
        authProvider: user.authProvider,
        isNewUser
      }
    });
  } catch (error) {
    console.error('Phone OTP verification failed:', error.message);
    if (error?.code === 11000) {
      return res.status(409).json({ error: 'This phone number is already linked to another account.' });
    }
    return res.status(500).json({ error: 'Phone verification failed. Please try again.' });
  }
};
