import { z } from 'zod';

const EnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16),
  DEV_DEFAULT_USERNAME: z.string().min(1).default('admin'),
  DEV_DEFAULT_PASSWORD: z.string().min(1).default('admin123'),
  DEV_DEFAULT_ROLE: z.string().min(1).default('Admin'),
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(raw: Record<string, string | undefined>): Env {
  const parsed = EnvSchema.safeParse(raw);
  if (!parsed.success) {
    // Keep message readable.
    const msg = parsed.error.issues
      .map((i) => `${i.path.join('.')}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment variables:\n${msg}`);
  }
  return parsed.data;
}

