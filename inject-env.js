// inject-env.js — runs at Netlify build time. Injects SUPABASE_URL and SUPABASE_ANON_KEY
// into public/index.html so the frontend can read them at runtime.

const fs = require('fs');
const path = require('path');

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_ANON_KEY;

if (!url || !key) {
  console.warn('!!! SUPABASE_URL / SUPABASE_ANON_KEY env vars not set. App will not connect to Supabase.');
}

const indexPath = path.join(__dirname, 'public', 'index.html');
let html = fs.readFileSync(indexPath, 'utf8');

const injection = `<script>window.SUPABASE_URL = ${JSON.stringify(url || '')}; window.SUPABASE_ANON_KEY = ${JSON.stringify(key || '')};</script>`;

// inject right before the main module script
html = html.replace('<script type="module">', injection + '\n<script type="module">');

fs.writeFileSync(indexPath, html);
console.log('Injected Supabase env vars into index.html');
