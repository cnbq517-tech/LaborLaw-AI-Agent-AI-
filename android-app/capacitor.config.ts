import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.laborlaw.aiassistant',
  appName: '劳动法律 AI 智能体',
  webDir: 'dist',
  android: {
    allowMixedContent: false,
    backgroundColor: '#0E1B30',
  },
  server: {
    androidScheme: 'https',
  },
};

export default config;
