# DaemonFlow website

The marketing site for DaemonFlow: a Next.js 16 app (App Router, TypeScript, plain CSS).

```sh
npm install
npm run dev      # http://localhost:3000
npm run build    # production build; every route is static
```

- Sections live in `src/components/`, one per file. `Demo.tsx` is the only client component: the hold-to-talk demo in the hero.
- Images are in `public/`, copied from the launch images in `../docs/assets/`.
- The download button links to `releases/latest/download/DaemonFlow-macOS.zip`, so keep that asset name on future releases.
- Set `NEXT_PUBLIC_SITE_URL` to the real domain when deploying, so the Open Graph image gets an absolute URL.
