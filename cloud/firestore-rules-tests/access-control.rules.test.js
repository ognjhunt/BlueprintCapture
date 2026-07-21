// Firebase-emulator contract tests for the reservation/session/user
// access-control rules in firestore.rules.
//
// Added with the 2026-07 audit fix: the previous reservations rule allowed
// write when the caller owned EITHER the existing doc or the incoming payload,
// which let any signed-in user overwrite someone else's reservation
// (job-squatting). sessions/sessionEvents creates were unscoped to auth.uid,
// and users/{uid} had no delete clause, silently breaking in-app account
// deletion. These tests pin the corrected contract.
//
// Run with: npm test (wraps `firebase emulators:exec --only firestore`).

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { after, before, beforeEach, describe, it } from "node:test";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_PATH = join(__dirname, "..", "..", "firestore.rules");

const OWNER_UID = "owner-uid-1";
const OTHER_UID = "other-uid-2";
const TARGET_ID = "target-xyz";

let testEnv;

function emulatorHostPort() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  const [host, port] = raw.split(":");
  return { host, port: Number(port) };
}

before(async () => {
  const { host, port } = emulatorHostPort();
  // Distinct projectId from capture-submissions.rules.test.js: node --test runs
  // files concurrently against one emulator, and clearFirestore() is
  // project-scoped — sharing an id would wipe the other file's in-flight docs.
  testEnv = await initializeTestEnvironment({
    projectId: "demo-blueprint-rules-access",
    firestore: {
      rules: readFileSync(RULES_PATH, "utf8"),
      host,
      port,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function ownerDb() {
  return testEnv.authenticatedContext(OWNER_UID).firestore();
}

function strangerDb() {
  return testEnv.authenticatedContext(OTHER_UID).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seedReservation(userId = OWNER_UID) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("reservations").doc(TARGET_ID).set({
      userId,
      reservedAt: 1,
    });
  });
}

describe("reservations", () => {
  it("allows a signed-in user to create a reservation claimed as themselves", async () => {
    await assertSucceeds(
      ownerDb().collection("reservations").doc(TARGET_ID).set({
        userId: OWNER_UID,
        reservedAt: 1,
      })
    );
  });

  it("denies creating a reservation claimed as someone else", async () => {
    await assertFails(
      strangerDb().collection("reservations").doc(TARGET_ID).set({
        userId: OWNER_UID,
        reservedAt: 1,
      })
    );
  });

  it("denies overwriting another user's reservation with your own userId (job-squatting)", async () => {
    await seedReservation(OWNER_UID);
    await assertFails(
      strangerDb().collection("reservations").doc(TARGET_ID).set({
        userId: OTHER_UID,
        reservedAt: 2,
      })
    );
  });

  it("denies deleting another user's reservation", async () => {
    await seedReservation(OWNER_UID);
    await assertFails(
      strangerDb().collection("reservations").doc(TARGET_ID).delete()
    );
  });

  it("allows the owner to update and delete their own reservation", async () => {
    await seedReservation(OWNER_UID);
    await assertSucceeds(
      ownerDb().collection("reservations").doc(TARGET_ID).set({
        userId: OWNER_UID,
        reservedAt: 2,
      })
    );
    await assertSucceeds(
      ownerDb().collection("reservations").doc(TARGET_ID).delete()
    );
  });

  it("denies the owner reassigning their reservation to another userId", async () => {
    await seedReservation(OWNER_UID);
    await assertFails(
      ownerDb().collection("reservations").doc(TARGET_ID).set({
        userId: OTHER_UID,
        reservedAt: 2,
      })
    );
  });

  it("denies reads by non-owners and unauthenticated clients", async () => {
    await seedReservation(OWNER_UID);
    await assertSucceeds(
      ownerDb().collection("reservations").doc(TARGET_ID).get()
    );
    await assertFails(
      strangerDb().collection("reservations").doc(TARGET_ID).get()
    );
    await assertFails(anonDb().collection("reservations").doc(TARGET_ID).get());
  });
});

describe("sessions", () => {
  it("allows creating a session scoped to the caller", async () => {
    await assertSucceeds(
      ownerDb().collection("sessions").doc("s1").set({
        userId: OWNER_UID,
        startedAt: 1,
      })
    );
  });

  it("denies creating a session claimed as another user", async () => {
    await assertFails(
      strangerDb().collection("sessions").doc("s1").set({
        userId: OWNER_UID,
        startedAt: 1,
      })
    );
  });

  it("denies creating a session with no userId", async () => {
    await assertFails(
      ownerDb().collection("sessions").doc("s1").set({ startedAt: 1 })
    );
  });
});

describe("sessionEvents", () => {
  it("allows creating an event scoped to the caller", async () => {
    await assertSucceeds(
      ownerDb().collection("sessionEvents").doc("e1").set({
        userId: OWNER_UID,
        type: "app_open",
      })
    );
  });

  it("denies creating an event claimed as another user", async () => {
    await assertFails(
      strangerDb().collection("sessionEvents").doc("e1").set({
        userId: OWNER_UID,
        type: "app_open",
      })
    );
  });

  it("denies updates and deletes even by the owner", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("sessionEvents").doc("e1").set({
        userId: OWNER_UID,
        type: "app_open",
      });
    });
    await assertFails(
      ownerDb().collection("sessionEvents").doc("e1").set({
        userId: OWNER_UID,
        type: "edited",
      })
    );
    await assertFails(
      ownerDb().collection("sessionEvents").doc("e1").delete()
    );
  });
});

describe("users self-deletion", () => {
  async function seedUser(uid) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("users").doc(uid).set({
        name: "Test User",
        stats: { availableBalance: 0 },
      });
    });
  }

  it("allows a user to delete their own users doc (in-app account deletion)", async () => {
    await seedUser(OWNER_UID);
    await assertSucceeds(ownerDb().collection("users").doc(OWNER_UID).delete());
  });

  it("denies deleting another user's doc", async () => {
    await seedUser(OWNER_UID);
    await assertFails(strangerDb().collection("users").doc(OWNER_UID).delete());
    await assertFails(anonDb().collection("users").doc(OWNER_UID).delete());
  });
});
