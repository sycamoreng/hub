import type { Config } from 'tailwindcss'

export default <Partial<Config>>{
  content: [
    './components/**/*.{vue,js,ts}',
    './layouts/**/*.vue',
    './pages/**/*.vue',
    './app.vue'
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Satoshi', 'system-ui', 'sans-serif']
      },
      colors: {
        sycamore: {
          50: '#eaf4fb',
          100: '#d2e8f6',
          200: '#a0d2ff',
          300: '#74b9e3',
          400: '#4ba1d0',
          500: '#3087b9',
          600: '#1f6f9c',
          700: '#0a445c',
          800: '#073042',
          900: '#04222f',
          950: '#02141c'
        },
        leaf: {
          50: '#e8f8ee',
          100: '#cdf0d8',
          200: '#9ee2b3',
          300: '#5ed188',
          400: '#26c165',
          500: '#179f50',
          600: '#109847',
          700: '#0d7a3a',
          800: '#0a5d2c',
          900: '#063f1e'
        }
      }
    }
  }
}
