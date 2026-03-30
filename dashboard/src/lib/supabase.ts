import { createClient, SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

// Create a safe client that won't throw during SSR/build when env vars are missing
function createSafeClient(): SupabaseClient {
  if (!supabaseUrl || !supabaseAnonKey) {
    // Return a proxy that returns empty data for all queries during build
    // This prevents build-time errors when env vars aren't set
    const handler: ProxyHandler<any> = {
      get: (_target, prop) => {
        if (prop === 'from' || prop === 'channel' || prop === 'removeChannel') {
          return (..._args: any[]) => new Proxy({}, handler);
        }
        if (prop === 'select' || prop === 'insert' || prop === 'update' || prop === 'delete' ||
            prop === 'eq' || prop === 'or' || prop === 'gte' || prop === 'order' || prop === 'limit' ||
            prop === 'on' || prop === 'subscribe') {
          return (..._args: any[]) => new Proxy({}, handler);
        }
        if (prop === 'then') {
          return (resolve: (v: any) => void) => resolve({ data: null, error: null });
        }
        return new Proxy({}, handler);
      },
    };
    return new Proxy({} as SupabaseClient, handler);
  }
  return createClient(supabaseUrl, supabaseAnonKey);
}

export const supabase = createSafeClient();
