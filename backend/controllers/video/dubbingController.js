import AIService from '../../services/aiService.js';
import fs from 'fs';
import path from 'path';

export const transcribeAudio = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No audio file uploaded' });
    }

    const audioPath = req.file.path;
    
    try {
      const transcript = await AIService.transcribe(audioPath);
      
      // Clean up uploaded file
      fs.unlinkSync(audioPath);
      
      return res.json({ 
        success: true, 
        transcript: transcript 
      });
    } catch (aiError) {
      // Clean up on error too
      if (fs.existsSync(audioPath)) fs.unlinkSync(audioPath);
      
      if (aiError.message === 'MODEL_LOADING') {
        return res.status(503).json({ 
          error: 'AI model is still loading, please try again in a few seconds',
          code: 'MODEL_LOADING'
        });
      }
      throw aiError;
    }
  } catch (error) {
    console.error('❌ [Dubbing Controller] Transcription error:', error);
    res.status(500).json({ error: 'Transcription failed', details: error.message });
  }
};

export const synthesizeSpeech = async (req, res) => {
  try {
    const { text, language } = req.body;
    
    if (!text) {
      return res.status(400).json({ error: 'Text is required for synthesis' });
    }

    const tempDir = path.join(process.cwd(), 'uploads', 'temp', 'tts');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

    const outputPath = path.join(tempDir, `tts_${Date.now()}.wav`);
    
    try {
      await AIService.synthesize(text, language || 'hindi', outputPath);
      
      // Send the file and then delete it
      res.sendFile(outputPath, (err) => {
        if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
        if (err) {
          console.error('❌ [Dubbing Controller] Error sending file:', err);
        }
      });
    } catch (aiError) {
      if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
      
      if (aiError.message === 'MODEL_LOADING') {
        return res.status(503).json({ 
          error: 'AI model is still loading, please try again in a few seconds',
          code: 'MODEL_LOADING'
        });
      }
      throw aiError;
    }
  } catch (error) {
    console.error('❌ [Dubbing Controller] Synthesis error:', error);
    res.status(500).json({ error: 'Speech synthesis failed', details: error.message });
  }
};

export const translateText = async (req, res) => {
  try {
    const { text, targetLang } = req.body;
    const validTargetLanguages = new Set(['hindi', 'english', 'hi_IN', 'en_XX']);

    if (typeof text !== 'string' || text.trim().length === 0) {
      return res.status(400).json({ error: 'Text is required' });
    }

    if (targetLang != null && !validTargetLanguages.has(targetLang)) {
      return res.status(422).json({ error: 'Unsupported target language' });
    }

    const translatedText = await AIService.translate(text, targetLang || 'hindi');
    if (typeof translatedText !== 'string' || translatedText.trim().length === 0) {
      throw new Error('Translation provider returned empty text');
    }

    res.json({ success: true, translatedText });
  } catch (error) {
    const status = error.message === 'MODEL_LOADING' ? 503 : 502;
    console.error('❌ [Dubbing Controller] Translation error:', {
      targetLang: req.body?.targetLang,
      textLength: typeof req.body?.text === 'string' ? req.body.text.length : 0,
      message: error.message,
    });
    res.status(status).json({ error: 'Translation failed' });
  }
};

import { HuggingFaceAIEngine } from '../../services/aiService/HuggingFaceAIEngine.js';
import { OpenAIAIEngine } from '../../services/aiService/OpenAIAIEngine.js';

export const getActiveAIEngine = async (req, res) => {
  try {
    const engine = AIService.getAIEngine();
    const translationEngine = AIService.getTranslationEngine();
    res.json({
      success: true,
      activeEngine: engine.constructor.name,
      translationEngine: translationEngine.constructor.name,
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to retrieve active AI Engine', details: error.message });
  }
};

export const setActiveAIEngine = async (req, res) => {
  try {
    const { provider } = req.body;
    if (!provider) {
      return res.status(400).json({ error: 'Provider is required' });
    }

    if (provider.toLowerCase() === 'openai') {
      AIService.setAIEngine(new OpenAIAIEngine());
    } else if (provider.toLowerCase() === 'huggingface' || provider.toLowerCase() === 'hf') {
      AIService.setAIEngine(new HuggingFaceAIEngine());
    } else {
      return res.status(400).json({ error: 'Unsupported provider. Choose "openai" or "huggingface"' });
    }

    res.json({
      success: true,
      activeEngine: AIService.getAIEngine().constructor.name,
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to swap AI Engine', details: error.message });
  }
};
