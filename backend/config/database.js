import mongoose from 'mongoose';

class DatabaseManager {
  constructor() {
    this.isConnected = false;
  }

  async connect() {
    if (this.isConnected) return;
    
    console.log('🔌 Connecting to MongoDB...');
    
    // Register error listener
    mongoose.connection.on('error', (err) => {
      console.error('❌ MongoDB connection error event:', err.message);
      this.isConnected = false;
    });

    await mongoose.connect(process.env.MONGO_URI, {
      maxPoolSize: 10,
      serverSelectionTimeoutMS: 30000,
      socketTimeoutMS: 45000,
      connectTimeoutMS: 30000,
      family: 4, // Force IPv4 to avoid similar DNS issues as Redis
    });
    
    this.isConnected = true;
    console.log("✅ MongoDB connected successfully");
    
    mongoose.connection.on('disconnected', this.handleDisconnect.bind(this));
  }

  async disconnect() {
    if (this.isConnected) {
      await mongoose.disconnect();
      this.isConnected = false;
      console.log('🔌 MongoDB disconnected');
    }
  }

  handleError(error) {
    console.error('❌ MongoDB connection error:', error);
    this.isConnected = false;
  }

  handleDisconnect() {
    // **FIX: Don't retry in test mode to allow clean teardown**
    if (process.env.NODE_ENV === 'test') {
      console.log('⚠️ MongoDB disconnected (Test Mode - skipping retry)');
      this.isConnected = false;
      return;
    }
    console.log('⚠️ MongoDB disconnected. Retrying in 5s...');
    this.isConnected = false;
    setTimeout(() => this.connect(), 5000);
  }

  getConnectionStatus() {
    return {
      isConnected: this.isConnected,
      readyState: mongoose.connection.readyState
    };
  }
}

export default new DatabaseManager();
