
// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

let plugin = require('tailwindcss/plugin')

module.exports = {
  content: ['./src/**/*.{html,gleam}', './index.html'],
  theme: {
    extend: {
      animation: {
				fadein: 'fadeIn 0.3s ease-in-out',
        fadeout: 'fadeOut 0.3s ease-in-out'
			},

			keyframes: {
				fadeIn: {
					from: { opacity: 0 },
					to: { opacity: 1 },
				},
        fadeOut: {
          from: { opacity: 1 },
          to: { opacity: 0 },
        }
			},
    },
  },
  plugins: [require('@tailwindcss/forms')],
}
