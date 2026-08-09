// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  modules: ['@nuxt/eslint', '@nuxt/ui'],

  // Static SPA: embedded in the Go binary and served from the same origin.
  ssr: false,

  nitro: {
    preset: 'static'
  },

  devtools: {
    enabled: false
  },

  css: ['~/assets/css/main.css'],

  colorMode: {
    preference: 'system'
  },

  runtimeConfig: {
    public: {
      // Same-origin when UI is served by the API; override for local Nuxt dev if needed.
      apiBase: '/api/v1',
      // Overridden at build/runtime by NUXT_PUBLIC_APP_VERSION (git tag in CI).
      appVersion: 'dev'
    }
  },

  compatibilityDate: '2026-06-30',

  eslint: {
    config: {
      stylistic: {
        commaDangle: 'never',
        braceStyle: '1tbs'
      }
    }
  },

  icon: {
    provider: 'none',
    clientBundle: {
      scan: true
    }
  }
})
