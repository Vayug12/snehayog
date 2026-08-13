import { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import { beat } from '../../utils/progressHeartbeat.js';

class CloudflareR2Service {
  constructor() {
    this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
    this.bucketName = process.env.CLOUDFLARE_R2_BUCKET_NAME;
    
    // **NEW: Support custom domain (cdn.snehayog.site) for public URLs**
    this.publicDomain = process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN;
    
    // **NEW: Presigned URL support**
    this.getSignedUrl = getSignedUrl;
    
    // **REMOVED: Sensitive configuration logging**
    
    // S3-compatible client for Cloudflare R2
    this.s3Client = new S3Client({
      region: 'auto',
      endpoint: `https://${this.accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY,
      },
    });
  }

  /**
   * Sanitize strings for use in R2 Keys (Removes spaces and special characters)
   */
  sanitizeKey(key) {
    if (!key) return '';
    // Replace characters that break URLs (like #, ?, whitespace) with underscores
    // We allow letters, numbers, dots, slashes, underscores, and hyphens
    return key.replace(/[^a-zA-Z0-9.\/_-]/g, '_');
  }

  /**
   * Download a file from R2 to local path
   * @param {string} key - R2 file key
   * @param {string} localPath - Destination local path
   */
  async downloadFile(key, localPath) {
    try {
      // Ensure directory exists
      const dir = path.dirname(localPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      const command = new GetObjectCommand({
        Bucket: this.bucketName,
        Key: key,
      });

      const response = await this.s3Client.send(command);
      
      // Pipe the stream to a file
      return new Promise((resolve, reject) => {
        const pipeline = response.Body.pipe(fs.createWriteStream(localPath));
        pipeline.on('finish', resolve);
        pipeline.on('error', reject);
      });
    } catch (error) {
       console.error(`❌ R2 Download Error for ${key}:`, error);
       throw error;
    }
  }

  /**
   * Delete a file from R2
   * @param {string} key - R2 file key
   */
  async deleteFile(key) {
    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucketName,
        Key: key,
      });
      await this.s3Client.send(command);
      return true;
    } catch (error) {
      console.error(`❌ R2 Delete Error for ${key}:`, error);
      throw error;
    }
  }


  /**
   * Get public URL for an R2 object key
   * Uses custom domain (cdn.snehayog.site) if configured, otherwise direct R2 URL
   */
  getPublicUrl(key) {
    if (!key) return '';
    if (key.startsWith('http')) return key;

    // **FIX: Normalize key path and ENCODE each segment for URL safety**
    const normalizedKey = key.startsWith('/') ? key.substring(1).replace(/\\/g, '/') : key.replace(/\\/g, '/');
    const encodedKey = normalizedKey.split('/').map(segment => encodeURIComponent(segment)).join('/');
    
    if (this.publicDomain) {
      // Use custom domain with HTTPS
      const cleanDomain = this.publicDomain.replace(/^https?:\/\//, '').replace(/\/$/, '');
      const url = `https://${cleanDomain}/${encodedKey}`;
      return url;
    }

    // Fallback to direct R2 URL if custom domain not set
    const directR2Url = `https://${this.bucketName}.${this.accountId}.r2.cloudflarestorage.com/${encodedKey}`;
    return directR2Url;
  }

  
  async uploadVideoToR2(filePath, fileName, userId) {
    try {
      const sanitizedName = this.sanitizeKey(fileName);
      const key = `videos/${userId}/${sanitizedName}_480p_${Date.now()}.mp4`;
      const fileSize = fs.statSync(filePath).size;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: fs.createReadStream(filePath),
        ContentType: 'video/mp4',
        CacheControl: 'public, max-age=31536000, immutable, stale-while-revalidate=604800',
        Metadata: {
          'video-quality': '480p',
          'processed-by': 'cloudinary-hybrid',
          'uploaded-by': userId,
          'upload-date': new Date().toISOString()
        }
      });
  
      await this.s3Client.send(command);
      
      const publicUrl = this.getPublicUrl(key);
      
      return {
        url: publicUrl,
        key: key,
        size: fileSize,
        format: 'mp4',
        quality: '480p'
      };
      
    } catch (error) {
      console.error('❌ Error uploading to R2:', error);
      throw error;
    }
  }

  /**
   * Upload thumbnail to R2 (S3-compatible)
   * Returns custom domain URL (cdn.snehayog.com) if configured
   */
  async uploadThumbnailToR2(thumbnailUrl, fileName, userId) {
    try {
      console.log('📤 Uploading thumbnail to R2 (S3-compatible)...');
      
      // Download thumbnail from Cloudinary
      const downloadResponse = await axios({
        method: 'GET',
        url: thumbnailUrl,
        responseType: 'arraybuffer'
      });
      
      const sanitizedName = this.sanitizeKey(fileName);
      const key = `thumbnails/${userId}/${sanitizedName}_thumb_${Date.now()}.jpg`;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: Buffer.from(downloadResponse.data),
        ContentType: 'image/jpeg',
        CacheControl: 'public, max-age=31536000, immutable, stale-while-revalidate=604800', // 1 year cache + SWR
        Metadata: {
          'thumbnail-for': fileName,
          'uploaded-by': userId,
          'upload-date': new Date().toISOString()
        }
      });

      await this.s3Client.send(command);
      
      // **USE CUSTOM DOMAIN** (cdn.snehayog.com) for public URL
      const publicUrl = this.getPublicUrl(key);
      console.log('✅ Thumbnail uploaded to R2');
      console.log('   Key:', key);
      console.log('   Public URL:', publicUrl);
      
      return publicUrl;
      
    } catch (error) {
      console.error('❌ Error uploading thumbnail to R2:', error);
      throw error;
    }
  }

  /**
   * Delete video from R2 (S3-compatible)
   */
  async deleteVideoFromR2(key) {
    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucketName,
        Key: key
      });

      await this.s3Client.send(command);
      console.log('🗑️ Video deleted from R2:', key);
      return true;
      
    } catch (error) {
      console.error('❌ Error deleting from R2:', error);
      return false;
    }
  }

  /**
   * Clean up local temp files
   */
  async cleanupLocalFile(filePath) {
    try {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        console.log('🧹 Temp file cleaned up:', filePath);
      }
    } catch (error) {
      console.warn('⚠️ Failed to cleanup temp file:', error);
    }
  }

  /**
   * Clean up temp directory
   */
  async cleanupTempDirectory() {
    try {
      const tempDir = path.join(process.cwd(), 'temp');
      if (fs.existsSync(tempDir)) {
        const files = fs.readdirSync(tempDir);
        for (const file of files) {
          fs.unlinkSync(path.join(tempDir, file));
        }
        console.log('🧹 Temp directory cleaned up');
      }
    } catch (error) {
      console.warn('⚠️ Failed to cleanup temp directory:', error);
    }
  }

  /**
   * Upload generic file to R2 (for HLS segments, playlists, etc.)
   * Returns custom domain URL (cdn.snehayog.com) if configured
   */
  async uploadFileToR2(filePath, key, contentType = 'application/octet-stream') {
    try {
      const sanitizedKey = this.sanitizeKey(key);
      const fileSize = fs.statSync(filePath).size;

      // Determine cache directives based on file type
      let cacheControl = 'public, max-age=86400, stale-while-revalidate=86400';
      if (/\.m3u8$/i.test(sanitizedKey)) {
        cacheControl = 'public, max-age=60, stale-while-revalidate=300';
      } else if (/\.(ts|mp4|m4s)$/i.test(sanitizedKey)) {
        cacheControl = 'public, max-age=31536000, immutable, stale-while-revalidate=604800';
      } else if (/\.(jpg|jpeg|png|webp)$/i.test(sanitizedKey)) {
        cacheControl = 'public, max-age=604800, stale-while-revalidate=604800';
      }
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: sanitizedKey,
        Body: fs.createReadStream(filePath),
        ContentType: contentType,
        CacheControl: cacheControl,
      });
  
      await this.s3Client.send(command);
      
      const publicUrl = this.getPublicUrl(sanitizedKey);
      console.log(`✅ File uploaded to R2: ${sanitizedKey}`);
      
      return {
        url: publicUrl,
        key: sanitizedKey,
        size: fileSize,
      };
      
    } catch (error) {
      console.error('❌ Error uploading file to R2:', error);
      throw error;
    }
  }

  /**
   * Upload entire HLS directory to R2 (playlist + segments)
   * Returns the master playlist URL
   */
  async uploadHLSDirectoryToR2(hlsDir, videoName, userId) {
    try {
      
      const files = fs.readdirSync(hlsDir);
      const sanitizedVideoName = this.sanitizeKey(videoName);
      let playlistKey = null;
      
      // Build upload tasks
      const tasks = [];
      for (const file of files) {
        const filePath = path.join(hlsDir, file);
        const key = `hls/${userId}/${sanitizedVideoName}/${file}`;
        
        if (file.endsWith('.m3u8')) {
          tasks.push({ filePath, key, contentType: 'application/x-mpegURL' });
          playlistKey = key;
        } else if (file.endsWith('.ts')) {
          tasks.push({ filePath, key, contentType: 'video/mp2t' });
        }
      }
      
      // Upload in batches of 5 to avoid memory spike
      const BATCH_SIZE = 5;
      for (let i = 0; i < tasks.length; i += BATCH_SIZE) {
        const batch = tasks.slice(i, i + BATCH_SIZE);
        await Promise.all(
          batch.map(t => this.uploadFileToR2(t.filePath, t.key, t.contentType))
        );
        // Encode ke baad ka sabse lamba silent stretch: bade video ke sau-sau
        // segments upload hote hain aur FFmpeg tick tab tak band ho chuka hota hai.
        // Har batch pe beat kiye bina watchdog is healthy upload ko hang samajh leta.
        beat();
      }
      
      if (!playlistKey) {
        throw new Error('No playlist file found in HLS directory');
      }
      
      return {
        playlistUrl: this.getPublicUrl(playlistKey),
        playlistKey: playlistKey,
        totalFiles: files.length,
        segments: files.filter(f => f.endsWith('.ts')).length,
      };
      
    } catch (error) {
      console.error('❌ Error uploading HLS directory to R2:', error);
      throw error;
    }
  }
  /**
   * Generates a presigned URL for direct client-side upload
   * @param {string} key - The R2 object key
   * @param {string} contentType - The MIME type of the file
   * @param {number} expiresIn - Expiration time in seconds (default 3600)
   */
  async getPresignedUploadUrl(key, contentType, expiresIn = 3600) {
    try {
      // Lazy load getSignedUrl to ensure dependency is available
      if (!this.getSignedUrl) {
         const { getSignedUrl } = await import('@aws-sdk/s3-request-presigner');
         this.getSignedUrl = getSignedUrl;
      }

      console.log(`🔑 Generating presigned upload URL for: ${key}`);
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        ContentType: contentType,
        // Enforce cache control for uploaded files
        CacheControl: 'public, max-age=31536000, immutable, stale-while-revalidate=604800' 
      });

      const url = await this.getSignedUrl(this.s3Client, command, { expiresIn: typeof expiresIn === 'number' ? expiresIn : 3600 });
      
      console.log('✅ Presigned URL generated successfully');
      return url;
    } catch (error) {
      console.error('❌ Error generating presigned URL:', error);
      throw error;
    }
  }

  /**
   * Compatibility wrapper for getPresignedUploadUrl
   */
  async generatePresignedUrl(key, contentType, operation = 'put', expiresIn = 3600) {
    // We only support 'put' for now via this service
    return this.getPresignedUploadUrl(key, contentType, expiresIn);
  }
}

export default new CloudflareR2Service();
