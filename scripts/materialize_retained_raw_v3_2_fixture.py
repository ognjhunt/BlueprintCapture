#!/usr/bin/env python3
"""Materialize a rights-cleared procedural Raw V3.2 development fixture.

The resulting bytes exercise the production bridge and Postshot transport. They
are synthetic software-test evidence only and do not qualify a physical site,
metric scale, reconstruction fidelity, task truth, or robot behavior.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import zlib


def canonical_json(value: object) -> str:
    def normalize_numbers(item: object) -> object:
        # Match JavaScript JSON.stringify, which emits integral finite Numbers
        # without a decimal suffix. The production bridge owns this canonical
        # digest contract.
        if isinstance(item, float) and item.is_integer():
            return int(item)
        if isinstance(item, list):
            return [normalize_numbers(child) for child in item]
        if isinstance(item, dict):
            return {key: normalize_numbers(child) for key, child in item.items()}
        return item

    return json.dumps(
        normalize_numbers(value),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )


def canonical_digest(value: dict, digest_field: str | None = None) -> str:
    normalized = dict(value)
    if digest_field:
        normalized.pop(digest_field, None)
    return "sha256:" + hashlib.sha256(canonical_json(normalized).encode()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(canonical_json(row) + "\n" for row in rows), encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def write_gray_png(path: Path, width: int, height: int, value: int, bit_depth: int) -> None:
    if bit_depth == 16:
        pixel = struct.pack(">H", value)
    else:
        pixel = bytes([value])
    scanline = b"\x00" + pixel * width
    payload = scanline * height
    encoded = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, bit_depth, 0, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(payload, 9))
        + png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encoded)


def render_ppm(path: Path, width: int, height: int, frame_index: int) -> None:
    pixels = bytearray(width * height * 3)
    shift = frame_index * 5
    for y in range(height):
        for x in range(width):
            checker = (((x + shift) // 32) + (y // 32)) & 1
            r = 42 + 55 * checker + ((x + shift) % 91)
            g = 38 + 45 * (1 - checker) + (y % 83)
            b = 55 + ((x + y + shift) % 117)
            if 150 + frame_index * 2 < x < 430 + frame_index * 2 and 120 < y < 360:
                edge = min(x - (150 + frame_index * 2), (430 + frame_index * 2) - x, y - 120, 360 - y)
                if edge < 9:
                    r, g, b = 245, 230, 40
                elif ((x + shift) // 18 + y // 18) & 1:
                    r, g, b = 180, 45, 35
                else:
                    r, g, b = 35, 130, 205
            offset = (y * width + x) * 3
            pixels[offset : offset + 3] = bytes((r % 256, g % 256, b % 256))
    path.write_bytes(f"P6\n{width} {height}\n255\n".encode() + pixels)


def time_value(index: int, fps: int) -> int | float:
    if index == 0:
        return 0
    return round(index / fps, 6)


def matrix(index: int) -> list[list[int | float]]:
    angle = math.radians(-3 + index * 0.25)
    c = round(math.cos(angle), 9)
    s = round(math.sin(angle), 9)
    return [
        [c, 0, s, round(index * 0.025, 6)],
        [0, 1, 0, 0],
        [-s, 0, c, round(0.03 * math.sin(index / 5), 6)],
        [0, 0, 0, 1],
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--scene-id", required=True)
    parser.add_argument("--capture-id", required=True)
    parser.add_argument("--site-id", required=True)
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--site-submission-id", required=True)
    parser.add_argument("--buyer-request-id", required=True)
    parser.add_argument("--capture-job-id", required=True)
    parser.add_argument("--creator-id", required=True)
    parser.add_argument("--app-build", required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()

    raw = Path(args.output).resolve()
    if raw.exists() and any(raw.iterdir()):
        raise SystemExit("fixture_output_must_be_empty")
    raw.mkdir(parents=True, exist_ok=True)
    frames_dir = raw / ".procedural_frames"
    frames_dir.mkdir()

    width, height, fps, frame_count = 640, 480, 10, 24
    for index in range(frame_count):
        render_ppm(frames_dir / f"frame_{index:06d}.ppm", width, height, index)
    subprocess.run(
        [
            args.ffmpeg,
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(fps),
            "-i",
            str(frames_dir / "frame_%06d.ppm"),
            "-frames:v",
            str(frame_count),
            "-c:v",
            "libx264",
            "-pix_fmt",
            "yuv420p",
            "-video_track_timescale",
            "1000",
            str(raw / "walkthrough.mov"),
        ],
        check=True,
    )
    for frame in frames_dir.iterdir():
        frame.unlink()
    frames_dir.rmdir()

    now = "2026-08-23T20:00:00Z"
    cfs = f"cfs-{args.capture_id}"
    raw_prefix = f"scenes/{args.scene_id}/captures/{args.capture_id}/raw"
    frame_ids = [f"{index + 1:06d}" for index in range(frame_count)]
    times = [time_value(index, fps) for index in range(frame_count)]
    intrinsics = {
        "authority": "arkit_arframe_exact_per_observation",
        "fx": 500,
        "fy": 500,
        "cx": 320,
        "cy": 240,
        "width": width,
        "height": height,
        "matrix_column_major": [500, 0, 0, 0, 500, 0, 320, 240, 1],
    }
    calibration_digest = canonical_digest(intrinsics)

    capabilities = {
        "camera_pose": True,
        "camera_intrinsics": True,
        "depth": True,
        "depth_confidence": True,
        "tracking_state": True,
        "relocalization_events": True,
        "motion": True,
        "motion_authoritative": False,
        "pose_rows": frame_count,
        "intrinsics_valid": True,
        "depth_frames": frame_count,
        "confidence_frames": frame_count,
        "tracking_state_rows": frame_count,
        "relocalization_event_rows": 0,
        "motion_samples": frame_count,
        "pose_authority": "procedural_development_fixture",
        "intrinsics_authority": "procedural_development_fixture",
        "depth_authority": "procedural_development_fixture",
        "motion_authority": "diagnostic_only",
        "motion_provenance": "procedural_development_fixture",
        "geometry_source": "arkit",
        "geometry_expected_downstream": True,
    }
    capture_rights = {
        "consent_status": "documented",
        "derived_scene_generation_allowed": True,
        "data_licensing_allowed": False,
        "capture_contributor_payout_eligible": False,
        "redaction_required": True,
        "permission_document_uri": None,
        "consent_scope": ["procedural_fixture_only"],
        "consent_notes": ["No human, customer, or physical-site data is present."],
    }
    upstream = {
        "site_submission_id": args.site_submission_id,
        "buyer_request_id": args.buyer_request_id,
        "capture_job_id": args.capture_job_id,
        "blockers": [],
        "claim_ceiling": "development_only_procedural_fixture",
    }
    manifest = {
        "schema_version": "v3",
        "capture_schema_version": "3.2.0",
        "scene_id": args.scene_id,
        "capture_id": args.capture_id,
        "site_id": args.site_id,
        "task_id": args.task_id,
        "site_submission_id": args.site_submission_id,
        "buyer_request_id": args.buyer_request_id,
        "capture_job_id": args.capture_job_id,
        "upstream_handoff": upstream,
        "capture_source": "iphone",
        "capture_tier_hint": "tier1_iphone",
        "capture_profile_id": "iphone_arkit_lidar",
        "capture_capabilities": capabilities,
        "coordinate_frame_session_id": cfs,
        "video_uri": "walkthrough.mov",
        "capture_start_epoch_ms": 1787515200000,
        "app_version": "1.0",
        "app_build": args.app_build,
        "ios_version": "26.0",
        "ios_build": "procedural-fixture",
        "os_version": "26.0",
        "hardware_model_identifier": "procedural-fixture",
        "device_model": "Procedural iPhone Pro contract fixture",
        "device_model_marketing": "Procedural iPhone Pro contract fixture",
        "has_lidar": True,
        "depth_supported": True,
        "fps_source": fps,
        "width": width,
        "height": height,
        "rights_profile": "operator_authorized_development_fixture",
        "requested_outputs": ["reconstruction_candidate"],
        "capture_rights": capture_rights,
        "scene_memory_capture": {
            "world_model_candidate": False,
            "operator_notes": ["Procedural development-only transport fixture."],
            "inaccessible_areas": [],
        },
    }
    write_json(raw / "manifest.json", manifest)
    write_json(
        raw / "rights_consent.json",
        {
            "schema_version": "v1",
            "scene_id": args.scene_id,
            "capture_id": args.capture_id,
            "consent_status": "documented",
            "capture_basis": "blueprint_authored_procedural_fixture",
            "derived_scene_generation_allowed": True,
            "data_licensing_allowed": False,
            "capture_contributor_payout_eligible": False,
            "permission_document_uri": None,
            "permission_document_sha256": None,
            "consent_scope": ["internal_development_fixture"],
            "consent_notes": ["Procedural pixels only; no physical site or person."],
            "redaction_required": True,
            "privacy_processing": {"redaction_required_before_derived_use": True},
            "retention": {"policy_id": "development-fixture", "live_enforcement_proven_by_bundle": False},
            "revocation": {"latest_status_check_required_before_downstream_use": True},
            "provider_upload": {"direct_mobile_upload_allowed": False, "third_party_provider_upload_authorized": False},
        },
    )
    context = {
        "schema_version": "v1",
        "scene_id": args.scene_id,
        "capture_id": args.capture_id,
        "site_id": args.site_id,
        "task_id": args.task_id,
        "site_submission_id": args.site_submission_id,
        "buyer_request_id": args.buyer_request_id,
        "capture_job_id": args.capture_job_id,
        "upstream_handoff": upstream,
        "capture_source": "iphone",
        "requested_outputs": ["reconstruction_candidate"],
        "scene_memory_capture": manifest["scene_memory_capture"],
        "capture_evidence": capabilities,
        "capture_rights": capture_rights,
        "claim_ceiling": "development_only_procedural_fixture",
    }
    write_json(raw / "capture_context.json", context)
    write_json(raw / "intake_packet.json", {"schema_version": "v1", "workflow_name": "Procedural Postshot transport check", "task_steps": ["Import", "Train", "Export", "Publish"], "owner": "blueprint_release_engineering"})
    write_json(raw / "task_hypothesis.json", {"schema_version": "v1", "workflow_name": "Procedural Postshot transport check", "task_steps": ["Import", "Train", "Export", "Publish"], "source": "authoritative_fixture_definition", "status": "accepted"})
    write_json(raw / "recording_session.json", {"schema_version": "v1", "scene_id": args.scene_id, "capture_id": args.capture_id, "coordinate_frame_session_id": cfs, "arkit_session_id": cfs, "world_frame_definition": "procedural_arkit_world_origin", "units": "meters", "handedness": "right_handed", "up_axis": "Y", "gravity_aligned": True, "session_reset_count": 0})
    write_json(raw / "capture_topology.json", {"schema_version": "v1", "capture_session_id": args.capture_id, "route_id": "procedural-orbit", "pass_id": "pass-1", "pass_index": 1, "intended_pass_role": "development_fixture", "coordinate_frame_session_id": cfs})
    write_json(raw / "route_anchors.json", {"schema_version": "v1", "route_anchors": []})
    write_json(raw / "checkpoint_events.json", {"schema_version": "v1", "checkpoint_events": []})
    write_json(raw / "relocalization_events.json", {"schema_version": "v1", "relocalization_events": []})
    write_json(raw / "overlap_graph.json", {"schema_version": "v1", "coordinate_frame_session_id": cfs, "observed_anchor_ids": [], "semantic_anchor_ids": []})
    write_json(raw / "video_track.json", {"schema_version": "v1", "video_file": "walkthrough.mov", "duration_sec": frame_count / fps, "frame_count": frame_count, "frame_count_source": "decoded_sample_presentation_timestamps", "decoded_pts_verified": True, "write_attempt_count": frame_count, "retained_frame_count": frame_count, "dropped_frame_count": 0, "nominal_fps": fps, "contains_vfr": False, "video_start_pts_sec": 0, "video_time_origin": "first_decoded_sample_presentation_timestamp", "t_video_semantics": "decoded_source_pts_minus_video_start_pts", "width": width, "height": height, "orientation": "landscape", "codec": "h264", "color_space": "bt709"})

    poses, frames, qualities, camera_states, retention, sync, motion = [], [], [], [], [], [], []
    candidates = []
    depth_rows, confidence_rows = [], []
    for index, frame_id in enumerate(frame_ids):
        t = times[index]
        transform = matrix(index)
        mono = 1_000_000_000 + index * 100_000_000
        depth_path = f"arkit/depth/{frame_id}.png"
        confidence_path = f"arkit/confidence/{frame_id}.png"
        write_gray_png(raw / depth_path, 64, 48, 1000 + index * 2, 16)
        write_gray_png(raw / confidence_path, 64, 48, 2, 8)
        depth_rows.append({"frame_id": frame_id, "depth_path": depth_path, "paired_confidence_path": confidence_path, "width": 64, "height": 48, "depth_source": "procedural_plane", "depth_valid_fraction": 1, "missing_depth_fraction": 0})
        confidence_rows.append({"frame_id": frame_id, "confidence_path": confidence_path, "paired_depth_path": depth_path})
        poses.append({"pose_schema_version": "3.0", "frame_id": frame_id, "t_capture_sec": t, "t_monotonic_ns": mono, "coordinate_frame_session_id": cfs, "T_world_camera": transform, "T_site_camera": transform, "tracking_state": "normal", "tracking_reason": None, "world_mapping_status": "mapped"})
        frames.append({"frame_id": frame_id, "frame_index": index, "timestamp": t, "t_capture_sec": t, "t_monotonic_ns": mono, "captured_at": now, "camera_transform": [cell for row in transform for cell in row], "intrinsics": intrinsics["matrix_column_major"], "image_resolution": [width, height], "coordinate_frame_session_id": cfs, "tracking_state": "normal", "tracking_reason": None, "world_mapping_status": "mapped", "relocalization_event": False, "smoothed_scene_depth_file": depth_path, "confidence_file": confidence_path})
        qualities.append({"frame_id": frame_id, "t_capture_sec": t, "coordinate_frame_session_id": cfs, "tracking_state": "normal", "tracking_reason": None, "world_mapping_status": "mapped", "relocalization_event": False, "sharpness_score": 100, "depth_source": "procedural_plane", "depth_valid_fraction": 1, "missing_depth_fraction": 0, "usable_for_pose": True, "usable_for_depth": True})
        camera_states.append({"frame_id": frame_id, "t_capture_sec": t, "coordinate_frame_session_id": cfs, "zoom_factor": 1, "focus_mode": "fixed_procedural", "focus_locked": True, "exposure_mode": "fixed_procedural", "exposure_locked": True, "white_balance_mode": "fixed_procedural", "video_stabilization_mode": "off", "torch_active": False, "hdr_active": False})
        retention.append({"write_attempt_index": index, "source_timestamp_sec": t, "frame_id": frame_id, "t_capture_sec": t, "retention_status": "retained", "drop_reason": None, "encoded_frame_index": index, "t_video_sec": t, "decoded_source_pts_sec": t})
        sync.append({"frame_id": frame_id, "t_video_sec": t, "decoded_source_pts_sec": t, "decoded_time_origin_pts_sec": 0, "t_capture_sec": t, "t_monotonic_ns": mono, "pose_frame_id": frame_id, "sync_status": "encoded_decoded_pts_match", "delta_ms": 0, "encoded_frame_index": index, "write_attempt_index": index})
        motion.append({"timestamp": t, "t_capture_sec": t, "t_monotonic_ns": mono, "wall_time": now, "motion_provenance": "procedural_development_fixture", "attitude": {"roll": 0, "pitch": 0, "yaw": 0, "quaternion": {"x": 0, "y": 0, "z": 0, "w": 1}}, "rotation_rate": {"x": 0, "y": 0, "z": 0}, "gravity": {"x": 0, "y": -1, "z": 0}, "user_acceleration": {"x": 0, "y": 0, "z": 0}})
        candidates.append({"candidate_id": f"rgb_{index:06d}", "source_video_uri": "walkthrough.mov", "output_image_relative_path": f"candidate_rgb/{index:06d}.png", "decoded_frame_ordinal": index, "encoded_frame_index": index, "decoded_pts_sec": t, "decoded_source_pts_sec": t, "t_capture_sec": t, "write_attempt_index": index, "frame_id": frame_id, "pose_frame_id": frame_id, "coordinate_frame_session_id": cfs, "site_frame_id": cfs, "site_frame_definition": "arkit_world_origin_at_session_start", "transform_semantics": "row_major_camera_to_site", "units": "meters", "handedness": "right_handed", "up_axis": "Y", "gravity_aligned": True, "T_site_camera": transform, "T_world_camera": transform, "camera_intrinsics": intrinsics, "camera_calibration_digest": calibration_digest, "tracking_state": "normal", "tracking_reason": None, "world_mapping_status": "mapped", "relocalization_event": False, "arkit_frame_row_ordinal": index, "arkit_pose_row_ordinal": index, "pose_assisted_eligible": True, "raw_observation_authority": True, "downstream_artifact_authority": False, "depth_path": depth_path, "confidence_path": confidence_path})

    write_jsonl(raw / "arkit/poses.jsonl", poses)
    write_jsonl(raw / "arkit/frames.jsonl", frames)
    write_jsonl(raw / "arkit/frame_quality.jsonl", qualities)
    write_jsonl(raw / "arkit/per_frame_camera_state.jsonl", camera_states)
    write_jsonl(raw / "video_frame_retention.jsonl", retention)
    write_jsonl(raw / "sync_map.jsonl", sync)
    write_jsonl(raw / "motion.jsonl", motion)
    write_jsonl(raw / "semantic_anchor_observations.jsonl", [])
    write_json(raw / "arkit/session_intrinsics.json", {"schema_version": "v1", "coordinate_frame_session_id": cfs, "camera_model": "pinhole", "principal_point_reference": "full_resolution_image", "distortion_model": "none", "distortion_coeffs": [], "intrinsics": {key: intrinsics[key] for key in ("fx", "fy", "cx", "cy", "width", "height")}})
    write_json(raw / "arkit/depth_manifest.json", {"schema_version": "arkit_depth_manifest.v2", "coordinate_frame_session_id": cfs, "representation": "per_frame_depth_map", "depth_encoding": "uint16_png", "encoding": "png_u16_mm", "units": "millimeters", "scale_to_meters": 0.001, "camera_ray_convention": "arkit_x_right_y_up_z_backward", "depth_intrinsics": {"fx": 50, "fy": 50, "cx": 32, "cy": 24, "width": 64, "height": 48}, "depth_registered_to_arkit_camera": True, "invalid_value_semantics": "0_means_missing", "missing_depth_reason": None, "frames": depth_rows})
    write_json(raw / "arkit/confidence_manifest.json", {"schema_version": "arkit_confidence_manifest.v2", "coordinate_frame_session_id": cfs, "representation": "per_frame_confidence_map", "confidence_encoding": "uint8_png", "encoding": "png_u8", "accepted_confidence_values": [2], "confidence_scale": {"0": "low_or_missing", "1": "medium", "2": "high"}, "frames": confidence_rows})
    write_json(raw / "reconstruction_qualification_request.json", {"schema_version": "reconstruction_qualification_request.v1", "status": "abstain_pending_downstream_measurements", "claim_ceiling": "development_only_procedural_fixture"})

    candidate_manifest = {
        "schema_version": "downstream_candidate_manifest.v1",
        "scene_id": args.scene_id,
        "capture_id": args.capture_id,
        "coordinate_frame_session_id": cfs,
        "source_video_uri": "walkthrough.mov",
        "source_video_sha256": sha256_file(raw / "walkthrough.mov"),
        "source_video_authority": "immutable_raw_capture_video",
        "decoded_timing_authority": "sync_map_decoded_sample_presentation_timestamps",
        "candidate_count": frame_count,
        "candidate_order": "encoded_frame_index_ascending",
        "selection_contract": {"selection_authority": "blueprint_pipeline_task_site_profile", "capture_default_selection": None, "selection_parameters_required": True, "allowed_deterministic_selectors": ["explicit_encoded_frame_ordinals", "profile_bound_even_decoded_pts_coverage", "profile_bound_quality_filter"], "smallest_missing_input_when_unselectable": "task_site_evidence_profile_with_frame_selection_parameters"},
        "provider_neutrality": {"mobile_app_direct_provider_upload_allowed": False, "third_party_provider_upload_authorized": False, "provider_selection_authority": "blueprint_pipeline", "provider_authorization_status": "not_granted_by_capture_manifest"},
        "allowed_use_scope": {"raw_observation_indexing_allowed": True, "derived_processing_allowed": True, "data_licensing_allowed": False, "requested_outputs": ["reconstruction_candidate"], "redaction_required_before_derived_use": True, "privacy_security_limits": [], "latest_revocation_check_required": True, "provider_upload_requires_separate_downstream_authorization": True},
        "claim_boundary": {"raw_capture_remains_authoritative": True, "candidate_manifest_qualifies_reconstruction": False, "candidate_manifest_qualifies_metric_scale": False, "candidate_manifest_qualifies_collision_or_physics": False, "candidate_manifest_proves_task_success": False},
        "candidates": candidates,
    }
    candidate_manifest["manifest_digest"] = canonical_digest(candidate_manifest, "manifest_digest")
    write_json(raw / "downstream_candidate_manifest.json", candidate_manifest)

    completion = {"schema_version": "v1", "scene_id": args.scene_id, "capture_id": args.capture_id, "raw_prefix": raw_prefix, "completed_at": now, "claim_ceiling": "development_only_procedural_fixture"}
    write_json(raw / "capture_upload_complete.json", completion)
    provenance = {"schema_version": "v1", "scene_id": args.scene_id, "capture_id": args.capture_id, "capture_source": "iphone", "captured_by_user_id": args.creator_id, "uploaded_by_user_id": args.creator_id, "capture_app_build": args.app_build, "capture_app_version": "1.0", "device_installation_id": "procedural-fixture", "bundle_created_at": now, "upload_completed_at": now, "bundle_sha256": "pending"}
    write_json(raw / "provenance.json", provenance)

    def artifact_hashes() -> dict[str, str]:
        return {path.relative_to(raw).as_posix(): sha256_file(path) for path in sorted(raw.rglob("*")) if path.is_file() and path.name != "hashes.json"}

    first = artifact_hashes()
    provenance["bundle_sha256"] = hashlib.sha256("\n".join(f"{key}:{first[key]}" for key in sorted(first)).encode()).hexdigest()
    write_json(raw / "provenance.json", provenance)
    final = artifact_hashes()
    bundle_sha = hashlib.sha256("\n".join(f"{key}:{final[key]}" for key in sorted(final)).encode()).hexdigest()
    write_json(raw / "hashes.json", {"schema_version": "v1", "bundle_sha256": bundle_sha, "artifacts": final})
    receipt = {"schema_version": "blueprint.retained_raw_v3_2_procedural_fixture.v1", "status": "materialized", "scene_id": args.scene_id, "capture_id": args.capture_id, "capture_job_id": args.capture_job_id, "raw_bundle_digest": "sha256:" + bundle_sha, "candidate_manifest_digest": candidate_manifest["manifest_digest"], "frame_count": frame_count, "claim_ceiling": "development_only_procedural_fixture", "physical_truth_inferred": False}
    write_json(raw.parent / "fixture_receipt.json", receipt)
    print(canonical_json(receipt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
