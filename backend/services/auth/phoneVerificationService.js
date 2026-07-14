import axios from 'axios';

const providerName = () => (process.env.PHONE_OTP_PROVIDER || '2factor').toLowerCase();

const requireTwoFactorConfig = () => {
  const apiKey = process.env.TWO_FACTOR_API_KEY;
  if (!apiKey) {
    throw new Error('TWO_FACTOR_API_KEY is not configured');
  }
  return apiKey;
};

const sendWithTwoFactor = async (phoneNumber, otp) => {
  const apiKey = requireTwoFactorConfig();
  const nationalNumber = phoneNumber.replace(/^\+91/, '');
  const template = process.env.TWO_FACTOR_OTP_TEMPLATE?.trim();
  const segments = [
    'https://2factor.in/API/V1',
    encodeURIComponent(apiKey),
    'SMS',
    encodeURIComponent(nationalNumber),
    encodeURIComponent(otp)
  ];
  if (template) segments.push(encodeURIComponent(template));

  const response = await axios.post(segments.join('/'), null, {
    timeout: 10000,
    validateStatus: status => status >= 200 && status < 500
  });

  const data = response.data || {};
  const status = String(data.Status || data.status || '').toLowerCase();
  if (response.status >= 400 || status !== 'success') {
    const providerMessage = data.Details || data.details || data.message || 'OTP provider rejected the request';
    throw new Error(`2Factor OTP send failed: ${providerMessage}`);
  }

  return {
    provider: '2factor',
    reference: String(data.Details || data.details || '')
  };
};

export const sendPhoneOtp = async (phoneNumber, otp) => {
  const provider = providerName();

  if (provider === 'mock') {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('Mock phone OTP provider is disabled in production');
    }
    return { provider: 'mock', reference: 'local-development' };
  }

  if (provider !== '2factor') {
    throw new Error(`Unsupported PHONE_OTP_PROVIDER: ${provider}`);
  }

  return sendWithTwoFactor(phoneNumber, otp);
};

export const getPhoneOtpProvider = providerName;
