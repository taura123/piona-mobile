import { PassengerType, PassengerCategory, ParsingStatus } from '@prisma/client';
import { prisma } from '../src/db';

async function main() {
  console.log("Seeding dummy passenger and bcbp_parser data for today (1 PM - 11 PM)...");
  
  const today = new Date();
  const year = today.getFullYear();
  const month = today.getMonth();
  const day = today.getDate();

  const user = await prisma.user.findFirst();
  if (!user) {
    throw new Error("No user found in database to act as scanner.");
  }

  const names = [
    "Budi Santoso", "Siti Aminah", "Andi Wijaya", "Rina Marlina", "Eko Prasetyo",
    "Dewi Lestari", "Rudi Hermawan", "Nina Kirana", "Hendra Gunawan", "Maya Putri"
  ];
  const routes = [
    { origin: "CGK", destination: "DPS", flightNumber: "GA-101" },
    { origin: "DPS", destination: "CGK", flightNumber: "GA-102" },
    { origin: "SUB", destination: "CGK", flightNumber: "GA-201" },
    { origin: "KNO", destination: "CGK", flightNumber: "GA-301" },
    { origin: "CGK", destination: "YIA", flightNumber: "GA-401" }
  ];
  const scanPoints = ["Gate 1", "Gate 2", "Gate 3", "Transfer Desk"];

  // Ensure scan points exist
  for (const sp of scanPoints) {
    await prisma.scanPoint.upsert({
      where: { name: sp },
      create: { name: sp },
      update: {},
    });
  }

  let count = 0;
  // Generate around 100 passengers
  for (let i = 0; i < 100; i++) {
    const hour = Math.floor(Math.random() * 11) + 13;
    const minute = Math.floor(Math.random() * 60);
    
    const flightDate = new Date(Date.UTC(year, month, day, 0, 0, 0));
    const scannedAt = new Date(year, month, day, hour, minute, 0);

    const type = Math.random() > 0.8 ? PassengerType.Infant : PassengerType.Adult;
    const category = Math.random() > 0.8 ? PassengerCategory.Transit : PassengerCategory.Normal;
    
    const route = routes[Math.floor(Math.random() * routes.length)];
    const origin = route.origin;
    const destination = route.destination;
    const flightNumber = route.flightNumber;

    const scanPoint = scanPoints[Math.floor(Math.random() * scanPoints.length)];
    const name = names[Math.floor(Math.random() * names.length)];
    const seatNumber = (Math.floor(Math.random() * 30) + 1) + ["A", "B", "C", "D", "E", "F"][Math.floor(Math.random() * 6)];
    const pnr = Math.random().toString(36).substring(2, 8).toUpperCase();

    try {
      await prisma.passenger.create({
        data: {
          pnr: pnr,
          name: name,
          flightNumber: flightNumber,
          origin: origin,
          destination: destination,
          seatNumber: seatNumber,
          sequenceNumber: (i + 1).toString().padStart(3, "0"),
          flightDate: flightDate,
          type: type,
          category: category,
          scannedAt: scannedAt,
          scanPoint: scanPoint,
          sent: "1",
          sendDate: scannedAt,
          parsers: {
            create: {
              rawBarcode: "M1" + name.replace(" ", "/") + " " + pnr + origin + destination + flightNumber.replace("-", ""),
              parsedData: { pnr, name, flightNumber, origin, destination, seatNumber },
              parsingStatus: ParsingStatus.success,
              scanTimestamp: scannedAt,
              scanPoint: scanPoint,
              scannerUserId: user.id
            }
          }
        }
      });
      count++;
    } catch (e) {
      // Ignore duplicates
    }
  }

  console.log(`Successfully created ${count} dummy passengers and BCBP records.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
