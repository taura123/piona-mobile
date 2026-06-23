import bcrypt from 'bcryptjs';

import { UserRole, UserStatus } from '@prisma/client';
import { prisma } from '../src/db';

async function main() {
  const username = process.env.DEV_DEFAULT_USERNAME?.trim() || 'admin';
  const password = process.env.DEV_DEFAULT_PASSWORD?.trim() || 'admin123';
  const roleRaw = process.env.DEV_DEFAULT_ROLE?.trim() || 'Admin';
  const role =
    roleRaw === 'IT'
      ? UserRole.IT
      : roleRaw === 'Scan'
        ? UserRole.Scan
        : roleRaw === 'View'
          ? UserRole.View
          : UserRole.Admin;

  const existing = await prisma.user.findUnique({ where: { username } });
  if (!existing) {
    const passwordHash = await bcrypt.hash(password, 10);
    await prisma.user.create({
      data: {
        username,
        password: passwordHash,
        role,
        status: UserStatus.Active,
      },
    });
  }
}

main()
  .catch((e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

