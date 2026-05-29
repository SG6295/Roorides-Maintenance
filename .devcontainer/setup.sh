#!/bin/bash
set -e

echo "→ Installing dependencies..."
npm install

echo "→ Installing Supabase CLI..."
curl -sSL https://supabase.com/install.sh | sh
export PATH="$HOME/.supabase/bin:$PATH"

echo "→ Creating .env.local from Codespaces secrets..."
cat > .env.local << EOF
# Supabase Configuration — Staging
VITE_SUPABASE_URL=${VITE_SUPABASE_URL}
VITE_SUPABASE_ANON_KEY=${VITE_SUPABASE_ANON_KEY}

# Database Connection — Staging (Session pooler)
DATABASE_URL=${DATABASE_URL}

# App Configuration
VITE_APP_NAME=NVS Maintenance
VITE_ASSIGNMENT_SLA_DAYS=1

# Supabase CLI auth
SUPABASE_ACCESS_TOKEN=${SUPABASE_ACCESS_TOKEN}
EOF

echo "→ Linking Supabase CLI to staging project..."
supabase link --project-ref bhzvnsnavfujfjimiesh

echo "✓ Setup complete. Run 'npm run dev' to start the dev server."
