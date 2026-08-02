import { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import IStorageProvider from '../IStorageProvider.js';
import fs from 'fs';
import path from 'path';

/**
 * Cloudflare R2 Storage Provider (The "R2 Codec")
 */
class R2StorageProvider extends IStorageProvider {
  constructor() {
    super();
    this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
    this.bucketName = process.env.CLOUDFLARE_R2_BUCKET_NAME;
    this.publicDomain = process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN;
    
    this.s3Client = new S3Client({
      region: 'auto',
      endpoint: `https://${this.accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY,
      },
    });
  }

  async upload(localPath, destinationKey, contentType = 'application/octet-stream') {
    try {
      const fileSize = fs.statSync(localPath).size;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: destinationKey,
        Body: fs.createReadStream(localPath),
        ContentType: contentType,
        CacheControl: 'public, max-age=31536000, immutable',
      });

      await this.s3Client.send(command);
      
      return {
        url: this.getPublicUrl(destinationKey),
        key: destinationKey,
        size: fileSize
      };
    } catch (error) {
      console.error(`❌ R2 Upload Error for ${destinationKey}:`, error);
      throw error;
    }
  }

  async download(key, localPath) {
    try {
      const dir = path.dirname(localPath);
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

      const command = new GetObjectCommand({
        Bucket: this.bucketName,
        Key: key,
      });

      const response = await this.s3Client.send(command);
      
      return new Promise((resolve, reject) => {
        const pipeline = response.Body.pipe(fs.createWriteStream(localPath));
        pipeline.on('finish', () => resolve(localPath));
        pipeline.on('error', reject);
      });
    } catch (error) {
       console.error(`❌ R2 Download Error for ${key}:`, error);
       throw error;
    }
  }

  async delete(key) {
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

  getPublicUrl(key) {
    if (!key) return '';
    if (key.startsWith('http')) return key;

    const normalizedKey = key.startsWith('/') ? key.substring(1).replace(/\\/g, '/') : key.replace(/\\/g, '/');
    const encodedKey = normalizedKey.split('/').map(segment => encodeURIComponent(segment)).join('/');
    
    if (this.publicDomain) {
      const cleanDomain = this.publicDomain.replace(/^https?:\/\//, '').replace(/\/$/, '');
      return `https://${cleanDomain}/${encodedKey}`;
    }

    return `https://${this.bucketName}.${this.accountId}.r2.cloudflarestorage.com/${encodedKey}`;
  }
}

export default R2StorageProvider;
