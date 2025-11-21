# yggdrasil

## Dev Container

- Build with VS Code/Dev Containers or `gh codespace create` (Docker socket from host is mounted).
- Tooling: terraform, kubectl, helm, flux, k9s, docker/compose, kustomize, sops, age, jq/yq.
- Base image: Ubuntu 22.04 (`.devcontainer/Dockerfile`).
- Open folder in container to get the toolchain; Docker host socket is required for `docker`/`compose`.

### Quick start

1. Install Docker on the host.
2. Open the repo in VS Code and select **Reopen in Container** (or use `Dev Containers: Open Folder in Container...`).
3. Verify tools (examples):
   - `terraform version`
   - `kubectl version --client`
   - `helm version`
   - `flux -v`
   - `docker info`

# yggdrasil
