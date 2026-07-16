// Firebase-emulator contract tests for the `capture_submissions` client
// security-rules contract in firestore.rules.
//
// These tests exercise the REAL deployed ruleset against payloads shaped
// exactly like the iOS (`CaptureUploadService.captureSubmissionPayload`) and
// Android (`CaptureUploadRepository.buildCaptureSubmissionPayload`) builders,
// so a rules/client drift fails here instead of in the field.
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
import { Timestamp } from "firebase/firestore";

const __dirname = dirname(fileURLToPath(import.meta.url));
const RULES_PATH = join(__dirname, "..", "..", "firestore.rules");

const CREATOR_ID = "creator-uid-1";
const OTHER_UID = "other-uid-2";
const CAPTURE_ID = "capture-abc-123";

let testEnv;

function emulatorHostPort() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  const [host, port] = raw.split(":");
  return { host, port: Number(port) };
}

before(async () => {
  const { host, port } = emulatorHostPort();
  testEnv = await initializeTestEnvironment({
    projectId: "demo-blueprint-rules",
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
  return testEnv.authenticatedContext(CREATOR_ID).firestore();
}

function strangerDb() {
  return testEnv.authenticatedContext(OTHER_UID).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

function submissionDoc(db, captureId = CAPTURE_ID) {
  return db.collection("capture_submissions").doc(captureId);
}

/** Payload shaped like the iOS builder (all keys iOS can serialize). */
function iosCreatePayload(overrides = {}) {
  const now = Timestamp.now();
  return {
    capture_id: CAPTURE_ID,
    scene_id: "scene-abc-123",
    creator_id: CREATOR_ID,
    job_id: "job-1",
    capture_source: "phone_video",
    status: "submitted",
    requested_outputs: ["frames"],
    has_site_identity: true,
    has_capture_topology: false,
    created_at: now,
    operational_state: {
      assignment_state: "unassigned_or_open_capture",
      upload_state: "uploading",
      qa_state: "queued",
      qa_outcome: null,
      repeat_ready: false,
    },
    lifecycle: {
      capture_started_at: now,
      upload_started_at: now,
    },
    estimated_payout_cents: 4500,
    rights_profile: "public_space",
    target_address: "123 Main St, Durham, NC",
    site_identity: {
      site_id: "site-1",
      site_id_source: "manual",
      place_id: null,
      site_name: "Main St Hardware",
      address_full: "123 Main St, Durham, NC",
      building_id: null,
      floor_id: null,
      room_id: null,
      zone_id: null,
    },
    city_context: { city: "Durham, NC", city_slug: "durham-nc" },
    target_context: { target_id: "site-1", workflow_fit: "shelf restock" },
    raw_prefix: `scenes/scene-abc-123/captures/${CAPTURE_ID}/raw/`,
    ...overrides,
  };
}

/** Payload shaped like the post-fix Android builder. */
function androidCreatePayload(overrides = {}) {
  const now = Timestamp.now();
  return {
    capture_id: CAPTURE_ID,
    scene_id: "scene-abc-123",
    creator_id: CREATOR_ID,
    capture_source: "phone_video",
    created_at: now,
    status: "submitted",
    operational_state: {
      assignment_state: "unassigned_or_open_capture",
      upload_state: "uploading",
      qa_state: "queued",
      repeat_ready: false,
    },
    lifecycle: {
      capture_started_at: now,
      upload_started_at: now,
    },
    raw_prefix: `scenes/scene-abc-123/captures/${CAPTURE_ID}/raw/`,
    ...overrides,
  };
}

function completionMerge() {
  const now = Timestamp.now();
  return {
    status: "submitted",
    submitted_at: now,
    created_at: now,
    operational_state: {
      assignment_state: "unassigned_or_open_capture",
      upload_state: "uploaded",
      qa_state: "queued",
      repeat_ready: false,
    },
    lifecycle: {
      capture_started_at: now,
      upload_started_at: now,
      capture_uploaded_at: now,
    },
  };
}

function failureMerge(status = "upload_failed") {
  const now = Timestamp.now();
  return {
    status,
    operational_state: {
      assignment_state: "unassigned_or_open_capture",
      upload_state: "failed",
      qa_state: "queued",
      repeat_ready: true,
    },
    lifecycle: {
      capture_started_at: now,
      upload_failed_at: now,
    },
    upload_error: {
      code: "upload_failed",
      message: "Network unavailable after retries.",
      recorded_at: now,
    },
  };
}

describe("capture_submissions create", () => {
  it("denies unauthenticated create", async () => {
    await assertFails(submissionDoc(anonDb()).set(iosCreatePayload()));
  });

  it("denies create claiming another creator's id", async () => {
    await assertFails(submissionDoc(strangerDb()).set(iosCreatePayload()));
  });

  it("allows a valid iOS-shaped create", async () => {
    await assertSucceeds(submissionDoc(ownerDb()).set(iosCreatePayload()));
  });

  it("allows a valid Android-shaped create (minimal, no optional metadata)", async () => {
    await assertSucceeds(submissionDoc(ownerDb()).set(androidCreatePayload()));
  });

  it("allows a valid Android-shaped create with optional job/site metadata", async () => {
    await assertSucceeds(
      submissionDoc(ownerDb()).set(
        androidCreatePayload({
          job_id: "job-9",
          capture_job_id: "capture-job-9",
          estimated_payout_cents: 2500,
          has_site_identity: true,
          site_identity: {
            site_id: "site-2",
            site_id_source: "reservation",
            site_name: "Warehouse 9",
            address_full: "9 Dock Rd, Durham, NC",
          },
          target_address: "9 Dock Rd, Durham, NC",
          city_context: { city: "Durham", city_slug: "durham-nc" },
        }),
      ),
    );
  });

  it("denies legacy Android motion/scheduling metadata keys on create", async () => {
    // These keys were removed from the Android payload builder: motion truth
    // lives in the raw bundle. The rules keep rejecting them so they cannot
    // silently reappear and break the whole registration write.
    for (const extra of [
      { capture_start_epoch_ms: 1752690000000 },
      { capture_duration_ms: 90000 },
      { motion_sample_count: 4200 },
      { motion_provenance: "phone_imu_accelerometer_gyroscope" },
      { priority_weight: 2 },
      { reservation_id: "res-1" },
      { imu_samples_available: true },
    ]) {
      await assertFails(
        submissionDoc(ownerDb()).set(androidCreatePayload(extra)),
      );
    }
  });

  it("denies create with a non-client status", async () => {
    for (const status of ["approved", "paid", "qa_passed", "processing"]) {
      await assertFails(
        submissionDoc(ownerDb()).set(iosCreatePayload({ status })),
      );
    }
  });

  it("denies create with client-authored QA outcome or payout fields", async () => {
    await assertFails(
      submissionDoc(ownerDb()).set(iosCreatePayload({ payout_cents: 9900 })),
    );
    await assertFails(
      submissionDoc(ownerDb()).set(
        iosCreatePayload({
          operational_state: {
            assignment_state: "unassigned_or_open_capture",
            upload_state: "uploading",
            qa_state: "queued",
            qa_outcome: "passed",
            repeat_ready: false,
          },
        }),
      ),
    );
  });

  it("denies arbitrary extra fields on create", async () => {
    await assertFails(
      submissionDoc(ownerDb()).set(iosCreatePayload({ totally_new_field: 1 })),
    );
  });
});

describe("capture_submissions transitions", () => {
  it("allows upload-start create followed by completion merge", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertSucceeds(doc.set(completionMerge(), { merge: true }));
  });

  it("allows a documented client failure transition", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertSucceeds(doc.set(failureMerge(), { merge: true }));
  });

  it("allows every iOS client failure status/qa-state pairing", async () => {
    // Mirrors CaptureUploadService.UploadError lifecycleStatus/lifecycleQaState.
    const pairings = [
      { status: "upload_failed", qa: "not_started" },
      { status: "raw_validation_failed", qa: "blocked_raw_validation" },
      { status: "local_preflight_failed", qa: "blocked_local_storage" },
      { status: "local_preflight_failed", qa: "blocked_local_capture_limits" },
    ];
    for (const [index, pairing] of pairings.entries()) {
      const captureId = `${CAPTURE_ID}-fail-${index}`;
      const doc = submissionDoc(ownerDb(), captureId);
      await assertSucceeds(
        doc.set(androidCreatePayload({ capture_id: captureId })),
      );
      const merge = failureMerge(pairing.status);
      merge.operational_state.qa_state = pairing.qa;
      await assertSucceeds(doc.set(merge, { merge: true }));
    }
  });

  it("allows retry after failure (failed -> uploading -> uploaded)", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertSucceeds(doc.set(failureMerge(), { merge: true }));
    await assertSucceeds(
      doc.set(
        {
          status: "submitted",
          operational_state: {
            assignment_state: "unassigned_or_open_capture",
            upload_state: "uploading",
            qa_state: "queued",
            repeat_ready: false,
          },
        },
        { merge: true },
      ),
    );
    await assertSucceeds(doc.set(completionMerge(), { merge: true }));
  });

  it("treats a replayed completion write as idempotent (allowed)", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertSucceeds(doc.set(completionMerge(), { merge: true }));
    // The client never got the ack and replays the same terminal write.
    await assertSucceeds(doc.set(completionMerge(), { merge: true }));
  });

  it("denies regressing an uploaded capture back to uploading or failed", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertSucceeds(doc.set(completionMerge(), { merge: true }));
    await assertFails(
      doc.set(
        {
          operational_state: {
            assignment_state: "unassigned_or_open_capture",
            upload_state: "uploading",
            qa_state: "queued",
            repeat_ready: false,
          },
        },
        { merge: true },
      ),
    );
    await assertFails(doc.set(failureMerge(), { merge: true }));
  });

  it("denies unauthenticated and wrong-owner updates", async () => {
    await submissionDoc(ownerDb()).set(androidCreatePayload());
    await assertFails(
      submissionDoc(anonDb()).set(completionMerge(), { merge: true }),
    );
    await assertFails(
      submissionDoc(strangerDb()).set(completionMerge(), { merge: true }),
    );
  });

  it("denies creator-id mutation", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertFails(
      doc.set({ creator_id: OTHER_UID }, { merge: true }),
    );
  });

  it("denies raw-prefix mutation once established", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertFails(
      doc.set(
        { raw_prefix: "scenes/other-scene/captures/other/raw/" },
        { merge: true },
      ),
    );
  });

  it("denies client escalation to approved/paid/QA states", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    for (const status of ["approved", "paid", "qa_passed"]) {
      await assertFails(doc.set({ status }, { merge: true }));
    }
    await assertFails(
      doc.set(
        {
          operational_state: {
            assignment_state: "unassigned_or_open_capture",
            upload_state: "uploaded",
            qa_state: "queued",
            qa_outcome: "passed",
            repeat_ready: false,
          },
          status: "submitted",
        },
        { merge: true },
      ),
    );
  });

  it("denies payout mutation on update", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(
      doc.set(androidCreatePayload({ estimated_payout_cents: 2500 })),
    );
    await assertFails(
      doc.set({ estimated_payout_cents: 990000 }, { merge: true }),
    );
    await assertFails(doc.set({ payout_cents: 990000 }, { merge: true }));
  });

  it("denies arbitrary-field injection on update", async () => {
    const doc = submissionDoc(ownerDb());
    await assertSucceeds(doc.set(androidCreatePayload()));
    await assertFails(
      doc.set({ world_model_candidate: true }, { merge: true }),
    );
  });

  it("denies client updates once the backend owns the record", async () => {
    // Backend (Admin SDK, bypasses rules) moves the record to a
    // server-owned status; the client may no longer touch it.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("capture_submissions")
        .doc(CAPTURE_ID)
        .set({
          ...iosCreatePayload(),
          status: "approved",
          payout_cents: 4500,
        });
    });
    await assertFails(
      submissionDoc(ownerDb()).set(failureMerge(), { merge: true }),
    );
  });

  it("denies reads of another creator's submission", async () => {
    await submissionDoc(ownerDb()).set(androidCreatePayload());
    await assertSucceeds(submissionDoc(ownerDb()).get());
    await assertFails(submissionDoc(strangerDb()).get());
    await assertFails(submissionDoc(anonDb()).get());
  });
});
