// ESLint 9 only reads flat config. Without this file `npm run lint` failed
// immediately ("couldn't find an eslint.config file"), and Next 16 removed
// the `next lint` wrapper that used to supply one.
import { defineConfig, globalIgnores } from 'eslint/config'
import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  globalIgnores([
    '.next/**',
    'out/**',
    'build/**',
    'next-env.d.ts',
    // Generated shadcn/ui primitives (and their copies in hooks/), kept as
    // upstream ships them so they can be re-generated. Lint the app's own code.
    'components/ui/**',
    'hooks/use-mobile.ts',
    'hooks/use-toast.ts',
  ]),
])
