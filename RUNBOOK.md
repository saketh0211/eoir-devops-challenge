# EO/IR Stack Release Runbook — v1.4.2

## 1. Scope and limitations

This runbook covers local validation, image packaging, offline transfer,
deployment checks, rollback, and runtime compatibility.

The supplied model file's SHA-256 is checked against models/manifest.json.
A matching checksum proves file integrity relative to the manifest; it does
not prove that the file is a valid or executable TensorRT engine.

The supplied file must be validated on the intended GPU platform before
production use. Do not claim successful TensorRT inference based only on
the HTTP health endpoint.

## 2. Findings, root causes, and fixes

| Area / file | Root cause | Fix / validation |
|---|---|---|
| docker-compose.yml — inference_worker healthcheck | Original check used an unconditional success command and could report a failed worker as healthy. | Query the worker /status endpoint; invalid checksum returns HTTP 500. Docker health transitions to unhealthy after failed checks. |
| docker-compose.yml — vision_api WORKER_URL | Using localhost from inside the API container points to the API container itself, not the worker. | Use http://inference_worker:9000 on the Compose network. |
| docker-compose.yml — networks | API must reach the worker and database while also exposing its API network. | API joins edge_dmz and sensor_backplane; sensor_backplane is internal. |
| docker-compose.yml — startup dependencies | Starting a container does not guarantee the service is ready. | API waits for worker and PostgreSQL health/readiness. |
| Dockerfile | Full Python image and unnecessary utilities increase image size and attack surface; root execution increases impact of compromise. | Use python:3.11-slim, copy only required application files, and run as non-root. Confirm actual image size after build. |
| .env / docker-compose.yml | Secrets must not be committed in orchestration files. | Keep credentials in untracked .env; commit only placeholder values in .env.example. Rotate any real credentials exposed in logs, commits, or chat. |
| models/manifest.json | Original manifest digest did not match the supplied engine file. | Update manifest to the actual file digest and test checksum consistency. This does not validate TensorRT engine compatibility. |
| .github/workflows/ci.yml | Tests were ignored with `|| true`, and a mutable latest tag was used. | Tests fail the job on failure; build is gated on tests; use commit-SHA tags and verify image existence. |
| Air-gap release | Offline targets need images, Compose configuration, models, and integrity checks. | package_airgap.sh exports images and files with SHA256SUMS; deploy_airgap.sh verifies before image loading. |

Line numbers may change as files are edited; use the named sections and commands above to locate the current implementation.

## 3. Pre-release validation

From the project directory:

    docker compose --env-file .env.example config --quiet
    python3 -m unittest discover -s tests -v
    docker compose up -d --build
    docker compose ps
    curl -i http://localhost:8000/health
    curl -i http://localhost:8000/api/v1/detect

Expected API health response is HTTP 200 with status healthy and worker_ready true.
Expected detect response is HTTP 200. Confirm that this is an application-level
test response, not proof of real TensorRT inference.

## 4. Air-gapped packaging

Run:

    ./package_airgap.sh

Transfer release_v1.4.2.tar.gz to the approved target using the organization's
approved media or file-transfer process.

On the target, verify the archive hash against the separately communicated
trusted hash before extraction. A checksum file inside an archive alone does
not authenticate the archive if an attacker can replace both the archive and
its checksum manifest.

Then run:

    ./deploy_airgap.sh ./release_v1.4.2.tar.gz

Deployment checksums must pass before any image is loaded. Create a target-local
.env from .env.example, replace placeholders with approved secrets, and review
the Compose configuration before starting services.

## 5. Offline deployment and validation

After verifying checksums and importing images:

    docker image ls
    docker compose --env-file .env config --quiet
    docker compose up -d
    docker compose ps
    curl -i http://localhost:8000/health
    curl -i http://localhost:8000/api/v1/detect

Do not run these commands until the release has been validated for the target
architecture and runtime.

## 6. Rollback within a 15-minute change window

Before the change:
- Record the current image IDs/tags and Compose configuration.
- Keep the last known-good release archive and its trusted SHA-256.
- Confirm access to the prior release and database recovery process.

If validation fails:
1. Stop the attempted deployment with `docker compose down`.
2. Restore the previous known-good Compose file and target-local environment.
3. Load the prior image archive with `docker load -i <previous-image-archive>`.
4. Start the previous release with `docker compose up -d`.
5. Check `docker compose ps`, `/health`, and `/api/v1/detect`.
6. Notify the change owner and record timestamps, errors, and rollback result.

Target rollback completion is within 15 minutes. Rehearse this procedure in a
non-production environment; database changes may require a separate approved
restore plan. Do not delete persistent data as part of routine rollback.

## 7. x86_64 CUDA/TensorRT versus Jetson Orin aarch64

Do not assume a TensorRT engine built on an x86_64 lab GPU is portable to
aarch64 Jetson Orin. Engine compatibility depends on GPU architecture,
TensorRT/CUDA versions, plugins, precision support, and build/runtime settings.

For each target:
- Record OS, CPU architecture, JetPack, CUDA, TensorRT, and driver versions.
- Build or generate the engine on the target or with a vendor-supported,
  verified compatibility workflow.
- Verify required plugins and dependencies.
- Run a real inference smoke test with representative inputs.
- Record the engine checksum and exact runtime compatibility metadata.
- Package architecture-specific images/engines separately if needed.

The manifest's target_arch field is metadata, not proof of compatibility.
The supplied engine file must be independently validated before production use.

## 8. Security notes

- Never package .env or real credentials.
- Use least-privilege credentials and rotate exposed real secrets.
- Use immutable version or commit-SHA tags for release artifacts.
- Keep a trusted archive checksum outside the archive.
- Verify all files before loading images or starting services.
- Treat the supplied model as untrusted until validated.
EOF
