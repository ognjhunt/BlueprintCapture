import test from "node:test";
import assert from "node:assert/strict";

import {
  captureObjectKind,
  parseCapturePath,
  resolveWalkthroughObjectName,
} from "./capture-paths.js";

test("parseCapturePath preserves canonical scene capture routing", () => {
  const parsed = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );

  assert.deepEqual(parsed, {
    mode: "scenes",
    sceneId: "scene-123",
    captureSourcePath: null,
    captureId: "capture-456",
    scenePrefix: "scenes/scene-123",
    capturePrefix: "scenes/scene-123/captures/capture-456",
    rawPrefix: "scenes/scene-123/captures/capture-456/raw",
    framesPrefix: "scenes/scene-123/captures/capture-456/frames",
    capturesPrefix: "scenes/scene-123/captures/capture-456",
    keyframeObjectName: "scenes/scene-123/images/capture-456_keyframe.jpg",
  });
});

test("parseCapturePath keeps legacy scene source inputs on legacy raw prefixes", () => {
  const parsed = parseCapturePath(
    "scenes/scene-123/android/capture-456/raw/walkthrough.mp4",
    "0"
  );

  assert.deepEqual(parsed, {
    mode: "scenes",
    sceneId: "scene-123",
    captureSourcePath: "android",
    captureId: "capture-456",
    scenePrefix: "scenes/scene-123",
    capturePrefix: "scenes/scene-123/android/capture-456",
    rawPrefix: "scenes/scene-123/android/capture-456/raw",
    framesPrefix: "scenes/scene-123/android/capture-456/frames",
    capturesPrefix: "scenes/scene-123/captures/capture-456",
    keyframeObjectName: "scenes/scene-123/images/capture-456_keyframe.jpg",
  });
});

test("parseCapturePath keeps target uploads isolated as legacy captures", () => {
  const parsed = parseCapturePath("targets/target-789/raw/walkthrough.mov", "12345");

  assert.deepEqual(parsed, {
    mode: "targets",
    sceneId: "target-789",
    captureSourcePath: "unknown",
    captureId: "legacy-12345",
    scenePrefix: "targets/target-789",
    capturePrefix: "targets/target-789",
    rawPrefix: "targets/target-789/raw",
    framesPrefix: "targets/target-789/frames",
    capturesPrefix: "targets/target-789/captures/legacy-12345",
    keyframeObjectName: "targets/target-789/images/legacy-12345_keyframe.jpg",
  });
});

test("captureObjectKind only treats walkthrough files and completion markers as triggers", () => {
  assert.equal(
    captureObjectKind("scenes/scene-123/captures/capture-456/raw/walkthrough.mov"),
    "walkthrough"
  );
  assert.equal(
    captureObjectKind("scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"),
    "walkthrough"
  );
  assert.equal(
    captureObjectKind("scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json"),
    "completion_marker"
  );
  assert.equal(
    captureObjectKind("scenes/scene-123/captures/capture-456/raw/manifest.json"),
    "other"
  );
});

test("resolveWalkthroughObjectName preserves raw video identity from finalized or manifest paths", () => {
  const pathInfo = parseCapturePath(
    "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json",
    "0"
  );
  assert.ok(pathInfo);

  assert.equal(
    resolveWalkthroughObjectName(
      { video_uri: "gs://bucket/scenes/scene-123/captures/capture-456/raw/walkthrough.mp4" },
      pathInfo
    ),
    "scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"
  );
  assert.equal(
    resolveWalkthroughObjectName(
      { video_uri: "raw/walkthrough.mp4" },
      pathInfo,
      "scenes/scene-123/captures/capture-456/raw/capture_upload_complete.json"
    ),
    "scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"
  );
  assert.equal(
    resolveWalkthroughObjectName(
      { video_uri: "raw/walkthrough.mov" },
      pathInfo,
      "scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"
    ),
    "scenes/scene-123/captures/capture-456/raw/walkthrough.mp4"
  );
});
