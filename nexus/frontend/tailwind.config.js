/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts}'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['ui-sans-serif', 'system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace'],
      },
      animation: {
        'pulse-danger': 'pulse-danger 1s ease-in-out infinite',
      },
      keyframes: {
        'pulse-danger': {
          '0%,100%': { boxShadow: '0 0 24px rgba(239,68,68,0.6)' },
          '50%': { boxShadow: '0 0 48px rgba(239,68,68,0.95)' },
        },
      },
    },
  },
  plugins: [],
}
