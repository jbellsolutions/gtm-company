const productionHost = process.env.RAILWAY_PUBLIC_DOMAIN
  ?? process.env.VERCEL_URL
  ?? process.env.SERVER_HOSTNAME

const allowedOrigins = ['localhost:3000']
if (productionHost) allowedOrigins.push(productionHost)

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    serverActions: {
      allowedOrigins,
    },
  },
}

export default nextConfig
